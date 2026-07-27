defmodule Bee.Repo do
  @moduledoc false
  use GenServer
  require Logger

  @lock_sweep_interval_ms 60_000
  @checkpoint_interval_ms 60_000
  @wal_threshold_bytes 10_000_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    db_path = Keyword.fetch!(opts, :db_path)
    prefix = Keyword.fetch!(opts, :prefix)
    jsonl_path = Keyword.get(opts, :jsonl_path)

    db_path |> Path.dirname() |> File.mkdir_p!()

    case Bee.Store.Migrate.run_at_boot(db_path) do
      :ok ->
        {:ok, conn} = Exqlite.Sqlite3.open(db_path)
        :ok = Bee.Store.init_schema(conn)

        dep_graph = Bee.Graph.new()
        alloc_graph = Bee.World.new()

        # Auto-import JSONL on first boot (empty DB + file exists)
        maybe_seed_from_jsonl(conn, jsonl_path, prefix)

        Bee.Graph.rebuild(dep_graph, conn)
        Bee.World.rebuild(alloc_graph, conn)

        schedule_lock_sweep()
        schedule_checkpoint()

        # Start the reader pool (AD-2, AD-3). Linked for now;
        # Story 3.3 moves it under Bee.Supervisor with :rest_for_one.
        pool_name = read_pool_name(opts)
        {:ok, pool_pid} =
          Bee.Read.Pool.start_link(db_path: db_path, name: pool_name)

        {:ok,
         %{
           conn: conn,
           dep_graph: dep_graph,
           alloc_graph: alloc_graph,
           prefix: prefix,
           jsonl_path: jsonl_path,
           export_mode: :on_write,
           db_path: db_path,
           pool_pid: pool_pid,
           pool_name: pool_name
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  # --- GenServer calls ---

  @impl true
  def handle_call(:conn, _from, state), do: {:reply, state.conn, state}

  def handle_call({:create, title, opts}, _from, state) do
    id = Bee.Id.next(state.conn, state.prefix)

    attrs = %{
      id: id,
      title: title,
      description: Keyword.get(opts, :description),
      priority: Keyword.get(opts, :priority),
      issue_type: Keyword.get(opts, :issue_type) || Keyword.get(opts, :type, "task"),
      labels: Keyword.get(opts, :labels, []) ++ label_list(Keyword.get(opts, :label)),
      parent: format_parent(Keyword.get(opts, :parent), state.prefix),
      project_id: Keyword.get(opts, :project_id),
      created_by: Keyword.get(opts, :actor)
    }

    {:ok, issue} = Bee.Store.insert_issue(state.conn, attrs)
    Bee.Graph.add_vertex(state.dep_graph, id)
    Bee.World.add_issue(state.alloc_graph, id, attrs.project_id)
    maybe_export(state)
    {:reply, {:ok, issue}, state}
  end

  def handle_call({:get, id}, _from, state) do
    full = resolve_id(id, state.prefix)
    lane = Bee.Query.Classifier.classify(:get)
    result = read_with_pool(state, lane, fn conn -> Bee.Store.get_issue(conn, full) end)
    {:reply, result, state}
  end

  def handle_call({:get, id, opts}, _from, state) do
    case Bee.Store.validate_opts(opts) do
      :ok ->
        full = resolve_id(id, state.prefix)
        lane = Bee.Query.Classifier.classify(:get)
        result = read_with_pool(state, lane, fn conn -> Bee.Store.get_issue(conn, full, opts) end)
        {:reply, result, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_comments, id}, _from, state) do
    full = resolve_id(id, state.prefix)
    lane = Bee.Query.Classifier.classify(:get_comments)
    result = read_with_pool(state, lane, fn conn -> {:ok, Bee.Store.get_comments(conn, full)} end)
    {:reply, result, state}
  end

  def handle_call({:list, opts}, _from, state) do
    case Bee.Store.validate_opts(opts) do
      :ok ->
        lane = Bee.Query.Classifier.classify(:list)
        result = read_with_pool(state, lane, fn conn -> Bee.Store.list_issues(conn, opts) end)
        {:reply, result, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:count, opts}, _from, state) do
    case Bee.Store.validate_opts(opts) do
      :ok ->
        lane = Bee.Query.Classifier.classify(:count)
        result = read_with_pool(state, lane, fn conn -> Bee.Store.count_issues(conn, opts) end)
        {:reply, result, state}

      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:tree_page, opts}, _from, state) do
    case Bee.Store.validate_opts(opts) do
      :ok ->
        lane = Bee.Query.Classifier.classify(:tree_page)
        result = read_with_pool(state, lane, fn conn -> Bee.Store.list_tree_page(conn, opts) end)
        {:reply, result, state}

      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:ready, _opts}, _from, state) do
    ready_ids = Bee.Graph.ready_issues(state.dep_graph, state.conn)

    issues =
      Enum.flat_map(ready_ids, fn id ->
        case Bee.Store.get_issue(state.conn, id) do
          {:ok, issue} -> [issue]
          _ -> []
        end
      end)

    {:reply, {:ok, issues}, state}
  end

  def handle_call({:update, id, attrs}, _from, state) do
    full = resolve_id(id, state.prefix)

    with {:ok, normalized_attrs} <- normalize_update_attrs(attrs, full, state),
         :ok <- Bee.Store.update_issue(state.conn, full, normalized_attrs) do
      maybe_export(state)
      {:reply, :ok, state}
    else
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def handle_call({:comment, id, text, opts}, _from, state) do
    full = resolve_id(id, state.prefix)

    case Bee.Store.insert_comment(state.conn, full, text, opts) do
      :ok ->
        maybe_export(state)
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, classify_write_error(reason)}, state}
    end
  end

  def handle_call({:block, id, blocker_id}, _from, state) do
    full_id = resolve_id(id, state.prefix)
    full_blocker = resolve_id(blocker_id, state.prefix)

    case Bee.Graph.add_dependency(state.dep_graph, full_id, full_blocker) do
      :ok ->
        Bee.Store.insert_dependency(state.conn, full_id, full_blocker)
        maybe_export(state)
        {:reply, :ok, state}

      {:error, :cycle} ->
        {:reply, {:error, :cycle}, state}
    end
  end

  def handle_call({:unblock, id, blocker_id}, _from, state) do
    full_id = resolve_id(id, state.prefix)
    full_blocker = resolve_id(blocker_id, state.prefix)
    Bee.Graph.remove_dependency(state.dep_graph, full_id, full_blocker)
    Bee.Store.remove_dependency(state.conn, full_id, full_blocker)
    maybe_export(state)
    {:reply, :ok, state}
  end

  def handle_call({:lock, id, opts}, _from, state) do
    full = resolve_id(id, state.prefix)

    # Ensure the locking agent exists in agents table (FK integrity)
    if locked_by = Keyword.get(opts, :locked_by) do
      Bee.Agents.insert_agent(state.conn, locked_by)
      Bee.World.add_agent(state.alloc_graph, locked_by)
    end

    result =
      case Bee.Lock.acquire(state.conn, full, opts) do
        {:ok, _} = ok ->
          maybe_export(state)
          ok

        {:error, reason} ->
          {:error, classify_write_error(reason)}
      end

    {:reply, result, state}
  end

  def handle_call({:unlock, id}, _from, state) do
    full = resolve_id(id, state.prefix)
    Bee.Lock.release(state.conn, full)
    maybe_export(state)
    {:reply, :ok, state}
  end

  def handle_call({:register_project, id, attrs}, _from, state) do
    result = Bee.Agents.insert_project(state.conn, id, attrs)
    Bee.World.add_project(state.alloc_graph, id)
    {:reply, result, state}
  end

  def handle_call({:register_agent, id, attrs}, _from, state) do
    result = Bee.Agents.insert_agent(state.conn, id, attrs)
    Bee.World.add_agent(state.alloc_graph, id)
    {:reply, result, state}
  end

  def handle_call({:assign, issue_id, agent_id}, _from, state) do
    full = resolve_id(issue_id, state.prefix)
    Bee.Agents.assign_issue(state.conn, full, agent_id)
    Bee.World.assign(state.alloc_graph, full, agent_id)
    maybe_export(state)
    {:reply, :ok, state}
  end

  def handle_call({:join_project, agent_id, project_id}, _from, state) do
    Bee.Agents.add_project_agent(state.conn, project_id, agent_id)
    Bee.World.join_project(state.alloc_graph, agent_id, project_id)
    {:reply, :ok, state}
  end

  def handle_call(:who_blocks_whom, _from, state) do
    result = Bee.World.who_blocks_whom(state.dep_graph, state.alloc_graph)
    {:reply, result, state}
  end

  def handle_call({:agent_load, agent_id}, _from, state) do
    result = Bee.World.agent_load(state.alloc_graph, agent_id, state.conn)
    {:reply, result, state}
  end

  def handle_call(:bottlenecks, _from, state) do
    result = Bee.World.bottlenecks(state.dep_graph, state.alloc_graph, state.conn)
    {:reply, result, state}
  end

  def handle_call({:import_jsonl, path}, _from, state) do
    result = Bee.Export.import_jsonl(state.conn, path, state.prefix)
    Bee.Graph.rebuild(state.dep_graph, state.conn)
    Bee.World.rebuild(state.alloc_graph, state.conn)
    maybe_export(state)
    {:reply, result, state}
  end

  def handle_call(:prefix, _from, state), do: {:reply, state.prefix, state}

  @impl true
  def handle_info(:sweep_locks, state) do
    swept = Bee.Lock.sweep_expired(state.conn)
    if swept > 0, do: Logger.info("Swept #{swept} expired locks")
    schedule_lock_sweep()
    {:noreply, state}
  end

  @impl true
  def handle_info(:checkpoint, state) do
    :ok = Bee.Store.wal_checkpoint(state.conn, :passive)
    maybe_log_wal_size(state.db_path)
    schedule_checkpoint()
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # AD-23: Stop the reader pool first so all read connections release
    # the WAL before the writer's TRUNCATE checkpoint. On a brutal kill
    # this does not run; the next boot's PASSIVE timer recovers.
    if Map.has_key?(state, :pool_pid) and is_pid(state[:pool_pid]) do
      try do
        Supervisor.stop(state.pool_pid, :shutdown)
      rescue
        e -> Logger.warning("Pool stop at terminate failed: #{inspect(e)}")
      end
    end

    # AD-23: TRUNCATE checkpoint succeeds here because the reader pool
    # is now dead — no persistent readers hold the WAL.
    try do
      Bee.Store.wal_checkpoint(state.conn, :truncate)
    rescue
      e -> Logger.warning("TRUNCATE checkpoint at terminate failed: #{inspect(e)}")
    end

    # AD-17: final JSONL flush on orderly/trapped exit
    maybe_export(state)

    Exqlite.Sqlite3.close(state.conn)
    :digraph.delete(state.dep_graph)
    :digraph.delete(state.alloc_graph)
    :ok
  end

  # --- Helpers ---

  defp maybe_export(%{jsonl_path: nil}), do: :ok
  defp maybe_export(%{export_mode: :disabled}), do: :ok

  defp maybe_export(state) do
    try do
      Bee.Export.export(state.conn, state.jsonl_path)
    rescue
      e -> Logger.warning("JSONL export failed: #{inspect(e)}")
    end
  end

  defp schedule_lock_sweep do
    Process.send_after(self(), :sweep_locks, @lock_sweep_interval_ms)
  end

  defp schedule_checkpoint do
    Process.send_after(self(), :checkpoint, @checkpoint_interval_ms)
  end

  defp maybe_log_wal_size(db_path) do
    wal_path = db_path <> "-wal"

    case File.stat(wal_path) do
      {:ok, %{size: size}} when size > @wal_threshold_bytes ->
        Logger.warning("Bee WAL exceeded threshold: #{div(size, 1_000_000)}MB (#{wal_path})")

      _ ->
        :ok
    end
  end

  # A SQLite FOREIGN KEY violation on a write that references an issue means the
  # target issue no longer exists (GC-3353: comment/lock against a deleted
  # issue). Translate that raw driver error into a structured `:not_found` so
  # callers get a clean not-found instead of a crashed GenServer. Structured
  # atoms (`:already_locked`, `:cycle`) and any other reason pass through.
  defp classify_write_error(reason) when is_binary(reason) do
    if reason =~ ~r/FOREIGN KEY/i, do: :not_found, else: reason
  end

  defp classify_write_error(reason), do: reason

  defp resolve_id(id, prefix), do: Bee.Id.to_prefixed(id, prefix)

  defp read_pool_name(opts) do
    base = Keyword.get(opts, :name, Bee.Repo)
    :"#{base}.ReadPool"
  end

  defp read_with_pool(state, lane, fun) do
    case state do
      %{pool_pid: pid, pool_name: pool_name} when is_pid(pid) ->
        actual_pool =
          case lane do
            :fast -> Bee.Read.Pool.fast_pool_name(pool_name)
            :compute -> Bee.Read.Pool.compute_pool_name(pool_name)
          end

        NimblePool.checkout!(
          actual_pool,
          nil,
          fn _from, conn ->
            try do
              {fun.(conn), conn}
            rescue
              e -> {{:error, {:read_failed, e}}, conn}
            end
          end,
          :infinity
        )

      _ ->
        fun.(state.conn)
    end
  end
  defp format_parent(parent, prefix), do: Bee.Id.format_parent(parent, prefix)

  defp normalize_update_attrs(attrs, issue_id, state) do
    attrs = Map.new(attrs)

    attrs =
      case {Map.fetch(attrs, :type), Map.has_key?(attrs, :issue_type)} do
        {{:ok, type}, false} -> attrs |> Map.delete(:type) |> Map.put(:issue_type, type)
        _ -> Map.delete(attrs, :type)
      end

    attrs =
      if Map.has_key?(attrs, :parent) do
        Map.update!(attrs, :parent, &format_parent(&1, state.prefix))
      else
        attrs
      end

    case validate_parent_update(attrs, issue_id, state.conn) do
      :ok -> {:ok, attrs}
      {:error, _reason} = error -> error
    end
  end

  defp validate_parent_update(attrs, issue_id, conn) do
    case Map.fetch(attrs, :parent) do
      {:ok, ^issue_id} ->
        {:error, :self_parent}

      {:ok, parent} when is_binary(parent) ->
        if parent_cycle?(conn, parent, issue_id) do
          {:error, :parent_cycle}
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  defp parent_cycle?(conn, current_parent, target_id) do
    case Bee.Store.issue_parent(conn, current_parent) do
      {:ok, ^target_id} ->
        true

      {:ok, nil} ->
        false

      {:ok, next_parent} when is_binary(next_parent) ->
        parent_cycle?(conn, next_parent, target_id)

      _ ->
        false
    end
  end

  defp label_list(nil), do: []
  defp label_list(label) when is_binary(label), do: [label]
  defp label_list(labels) when is_list(labels), do: labels

  defp maybe_seed_from_jsonl(_conn, nil, _prefix), do: :ok

  defp maybe_seed_from_jsonl(conn, jsonl_path, prefix) do
    with true <- File.exists?(jsonl_path),
         {:ok, []} <- Bee.Store.list_issues_raw(conn) do
      Logger.info("Seeding from #{jsonl_path}")
      Bee.Export.import_jsonl(conn, jsonl_path, prefix)
      :ok
    else
      _ -> :ok
    end
  end
end
