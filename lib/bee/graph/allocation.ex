defmodule Bee.Graph.Allocation do
  @moduledoc false

  @spec agent_load(Exqlite.Sqlite3.db(), String.t()) :: non_neg_integer()
  def agent_load(conn, agent_id) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT COUNT(*) FROM issues WHERE assigned_to = ? AND status = 'open'"
      )

    :ok = Exqlite.Sqlite3.bind(stmt, [agent_id])

    try do
      case Exqlite.Sqlite3.step(conn, stmt) do
        {:row, [count]} -> count
        :done -> 0
      end
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  @spec who_blocks_whom(Exqlite.Sqlite3.db()) :: [{String.t(), String.t()}]
  def who_blocks_whom(conn) do
    types = Bee.Dependency.Type.gating() |> Enum.map(&Bee.Dependency.Type.storage_name/1)
    placeholders = Enum.map_join(types, ", ", fn _ -> "?" end)

    sql = """
    SELECT DISTINCT blocker.assigned_to, blocked.assigned_to
    FROM dependencies dep
    INNER JOIN issues blocker ON blocker.id = dep.depends_on_id
    INNER JOIN issues blocked ON blocked.id = dep.issue_id
    WHERE dep.dep_type IN (#{placeholders})
      AND blocker.assigned_to IS NOT NULL
      AND blocked.assigned_to IS NOT NULL
      AND blocker.assigned_to != blocked.assigned_to
    ORDER BY blocker.assigned_to, blocked.assigned_to
    """

    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    :ok = Exqlite.Sqlite3.bind(stmt, types)

    try do
      collect(conn, stmt)
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  defp collect(conn, stmt) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [blocker, blocked]} -> [{blocker, blocked} | collect(conn, stmt)]
      :done -> []
    end
  end
end
