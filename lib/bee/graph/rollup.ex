defmodule Bee.Graph.Rollup do
  @moduledoc false

  @scopes [:tree, :closure, :critical_path]
  @kinds [:estimate, :actual]
  @meanings [:spent, :to_complete]

  @spec compute(Exqlite.Sqlite3.db(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def compute(conn, issue_id, opts) when is_list(opts) do
    opts = Keyword.merge([scope: :tree, kind: :actual, meaning: :spent], opts)

    with :ok <- validate_opts(opts),
         {:ok, _issue} <- Bee.Store.get_issue(conn, issue_id),
         {:ok, rows} <- scope_rows(conn, issue_id, Keyword.fetch!(opts, :scope)),
         rows <- filter_cancelled(rows, Keyword.fetch!(opts, :meaning)),
         values <- latest_effort(conn, Enum.map(rows, & &1.id), Keyword.fetch!(opts, :kind)),
         rows <- select_critical_path(rows, values, conn, issue_id, Keyword.fetch!(opts, :scope)) do
      {:ok, summarize(rows, values)}
    end
  end

  def compute(_conn, _issue_id, _opts), do: {:error, :invalid_rollup}

  defp validate_opts(opts) when is_list(opts) do
    scope = Keyword.get(opts, :scope, :tree)
    kind = Keyword.get(opts, :kind, :actual)
    meaning = Keyword.get(opts, :meaning, :spent)

    if Keyword.keyword?(opts) and Keyword.keys(opts) -- [:scope, :kind, :meaning] == [] and
         scope in @scopes and kind in @kinds and meaning in @meanings do
      :ok
    else
      {:error, :invalid_rollup}
    end
  end

  defp validate_opts(_opts), do: {:error, :invalid_rollup}

  defp scope_rows(conn, issue_id, :tree) do
    query_scope(
      conn,
      """
      WITH RECURSIVE scope(id) AS (
        SELECT ?
        UNION
        SELECT child.id FROM issues child JOIN scope ON child.parent = scope.id
      )
      SELECT issues.id, issues.status FROM scope JOIN issues ON issues.id = scope.id ORDER BY issues.id
      """,
      [issue_id]
    )
  end

  defp scope_rows(conn, issue_id, scope) when scope in [:closure, :critical_path] do
    types = Enum.map(Bee.Dependency.Type.gating(), &Bee.Dependency.Type.storage_name/1)
    placeholders = Enum.map_join(types, ", ", fn _ -> "?" end)

    query_scope(
      conn,
      """
      WITH RECURSIVE scope(id) AS (
        SELECT ?
        UNION
        SELECT dep.depends_on_id
        FROM dependencies dep
        JOIN scope ON dep.issue_id = scope.id
        WHERE dep.dep_type IN (#{placeholders})
      )
      SELECT issues.id, issues.status FROM scope JOIN issues ON issues.id = scope.id ORDER BY issues.id
      """,
      [issue_id | types]
    )
  end

  defp query_scope(conn, sql, params) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    :ok = Exqlite.Sqlite3.bind(stmt, params)

    try do
      {:ok, collect_rows(conn, stmt)}
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  defp latest_effort(_conn, [], _kind), do: %{}

  defp latest_effort(conn, ids, kind) do
    placeholders = Enum.map_join(ids, ", ", fn _ -> "?" end)

    sql = """
    WITH latest AS (
      SELECT issue_id, value,
             ROW_NUMBER() OVER (PARTITION BY issue_id, measure, json_extract(dims, '$.kind') ORDER BY seq DESC) AS row_num
      FROM measurements
      WHERE measure = 'effort' AND json_extract(dims, '$.kind') = ? AND issue_id IN (#{placeholders})
    )
    SELECT issue_id, value FROM latest WHERE row_num = 1
    """

    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    :ok = Exqlite.Sqlite3.bind(stmt, [Atom.to_string(kind) | ids])

    try do
      collect_values(conn, stmt, %{})
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  defp filter_cancelled(rows, :spent), do: rows
  defp filter_cancelled(rows, :to_complete), do: Enum.reject(rows, &(&1.status == "cancelled"))

  defp select_critical_path(rows, _values, _conn, _issue_id, scope) when scope != :critical_path,
    do: rows

  defp select_critical_path(rows, values, _conn, _issue_id, :critical_path)
       when map_size(values) != length(rows),
       do: rows

  defp select_critical_path(rows, values, conn, issue_id, :critical_path) do
    ids = MapSet.new(Enum.map(rows, & &1.id))
    edges = gating_edges(conn, ids)
    {path, _memo} = longest_path(issue_id, edges, values, %{})
    Enum.filter(rows, &(&1.id in path))
  end

  defp gating_edges(conn, ids) do
    types = Enum.map(Bee.Dependency.Type.gating(), &Bee.Dependency.Type.storage_name/1)
    placeholders = Enum.map_join(types, ", ", fn _ -> "?" end)

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT issue_id, depends_on_id FROM dependencies WHERE dep_type IN (#{placeholders})"
      )

    :ok = Exqlite.Sqlite3.bind(stmt, types)

    try do
      collect_edges(conn, stmt, ids, %{})
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  defp longest_path(id, edges, values, memo) do
    case Map.fetch(memo, id) do
      {:ok, path} ->
        {path, memo}

      :error ->
        {child_path, memo} =
          Enum.reduce(Map.get(edges, id, []), {[], memo}, fn child, {best_path, memo} ->
            {path, memo} = longest_path(child, edges, values, memo)

            if best_path == [] or path_weight(path, values) > path_weight(best_path, values),
              do: {path, memo},
              else: {best_path, memo}
          end)

        path = [id | child_path]
        {path, Map.put(memo, id, path)}
    end
  end

  defp path_weight([], _values), do: 0.0
  defp path_weight(path, values), do: Enum.sum(Enum.map(path, &Map.fetch!(values, &1)))

  defp summarize(rows, values) do
    {covered, missing, partial_total, missing_ids} =
      Enum.reduce(rows, {0, 0, 0.0, []}, fn %{id: id}, {covered, missing, total, ids} ->
        case Map.fetch(values, id) do
          {:ok, value} -> {covered + 1, missing, total + value, ids}
          :error -> {covered, missing + 1, total, [id | ids]}
        end
      end)

    %{
      total: if(missing == 0, do: partial_total, else: nil),
      partial_total: partial_total,
      covered: covered,
      missing: missing,
      gates: [],
      withheld: if(missing == 0, do: %{}, else: %{missing_measure: missing}),
      refine: if(missing == 0, do: [], else: [record_effort: Enum.reverse(missing_ids)])
    }
  end

  defp collect_rows(conn, stmt), do: collect_rows(conn, stmt, [])

  defp collect_rows(conn, stmt, acc) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [id, status]} -> collect_rows(conn, stmt, [%{id: id, status: status} | acc])
      :done -> Enum.reverse(acc)
    end
  end

  defp collect_values(conn, stmt, acc) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [id, value]} -> collect_values(conn, stmt, Map.put(acc, id, value))
      :done -> acc
    end
  end

  defp collect_edges(conn, stmt, ids, acc) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [from, to]} ->
        acc =
          if MapSet.member?(ids, from) and MapSet.member?(ids, to),
            do: Map.update(acc, from, [to], &[to | &1]),
            else: acc

        collect_edges(conn, stmt, ids, acc)

      :done ->
        acc
    end
  end
end
