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
  @doc """
  Sweeps expired locks, emitting one event per expired lock (Story 3.5, AD-19).

  Each lock release and its event emission are one transaction — a released
  lock no longer matches the "expired AND held" query, so a re-dispatch is
  a no-op, not a second event (cascade F3).
  """
  def sweep_expired(conn) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    # Query all expired locks
    expired = query_expired_locks(conn, now)

    # For each expired lock: release + emit event in one transaction
    Enum.each(expired, fn {issue_id, locked_by} ->
      with :ok <- run_sql(conn, "BEGIN IMMEDIATE", []),
           :ok <- run_sql(conn, "DELETE FROM locks WHERE issue_id = ?", [issue_id]),
           :ok <- Bee.Store.insert_event(conn, issue_id, actor: locked_by),
           :ok <- run_sql(conn, "COMMIT", []) do
        :ok
      else
        {:error, _reason} ->
          run_sql(conn, "ROLLBACK", [])
      end
    end)

    length(expired)
  end

  defp query_expired_locks(conn, now) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT issue_id, locked_by FROM locks WHERE expires_at < ?")
    :ok = Exqlite.Sqlite3.bind(stmt, [now])

    rows = collect_rows(conn, stmt, [])
    Exqlite.Sqlite3.release(conn, stmt)
    rows
  end

  defp collect_rows(conn, stmt, acc) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [issue_id, locked_by]} -> collect_rows(conn, stmt, [{issue_id, locked_by} | acc])
      :done -> Enum.reverse(acc)
    end
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
