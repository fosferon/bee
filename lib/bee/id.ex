defmodule Bee.Id do
  @moduledoc false

  @spec next(Exqlite.Sqlite3.db(), String.t()) :: String.t()
  def next(conn, prefix) do
    sql = """
    INSERT INTO id_counter (prefix, next_id) VALUES (?, 1)
    ON CONFLICT(prefix) DO UPDATE SET next_id = next_id + 1
    RETURNING next_id
    """

    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    :ok = Exqlite.Sqlite3.bind(stmt, [prefix])
    {:row, [id]} = Exqlite.Sqlite3.step(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    "#{prefix}-#{id}"
  end

  @spec current(Exqlite.Sqlite3.db(), String.t()) :: integer()
  def current(conn, prefix) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT next_id FROM id_counter WHERE prefix = ?")
    :ok = Exqlite.Sqlite3.bind(stmt, [prefix])

    result =
      case Exqlite.Sqlite3.step(conn, stmt) do
        {:row, [id]} -> id - 1
        :done -> 0
      end

    Exqlite.Sqlite3.release(conn, stmt)
    result
  end

  @spec set(Exqlite.Sqlite3.db(), String.t(), integer()) :: :ok
  def set(conn, prefix, value) do
    sql = """
    INSERT INTO id_counter (prefix, next_id) VALUES (?, ?)
    ON CONFLICT(prefix) DO UPDATE SET next_id = excluded.next_id
    """

    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    :ok = Exqlite.Sqlite3.bind(stmt, [prefix, value + 1])
    :done = Exqlite.Sqlite3.step(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    :ok
  end
end
