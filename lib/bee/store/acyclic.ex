defmodule Bee.Store.Acyclic do
  @moduledoc false

  @spec dependency(Exqlite.Sqlite3.db(), String.t(), String.t()) :: :ok | {:error, :cycle}
  def dependency(_conn, issue_id, issue_id), do: {:error, :cycle}

  def dependency(conn, issue_id, depends_on_id) do
    sql = """
    WITH RECURSIVE reachable(id) AS (
      SELECT issue_id FROM dependencies WHERE depends_on_id = ?
      UNION
      SELECT d.issue_id
      FROM dependencies d
      INNER JOIN reachable r ON d.depends_on_id = r.id
    )
    SELECT 1 FROM reachable WHERE id = ? LIMIT 1
    """

    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    :ok = Exqlite.Sqlite3.bind(stmt, [issue_id, depends_on_id])

    try do
      case Exqlite.Sqlite3.step(conn, stmt) do
        {:row, [1]} -> {:error, :cycle}
        :done -> :ok
      end
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end
end
