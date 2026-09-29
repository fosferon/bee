defmodule Bee.Store.Tree do
  @moduledoc false

  # Parent-edge reads over a set of issues, one recursive CTE each (GC-5834):
  # ancestor chains (for `Bee.ancestors/2`, the `path` field, and `keep_ancestors`)
  # and subtree roll-ups (the `fold` field). Ids in and out are stored ids
  # ("bee-12"); callers convert to numeric ids at the edge.

  # Cycle guard. Bee.Store.Acyclic keeps parent edges acyclic, but a recursive CTE
  # must terminate even over a database something else wrote.
  @walk_cap 20

  @doc """
  Returns `%{id => [ancestor]}` for each id that has a parent, each chain ordered
  root first. An ancestor is `%{id, title, status, issue_type, project_id, dist}`,
  where `dist` is its parent distance from the issue (the parent is 1). The walk
  only continues through stored rows, so a dangling parent reference ends the chain.
  """
  @spec ancestor_chains(Exqlite.Sqlite3.db(), [String.t()]) :: %{String.t() => [map()]}
  def ancestor_chains(_conn, []), do: %{}

  def ancestor_chains(conn, ids) do
    placeholders = Enum.map_join(ids, ", ", fn _ -> "?" end)

    sql = """
    WITH RECURSIVE bee_anc(start_id, anc_id, dist) AS (
      SELECT id, parent, 1 FROM issues WHERE id IN (#{placeholders}) AND parent IS NOT NULL
      UNION ALL
      SELECT bee_anc.start_id, up.parent, bee_anc.dist + 1
      FROM bee_anc JOIN issues up ON up.id = bee_anc.anc_id
      WHERE up.parent IS NOT NULL AND bee_anc.dist < ?
    )
    SELECT bee_anc.start_id, bee_anc.anc_id, bee_anc.dist,
           issues.title, issues.status, issues.issue_type, issues.project_id
    FROM bee_anc JOIN issues ON issues.id = bee_anc.anc_id
    ORDER BY bee_anc.start_id, bee_anc.dist DESC
    """

    conn
    |> rows(sql, ids ++ [@walk_cap])
    |> Enum.reduce(%{}, fn [start_id, anc_id, dist, title, status, issue_type, project_id], acc ->
      ancestor = %{
        id: anc_id,
        title: title,
        status: status,
        issue_type: issue_type,
        project_id: project_id,
        dist: dist
      }

      Map.update(acc, start_id, [ancestor], &[ancestor | &1])
    end)
    |> Map.new(fn {id, chain} -> {id, Enum.reverse(chain)} end)
  end

  @doc """
  Returns `%{id => rollup}` over ALL descendants of each id, at any depth and any
  status: `%{total, open, in_progress, blocked, closed, cancelled,
  max_open_priority}`. `blocked` counts open descendants with an unresolved gating
  dependency (so it is a subset of `open`); `max_open_priority` is the highest raw
  priority among descendants that are neither closed nor cancelled. Ids without
  descendants get an all-zero roll-up.
  """
  @spec rollups(Exqlite.Sqlite3.db(), [String.t()]) :: %{String.t() => map()}
  def rollups(_conn, []), do: %{}

  def rollups(conn, ids) do
    placeholders = Enum.map_join(ids, ", ", fn _ -> "?" end)
    types = Bee.Dependency.Type.gating() |> Enum.map(&Bee.Dependency.Type.storage_name/1)

    sql = """
    WITH RECURSIVE bee_desc(root_id, desc_id, lvl) AS (
      SELECT parent, id, 1 FROM issues WHERE parent IN (#{placeholders})
      UNION ALL
      SELECT bee_desc.root_id, child.id, bee_desc.lvl + 1
      FROM issues child JOIN bee_desc ON child.parent = bee_desc.desc_id
      WHERE bee_desc.lvl < ?
    )
    SELECT tree.root_id,
           COUNT(*),
           SUM(issues.status = 'open'),
           SUM(issues.status = 'in_progress'),
           SUM(#{Bee.Store.blocked_clause("issues", types)}),
           SUM(issues.status = 'closed'),
           SUM(issues.status = 'cancelled'),
           MAX(CASE WHEN issues.status NOT IN ('closed', 'cancelled') THEN issues.priority END)
    FROM (SELECT DISTINCT root_id, desc_id FROM bee_desc) AS tree
    JOIN issues ON issues.id = tree.desc_id
    GROUP BY tree.root_id
    """

    found =
      conn
      |> rows(sql, ids ++ [@walk_cap] ++ types)
      |> Map.new(fn [root_id, total, open, in_progress, blocked, closed, cancelled, max_pri] ->
        {root_id,
         %{
           total: total,
           open: open,
           in_progress: in_progress,
           blocked: blocked,
           closed: closed,
           cancelled: cancelled,
           max_open_priority: max_pri
         }}
      end)

    Map.new(ids, fn id -> {id, Map.get(found, id, empty_rollup())} end)
  end

  defp empty_rollup do
    %{
      total: 0,
      open: 0,
      in_progress: 0,
      blocked: 0,
      closed: 0,
      cancelled: 0,
      max_open_priority: nil
    }
  end

  defp rows(conn, sql, params) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    :ok = Exqlite.Sqlite3.bind(stmt, params)

    try do
      collect(conn, stmt)
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  defp collect(conn, stmt) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, row} -> [row | collect(conn, stmt)]
      :done -> []
    end
  end
end
