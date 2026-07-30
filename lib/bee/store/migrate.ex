defmodule Bee.Store.Migrate do
  @moduledoc false
  require Logger

  @type migration :: {pos_integer(), atom(), (Exqlite.Sqlite3.db() -> :ok | {:error, term()})}

  @base_project_columns ~w(id name path status created_at updated_at)
  @adopted_project_columns ~w(
    description stack domain repo_url canonical_path source last_synced_at
  )
  @canonical_project_fingerprint [
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
  @folded_project_columns ~w(
    branch binary_path launchd_service data_dir notes ports_json domains_json tags_json
    commands_json key_files_json related_projects_json metadata_json
  )
  @core_tables ~w(
    projects agents project_agents issues issue_labels dependencies comments locks id_counter
  )
  @core_column_fingerprints %{
    "agents" => [
      {"id", "TEXT", 0, nil, 1},
      {"name", "TEXT", 1, nil, 0},
      {"type", "TEXT", 1, "'worker'", 0},
      {"status", "TEXT", 1, "'idle'", 0},
      {"capabilities", "TEXT", 0, nil, 0},
      {"updated_at", "TEXT", 1, nil, 0}
    ],
    "project_agents" => [
      {"project_id", "TEXT", 1, nil, 1},
      {"agent_id", "TEXT", 1, nil, 2},
      {"role", "TEXT", 1, "'worker'", 0}
    ],
    "issues" => [
      {"id", "TEXT", 0, nil, 1},
      {"title", "TEXT", 1, nil, 0},
      {"description", "TEXT", 0, nil, 0},
      {"status", "TEXT", 1, "'open'", 0},
      {"priority", "INTEGER", 0, nil, 0},
      {"issue_type", "TEXT", 1, "'task'", 0},
      {"project_id", "TEXT", 0, nil, 0},
      {"assigned_to", "TEXT", 0, nil, 0},
      {"parent", "TEXT", 0, nil, 0},
      {"created_at", "TEXT", 1, nil, 0},
      {"created_by", "TEXT", 0, nil, 0},
      {"updated_at", "TEXT", 1, nil, 0},
      {"closed_at", "TEXT", 0, nil, 0},
      {"close_reason", "TEXT", 0, nil, 0}
    ],
    "issue_labels" => [{"issue_id", "TEXT", 1, nil, 1}, {"label", "TEXT", 1, nil, 2}],
    "dependencies" => [
      {"issue_id", "TEXT", 1, nil, 1},
      {"depends_on_id", "TEXT", 1, nil, 2},
      {"dep_type", "TEXT", 1, "'blocks'", 0},
      {"created_at", "TEXT", 1, nil, 0}
    ],
    "comments" => [
      {"id", "INTEGER", 0, nil, 1},
      {"issue_id", "TEXT", 1, nil, 0},
      {"body", "TEXT", 1, nil, 0},
      {"author", "TEXT", 0, nil, 0},
      {"created_at", "TEXT", 1, nil, 0}
    ],
    "locks" => [
      {"issue_id", "TEXT", 0, nil, 1},
      {"locked_by", "TEXT", 0, nil, 0},
      {"locked_at", "TEXT", 1, nil, 0},
      {"expires_at", "TEXT", 1, nil, 0}
    ],
    "id_counter" => [{"prefix", "TEXT", 0, nil, 1}, {"next_id", "INTEGER", 1, "1", 0}]
  }
  @legacy_extended_objects ~w(
    labels issue_project_backfill_log issues_fts issues_fts_ai issues_fts_ad issues_fts_au
  )

  @spec migrations() :: [migration()]
  def migrations,
    do: [
      migration_000(),
      migration_001(),
      migration_002(),
      migration_003(),
      migration_004(),
      migration_005(),
      migration_006()
    ]

  @spec migration_000() :: migration()
  def migration_000, do: {1, :baseline_normalization, &normalize_baseline/1}

  @spec migration_001() :: migration()
  def migration_001, do: {2, :fts_rebuild_and_labels_merge, &rebuild_fts_and_merge_labels/1}

  @spec migration_002() :: migration()
  def migration_002, do: {3, :add_issues_metadata, &add_issues_metadata/1}

  @spec migration_003() :: migration()
  def migration_003, do: {4, :add_events_measurements_intents, &add_events_measurements_intents/1}

  @spec migration_004() :: migration()
  def migration_004, do: {5, :rebuild_dependencies_pk, &rebuild_dependencies_pk/1}

  @spec migration_005() :: migration()
  def migration_005, do: {6, :add_event_envelope, &add_event_envelope/1}

  @spec migration_006() :: migration()
  def migration_006, do: {7, :add_measure_domains, &add_measure_domains/1}

  @spec detect_baseline(Exqlite.Sqlite3.db()) ::
          {:ok, :fresh | :legacy_base | :legacy_extended} | {:error, :unknown_baseline}
  def detect_baseline(conn) do
    case user_table_names(conn) do
      [] ->
        {:ok, :fresh}

      _tables ->
        with :ok <- validate_core_tables(conn),
             {:ok, project_columns} <- project_column_names(conn),
             {:ok, support_state} <- legacy_extended_object_state(conn) do
          detect_populated_baseline(project_columns, support_state)
        else
          _ -> {:error, :unknown_baseline}
        end
    end
  end

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
    foreign_keys_disabled? = name in [:baseline_normalization, :rebuild_dependencies_pk]

    with :ok <- maybe_disable_foreign_keys(conn, foreign_keys_disabled?) do
      try do
        with :ok <- execute(conn, "BEGIN IMMEDIATE"),
             :ok <- run.(conn),
             :ok <- verify_foreign_keys(conn, foreign_keys_disabled?),
             :ok <- execute(conn, "PRAGMA user_version = #{version}"),
             :ok <- execute(conn, "COMMIT") do
          :ok
        else
          {:error, reason} ->
            rollback(conn)
            {:error, {:migration_failed, name, reason}}
        end
      after
        if foreign_keys_disabled?, do: execute(conn, "PRAGMA foreign_keys=ON")
      end
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

  defp normalize_baseline(conn) do
    with {:ok, baseline} <- detect_baseline(conn),
         :ok <- prepare_baseline(conn, baseline),
         {:ok, before_counts} <- protected_row_counts(conn),
         :ok <- rebuild_projects(conn, baseline),
         :ok <- create_baseline_support_objects(conn, baseline),
         :ok <- verify_protected_row_counts(conn, before_counts),
         :ok <- verify_fts_row_count(conn),
         :ok <- verify_canonical_projects(conn) do
      :ok
    end
  end

  defp rebuild_fts_and_merge_labels(conn) do
    with :ok <- merge_ghost_labels(conn) do
      rebuild_fts(conn)
    end
  end

  defp merge_ghost_labels(conn) do
    with {:ok, orphan_count} <-
           scalar(
             conn,
             """
             SELECT COUNT(*)
             FROM labels
             LEFT JOIN issues ON issues.id = labels.issue_id
             WHERE issues.id IS NULL
             """
           ),
         :ok <-
           execute(
             conn,
             """
             INSERT OR IGNORE INTO issue_labels (issue_id, label)
             SELECT labels.issue_id, labels.label
             FROM labels
             INNER JOIN issues ON issues.id = labels.issue_id
             """
           ),
         :ok <- execute(conn, "DROP TABLE labels") do
      if orphan_count > 0 do
        Logger.warning("Bee migration 001 skipped #{orphan_count} orphaned legacy labels")
      end

      :ok
    else
      _ -> {:error, :labels_merge_failed}
    end
  end

  defp rebuild_fts(conn) do
    statements = [
      "DROP TRIGGER issues_fts_ai",
      "DROP TRIGGER issues_fts_ad",
      "DROP TRIGGER issues_fts_au",
      "DROP TABLE issues_fts",
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
      """,
      "INSERT INTO issues_fts (issue_id, title, description) SELECT id, title, COALESCE(description, '') FROM issues"
    ]

    case Enum.reduce_while(statements, :ok, fn sql, :ok ->
           case execute(conn, sql) do
             :ok -> {:cont, :ok}
             {:error, _reason} -> {:halt, :error}
           end
         end) do
      :ok -> verify_fts_row_count(conn)
      :error -> {:error, :fts_rebuild_failed}
      {:error, _reason} -> {:error, :fts_rebuild_failed}
    end
  end

  # --- Migration 002: issues.metadata ---

  defp add_issues_metadata(conn) do
    execute(conn, "ALTER TABLE issues ADD COLUMN metadata TEXT NOT NULL DEFAULT '{}'")
  end

  # --- Migration 003: events, measurements, intents, measures, intent_usage ---

  defp add_events_measurements_intents(conn) do
    statements = [
      """
      CREATE TABLE events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        issue_id TEXT NOT NULL REFERENCES issues(id) ON DELETE RESTRICT,
        seq INTEGER NOT NULL,
        actor TEXT,
        created_at TEXT NOT NULL,
        UNIQUE(issue_id, seq)
      )
      """,
      """
      CREATE TABLE measurements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        issue_id TEXT NOT NULL REFERENCES issues(id) ON DELETE RESTRICT,
        seq INTEGER NOT NULL,
        measure TEXT NOT NULL,
        value REAL NOT NULL,
        unit TEXT NOT NULL,
        dims TEXT NOT NULL DEFAULT '{}',
        source TEXT,
        recorded_at TEXT NOT NULL,
        UNIQUE(issue_id, seq)
      )
      """,
      """
      CREATE TABLE intents (
        name TEXT PRIMARY KEY,
        spec_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
      """,
      """
      CREATE TABLE measures (
        name TEXT PRIMARY KEY,
        unit TEXT NOT NULL,
        registered_at TEXT NOT NULL
      )
      """,
      """
      CREATE TABLE intent_usage (
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        count INTEGER NOT NULL DEFAULT 0,
        last_used_at TEXT,
        PRIMARY KEY (name, kind)
      )
      """,
      "INSERT OR IGNORE INTO measures (name, unit, registered_at) VALUES ('effort', 'minutes', datetime('now'))"
    ]

    case Enum.reduce_while(statements, :ok, fn sql, :ok ->
           case execute(conn, sql) do
             :ok -> {:cont, :ok}
             {:error, _reason} -> {:halt, :error}
           end
         end) do
      :ok -> :ok
      :error -> {:error, :events_measurements_intents_failed}
      {:error, _reason} -> {:error, :events_measurements_intents_failed}
    end
  end

  # --- Migration 004: dependencies PK rebuild ---

  defp rebuild_dependencies_pk(conn) do
    statements = [
      """
      CREATE TABLE dependencies_new (
        issue_id TEXT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
        depends_on_id TEXT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
        dep_type TEXT NOT NULL DEFAULT 'blocks',
        created_at TEXT NOT NULL,
        PRIMARY KEY (issue_id, depends_on_id, dep_type)
      )
      """,
      "INSERT INTO dependencies_new SELECT * FROM dependencies",
      "DROP TABLE dependencies",
      "ALTER TABLE dependencies_new RENAME TO dependencies",
      "CREATE INDEX idx_dependencies_reverse ON dependencies (depends_on_id, dep_type)"
    ]

    case Enum.reduce_while(statements, :ok, fn sql, :ok ->
           case execute(conn, sql) do
             :ok -> {:cont, :ok}
             {:error, _reason} -> {:halt, :error}
           end
         end) do
      :ok -> :ok
      :error -> {:error, :dependencies_pk_rebuild_failed}
      {:error, _reason} -> {:error, :dependencies_pk_rebuild_failed}
    end
  end

  # --- Migration 005: event type and canonical JSON payload ---

  defp add_event_envelope(conn) do
    statements = [
      "ALTER TABLE events ADD COLUMN event_type TEXT NOT NULL DEFAULT 'legacy.unknown'",
      "ALTER TABLE events ADD COLUMN payload TEXT NOT NULL DEFAULT '{\"fields\":{},\"refs\":{},\"rejected\":{}}'",
      "CREATE INDEX idx_events_issue_seq ON events (issue_id, seq)"
    ]

    case Enum.reduce_while(statements, :ok, fn sql, :ok ->
           case execute(conn, sql) do
             :ok -> {:cont, :ok}
             {:error, _reason} -> {:halt, :error}
           end
         end) do
      :ok -> :ok
      :error -> {:error, :event_envelope_failed}
      {:error, _reason} -> {:error, :event_envelope_failed}
    end
  end

  defp add_measure_domains(conn) do
    statements = [
      "ALTER TABLE measures ADD COLUMN domain TEXT NOT NULL DEFAULT 'any'",
      "UPDATE measures SET domain = 'non_negative' WHERE name = 'effort'"
    ]

    case Enum.reduce_while(statements, :ok, fn sql, :ok ->
           case execute(conn, sql) do
             :ok -> {:cont, :ok}
             {:error, _reason} -> {:halt, :error}
           end
         end) do
      :ok -> :ok
      :error -> {:error, :measure_domains_failed}
      {:error, _reason} -> {:error, :measure_domains_failed}
    end
  end

  defp prepare_baseline(conn, :fresh), do: create_fresh_core_schema(conn)
  defp prepare_baseline(_conn, :legacy_base), do: :ok
  defp prepare_baseline(_conn, :legacy_extended), do: :ok

  defp rebuild_projects(conn, baseline) do
    with {:ok, projects} <- read_projects(conn, baseline),
         :ok <- execute(conn, canonical_projects_table_sql("projects_baseline_new")),
         :ok <- insert_projects(conn, projects),
         :ok <- execute(conn, "DROP TABLE projects"),
         :ok <- execute(conn, "ALTER TABLE projects_baseline_new RENAME TO projects"),
         :ok <- execute(conn, "CREATE INDEX idx_projects_status ON projects(status)"),
         :ok <- execute(conn, "CREATE INDEX idx_projects_domain ON projects(domain)") do
      :ok
    end
  end

  defp create_fresh_core_schema(conn) do
    statements = [
      canonical_projects_table_sql("projects"),
      """
      CREATE TABLE agents (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'worker',
        status TEXT NOT NULL DEFAULT 'idle',
        capabilities TEXT,
        updated_at TEXT NOT NULL
      )
      """,
      """
      CREATE TABLE project_agents (
        project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
        agent_id TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
        role TEXT NOT NULL DEFAULT 'worker',
        PRIMARY KEY (project_id, agent_id)
      )
      """,
      """
      CREATE TABLE issues (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT,
        status TEXT NOT NULL DEFAULT 'open',
        priority INTEGER,
        issue_type TEXT NOT NULL DEFAULT 'task',
        project_id TEXT REFERENCES projects(id),
        assigned_to TEXT REFERENCES agents(id),
        parent TEXT REFERENCES issues(id),
        created_at TEXT NOT NULL,
        created_by TEXT,
        updated_at TEXT NOT NULL,
        closed_at TEXT,
        close_reason TEXT
      )
      """,
      "CREATE INDEX idx_issues_status ON issues(status)",
      "CREATE INDEX idx_issues_project ON issues(project_id)",
      "CREATE INDEX idx_issues_assigned ON issues(assigned_to)",
      """
      CREATE TABLE issue_labels (
        issue_id TEXT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
        label TEXT NOT NULL,
        PRIMARY KEY (issue_id, label)
      )
      """,
      """
      CREATE TABLE dependencies (
        issue_id TEXT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
        depends_on_id TEXT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
        dep_type TEXT NOT NULL DEFAULT 'blocks',
        created_at TEXT NOT NULL,
        PRIMARY KEY (issue_id, depends_on_id)
      )
      """,
      """
      CREATE TABLE comments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        issue_id TEXT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
        body TEXT NOT NULL,
        author TEXT,
        created_at TEXT NOT NULL
      )
      """,
      """
      CREATE TABLE locks (
        issue_id TEXT PRIMARY KEY REFERENCES issues(id) ON DELETE CASCADE,
        locked_by TEXT REFERENCES agents(id),
        locked_at TEXT NOT NULL,
        expires_at TEXT NOT NULL
      )
      """,
      """
      CREATE TABLE id_counter (
        prefix TEXT PRIMARY KEY,
        next_id INTEGER NOT NULL DEFAULT 1
      )
      """
    ]

    Enum.reduce_while(statements, :ok, fn sql, :ok ->
      case execute(conn, sql) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp read_projects(_conn, :fresh), do: {:ok, []}

  defp read_projects(conn, :legacy_base) do
    project_rows(conn, @base_project_columns, &normalize_legacy_base_project/1)
  end

  defp read_projects(conn, :legacy_extended) do
    columns = @base_project_columns ++ @adopted_project_columns ++ @folded_project_columns
    project_rows(conn, columns, &normalize_legacy_extended_project/1)
  end

  defp project_rows(conn, columns, normalize) do
    sql = "SELECT #{Enum.join(columns, ", ")} FROM projects"

    case Exqlite.Sqlite3.prepare(conn, sql) do
      {:ok, stmt} ->
        try do
          collect_project_rows(conn, stmt, columns, normalize, [])
        after
          Exqlite.Sqlite3.release(conn, stmt)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp collect_project_rows(conn, stmt, columns, normalize, rows) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, values} ->
        project =
          columns
          |> Enum.zip(values)
          |> Map.new()
          |> normalize.()

        collect_project_rows(conn, stmt, columns, normalize, [project | rows])

      :done ->
        {:ok, Enum.reverse(rows)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_legacy_base_project(project) do
    project
    |> Map.merge(Map.new(@adopted_project_columns, fn column -> {column, nil} end))
    |> Map.put("source", "manual")
    |> Map.put("metadata", "{}")
  end

  defp normalize_legacy_extended_project(project) do
    metadata =
      @folded_project_columns
      |> Map.new(fn column -> {column, decode_json_or_preserve(Map.get(project, column))} end)
      |> then(&%{"legacy_extended" => &1})
      |> Jason.encode!()

    project
    |> Map.take(@base_project_columns ++ @adopted_project_columns)
    |> Map.put("metadata", metadata)
  end

  defp decode_json_or_preserve(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} -> decoded
      {:error, _reason} -> value
    end
  end

  defp decode_json_or_preserve(value), do: value

  defp insert_projects(conn, projects) do
    columns = @base_project_columns ++ @adopted_project_columns ++ ["metadata"]
    placeholders = Enum.map_join(columns, ", ", fn _ -> "?" end)

    sql =
      "INSERT INTO projects_baseline_new (#{Enum.join(columns, ", ")}) VALUES (#{placeholders})"

    Enum.reduce_while(projects, :ok, fn project, :ok ->
      case execute_with_params(conn, sql, Enum.map(columns, &Map.fetch!(project, &1))) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp create_baseline_support_objects(_conn, :legacy_extended), do: :ok

  defp create_baseline_support_objects(conn, _baseline) do
    statements = [
      "CREATE INDEX idx_issues_parent ON issues(parent)",
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
      """,
      "INSERT INTO issues_fts (issue_id, title, description) SELECT id, title, COALESCE(description, '') FROM issues"
    ]

    Enum.reduce_while(statements, :ok, fn sql, :ok ->
      case execute(conn, sql) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp canonical_projects_table_sql(table_name) do
    """
    CREATE TABLE #{table_name} (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      path TEXT,
      status TEXT NOT NULL DEFAULT 'active',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      description TEXT,
      stack TEXT,
      domain TEXT,
      repo_url TEXT,
      canonical_path TEXT,
      source TEXT NOT NULL DEFAULT 'manual',
      last_synced_at TEXT,
      metadata TEXT NOT NULL DEFAULT '{}'
    )
    """
  end

  defp protected_row_counts(conn) do
    @core_tables
    |> Enum.reject(&(&1 in ["agents", "project_agents", "locks", "id_counter"]))
    |> Enum.reduce_while({:ok, %{}}, fn table, {:ok, counts} ->
      case scalar(conn, "SELECT COUNT(*) FROM #{table}") do
        {:ok, count} -> {:cont, {:ok, Map.put(counts, table, count)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp verify_protected_row_counts(conn, expected) do
    case protected_row_counts(conn) do
      {:ok, ^expected} -> :ok
      _ -> {:error, :verification_mismatch}
    end
  end

  defp verify_fts_row_count(conn) do
    with {:ok, issues_count} <- scalar(conn, "SELECT COUNT(*) FROM issues"),
         {:ok, fts_count} <- scalar(conn, "SELECT COUNT(*) FROM issues_fts"),
         true <- issues_count == fts_count do
      :ok
    else
      _ -> {:error, :verification_mismatch}
    end
  end

  defp verify_canonical_projects(conn) do
    if table_columns(conn, "projects") == @canonical_project_fingerprint do
      :ok
    else
      {:error, :verification_mismatch}
    end
  end

  defp verify_foreign_keys(_conn, false), do: :ok
  defp verify_foreign_keys(conn, true), do: foreign_key_check(conn)

  defp maybe_disable_foreign_keys(_conn, false), do: :ok
  defp maybe_disable_foreign_keys(conn, true), do: execute(conn, "PRAGMA foreign_keys=OFF")

  defp detect_populated_baseline(@base_project_columns, :absent), do: {:ok, :legacy_base}

  defp detect_populated_baseline(project_columns, :present) do
    if Enum.sort(project_columns) ==
         Enum.sort(@base_project_columns ++ @adopted_project_columns ++ @folded_project_columns) do
      {:ok, :legacy_extended}
    else
      {:error, :unknown_baseline}
    end
  end

  defp detect_populated_baseline(_project_columns, _support_state),
    do: {:error, :unknown_baseline}

  defp validate_core_tables(conn) do
    with true <- Enum.all?(@core_tables, &table_exists?(conn, &1)),
         true <- core_columns_match?(conn),
         {:ok, project_columns} <- project_column_names(conn),
         true <-
           Enum.take(project_columns, length(@base_project_columns)) == @base_project_columns do
      :ok
    else
      _ -> {:error, :unknown_baseline}
    end
  end

  defp core_columns_match?(conn) do
    Enum.all?(@core_column_fingerprints, fn {table, expected_columns} ->
      actual_columns = table_columns(conn, table)

      actual_columns == expected_columns or
        (table == "issues" and priority_default_zero?(actual_columns, expected_columns)) or
        (table == "dependencies" and dependencies_pk_matches?(actual_columns, expected_columns))
    end)
  end

  defp priority_default_zero?(actual_columns, expected_columns) do
    actual_columns ==
      Enum.map(expected_columns, fn
        {"priority", "INTEGER", 0, nil, 0} -> {"priority", "INTEGER", 0, "0", 0}
        column -> column
      end)
  end

  defp dependencies_pk_matches?(actual_columns, expected_columns) do
    actual_columns ==
      Enum.map(expected_columns, fn
        {"dep_type", "TEXT", 1, "'blocks'", 0} -> {"dep_type", "TEXT", 1, "'blocks'", 3}
        column -> column
      end)
  end

  defp project_column_names(conn) do
    case Exqlite.Sqlite3.prepare(conn, "PRAGMA table_info(projects)") do
      {:ok, stmt} ->
        try do
          collect_column_names(conn, stmt, [])
        after
          Exqlite.Sqlite3.release(conn, stmt)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp collect_column_names(conn, stmt, columns) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [_cid, name | _]} -> collect_column_names(conn, stmt, [name | columns])
      :done -> {:ok, Enum.reverse(columns)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp table_columns(conn, table) do
    case Exqlite.Sqlite3.prepare(conn, "PRAGMA table_info(#{table})") do
      {:ok, stmt} ->
        try do
          collect_column_details(conn, stmt, [])
        after
          Exqlite.Sqlite3.release(conn, stmt)
        end

      {:error, _reason} ->
        []
    end
  end

  defp collect_column_details(conn, stmt, columns) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [_cid, name, type, not_null, default, primary_key]} ->
        collect_column_details(
          conn,
          stmt,
          [{name, type, not_null, default, primary_key} | columns]
        )

      :done ->
        Enum.reverse(columns)

      {:error, _reason} ->
        []
    end
  end

  defp legacy_extended_object_state(conn) do
    if Enum.all?(@legacy_extended_objects, &object_exists?(conn, &1)) do
      {:ok, :present}
    else
      if Enum.all?(@legacy_extended_objects, &(not object_exists?(conn, &1))) do
        {:ok, :absent}
      else
        {:error, :unknown_baseline}
      end
    end
  end

  defp user_table_names(conn) do
    case Exqlite.Sqlite3.prepare(
           conn,
           "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
         ) do
      {:ok, stmt} ->
        try do
          collect_table_names(conn, stmt, [])
        after
          Exqlite.Sqlite3.release(conn, stmt)
        end

      {:error, _reason} ->
        ["unknown"]
    end
  end

  defp collect_table_names(conn, stmt, tables) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [name]} -> collect_table_names(conn, stmt, [name | tables])
      :done -> Enum.reverse(tables)
      {:error, _reason} -> ["unknown"]
    end
  end

  defp table_exists?(conn, table_name), do: object_exists?(conn, table_name, "table")
  defp object_exists?(conn, object_name), do: object_exists?(conn, object_name, nil)

  defp object_exists?(conn, object_name, type) do
    sql =
      if type do
        "SELECT 1 FROM sqlite_master WHERE type = ? AND name = ?"
      else
        "SELECT 1 FROM sqlite_master WHERE name = ?"
      end

    params = if type, do: [type, object_name], else: [object_name]

    case query_one(conn, sql, params) do
      {:ok, [1]} -> true
      _ -> false
    end
  end

  defp execute_with_params(conn, sql, params) do
    case Exqlite.Sqlite3.prepare(conn, sql) do
      {:ok, stmt} ->
        try do
          with :ok <- Exqlite.Sqlite3.bind(stmt, params) do
            case Exqlite.Sqlite3.step(conn, stmt) do
              :done -> :ok
              {:error, reason} -> {:error, reason}
              other -> {:error, other}
            end
          end
        after
          Exqlite.Sqlite3.release(conn, stmt)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp query_one(conn, sql, params) do
    case Exqlite.Sqlite3.prepare(conn, sql) do
      {:ok, stmt} ->
        try do
          with :ok <- Exqlite.Sqlite3.bind(stmt, params) do
            case Exqlite.Sqlite3.step(conn, stmt) do
              {:row, row} -> {:ok, row}
              :done -> :done
              {:error, reason} -> {:error, reason}
            end
          end
        after
          Exqlite.Sqlite3.release(conn, stmt)
        end

      {:error, reason} ->
        {:error, reason}
    end
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
