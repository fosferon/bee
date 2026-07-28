defmodule Bee.Store.Measurements do
  @moduledoc false

  @spec register(Exqlite.Sqlite3.db(), String.t(), String.t()) ::
          :ok | {:error, :invalid_measure | :unit_mismatch | term()}
  def register(conn, name, unit)
      when is_binary(name) and name != "" and is_binary(unit) and unit != "" do
    case registered_unit(conn, name) do
      nil ->
        execute(
          conn,
          "INSERT INTO measures (name, unit, registered_at) VALUES (?, ?, ?)",
          [name, unit, now_iso()]
        )

      ^unit ->
        :ok

      _other ->
        {:error, :unit_mismatch}
    end
  end

  def register(_conn, _name, _unit), do: {:error, :invalid_measure}

  defp registered_unit(conn, name) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT unit FROM measures WHERE name = ?")
    :ok = Exqlite.Sqlite3.bind(stmt, [name])

    try do
      case Exqlite.Sqlite3.step(conn, stmt) do
        {:row, [unit]} -> unit
        :done -> nil
      end
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
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

  defp now_iso, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
