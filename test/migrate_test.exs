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

    File.rm(backup_path)

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

  test "normalises a fresh database to the canonical baseline projects schema", %{conn: conn} do
    assert {:ok, :fresh} = Migrate.detect_baseline(conn)
    assert :ok = Migrate.run(conn, migrations: [Migrate.migration_000()])

    assert {:ok, 1} = Migrate.user_version(conn)
    assert canonical_project_columns() == table_columns(conn, "projects")
    assert table_exists?(conn, "issues_fts")
    assert table_exists?(conn, "labels")
    assert table_exists?(conn, "issue_project_backfill_log")
  end

  test "normalises the DevMan baseline to the canonical baseline projects schema", %{conn: conn} do
    :ok = Bee.Store.init_schema(conn)

    assert {:ok, :devman} = Migrate.detect_baseline(conn)
    assert :ok = Migrate.run(conn, migrations: [Migrate.migration_000()])

    assert {:ok, 1} = Migrate.user_version(conn)
    assert canonical_project_columns() == table_columns(conn, "projects")
    assert table_exists?(conn, "issues_fts")
    assert table_exists?(conn, "labels")
    assert table_exists?(conn, "issue_project_backfill_log")
  end

  test "normalises the gc_daemon baseline and folds legacy project data into metadata", %{
    conn: conn
  } do
    create_gc_daemon_baseline(conn)

    assert {:ok, :gc_daemon} = Migrate.detect_baseline(conn)
    assert :ok = Migrate.run(conn, migrations: [Migrate.migration_000()])

    assert {:ok, 1} = Migrate.user_version(conn)
    assert canonical_project_columns() == table_columns(conn, "projects")

    assert ["daemon", "elixir", "ops", "https://example.test/bee", "/srv/bee", "sync", nil] =
             project_adopted_values(conn, "bee")

    assert %{
             "gc_daemon" => %{
               "branch" => "main",
               "ports_json" => %{"http" => 4242},
               "domains_json" => ["bee.example.test"],
               "metadata_json" => %{"owner" => "gc"}
             }
           } = project_metadata(conn, "bee")

    refute index_exists?(conn, "idx_projects_legacy")
    assert index_exists?(conn, "idx_projects_status")
    assert index_exists?(conn, "idx_projects_domain")
  end

  test "refuses an unrecognised populated database without stamping a version", %{conn: conn} do
    :ok = Exqlite.Sqlite3.execute(conn, "CREATE TABLE unexpected (id INTEGER)")

    assert {:error, {:migration_failed, :baseline_normalization, :unknown_baseline}} =
             Migrate.run(conn, migrations: [Migrate.migration_000()])

    assert {:ok, 0} = Migrate.user_version(conn)
    assert table_exists?(conn, "unexpected")
  end

  test "merges valid ghost labels, accounts for orphans, and rebuilds FTS", %{conn: conn} do
    assert :ok =
             Migrate.run(conn,
               migrations: [Migrate.migration_000()]
             )

    :ok =
      Exqlite.Sqlite3.execute(
        conn,
        """
        INSERT INTO issues (
          id, title, status, issue_type, created_at, updated_at
        ) VALUES ('GC-1', 'Running', 'open', 'task', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
        """
      )

    :ok =
      Exqlite.Sqlite3.execute(
        conn,
        """
        INSERT INTO issues (
          id, title, status, issue_type, created_at, updated_at
        ) VALUES ('GC-2', 'Two', 'open', 'task', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
        """
      )

    :ok = Exqlite.Sqlite3.execute(conn, "INSERT INTO issue_labels VALUES ('GC-1', 'duplicate')")
    :ok = Exqlite.Sqlite3.execute(conn, "INSERT INTO labels VALUES ('GC-1', 'duplicate')")
    :ok = Exqlite.Sqlite3.execute(conn, "INSERT INTO labels VALUES ('GC-1', 'merged')")
    :ok = Exqlite.Sqlite3.execute(conn, "PRAGMA foreign_keys=OFF")
    :ok = Exqlite.Sqlite3.execute(conn, "INSERT INTO labels VALUES ('missing', 'orphan')")
    :ok = Exqlite.Sqlite3.execute(conn, "PRAGMA foreign_keys=ON")

    assert :ok = Migrate.run(conn, migrations: [Migrate.migration_000(), Migrate.migration_001()])

    assert {:ok, 2} = Migrate.user_version(conn)
    refute table_exists?(conn, "labels")
    assert ["duplicate", "merged"] == labels_for(conn, "GC-1")
    assert 2 == scalar(conn, "SELECT COUNT(*) FROM issues_fts")
    assert 1 == scalar(conn, "SELECT COUNT(*) FROM issues_fts WHERE issues_fts MATCH 'run'")
  end

  test "migration 002 adds issues.metadata column with NOT NULL DEFAULT", %{conn: conn} do
    assert :ok = Migrate.run(conn, migrations: Migrate.migrations())

    assert {:ok, 6} = Migrate.user_version(conn)
    assert column_exists?(conn, "issues", "metadata")
    assert "TEXT" == column_type(conn, "issues", "metadata")
    assert "'{}'" == column_default(conn, "issues", "metadata")
  end

  test "migration 003 creates events, measurements, intents, measures, intent_usage and seeds effort",
       %{
         conn: conn
       } do
    assert :ok = Migrate.run(conn, migrations: [Migrate.migration_000(), Migrate.migration_001()])

    assert :ok = Migrate.run(conn, migrations: Migrate.migrations())

    assert {:ok, 6} = Migrate.user_version(conn)
    assert table_exists?(conn, "events")
    assert column_exists?(conn, "events", "event_type")
    assert column_exists?(conn, "events", "payload")
    assert table_exists?(conn, "measurements")
    assert table_exists?(conn, "intents")
    assert table_exists?(conn, "measures")
    assert table_exists?(conn, "intent_usage")

    assert 1 ==
             scalar(
               conn,
               "SELECT COUNT(*) FROM measures WHERE name = 'effort' AND unit = 'minutes'"
             )

    assert "minutes" == scalar(conn, "SELECT unit FROM measures WHERE name = 'effort'")
  end

  test "migration 003 seed effort is idempotent across full ladder runs", %{conn: conn} do
    assert :ok = Migrate.run(conn, migrations: Migrate.migrations())
    assert 1 == scalar(conn, "SELECT COUNT(*) FROM measures WHERE name = 'effort'")

    assert :ok = Migrate.run(conn, migrations: Migrate.migrations())
    assert 1 == scalar(conn, "SELECT COUNT(*) FROM measures WHERE name = 'effort'")
  end

  test "migration 003 events FK enforces ON DELETE RESTRICT", %{conn: conn} do
    assert :ok = Migrate.run(conn, migrations: Migrate.migrations())

    :ok =
      Exqlite.Sqlite3.execute(
        conn,
        """
        INSERT INTO issues (id, title, status, issue_type, created_at, updated_at)
        VALUES ('GC-1', 'Test', 'open', 'task', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
        """
      )

    :ok =
      Exqlite.Sqlite3.execute(
        conn,
        "INSERT INTO events (issue_id, seq, actor, created_at) VALUES ('GC-1', 1, 'test', '2026-01-01T00:00:00Z')"
      )

    assert {:error, _} =
             Exqlite.Sqlite3.execute(conn, "DELETE FROM issues WHERE id = 'GC-1'")
  end

  test "migration 004 rebuilds dependencies PK to (issue_id, depends_on_id, dep_type)", %{
    conn: conn
  } do
    assert :ok =
             Migrate.run(conn,
               migrations: [
                 Migrate.migration_000(),
                 Migrate.migration_001(),
                 Migrate.migration_002()
               ]
             )

    :ok =
      Exqlite.Sqlite3.execute(
        conn,
        """
        INSERT INTO issues (id, title, status, issue_type, created_at, updated_at)
        VALUES ('GC-1', 'A', 'open', 'task', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
        """
      )

    :ok =
      Exqlite.Sqlite3.execute(
        conn,
        """
        INSERT INTO issues (id, title, status, issue_type, created_at, updated_at)
        VALUES ('GC-2', 'B', 'open', 'task', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
        """
      )

    :ok =
      Exqlite.Sqlite3.execute(
        conn,
        """
        INSERT INTO dependencies (issue_id, depends_on_id, dep_type, created_at)
        VALUES ('GC-1', 'GC-2', 'blocks', '2026-01-01T00:00:00Z')
        """
      )

    assert :ok = Migrate.run(conn, migrations: Migrate.migrations())

    assert {:ok, 6} = Migrate.user_version(conn)
    assert 1 == scalar(conn, "SELECT COUNT(*) FROM dependencies")
    assert ["GC-2"] == dependency_targets(conn, "GC-1")
    assert index_exists?(conn, "idx_dependencies_reverse")

    :ok =
      Exqlite.Sqlite3.execute(
        conn,
        """
        INSERT INTO dependencies (issue_id, depends_on_id, dep_type, created_at)
        VALUES ('GC-1', 'GC-2', 'related', '2026-01-01T00:00:00Z')
        """
      )

    assert 2 ==
             scalar(
               conn,
               "SELECT COUNT(*) FROM dependencies WHERE issue_id = 'GC-1' AND depends_on_id = 'GC-2'"
             )
  end

  test "full migration ladder reaches version 6 on a fresh database", %{conn: conn} do
    assert :ok = Migrate.run(conn, migrations: Migrate.migrations())
    assert {:ok, 6} = Migrate.user_version(conn)
    assert table_exists?(conn, "events")
    assert table_exists?(conn, "measurements")
    assert table_exists?(conn, "intents")
    assert table_exists?(conn, "measures")
    assert table_exists?(conn, "intent_usage")
    assert index_exists?(conn, "idx_dependencies_reverse")
    assert column_exists?(conn, "issues", "metadata")
  end

  defp column_exists?(conn, table, column) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "PRAGMA table_info(#{table})")

    try do
      column_loop(conn, stmt, column)
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  defp column_loop(conn, stmt, column) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [_cid, name | _]} -> name == column or column_loop(conn, stmt, column)
      :done -> false
    end
  end

  defp column_type(conn, table, column) do
    {:row, [_cid, _name, type | _rest]} = find_column_row(conn, table, column)
    type
  end

  defp column_default(conn, table, column) do
    {:row, [_cid, _name, _type, _not_null, default | _rest]} =
      find_column_row(conn, table, column)

    default
  end

  defp find_column_row(conn, table, column) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "PRAGMA table_info(#{table})")

    try do
      find_column_loop(conn, stmt, column)
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  defp find_column_loop(conn, stmt, column) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [_cid, name | _] = row} when name == column -> {:row, row}
      {:row, _} -> find_column_loop(conn, stmt, column)
      :done -> flunk("column #{column} not found in table")
    end
  end

  defp dependency_targets(conn, issue_id) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT depends_on_id FROM dependencies WHERE issue_id = ? ORDER BY depends_on_id"
      )

    :ok = Exqlite.Sqlite3.bind(stmt, [issue_id])

    try do
      Stream.repeatedly(fn -> Exqlite.Sqlite3.step(conn, stmt) end)
      |> Enum.take_while(&match?({:row, _}, &1))
      |> Enum.map(fn {:row, [id]} -> id end)
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
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

  defp create_gc_daemon_baseline(conn) do
    :ok = Bee.Store.init_schema(conn)

    [
      "ALTER TABLE projects ADD COLUMN canonical_path TEXT",
      "ALTER TABLE projects ADD COLUMN description TEXT",
      "ALTER TABLE projects ADD COLUMN stack TEXT",
      "ALTER TABLE projects ADD COLUMN domain TEXT",
      "ALTER TABLE projects ADD COLUMN repo_url TEXT",
      "ALTER TABLE projects ADD COLUMN branch TEXT",
      "ALTER TABLE projects ADD COLUMN binary_path TEXT",
      "ALTER TABLE projects ADD COLUMN launchd_service TEXT",
      "ALTER TABLE projects ADD COLUMN data_dir TEXT",
      "ALTER TABLE projects ADD COLUMN notes TEXT",
      "ALTER TABLE projects ADD COLUMN ports_json TEXT NOT NULL DEFAULT '{}'",
      "ALTER TABLE projects ADD COLUMN domains_json TEXT NOT NULL DEFAULT '[]'",
      "ALTER TABLE projects ADD COLUMN tags_json TEXT NOT NULL DEFAULT '[]'",
      "ALTER TABLE projects ADD COLUMN commands_json TEXT NOT NULL DEFAULT '[]'",
      "ALTER TABLE projects ADD COLUMN key_files_json TEXT NOT NULL DEFAULT '[]'",
      "ALTER TABLE projects ADD COLUMN related_projects_json TEXT NOT NULL DEFAULT '[]'",
      "ALTER TABLE projects ADD COLUMN metadata_json TEXT NOT NULL DEFAULT '{}'",
      "ALTER TABLE projects ADD COLUMN source TEXT NOT NULL DEFAULT 'manual'",
      "ALTER TABLE projects ADD COLUMN last_synced_at TEXT",
      "CREATE INDEX idx_projects_status ON projects(status)",
      "CREATE INDEX idx_projects_domain ON projects(domain)",
      "CREATE INDEX idx_projects_legacy ON projects(branch)",
      """
      CREATE TABLE labels (
        issue_id TEXT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
        label TEXT NOT NULL,
        PRIMARY KEY (issue_id, label)
      )
      """,
      """
      CREATE TABLE issue_project_backfill_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        run_id TEXT NOT NULL,
        issue_id TEXT NOT NULL,
        old_project_id TEXT,
        new_project_id TEXT NOT NULL,
        rule TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
      """,
      """
      CREATE VIRTUAL TABLE issues_fts USING fts5(
        issue_id UNINDEXED,
        title,
        description,
        tokenize='porter unicode61'
      )
      """,
      """
      CREATE TRIGGER issues_fts_ai AFTER INSERT ON issues BEGIN
        INSERT INTO issues_fts (issue_id, title, description)
        VALUES (new.id, new.title, COALESCE(new.description, ''));
      END
      """,
      """
      CREATE TRIGGER issues_fts_ad AFTER DELETE ON issues BEGIN
        DELETE FROM issues_fts WHERE issue_id = old.id;
      END
      """,
      """
      CREATE TRIGGER issues_fts_au AFTER UPDATE ON issues BEGIN
        DELETE FROM issues_fts WHERE issue_id = old.id;
        INSERT INTO issues_fts (issue_id, title, description)
        VALUES (new.id, new.title, COALESCE(new.description, ''));
      END
      """
    ]
    |> Enum.each(fn sql -> :ok = Exqlite.Sqlite3.execute(conn, sql) end)

    :ok =
      Exqlite.Sqlite3.execute(
        conn,
        """
        INSERT INTO projects (
          id, name, path, status, created_at, updated_at, canonical_path, description,
          stack, domain, repo_url, branch, binary_path, launchd_service, data_dir, notes,
          ports_json, domains_json, tags_json, commands_json, key_files_json,
          related_projects_json, metadata_json, source, last_synced_at
        ) VALUES (
          'bee', 'Bee', '/srv/bee', 'active', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z',
          '/srv/bee', 'daemon', 'elixir', 'ops', 'https://example.test/bee', 'main',
          '/usr/local/bin/bee', 'com.example.bee', '/var/lib/bee', 'not json',
          '{"http":4242}', '["bee.example.test"]', '["core"]', '["mix test"]',
          '["mix.exs"]', '["gc"]', '{"owner":"gc"}', 'sync', NULL
        )
        """
      )
  end

  defp canonical_project_columns do
    [
      {"id", "TEXT", 0, nil, 1},
      {"name", "TEXT", 1, nil, 0},
      {"path", "TEXT", 0, nil, 0},
      {"status", "TEXT", 1, "'active'", 0},
      {"created_at", "TEXT", 1, nil, 0},
      {"updated_at", "TEXT", 1, nil, 0},
      {"description", "TEXT", 0, nil, 0},
      {"stack", "TEXT", 0, nil, 0},
      {"domain", "TEXT", 0, nil, 0},
      {"repo_url", "TEXT", 0, nil, 0},
      {"canonical_path", "TEXT", 0, nil, 0},
      {"source", "TEXT", 1, "'manual'", 0},
      {"last_synced_at", "TEXT", 0, nil, 0},
      {"metadata", "TEXT", 1, "'{}'", 0}
    ]
  end

  defp table_columns(conn, table) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "PRAGMA table_info(#{table})")

    try do
      Stream.repeatedly(fn -> Exqlite.Sqlite3.step(conn, stmt) end)
      |> Enum.take_while(&match?({:row, _}, &1))
      |> Enum.map(fn {:row, [_cid, name, type, not_null, default, primary_key]} ->
        {name, type, not_null, default, primary_key}
      end)
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  defp project_adopted_values(conn, id) do
    scalar_row(
      conn,
      """
      SELECT description, stack, domain, repo_url, canonical_path, source, last_synced_at
      FROM projects WHERE id = '#{id}'
      """
    )
  end

  defp project_metadata(conn, id) do
    [metadata] = scalar_row(conn, "SELECT metadata FROM projects WHERE id = '#{id}'")
    Jason.decode!(metadata)
  end

  defp scalar_row(conn, sql) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)

    try do
      {:row, row} = Exqlite.Sqlite3.step(conn, stmt)
      row
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  defp index_exists?(conn, index_name) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = ?"
      )

    :ok = Exqlite.Sqlite3.bind(stmt, [index_name])
    result = Exqlite.Sqlite3.step(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    result == {:row, [1]}
  end

  defp labels_for(conn, issue_id) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT label FROM issue_labels WHERE issue_id = ? ORDER BY label"
      )

    :ok = Exqlite.Sqlite3.bind(stmt, [issue_id])

    try do
      Stream.repeatedly(fn -> Exqlite.Sqlite3.step(conn, stmt) end)
      |> Enum.take_while(&match?({:row, _}, &1))
      |> Enum.map(fn {:row, [label]} -> label end)
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  defp scalar(conn, sql) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)

    try do
      {:row, [value]} = Exqlite.Sqlite3.step(conn, stmt)
      value
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end
end
