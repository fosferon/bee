defmodule Bee.Store.Checked do
  @moduledoc false

  # Statement helpers for writes that must fail as values, never as exceptions: every
  # prepare, bind, columns and step error comes back as `{:error, reason}`, and the
  # statement is released in `after` whatever happens. The keyed create and the
  # external-key lookup use them so a driver failure reaches the caller's transaction
  # (and its ROLLBACK) instead of crashing the writer.

  @spec exec(Exqlite.Sqlite3.db(), String.t(), list()) :: :ok | {:error, term()}
  def exec(conn, sql, params) do
    with_statement(conn, sql, params, fn stmt ->
      case Exqlite.Sqlite3.step(conn, stmt) do
        :done -> :ok
        {:error, reason} -> {:error, reason}
        other -> {:error, {:unexpected_step, other}}
      end
    end)
  end

  @doc "All rows, each as `{columns, values}`."
  @spec rows(Exqlite.Sqlite3.db(), String.t(), list()) ::
          {:ok, [{[String.t()], list()}]} | {:error, term()}
  def rows(conn, sql, params) do
    with_statement(conn, sql, params, fn stmt ->
      with {:ok, cols} <- Exqlite.Sqlite3.columns(conn, stmt),
           {:ok, rows} <- collect(conn, stmt, []) do
        {:ok, Enum.map(rows, &{cols, &1})}
      end
    end)
  end

  @doc "The single column of every row."
  @spec scalars(Exqlite.Sqlite3.db(), String.t(), list()) :: {:ok, list()} | {:error, term()}
  def scalars(conn, sql, params) do
    with_statement(conn, sql, params, fn stmt ->
      with {:ok, rows} <- collect(conn, stmt, []) do
        Enum.reduce_while(rows, {:ok, []}, fn
          [value], {:ok, acc} -> {:cont, {:ok, [value | acc]}}
          row, _acc -> {:halt, {:error, {:unexpected_row, row}}}
        end)
        |> case do
          {:ok, values} -> {:ok, Enum.reverse(values)}
          error -> error
        end
      end
    end)
  end

  defp with_statement(conn, sql, params, fun) do
    case Exqlite.Sqlite3.prepare(conn, sql) do
      {:ok, stmt} ->
        try do
          case Exqlite.Sqlite3.bind(stmt, params) do
            :ok -> fun.(stmt)
            {:error, reason} -> {:error, reason}
          end
        after
          Exqlite.Sqlite3.release(conn, stmt)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp collect(conn, stmt, acc) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, row} -> collect(conn, stmt, [row | acc])
      :done -> {:ok, Enum.reverse(acc)}
      {:error, reason} -> {:error, reason}
    end
  end
end
