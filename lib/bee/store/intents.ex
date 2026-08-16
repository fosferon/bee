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

  @spec list(Exqlite.Sqlite3.db()) :: {:ok, [map()]} | {:error, term()}
  def list(conn) do
    sql = """
    SELECT intents.name, intents.spec_json, intents.created_at,
           COALESCE(intent_usage.count, 0), intent_usage.last_used_at
    FROM intents
    LEFT JOIN intent_usage
      ON intent_usage.name = intents.name AND intent_usage.kind = 'registered'
    ORDER BY intents.name ASC
    """

    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)

    try do
      {:ok, collect_intents(conn, stmt)}
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  @spec record_usage(Exqlite.Sqlite3.db(), String.t(), String.t()) :: :ok | {:error, term()}
  def record_usage(conn, name, kind) do
    sql = """
    INSERT INTO intent_usage (name, kind, count, last_used_at)
    VALUES (?, ?, 1, ?)
    ON CONFLICT(name, kind) DO UPDATE SET
      count = intent_usage.count + 1,
      last_used_at = excluded.last_used_at
    """

    execute(conn, sql, [name, kind, DateTime.utc_now() |> DateTime.to_iso8601()])
  end

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

  defp collect_intents(conn, stmt) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [name, spec_json, created_at, usage_count, last_used_at]} ->
        [
          %{
            name: name,
            spec: Jason.decode!(spec_json),
            created_at: created_at,
            usage_count: usage_count,
            last_used_at: last_used_at
          }
          | collect_intents(conn, stmt)
        ]

      :done ->
        []
    end
  end
end
