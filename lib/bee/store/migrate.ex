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
             | :backup_failed
             | :integrity_check_failed
             | :verification_mismatch
             | {:migration_failed, atom(), term()}
             | term()}
  def run_at_boot(db_path, opts \\ []) do
    case Exqlite.Sqlite3.open(db_path) do
      {:ok, conn} ->
        try do
          migrations = Keyword.get(opts, :migrations, migrations())

          with :ok <- configure_connection(conn),
               :ok <- validate_plan(migrations),
               {:ok, current_version} <- user_version(conn),
               target_version = target_version(migrations),
               :ok <- version_gate(current_version, target_version),
               :ok <- maybe_backup(conn, db_path, current_version, migrations, opts) do
            run(conn, migrations: migrations)
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

  defp maybe_backup(conn, db_path, current_version, migrations, opts) do
    if current_version == target_version(migrations) do
      :ok
    else
      backup_path = Keyword.get(opts, :backup_path, default_backup_path(db_path))

      with :ok <- ensure_backup_target(backup_path),
           :ok <- vacuum_into(conn, backup_path),
           :ok <- verify_backup(conn, backup_path) do
        :ok
      else
        {:error, :integrity_check_failed} = error -> error
        {:error, :verification_mismatch} = error -> error
        {:error, _reason} -> {:error, :backup_failed}
      end
    end
  end

  defp ensure_backup_target(backup_path) do
    with :ok <- File.mkdir_p(Path.dirname(backup_path)),
         false <- File.exists?(backup_path) do
      :ok
    else
      true -> {:error, :backup_exists}
      {:error, reason} -> {:error, reason}
    end
  end

  defp vacuum_into(conn, backup_path) do
    execute(conn, "VACUUM INTO '#{String.replace(backup_path, "'", "''")}'")
  end

  defp verify_backup(source_conn, backup_path) do
    case Exqlite.Sqlite3.open(backup_path) do
      {:ok, backup_conn} ->
        try do
          with :ok <- integrity_check(backup_conn),
               :ok <- foreign_key_check(backup_conn),
               {:ok, source_version} <- user_version(source_conn),
               {:ok, backup_version} <- user_version(backup_conn),
               :ok <- version_matches(source_version, backup_version) do
            :ok
          end
        after
          Exqlite.Sqlite3.close(backup_conn)
        end

      {:error, _reason} ->
        {:error, :integrity_check_failed}
    end
  end

  defp integrity_check(conn) do
    case scalar(conn, "PRAGMA integrity_check") do
      {:ok, "ok"} -> :ok
      _ -> {:error, :integrity_check_failed}
    end
  end

  defp foreign_key_check(conn) do
    case first_row(conn, "PRAGMA foreign_key_check") do
      :done -> :ok
      {:row, _row} -> {:error, :verification_mismatch}
      {:error, _reason} -> {:error, :verification_mismatch}
    end
  end

  defp version_matches(version, version), do: :ok
  defp version_matches(_source_version, _backup_version), do: {:error, :verification_mismatch}

  defp scalar(conn, sql) do
    case first_row(conn, sql) do
      {:row, [value]} -> {:ok, value}
      :done -> {:error, :no_row}
      {:error, _reason} = error -> error
    end
  end

  defp first_row(conn, sql) do
    case Exqlite.Sqlite3.prepare(conn, sql) do
      {:ok, stmt} ->
        try do
          Exqlite.Sqlite3.step(conn, stmt)
        after
          Exqlite.Sqlite3.release(conn, stmt)
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp default_backup_path(db_path) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic)
    backup_dir = Path.join([Path.dirname(db_path), "backups", Path.basename(db_path)])
    Path.join(backup_dir, "#{Path.basename(db_path)}.#{timestamp}.vacuum.bak")
  end

  defp rollback(conn) do
    _ = Exqlite.Sqlite3.execute(conn, "ROLLBACK")
    :ok
  end
end
