defmodule Bee.Store.Migrate do
  @moduledoc false

  @type migration :: {pos_integer(), atom(), (Exqlite.Sqlite3.db() -> :ok | {:error, term()})}

  @spec migrations() :: [migration()]
  def migrations, do: []

  @spec target_version() :: non_neg_integer()
  def target_version, do: target_version(migrations())

  @spec target_version([migration()]) :: non_neg_integer()
  def target_version([]), do: 0
  def target_version(migrations), do: migrations |> List.last() |> elem(0)

  @spec version_map() :: %{non_neg_integer() => atom()}
  def version_map, do: version_map(migrations())

  @spec version_map([migration()]) :: %{pos_integer() => atom()}
  def version_map(migrations) do
    Map.new(migrations, fn {version, name, _run} -> {version, name} end)
  end

  @spec run_at_boot(Path.t(), keyword()) ::
          :ok
          | {:error,
             :version_ahead
             | :invalid_migration_plan
             | {:migration_failed, atom(), term()}
             | term()}
  def run_at_boot(db_path, opts \\ []) do
    case Exqlite.Sqlite3.open(db_path) do
      {:ok, conn} ->
        try do
          with :ok <- configure_connection(conn),
               result <- run(conn, opts) do
            result
          end
        after
          Exqlite.Sqlite3.close(conn)
        end

      {:error, _reason} = error ->
        error
    end
  end

  @spec user_version(Exqlite.Sqlite3.db()) :: {:ok, non_neg_integer()} | {:error, term()}
  def user_version(conn) do
    case Exqlite.Sqlite3.prepare(conn, "PRAGMA user_version") do
      {:ok, stmt} ->
        try do
          case Exqlite.Sqlite3.step(conn, stmt) do
            {:row, [version]} -> {:ok, version}
            :done -> {:error, :user_version_missing}
            {:error, _reason} = error -> error
          end
        after
          Exqlite.Sqlite3.release(conn, stmt)
        end

      {:error, _reason} = error ->
        error
    end
  end

  @spec run(Exqlite.Sqlite3.db(), keyword()) ::
          :ok
          | {:error,
             :version_ahead | :invalid_migration_plan | {:migration_failed, atom(), term()}}
  def run(conn, opts \\ []) do
    migrations = Keyword.get(opts, :migrations, migrations())

    with :ok <- validate_plan(migrations),
         {:ok, current_version} <- user_version(conn),
         target_version = target_version(migrations),
         :ok <- version_gate(current_version, target_version) do
      migrations
      |> Enum.drop_while(fn {version, _name, _run} -> version <= current_version end)
      |> Enum.reduce_while(:ok, fn migration, :ok ->
        case apply_migration(conn, migration) do
          :ok -> {:cont, :ok}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    end
  end

  defp validate_plan([]), do: :ok

  defp validate_plan(migrations) do
    versions = Enum.map(migrations, &elem(&1, 0))

    if versions == Enum.to_list(1..length(migrations)) do
      :ok
    else
      {:error, :invalid_migration_plan}
    end
  end

  defp version_gate(current, target) when current > target, do: {:error, :version_ahead}
  defp version_gate(_current, _target), do: :ok

  defp apply_migration(conn, {version, name, run}) do
    with :ok <- execute(conn, "BEGIN IMMEDIATE"),
         :ok <- run.(conn),
         :ok <- execute(conn, "PRAGMA user_version = #{version}"),
         :ok <- execute(conn, "COMMIT") do
      :ok
    else
      {:error, reason} ->
        rollback(conn)
        {:error, {:migration_failed, name, reason}}
    end
  end

  defp execute(conn, sql) do
    case Exqlite.Sqlite3.execute(conn, sql) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp configure_connection(conn) do
    Enum.reduce_while(
      ["PRAGMA foreign_keys=ON", "PRAGMA busy_timeout=5000", "PRAGMA synchronous=NORMAL"],
      :ok,
      fn sql, :ok ->
        case execute(conn, sql) do
          :ok -> {:cont, :ok}
          {:error, _reason} = error -> {:halt, error}
        end
      end
    )
  end

  defp rollback(conn) do
    _ = Exqlite.Sqlite3.execute(conn, "ROLLBACK")
    :ok
  end
end
