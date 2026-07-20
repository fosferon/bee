defmodule Bee.Repo do
  @moduledoc false
  use GenServer
  require Logger

  @lock_sweep_interval_ms 60_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    db_path = Keyword.fetch!(opts, :db_path)
    prefix = Keyword.fetch!(opts, :prefix)
    jsonl_path = Keyword.get(opts, :jsonl_path)

    db_path |> Path.dirname() |> File.mkdir_p!()

    {:ok, conn} = Exqlite.Sqlite3.open(db_path)
    :ok = Bee.Store.init_schema(conn)

    dep_graph = Bee.Graph.new()
    alloc_graph = Bee.World.new()

    # Auto-import JSONL on first boot (empty DB + file exists)
    maybe_seed_from_jsonl(conn, jsonl_path, prefix)

    Bee.Graph.rebuild(dep_graph, conn)
    Bee.World.rebuild(alloc_graph, conn)

    schedule_lock_sweep()

    {:ok,
     %{
       conn: conn,
       dep_graph: dep_graph,
       alloc_graph: alloc_graph,
       prefix: prefix,
       jsonl_path: jsonl_path,
       export_mode: :on_write
     }}
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
    {:reply, Bee.Store.get_issue(state.conn, full), state}
  end

  def handle_call({:list, opts}, _from, state) do
    {:reply, Bee.Store.list_issues(state.conn, opts), state}
  end

  def handle_call({:count, opts}, _from, state) do
    {:reply, Bee.Store.count_issues(state.conn, opts), state}
  end

  def handle_call({:tree_page, opts}, _from, state) do
    {:reply, Bee.Store.list_tree_page(state.conn, opts), state}
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
    Bee.Store.insert_comment(state.conn, full, text, opts)
    maybe_export(state)
    {:reply, :ok, state}
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

    result = Bee.Lock.acquire(state.conn, full, opts)
    if match?({:ok, _}, result), do: maybe_export(state)
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
  def terminate(_reason, state) do
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

  defp resolve_id(id, prefix) when is_integer(id), do: "#{prefix}-#{id}"

  defp resolve_id(id, prefix) when is_binary(id) do
    if String.contains?(id, "-") do
      id
    else
      case Integer.parse(id) do
        {_n, ""} -> "#{prefix}-#{id}"
        _ -> id
      end
    end
  end

  defp resolve_id(id, _prefix), do: to_string(id)

  defp format_parent(nil, _prefix), do: nil
  defp format_parent("", _prefix), do: nil
  defp format_parent(parent, prefix) when is_integer(parent), do: "#{prefix}-#{parent}"

  defp format_parent(parent, prefix) when is_binary(parent) do
    if String.contains?(parent, "-"), do: parent, else: "#{prefix}-#{parent}"
  end

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
