defmodule Bee.Store.Intents do
  @moduledoc false

  @spec put(Exqlite.Sqlite3.db(), String.t(), String.t()) :: :ok | {:error, term()}
  def put(conn, name, spec_json) do
    sql = """
    INSERT INTO intents (name, spec_json, created_at)
    VALUES (?, ?, ?)
    ON CONFLICT(name) DO UPDATE SET spec_json = excluded.spec_json
    """

    execute(conn, sql, [name, spec_json, DateTime.utc_now() |> DateTime.to_iso8601()])
  end

  @spec get(Exqlite.Sqlite3.db(), String.t()) :: {:ok, String.t()} | {:error, :unknown_intent}
  def get(conn, name) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT spec_json FROM intents WHERE name = ?")
    :ok = Exqlite.Sqlite3.bind(stmt, [name])

    try do
      case Exqlite.Sqlite3.step(conn, stmt) do
        {:row, [spec_json]} -> {:ok, spec_json}
        :done -> {:error, :unknown_intent}
      end
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  @spec delete(Exqlite.Sqlite3.db(), String.t()) :: :ok
  def delete(conn, name), do: execute(conn, "DELETE FROM intents WHERE name = ?", [name])

  defp execute(conn, sql, params) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    :ok = Exqlite.Sqlite3.bind(stmt, params)

    try do
      case Exqlite.Sqlite3.step(conn, stmt) do
        :done -> :ok
        {:error, reason} -> {:error, reason}
      end
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end
end
