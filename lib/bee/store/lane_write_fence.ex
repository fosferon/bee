defmodule Bee.Store.LaneWriteFence do
  @moduledoc """
  Positive, Bee-owned classification of the complete target set of a legacy
  mutation. Called in Repo's mailbox using its writer connection. A read of
  this classification is diagnostic; Repo rechecks every actual write.

  Once enabled, linked targets require a future admitted owner command. An
  absent lane field in a request is never evidence that its targets are neutral.
  """

  @reads ~w(get get_comments list count query ancestors ask list_intents list_measures tree_page ready traverse candidates list_projects list_agents who_blocks_whom agent_load critical_path rollup bottlenecks prefix reconcile_lane_issue)a
  @mutations ~w(create update comment block unblock lock unlock assign measure register_project register_agent join_project register_measure register_intent remove_intent import_jsonl sweep_expired_locks upsert_project_registry backfill_projects)a

  def reads, do: @reads
  def mutations, do: @mutations

  def classify(conn, request, prefix) do
    with {:ok, targets, prepared} <- targets(conn, request, prefix),
         {:ok, bindings} <- bindings(conn, targets) do
      {:ok,
       %{
         targets: targets,
         bindings: bindings,
         request: prepared,
         classification:
           if(bindings == [],
             do: :legacy_only_excluded_from_lane_truth,
             else: :prohibited_once_lane_bound
           )
       }}
    end
  end

  def legacy_admission(conn, request, prefix) do
    case classify(conn, request, prefix) do
      {:ok, %{bindings: [], request: prepared}} -> {:ok, prepared}
      {:ok, _} -> {:error, :lane_bound_owner_command_required}
      {:error, _} = error -> error
    end
  end

  def read?(request), do: operation(request) in @reads
  def operation(request) when is_tuple(request) and tuple_size(request) > 0, do: elem(request, 0)
  def operation(request) when is_atom(request), do: request
  def operation(_), do: nil

  defp targets(_conn, {:create, _title, opts} = request, prefix) when is_list(opts) do
    if Keyword.keyword?(opts),
      do: finish([Keyword.get(opts, :parent)], request, prefix),
      else: invalid()
  end

  defp targets(conn, {:update, id, attrs} = request, prefix) when is_map(attrs) do
    with {:ok, _} <- full_id(id, prefix),
         {:ok, ids, _} <-
           finish([id, Map.get(attrs, :parent, Map.get(attrs, "parent"))], request, prefix),
         {:ok, rows} <- query(conn, "SELECT parent FROM issues WHERE id = ?", [hd(ids)]) do
      finish(ids ++ Enum.map(rows, &hd/1), request, prefix)
    end
  end

  defp targets(_conn, {op, id, _} = request, prefix) when op in [:measure, :assign],
    do: required([id], request, prefix)

  defp targets(_conn, {:comment, id, _, _} = request, prefix), do: required([id], request, prefix)
  defp targets(_conn, {:lock, id, _} = request, prefix), do: required([id], request, prefix)
  defp targets(_conn, {:unlock, id} = request, prefix), do: required([id], request, prefix)

  defp targets(_conn, {op, id, other} = request, prefix) when op in [:block, :unblock],
    do: required([id, other], request, prefix)

  defp targets(_conn, {op, id, other, _} = request, prefix) when op in [:block, :unblock],
    do: required([id, other], request, prefix)

  defp targets(conn, {:register_project, project, _} = request, prefix),
    do:
      queried_targets(
        conn,
        "SELECT id FROM issues WHERE project_id = ?",
        [project],
        request,
        prefix
      )

  defp targets(conn, {:upsert_project_registry, project, _, _} = request, prefix),
    do:
      queried_targets(
        conn,
        "SELECT id FROM issues WHERE project_id = ?",
        [project],
        request,
        prefix
      )

  defp targets(conn, {:backfill_projects, rows, run_id, now}, prefix)
       when is_list(rows) and is_binary(run_id) and is_binary(now) do
    if Enum.all?(
         rows,
         &match?(
           %{id: _, project_id: project, rule: rule}
           when is_binary(project) and is_binary(rule),
           &1
         )
       ) do
      Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, ids} ->
        case targets(conn, {:update, row.id, %{project_id: row.project_id}}, prefix) do
          {:ok, current, _} -> {:cont, {:ok, ids ++ current}}
          {:error, _} = error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, ids} -> finish(ids, {:backfill_projects, rows, run_id, now}, prefix)
        {:error, _} = error -> error
      end
    else
      invalid()
    end
  end

  defp targets(conn, {:register_agent, agent, _} = request, prefix),
    do:
      queried_targets(
        conn,
        "SELECT id FROM issues WHERE assigned_to = ?",
        [agent],
        request,
        prefix
      )

  defp targets(conn, {:join_project, agent, project} = request, prefix),
    do:
      queried_targets(
        conn,
        "SELECT id FROM issues WHERE assigned_to = ? OR project_id = ?",
        [agent, project],
        request,
        prefix
      )

  defp targets(conn, {:register_measure, name, _, _} = request, prefix),
    do:
      queried_targets(
        conn,
        "SELECT issue_id FROM measurements WHERE measure = ?",
        [name],
        request,
        prefix
      )

  # Intent definitions are query configuration; they do not mutate issues or lane links.
  defp targets(_conn, {op, _, _} = request, prefix) when op == :register_intent,
    do: finish([], request, prefix)

  defp targets(_conn, {:remove_intent, _} = request, prefix), do: finish([], request, prefix)

  defp targets(conn, :sweep_expired_locks, prefix) do
    with {:ok, rows} <-
           query(conn, "SELECT issue_id FROM locks WHERE expires_at < ?", [
             DateTime.utc_now() |> DateTime.to_iso8601()
           ]) do
      ids = Enum.map(rows, &hd/1)
      finish(ids, {:sweep_expired_targets, ids}, prefix)
    end
  end

  defp targets(conn, {:import_jsonl, path}, prefix) do
    with {:ok, entries} <- Bee.Export.read_entries(path),
         true <- Enum.all?(entries, &(is_map(&1) and is_binary(&1["id"]))) do
      ids =
        Enum.flat_map(entries, fn entry ->
          deps = Map.get(entry, "dependencies", [])
          comments = Map.get(entry, "comments", [])

          if is_list(deps) and is_list(comments) and Enum.all?(deps ++ comments, &is_map/1) do
            [entry["id"], entry["parent"]] ++
              Enum.flat_map(deps, &[&1["issue_id"], &1["depends_on_id"]]) ++
              Enum.map(comments, & &1["issue_id"])
          else
            [:invalid_import_target]
          end
        end)

      with {:ok, ids, _} <- finish(ids, {:import_entries, entries}, prefix),
           {:ok, collateral} <- existing_import_targets(conn, Enum.map(entries, & &1["id"])) do
        finish(ids ++ collateral, {:import_entries, entries}, prefix)
      end
    else
      false -> invalid()
      {:error, _} = error -> error
    end
  end

  defp targets(_, _, _), do: {:error, :unclassified_bee_mutation}

  defp existing_import_targets(conn, ids) do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
      with {:ok, parents} <- query(conn, "SELECT parent FROM issues WHERE id = ?", [id]),
           {:ok, edges} <-
             query(
               conn,
               "SELECT issue_id, depends_on_id FROM dependencies WHERE issue_id = ? OR depends_on_id = ?",
               [id, id]
             ) do
        {:cont, {:ok, acc ++ List.flatten(parents ++ edges)}}
      else
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp queried_targets(conn, sql, params, request, prefix) do
    with {:ok, rows} <- query(conn, sql, params),
         do: finish(Enum.map(rows, &hd/1), request, prefix)
  end

  defp required(ids, request, prefix) do
    if Enum.any?(ids, &is_nil/1), do: invalid(), else: finish(ids, request, prefix)
  end

  defp finish(ids, request, prefix) do
    ids = Enum.reject(ids, &is_nil/1)

    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
      case full_id(id, prefix) do
        {:ok, full} -> {:cont, {:ok, [full | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, Enum.uniq(Enum.reverse(ids)), request}
      {:error, _} = error -> error
    end
  end

  defp full_id(id, prefix) when is_integer(id) and id > 0,
    do: {:ok, prefix <> "-" <> Integer.to_string(id)}

  defp full_id(id, prefix) when is_binary(id) do
    full = Bee.Id.to_prefixed(id, prefix)

    case Bee.Id.parse(full) do
      {:ok, n} when n > 0 -> {:ok, full}
      _ -> invalid()
    end
  rescue
    _ in ArgumentError -> invalid()
  end

  defp full_id(_, _), do: invalid()
  defp invalid, do: {:error, :invalid_lane_mutation}

  defp bindings(conn, ids) do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
      case query(
             conn,
             "SELECT lane_id FROM lane_issue_links WHERE issue_id = ? ORDER BY lane_id",
             [id]
           ) do
        {:ok, rows} ->
          {:cont, {:ok, acc ++ Enum.map(rows, fn [lane] -> %{issue_id: id, lane_id: lane} end)}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
  end

  defp query(conn, sql, params) do
    with {:ok, stmt} <- Exqlite.Sqlite3.prepare(conn, sql) do
      try do
        with :ok <- Exqlite.Sqlite3.bind(stmt, params), do: collect(conn, stmt, [])
      after
        Exqlite.Sqlite3.release(conn, stmt)
      end
    end
  end

  defp collect(conn, stmt, acc) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, row} -> collect(conn, stmt, [row | acc])
      :done -> {:ok, Enum.reverse(acc)}
      {:error, reason} -> {:error, {:lane_classification_indeterminate, reason}}
    end
  end
end
