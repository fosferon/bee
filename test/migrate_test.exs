defmodule Bee.Store.MigrateTest do
  use ExUnit.Case, async: true

  alias Bee.Store.Migrate

  setup do
    path = Path.join(System.tmp_dir!(), "bee_migrate_#{System.unique_integer([:positive])}.db")
    {:ok, conn} = Exqlite.Sqlite3.open(path)

    on_exit(fn ->
      Exqlite.Sqlite3.close(conn)
      File.rm(path)
    end)

    %{conn: conn}
  end

  test "runs pending migrations in ascending order and stamps each version", %{conn: conn} do
    migrations = [
      {1, :one,
       fn migration_conn ->
         send(self(), :migration_one)
         Exqlite.Sqlite3.execute(migration_conn, "CREATE TABLE first_marker (id INTEGER)")
       end},
      {2, :two,
       fn migration_conn ->
         send(self(), :migration_two)
         Exqlite.Sqlite3.execute(migration_conn, "CREATE TABLE second_marker (id INTEGER)")
       end}
    ]

    assert :ok = Migrate.run(conn, migrations: migrations)
    assert_received :migration_one
    assert_received :migration_two
    assert {:ok, 2} = Migrate.user_version(conn)
    assert table_exists?(conn, "first_marker")
    assert table_exists?(conn, "second_marker")
  end

  test "does nothing when already at target version", %{conn: conn} do
    migrations = [
      {1, :one,
       fn _migration_conn ->
         send(self(), :migration_one)
         :ok
       end}
    ]

    assert :ok = Migrate.run(conn, migrations: migrations)
    assert_received :migration_one
    assert :ok = Migrate.run(conn, migrations: migrations)
    refute_received :migration_one
  end

  test "rolls back a failed migration and leaves its version unstamped", %{conn: conn} do
    migrations = [
      {1, :one,
       fn migration_conn ->
         :ok =
           Exqlite.Sqlite3.execute(migration_conn, "CREATE TABLE rolled_back_marker (id INTEGER)")

         {:error, :boom}
       end}
    ]

    assert {:error, {:migration_failed, :one, :boom}} = Migrate.run(conn, migrations: migrations)
    assert {:ok, 0} = Migrate.user_version(conn)
    refute table_exists?(conn, "rolled_back_marker")
  end

  test "resumes from the first migration that previously failed", %{conn: conn} do
    failing_plan = [
      {1, :one,
       fn migration_conn ->
         Exqlite.Sqlite3.execute(migration_conn, "CREATE TABLE committed_marker (id INTEGER)")
       end},
      {2, :two, fn _migration_conn -> {:error, :boom} end}
    ]

    assert {:error, {:migration_failed, :two, :boom}} =
             Migrate.run(conn, migrations: failing_plan)

    assert {:ok, 1} = Migrate.user_version(conn)
    assert table_exists?(conn, "committed_marker")

    resumed_plan = [
      {1, :one, fn _migration_conn -> flunk("migration one must not rerun") end},
      {2, :two,
       fn migration_conn ->
         Exqlite.Sqlite3.execute(migration_conn, "CREATE TABLE resumed_marker (id INTEGER)")
       end}
    ]

    assert :ok = Migrate.run(conn, migrations: resumed_plan)
    assert {:ok, 2} = Migrate.user_version(conn)
    assert table_exists?(conn, "resumed_marker")
  end

  test "refuses to run against a database newer than its migration plan", %{conn: conn} do
    :ok = Exqlite.Sqlite3.execute(conn, "PRAGMA user_version = 2")

    migrations = [
      {1, :one,
       fn _migration_conn ->
         send(self(), :migration_one)
         :ok
       end}
    ]

    assert {:error, :version_ahead} = Migrate.run(conn, migrations: migrations)
    refute_received :migration_one
  end

  test "rejects a migration plan with a gap or duplicate version", %{conn: conn} do
    invalid_plan = [
      {1, :one, fn _migration_conn -> :ok end},
      {3, :three, fn _migration_conn -> :ok end}
    ]

    assert {:error, :invalid_migration_plan} = Migrate.run(conn, migrations: invalid_plan)
  end

  test "exposes named target version and migration map" do
    migrations = [
      {1, :baseline, fn _migration_conn -> :ok end},
      {2, :fts_rebuild, fn _migration_conn -> :ok end}
    ]

    assert 2 == Migrate.target_version(migrations)
    assert %{1 => :baseline, 2 => :fts_rebuild} == Migrate.version_map(migrations)
  end

  test "creates and verifies a VACUUM backup before applying pending migrations", %{
    conn: conn
  } do
    backup_path =
      Path.join(System.tmp_dir!(), "bee_backup_#{System.unique_integer([:positive])}.db")

    migrations = [
      {1, :one,
       fn migration_conn ->
         Exqlite.Sqlite3.execute(migration_conn, "CREATE TABLE migrated_marker (id INTEGER)")
       end}
    ]

    assert :ok =
             Migrate.run_at_boot(database_path(conn),
               migrations: migrations,
               backup_path: backup_path
             )

    assert File.exists?(backup_path)
    assert table_exists?(conn, "migrated_marker")

    {:ok, backup_conn} = Exqlite.Sqlite3.open(backup_path)
    assert {:ok, 0} = Migrate.user_version(backup_conn)
    assert integrity_check?(backup_conn)
    refute table_exists?(backup_conn, "migrated_marker")
    Exqlite.Sqlite3.close(backup_conn)

    on_exit(fn -> File.rm(backup_path) end)
  end

  test "does not create a backup when no migration is pending", %{conn: conn} do
    backup_path =
      Path.join(System.tmp_dir!(), "bee_backup_#{System.unique_integer([:positive])}.db")

    assert :ok =
             Migrate.run_at_boot(database_path(conn), migrations: [], backup_path: backup_path)

    refute File.exists?(backup_path)
  end

  test "aborts before migration when the backup target already exists", %{conn: conn} do
    backup_path =
      Path.join(System.tmp_dir!(), "bee_backup_#{System.unique_integer([:positive])}.db")

    File.write!(backup_path, "do not overwrite")

    migrations = [
      {1, :one,
       fn _migration_conn ->
         flunk("migration must not run when preflight backup fails")
       end}
    ]

    assert {:error, :backup_failed} =
             Migrate.run_at_boot(database_path(conn),
               migrations: migrations,
               backup_path: backup_path
             )

    assert {:ok, 0} = Migrate.user_version(conn)
    assert "do not overwrite" = File.read!(backup_path)

    on_exit(fn -> File.rm(backup_path) end)
  end

  defp table_exists?(conn, table_name) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?"
      )

    :ok = Exqlite.Sqlite3.bind(stmt, [table_name])
    result = Exqlite.Sqlite3.step(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)

    result == {:row, [1]}
  end

  defp database_path(conn) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "PRAGMA database_list")

    try do
      {:row, [_sequence, "main", path]} = Exqlite.Sqlite3.step(conn, stmt)
      path
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  defp integrity_check?(conn) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "PRAGMA integrity_check")

    try do
      Exqlite.Sqlite3.step(conn, stmt) == {:row, ["ok"]}
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end
end
