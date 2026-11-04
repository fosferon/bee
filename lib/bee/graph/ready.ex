defmodule Bee.Graph.Ready do
  @moduledoc false

  @spec issue_ids(Exqlite.Sqlite3.db()) :: [String.t()]
  def issue_ids(conn) do
    types = Bee.Dependency.Type.gating() |> Enum.map(&Bee.Dependency.Type.storage_name/1)
    placeholders = Enum.map_join(types, ", ", fn _ -> "?" end)

    sql = """
    SELECT issue.id
    FROM issues issue
    WHERE issue.status = 'open'
      AND NOT EXISTS (
        SELECT 1
        FROM dependencies dep
        INNER JOIN issues blocker ON blocker.id = dep.depends_on_id
        WHERE dep.issue_id = issue.id
          AND dep.dep_type IN (#{placeholders})
          AND blocker.status NOT IN ('closed', 'cancelled')
      )
    ORDER BY issue.id ASC
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
      {:row, [id]} -> [id | collect(conn, stmt)]
      :done -> []
    end
  end
end
