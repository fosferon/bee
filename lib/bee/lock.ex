defmodule Bee.Lock do
  @moduledoc false

  @default_ttl_minutes 30

  @spec acquire(Exqlite.Sqlite3.db(), String.t(), keyword()) ::
          {:ok, map()} | {:error, :already_locked} | {:error, term()}
  def acquire(conn, issue_id, opts \\ []) do
    force = Keyword.get(opts, :force, false)
    locked_by = Keyword.get(opts, :locked_by)
    ttl_minutes = Keyword.get(opts, :ttl, @default_ttl_minutes)

    now = DateTime.utc_now()
    now_iso = DateTime.to_iso8601(now)
    expires_at = DateTime.add(now, ttl_minutes * 60) |> DateTime.to_iso8601()

    lock = %{issue_id: issue_id, locked_by: locked_by, locked_at: now_iso, expires_at: expires_at}

    if force do
      with :ok <-
             run_sql(
               conn,
               "INSERT OR REPLACE INTO locks (issue_id, locked_by, locked_at, expires_at) VALUES (?, ?, ?, ?)",
               [issue_id, locked_by, now_iso, expires_at]
             ) do
        {:ok, lock}
      end
    else
      case get(conn, issue_id) do
        nil ->
          with :ok <-
                 run_sql(
                   conn,
                   "INSERT INTO locks (issue_id, locked_by, locked_at, expires_at) VALUES (?, ?, ?, ?)",
                   [issue_id, locked_by, now_iso, expires_at]
                 ) do
            {:ok, lock}
          end

        _existing ->
          {:error, :already_locked}
      end
    end
  end

  @spec release(Exqlite.Sqlite3.db(), String.t()) :: :ok
  def release(conn, issue_id) do
    run_sql(conn, "DELETE FROM locks WHERE issue_id = ?", [issue_id])
    :ok
  end

  @spec get(Exqlite.Sqlite3.db(), String.t()) :: map() | nil
  def get(conn, issue_id) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT * FROM locks WHERE issue_id = ?")
    :ok = Exqlite.Sqlite3.bind(stmt, [issue_id])

    result =
      case Exqlite.Sqlite3.step(conn, stmt) do
        {:row, row} ->
          {:ok, cols} = Exqlite.Sqlite3.columns(conn, stmt)
          Enum.zip(cols, row) |> Map.new()

        :done ->
          nil
      end

    Exqlite.Sqlite3.release(conn, stmt)
    result
  end

  @spec sweep_expired(Exqlite.Sqlite3.db()) :: integer()
  def sweep_expired(conn) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    run_sql(conn, "DELETE FROM locks WHERE expires_at < ?", [now])

    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT changes()")
    {:row, [changes]} = Exqlite.Sqlite3.step(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    changes
  end

  # Fail soft (GC-3353): surface constraint errors (e.g. a lock referencing a
  # missing issue -> FOREIGN KEY violation) instead of a `{:badmatch}` that
  # crashed the owning `Bee.Repo` GenServer. Always release the statement.
  @spec run_sql(Exqlite.Sqlite3.db(), String.t(), list()) :: :ok | {:error, term()}
  defp run_sql(conn, sql, params) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    :ok = Exqlite.Sqlite3.bind(stmt, params)
    result = Exqlite.Sqlite3.step(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)

    case result do
      :done -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
