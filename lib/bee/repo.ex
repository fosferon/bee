defmodule Bee.Repo do
  @moduledoc false
  use GenServer
  require Logger

  @checkpoint_interval_ms 60_000
  @wal_threshold_bytes 10_000_000
  @export_debounce_ms 5_000
  @export_flush_bound_ms 10_000

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

    skip_migration? = Keyword.get(opts, :skip_migration?, false)

    migration_result =
      if skip_migration? do
        :ok
      else
        Bee.Store.Migrate.run_at_boot(db_path)
      end

    case migration_result do
      :ok ->
        {:ok, conn} = Exqlite.Sqlite3.open(db_path)
        :ok = Bee.Store.init_schema(conn)

        dep_graph = Bee.Graph.new()
        alloc_graph = Bee.World.new()

        # Auto-import JSONL on first boot (empty DB + file exists)
        maybe_seed_from_jsonl(conn, jsonl_path, prefix)

        Bee.Graph.rebuild(dep_graph, conn)
        Bee.World.rebuild(alloc_graph, conn)

        # Sweeper is a separate process (Story 3.5) — no timer needed here.
        schedule_checkpoint()

        # Start the reader pool (AD-2, AD-3). When running under
        # Bee.Supervisor (start_pool?: false), the pool is a separate
        # child. When standalone (tests), Repo starts it internally.
        pool_name = read_pool_name(opts)
        start_pool? = Keyword.get(opts, :start_pool?, true)

        pool_pid =
          if start_pool? do
            {:ok, pid} = Bee.Read.Pool.start_link(db_path: db_path, name: pool_name)
            pid
          else
            nil
          end

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
           pool_name: pool_name,
           export_timer: nil
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  # --- GenServer calls ---

  @impl true
  def handle_call(:conn, _from, state), do: {:reply, state.conn, state}

  def handle_call({:create, title, opts}, _from, state) do
    result =
      transaction(state.conn, fn ->
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

        with {:ok, issue} <- Bee.Store.insert_issue(state.conn, attrs),
             {:ok, _seq} <-
               Bee.Store.Events.record(state.conn, id, "issue.created",
                 actor: attrs.created_by,
                 fields:
                   Map.take(attrs, [
                     :id,
                     :title,
                     :description,
                     :priority,
                     :issue_type,
                     :parent,
                     :project_id,
                     :created_by
                   ])
               ) do
          {:ok, {id, attrs, issue}}
        end
      end)

    case result do
      {:ok, {id, attrs, issue}} ->
        Bee.Graph.add_vertex(state.dep_graph, id)
        Bee.World.add_issue(state.alloc_graph, id, attrs.project_id)
        {:reply, {:ok, issue}, schedule_export(state)}

      {:error, reason} ->
        {:reply, {:error, classify_write_error(reason)}, state}
    end
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

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:count, opts}, _from, state) do
    case Bee.Store.validate_opts(opts) do
      :ok ->
        lane = Bee.Query.Classifier.classify(:count)
        result = read_with_pool(state, lane, fn conn -> Bee.Store.count_issues(conn, opts) end)
        {:reply, result, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:query, spec}, _from, state) do
    case Bee.Query.Spec.new(spec) do
      {:ok, spec} ->
        lane = Bee.Query.Classifier.classify(spec)

        result =
          read_with_pool(state, lane, fn conn -> Bee.Query.Interpreter.execute(conn, spec) end)

        {:reply, result, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:ask, intent, opts}, _from, state) do
    result =
      with {:ok, spec} <- resolve_intent(state.conn, intent, opts) do
        lane = Bee.Query.Classifier.classify(spec)
        read_with_pool(state, lane, fn conn -> Bee.Query.Interpreter.execute(conn, spec) end)
      end

    if match?({:ok, _}, result), do: record_intent_usage_async(self(), intent)

    {:reply, result, state}
  end

  def handle_call({:register_intent, name, spec}, _from, state) do
    result = Bee.Intent.Registry.register(state.conn, name, spec)
    {:reply, result, state}
  end

  def handle_call({:remove_intent, name}, _from, state) do
    result = Bee.Intent.Registry.remove(state.conn, name)
    {:reply, result, state}
  end

  def handle_call({:register_measure, name, unit, opts}, _from, state) do
    result =
      transaction(state.conn, fn ->
        case Bee.Store.Measurements.register(state.conn, name, unit, opts) do
          :ok -> {:ok, :registered}
          {:error, _reason} = error -> error
        end
      end)

    case result do
      {:ok, :registered} -> {:reply, :ok, state}
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def handle_call({:measure, issue_id, attrs}, _from, state) do
    full = resolve_id(issue_id, state.prefix)

    result =
      transaction(state.conn, fn ->
        with {:ok, _issue} <- Bee.Store.get_issue(state.conn, full),
             {:ok, measurement} <- Bee.Store.Measurements.prepare(state.conn, attrs),
             {:ok, seq} <-
               Bee.Store.Events.record(state.conn, full, "measurement.recorded",
                 fields: fn seq ->
                   %{measure: Map.put(measurement, :seq, seq)}
                 end
               ),
             :ok <- Bee.Store.Measurements.record(state.conn, full, seq, measurement) do
          {:ok, :recorded}
        end
      end)

    case result do
      {:ok, :recorded} -> {:reply, :ok, schedule_export(state)}
      {:error, reason} -> {:reply, {:error, classify_write_error(reason)}, state}
    end
  end

  def handle_call({:tree_page, opts}, _from, state) do
    case Bee.Store.validate_opts(opts) do
      :ok ->
        lane = Bee.Query.Classifier.classify(:tree_page)
        result = read_with_pool(state, lane, fn conn -> Bee.Store.list_tree_page(conn, opts) end)
        {:reply, result, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:ready, _opts}, _from, state) do
    result =
      read_with_pool(state, :fast, fn conn ->
        issues =
          conn
          |> Bee.Graph.Ready.issue_ids()
          |> Enum.flat_map(fn id ->
            case Bee.Store.get_issue(conn, id) do
              {:ok, issue} -> [issue]
              _ -> []
            end
          end)

        {:ok, issues}
      end)

    {:reply, result, state}
  end

  def handle_call({:update, id, attrs}, _from, state) do
    full = resolve_id(id, state.prefix)

    case normalize_update_attrs(attrs, full, state) do
      {:ok, normalized_attrs} when map_size(normalized_attrs) == 0 ->
        {:reply, :ok, state}

      {:ok, normalized_attrs} ->
        {measure_attrs, issue_attrs} = Map.pop(normalized_attrs, :measure)

        result =
          transaction(state.conn, fn ->
            with {:ok, measurement} <- prepare_measurement(state.conn, measure_attrs),
                 :ok <- Bee.Store.update_issue(state.conn, full, issue_attrs),
                 {:ok, seq} <-
                   Bee.Store.Events.record(state.conn, full, "issue.updated",
                     fields: fn seq ->
                       fields = Map.drop(issue_attrs, [:labels])

                       if measurement do
                         Map.put(fields, :measure, Map.put(measurement, :seq, seq))
                       else
                         fields
                       end
                     end
                   ),
                 :ok <- record_measurement(state.conn, full, seq, measurement) do
              {:ok, :updated}
            end
          end)

        case result do
          {:ok, :updated} -> {:reply, :ok, schedule_export(state)}
          {:error, reason} -> {:reply, {:error, classify_write_error(reason)}, state}
        end

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:comment, id, text, opts}, _from, state) do
    full = resolve_id(id, state.prefix)

    result =
      transaction(state.conn, fn ->
        with :ok <- Bee.Store.insert_comment(state.conn, full, text, opts),
             {:ok, _seq} <-
               Bee.Store.Events.record(state.conn, full, "issue.commented",
                 actor: Keyword.get(opts, :author),
                 fields: %{body: text}
               ) do
          {:ok, :commented}
        end
      end)

    case result do
      {:ok, :commented} -> {:reply, :ok, schedule_export(state)}
      {:error, reason} -> {:reply, {:error, classify_write_error(reason)}, state}
    end
  end

  def handle_call({:block, id, blocker_id}, _from, state) do
    block_dependency(id, blocker_id, :blocks, state)
  end

  def handle_call({:block, id, blocker_id, opts}, _from, state) when is_list(opts) do
    if Keyword.keyword?(opts) do
      case Keyword.fetch(opts, :type) do
        {:ok, type} -> block_dependency(id, blocker_id, type, state)
        :error -> block_dependency(id, blocker_id, :blocks, state)
      end
    else
      {:reply, {:error, :unknown_dep_type}, state}
    end
  end

  def handle_call({:block, _id, _blocker_id, _opts}, _from, state),
    do: {:reply, {:error, :unknown_dep_type}, state}

  def handle_call({:traverse, id, opts}, _from, state) when is_list(opts) do
    full_id = resolve_id(id, state.prefix)

    result =
      read_with_pool(state, :compute, fn conn ->
        with {:ok, ids} <- Bee.Store.Deps.traverse(conn, full_id, opts) do
          {:ok, Enum.map(ids, &Bee.Id.parse!/1)}
        end
      end)

    {:reply, result, state}
  end

  def handle_call({:traverse, _id, _opts}, _from, state),
    do: {:reply, {:error, :invalid_spec}, state}

  def handle_call({:candidates, id}, _from, state) do
    full_id = resolve_id(id, state.prefix)

    result =
      read_with_pool(state, :compute, fn conn -> Bee.Query.Candidates.for_issue(conn, full_id) end)

    {:reply, result, state}
  end

  def handle_call({:unblock, id, blocker_id}, _from, state) do
    unblock_dependency(id, blocker_id, :blocks, state)
  end

  def handle_call({:unblock, id, blocker_id, opts}, _from, state) when is_list(opts) do
    if Keyword.keyword?(opts) do
      case Keyword.fetch(opts, :type) do
        {:ok, type} -> unblock_dependency(id, blocker_id, type, state)
        :error -> unblock_dependency(id, blocker_id, :blocks, state)
      end
    else
      {:reply, {:error, :unknown_dep_type}, state}
    end
  end

  def handle_call({:unblock, _id, _blocker_id, _opts}, _from, state),
    do: {:reply, {:error, :unknown_dep_type}, state}

  def handle_call({:lock, id, opts}, _from, state) do
    full = resolve_id(id, state.prefix)

    result =
      transaction(state.conn, fn ->
        if locked_by = Keyword.get(opts, :locked_by) do
          Bee.Agents.insert_agent(state.conn, locked_by)
        end

        with {:ok, lock} <- Bee.Lock.acquire(state.conn, full, opts),
             {:ok, _seq} <-
               Bee.Store.Events.record(state.conn, full, "lock.acquired",
                 actor: lock.locked_by,
                 fields: Map.take(lock, [:locked_by, :locked_at, :expires_at])
               ) do
          {:ok, lock}
        end
      end)

    case result do
      {:ok, lock} ->
        if lock.locked_by, do: Bee.World.add_agent(state.alloc_graph, lock.locked_by)
        {:reply, {:ok, lock}, schedule_export(state)}

      {:error, reason} ->
        {:reply, {:error, classify_write_error(reason)}, state}
    end
  end

  def handle_call({:unlock, id}, _from, state) do
    full = resolve_id(id, state.prefix)

    result =
      transaction(state.conn, fn ->
        case Bee.Lock.get(state.conn, full) do
          nil ->
            {:ok, :unchanged}

          lock ->
            with :ok <- Bee.Lock.release(state.conn, full),
                 {:ok, _seq} <-
                   Bee.Store.Events.record(state.conn, full, "lock.released",
                     actor: Map.get(lock, "locked_by"),
                     fields: %{}
                   ) do
              {:ok, :unlocked}
            end
        end
      end)

    case result do
      {:ok, :unlocked} -> {:reply, :ok, schedule_export(state)}
      {:ok, :unchanged} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, classify_write_error(reason)}, state}
    end
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

    result =
      transaction(state.conn, fn ->
        with {:ok, issue} <- Bee.Store.get_issue(state.conn, full) do
          if issue.assigned_to == agent_id do
            {:ok, :unchanged}
          else
            with :ok <- Bee.Agents.assign_issue(state.conn, full, agent_id),
                 {:ok, _seq} <-
                   Bee.Store.Events.record(state.conn, full, "issue.updated",
                     fields: %{assigned_to: agent_id}
                   ) do
              {:ok, :assigned}
            end
          end
        end
      end)

    case result do
      {:ok, :assigned} ->
        Bee.World.assign(state.alloc_graph, full, agent_id)
        {:reply, :ok, schedule_export(state)}

      {:ok, :unchanged} ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, classify_write_error(reason)}, state}
    end
  end

  def handle_call({:join_project, agent_id, project_id}, _from, state) do
    Bee.Agents.add_project_agent(state.conn, project_id, agent_id)
    Bee.World.join_project(state.alloc_graph, agent_id, project_id)
    {:reply, :ok, state}
  end

  def handle_call(:who_blocks_whom, _from, state) do
    result = read_with_pool(state, :compute, &Bee.Graph.Allocation.who_blocks_whom/1)
    {:reply, result, state}
  end

  def handle_call({:agent_load, agent_id}, _from, state) do
    result = read_with_pool(state, :compute, &Bee.Graph.Allocation.agent_load(&1, agent_id))
    {:reply, result, state}
  end

  def handle_call(:critical_path, _from, state) do
    result =
      read_with_pool(state, :compute, fn conn ->
        {:ok, conn |> Bee.Store.Deps.critical_path() |> Enum.map(&Bee.Id.parse!/1)}
      end)

    {:reply, result, state}
  end

  def handle_call(:bottlenecks, _from, state) do
    result = read_with_pool(state, :compute, &Bee.Graph.Allocation.bottlenecks/1)
    {:reply, result, state}
  end

  def handle_call({:import_jsonl, path}, _from, state) do
    result = Bee.Export.import_jsonl(state.conn, path, state.prefix)
    Bee.Graph.rebuild(state.dep_graph, state.conn)
    Bee.World.rebuild(state.alloc_graph, state.conn)
    state = schedule_export(state)
    {:reply, result, state}
  end

  def handle_call(:prefix, _from, state), do: {:reply, state.prefix, state}

  def handle_call(:sweep_expired_locks, _from, state) do
    # Story 3.5: Sweeper dispatches through the writer (no own connection).
    # One event per expired lock, release + event in one transaction (AD-19).
    swept = Bee.Lock.sweep_expired(state.conn)
    state = schedule_export(state)
    {:reply, swept, state}
  end

  @impl true
  def handle_info(:checkpoint, state) do
    :ok = Bee.Store.wal_checkpoint(state.conn, :passive)
    maybe_log_wal_size(state.db_path)
    schedule_checkpoint()
    {:noreply, state}
  end

  @impl true
  def handle_info(:flush_export, state) do
    flush_export(state)
    {:noreply, %{state | export_timer: nil}}
  end

  # Trapped exit from linked process (Task.async for flush, pool, etc.)
  @impl true
  def handle_info({:EXIT, _pid, _reason}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast({:record_intent_usage, name, kind}, state) do
    _ = Bee.Store.Intents.record_usage(state.conn, name, kind)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # AD-23: Stop the reader pool first (if we own it) so all read
    # connections release the WAL before the writer's TRUNCATE checkpoint.
    # Under Bee.Supervisor, the pool is a separate child that dies first
    # via reverse-order shutdown — so we only stop it here if we started it.
    pool_pid = Map.get(state, :pool_pid)

    if pool_pid != nil and Process.alive?(pool_pid) do
      try do
        Supervisor.stop(pool_pid, :shutdown)
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

    # AD-17: final JSONL flush on orderly/trapped exit (bounded, atomic)
    # On brutal kill this does NOT run; the window is lost but recoverable
    # by re-export since JSONL is derived (Story 3.3 shutdown invariant).
    if state[:export_timer] do
      Process.cancel_timer(state[:export_timer])
    end

    flush_export(state)

    Exqlite.Sqlite3.close(state.conn)
    :digraph.delete(state.dep_graph)
    :digraph.delete(state.alloc_graph)
    :ok
  end

  # --- Helpers ---

  defp block_dependency(id, blocker_id, type, state) do
    full_id = resolve_id(id, state.prefix)
    full_blocker = resolve_id(blocker_id, state.prefix)

    result =
      transaction(state.conn, fn ->
        with :ok <- Bee.Dependency.Type.validate(type),
             :ok <- Bee.Store.Acyclic.dependency(state.conn, full_id, full_blocker),
             :ok <- Bee.Store.insert_dependency(state.conn, full_id, full_blocker, type),
             {:ok, _seq} <-
               Bee.Store.Events.record(state.conn, full_id, "dep.added",
                 fields: %{
                   depends_on_id: full_blocker,
                   dep_type: Bee.Dependency.Type.storage_name(type)
                 }
               ) do
          {:ok, :blocked}
        end
      end)

    case result do
      {:ok, :blocked} ->
        if type in Bee.Dependency.Type.gating() do
          :ok = Bee.Graph.add_dependency(state.dep_graph, full_id, full_blocker)
        end

        {:reply, :ok, schedule_export(state)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp transaction(conn, fun) do
    with :ok <- execute(conn, "BEGIN IMMEDIATE"),
         {:ok, result} <- fun.(),
         :ok <- execute(conn, "COMMIT") do
      {:ok, result}
    else
      {:error, _reason} = error ->
        _ = execute(conn, "ROLLBACK")
        error
    end
  end

  defp execute(conn, sql) do
    case Exqlite.Sqlite3.execute(conn, sql) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp unblock_dependency(id, blocker_id, type, state) do
    full_id = resolve_id(id, state.prefix)
    full_blocker = resolve_id(blocker_id, state.prefix)

    result =
      transaction(state.conn, fn ->
        with :ok <- Bee.Dependency.Type.validate(type),
             true <- Bee.Store.dependency_exists?(state.conn, full_id, full_blocker, type),
             :ok <- Bee.Store.remove_dependency(state.conn, full_id, full_blocker, type),
             {:ok, _seq} <-
               Bee.Store.Events.record(state.conn, full_id, "dep.removed",
                 fields: %{
                   depends_on_id: full_blocker,
                   dep_type: Bee.Dependency.Type.storage_name(type)
                 }
               ) do
          {:ok, :unblocked}
        else
          false -> {:ok, :unchanged}
          {:error, _reason} = error -> error
        end
      end)

    case result do
      {:ok, :unblocked} ->
        unless Bee.Store.has_gating_dependency?(state.conn, full_id, full_blocker) do
          :ok = Bee.Graph.remove_dependency(state.dep_graph, full_id, full_blocker)
        end

        {:reply, :ok, schedule_export(state)}

      {:ok, :unchanged} ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp schedule_export(%{jsonl_path: nil} = state), do: state
  defp schedule_export(%{export_mode: :disabled} = state), do: state

  defp schedule_export(state) do
    # Cancel any pending debounce timer
    if state[:export_timer] do
      Process.cancel_timer(state[:export_timer])
    end

    # Schedule a new flush after the debounce period
    timer = Process.send_after(self(), :flush_export, @export_debounce_ms)
    %{state | export_timer: timer}
  end

  defp flush_export(%{jsonl_path: nil}), do: :ok
  defp flush_export(%{export_mode: :disabled}), do: :ok

  defp flush_export(state) do
    task =
      Task.async(fn ->
        {:ok, conn} = Exqlite.Sqlite3.open(state.db_path)
        :ok = Bee.Store.configure_pragmas(conn)

        try do
          Bee.Export.export(conn, state.jsonl_path)
        after
          Exqlite.Sqlite3.close(conn)
        end
      end)

    case Task.yield(task, @export_flush_bound_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, :ok} -> :ok
      nil -> {:error, :flush_bound_exceeded}
      {:exit, reason} -> {:error, {:export_crashed, reason}}
    end
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

  defp resolve_intent(_conn, intent, opts) when is_atom(intent),
    do: Bee.Intent.Core.resolve(intent, opts)

  defp resolve_intent(conn, intent, _opts) when is_binary(intent),
    do: Bee.Intent.Registry.resolve(conn, intent)

  defp resolve_intent(_conn, _intent, _opts), do: {:error, :unknown_intent}

  defp record_intent_usage_async(repo, intent) do
    {name, kind} =
      case intent do
        intent when is_atom(intent) -> {Atom.to_string(intent), "core"}
        intent when is_binary(intent) -> {intent, "registered"}
      end

    Task.start(fn -> GenServer.cast(repo, {:record_intent_usage, name, kind}) end)
  end

  defp read_pool_name(opts) do
    case Keyword.get(opts, :pool_name) do
      nil ->
        base = Keyword.get(opts, :name, Bee.Repo)
        :"#{base}.ReadPool"

      name ->
        name
    end
  end

  defp read_with_pool(state, lane, fun) do
    pool_name = Map.get(state, :pool_name)
    pool_pid = Map.get(state, :pool_pid)

    actual_pool =
      case lane do
        :fast -> Bee.Read.Pool.fast_pool_name(pool_name)
        :compute -> Bee.Read.Pool.compute_pool_name(pool_name)
      end

    # Use the pool if it's running (either linked pid or external supervisor child)
    pool_alive? =
      (pool_pid != nil and Process.alive?(pool_pid)) or
        (is_atom(actual_pool) and GenServer.whereis(actual_pool) != nil)

    if pool_alive? do
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
    else
      fun.(state.conn)
    end
  end

  defp format_parent(parent, prefix), do: Bee.Id.format_parent(parent, prefix)

  defp prepare_measurement(_conn, nil), do: {:ok, nil}
  defp prepare_measurement(conn, attrs), do: Bee.Store.Measurements.prepare(conn, attrs)

  defp record_measurement(_conn, _issue_id, _seq, nil), do: :ok

  defp record_measurement(conn, issue_id, seq, measurement),
    do: Bee.Store.Measurements.record(conn, issue_id, seq, measurement)

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
    else
      false ->
        :ok

      {:ok, [_ | _]} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to check DB for seeding from #{jsonl_path}: #{inspect(reason)}")
        :ok
    end
  end
end
