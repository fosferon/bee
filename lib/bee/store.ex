defmodule Bee.Store do
  @moduledoc false

  @spec init_schema(Exqlite.Sqlite3.db()) :: :ok
  def init_schema(conn) do
    Exqlite.Sqlite3.execute(conn, "PRAGMA journal_mode=WAL")
    Exqlite.Sqlite3.execute(conn, "PRAGMA foreign_keys=ON")
    Exqlite.Sqlite3.execute(conn, "PRAGMA synchronous=NORMAL")

    statements = [
      """
      CREATE TABLE IF NOT EXISTS projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        path TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS agents (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'worker',
        status TEXT NOT NULL DEFAULT 'idle',
        capabilities TEXT,
        updated_at TEXT NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS project_agents (
        project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
        agent_id TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
        role TEXT NOT NULL DEFAULT 'worker',
        PRIMARY KEY (project_id, agent_id)
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS issues (
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
      "CREATE INDEX IF NOT EXISTS idx_issues_status ON issues(status)",
      "CREATE INDEX IF NOT EXISTS idx_issues_project ON issues(project_id)",
      "CREATE INDEX IF NOT EXISTS idx_issues_assigned ON issues(assigned_to)",
      """
      CREATE TABLE IF NOT EXISTS issue_labels (
        issue_id TEXT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
        label TEXT NOT NULL,
        PRIMARY KEY (issue_id, label)
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS dependencies (
        issue_id TEXT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
        depends_on_id TEXT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
        dep_type TEXT NOT NULL DEFAULT 'blocks',
        created_at TEXT NOT NULL,
        PRIMARY KEY (issue_id, depends_on_id)
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS comments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        issue_id TEXT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
        body TEXT NOT NULL,
        author TEXT,
        created_at TEXT NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS locks (
        issue_id TEXT PRIMARY KEY REFERENCES issues(id) ON DELETE CASCADE,
        locked_by TEXT REFERENCES agents(id),
        locked_at TEXT NOT NULL,
        expires_at TEXT NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS id_counter (
        prefix TEXT PRIMARY KEY,
        next_id INTEGER NOT NULL DEFAULT 1
      )
      """
    ]

    Enum.each(statements, fn sql ->
      :ok = Exqlite.Sqlite3.execute(conn, sql)
    end)

    :ok
  end

  # --- Issue CRUD ---

  @spec insert_issue(Exqlite.Sqlite3.db(), map()) :: {:ok, map()}
  def insert_issue(conn, attrs) do
    now = now_iso()
    id = Map.fetch!(attrs, :id)

    sql = """
    INSERT INTO issues (id, title, description, status, priority, issue_type,
                        project_id, assigned_to, parent, created_at, created_by, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    exec(conn, sql, [
      id,
      Map.fetch!(attrs, :title),
      Map.get(attrs, :description),
      Map.get(attrs, :status, "open"),
      Map.get(attrs, :priority),
      Map.get(attrs, :issue_type, "task"),
      Map.get(attrs, :project_id),
      Map.get(attrs, :assigned_to),
      Map.get(attrs, :parent),
      Map.get(attrs, :created_at, now),
      Map.get(attrs, :created_by),
      now
    ])

    labels = Map.get(attrs, :labels, [])
    Enum.each(labels, fn label -> insert_label(conn, id, label) end)

    get_issue(conn, id)
  end

  @spec get_issue(Exqlite.Sqlite3.db(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_issue(conn, id) do
    sql = "SELECT * FROM issues WHERE id = ?"
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    :ok = Exqlite.Sqlite3.bind(stmt, [id])

    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, row} ->
        {:ok, cols} = Exqlite.Sqlite3.columns(conn, stmt)
        Exqlite.Sqlite3.release(conn, stmt)
        issue = row_to_issue(cols, row) |> enrich_issue(conn)
        {:ok, issue}

      :done ->
        Exqlite.Sqlite3.release(conn, stmt)
        {:error, :not_found}
    end
  end

  @spec update_issue(Exqlite.Sqlite3.db(), String.t(), map()) :: :ok
  def update_issue(conn, id, attrs) do
    sets = []
    vals = []

    {sets, vals} = maybe_set(sets, vals, attrs, :title)
    {sets, vals} = maybe_set(sets, vals, attrs, :description)
    {sets, vals} = maybe_set(sets, vals, attrs, :status)
    {sets, vals} = maybe_set(sets, vals, attrs, :priority)
    {sets, vals} = maybe_set(sets, vals, attrs, :assigned_to)
    {sets, vals} = maybe_set(sets, vals, attrs, :project_id)
    {sets, vals} = maybe_set(sets, vals, attrs, :close_reason)

    {sets, vals} =
      if Map.has_key?(attrs, :closed_at) do
        {["closed_at = ?" | sets], [Map.get(attrs, :closed_at) | vals]}
      else
        {sets, vals}
      end

    if sets == [] and not Map.has_key?(attrs, :labels) do
      :ok
    else
      unless sets == [] do
        sets = ["updated_at = ?" | sets]
        vals = [now_iso() | vals]

        set_clause = sets |> Enum.reverse() |> Enum.join(", ")
        sql = "UPDATE issues SET #{set_clause} WHERE id = ?"
        exec(conn, sql, Enum.reverse(vals) ++ [id])
      end

      if Map.has_key?(attrs, :labels) do
        exec(conn, "DELETE FROM issue_labels WHERE issue_id = ?", [id])
        Enum.each(Map.get(attrs, :labels, []), fn label -> insert_label(conn, id, label) end)
      end

      :ok
    end
  end

  @spec list_issues(Exqlite.Sqlite3.db(), keyword()) :: {:ok, [map()]}
  def list_issues(conn, opts \\ []) do
    {where, params} = build_where(opts)
    sql = "SELECT * FROM issues#{where} ORDER BY created_at ASC"
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    unless params == [], do: :ok = Exqlite.Sqlite3.bind(stmt, params)
    rows = collect_rows(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    {:ok, Enum.map(rows, fn {cols, row} -> row_to_issue(cols, row) |> enrich_issue(conn) end)}
  end

  @spec list_issues_raw(Exqlite.Sqlite3.db(), keyword()) :: {:ok, [map()]}
  def list_issues_raw(conn, opts \\ []) do
    {where, params} = build_where(opts)
    sql = "SELECT * FROM issues#{where} ORDER BY created_at ASC"
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    unless params == [], do: :ok = Exqlite.Sqlite3.bind(stmt, params)
    rows = collect_rows(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    {:ok, Enum.map(rows, fn {cols, row} -> row_to_issue(cols, row) end)}
  end

  # --- Labels ---

  defp insert_label(conn, issue_id, label) do
    exec(conn, "INSERT OR IGNORE INTO issue_labels (issue_id, label) VALUES (?, ?)", [
      issue_id,
      label
    ])
  end

  @spec get_labels(Exqlite.Sqlite3.db(), String.t()) :: [String.t()]
  def get_labels(conn, issue_id) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(conn, "SELECT label FROM issue_labels WHERE issue_id = ?")

    :ok = Exqlite.Sqlite3.bind(stmt, [issue_id])
    labels = collect_scalars(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    labels
  end

  # --- Comments ---

  @spec insert_comment(Exqlite.Sqlite3.db(), String.t(), String.t(), keyword()) :: :ok
  def insert_comment(conn, issue_id, body, opts \\ []) do
    now = now_iso()
    author = Keyword.get(opts, :author)

    exec(conn, "INSERT INTO comments (issue_id, body, author, created_at) VALUES (?, ?, ?, ?)", [
      issue_id,
      body,
      author,
      now
    ])

    :ok
  end

  @spec get_comments(Exqlite.Sqlite3.db(), String.t()) :: [map()]
  def get_comments(conn, issue_id) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT id, issue_id, body, author, created_at FROM comments WHERE issue_id = ? ORDER BY created_at ASC"
      )

    :ok = Exqlite.Sqlite3.bind(stmt, [issue_id])
    rows = collect_rows(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)

    Enum.map(rows, fn {cols, row} ->
      map = Enum.zip(cols, row) |> Map.new()

      %{
        id: map["id"],
        issue_id: map["issue_id"],
        body: map["body"],
        author: map["author"],
        created_at: map["created_at"]
      }
    end)
  end

  # --- Dependencies ---

  @spec insert_dependency(Exqlite.Sqlite3.db(), String.t(), String.t()) :: :ok
  def insert_dependency(conn, issue_id, depends_on_id) do
    exec(
      conn,
      "INSERT OR IGNORE INTO dependencies (issue_id, depends_on_id, dep_type, created_at) VALUES (?, ?, 'blocks', ?)",
      [issue_id, depends_on_id, now_iso()]
    )

    :ok
  end

  @spec remove_dependency(Exqlite.Sqlite3.db(), String.t(), String.t()) :: :ok
  def remove_dependency(conn, issue_id, depends_on_id) do
    exec(conn, "DELETE FROM dependencies WHERE issue_id = ? AND depends_on_id = ?", [
      issue_id,
      depends_on_id
    ])

    :ok
  end

  @spec get_blocked_by(Exqlite.Sqlite3.db(), String.t()) :: [String.t()]
  def get_blocked_by(conn, issue_id) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT depends_on_id FROM dependencies WHERE issue_id = ?"
      )

    :ok = Exqlite.Sqlite3.bind(stmt, [issue_id])
    result = collect_scalars(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    result
  end

  @spec get_blocks(Exqlite.Sqlite3.db(), String.t()) :: [String.t()]
  def get_blocks(conn, issue_id) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT issue_id FROM dependencies WHERE depends_on_id = ?"
      )

    :ok = Exqlite.Sqlite3.bind(stmt, [issue_id])
    result = collect_scalars(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    result
  end

  # --- Helpers ---

  defp exec(conn, sql, params) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    :ok = Exqlite.Sqlite3.bind(stmt, params)
    :done = Exqlite.Sqlite3.step(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    :ok
  end

  def collect_rows(conn, stmt) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, row} ->
        {:ok, cols} = Exqlite.Sqlite3.columns(conn, stmt)
        [{cols, row} | collect_rows(conn, stmt)]

      :done ->
        []
    end
  end

  defp collect_scalars(conn, stmt) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [val]} -> [val | collect_scalars(conn, stmt)]
      :done -> []
    end
  end

  defp row_to_issue(cols, row) do
    map = Enum.zip(cols, row) |> Map.new()

    %{
      id: map["id"],
      title: map["title"],
      description: map["description"],
      status: map["status"],
      priority: map["priority"],
      issue_type: map["issue_type"],
      project_id: map["project_id"],
      assigned_to: map["assigned_to"],
      parent: map["parent"],
      created_at: map["created_at"],
      created_by: map["created_by"],
      updated_at: map["updated_at"],
      closed_at: map["closed_at"],
      close_reason: map["close_reason"]
    }
  end

  defp enrich_issue(issue, conn) do
    labels = get_labels(conn, issue.id)
    blocked_by = get_blocked_by(conn, issue.id)
    blocks = get_blocks(conn, issue.id)

    numeric_id = parse_numeric_id(issue.id)
    blocked_by_numeric = Enum.map(blocked_by, &parse_numeric_id/1)
    blocks_numeric = Enum.map(blocks, &parse_numeric_id/1)
    parent_numeric = if issue.parent, do: parse_numeric_id(issue.parent)

    lock = get_lock_info(conn, issue.id)

    Map.merge(issue, %{
      id: numeric_id,
      labels: labels,
      blocked_by: blocked_by_numeric,
      blocks: blocks_numeric,
      parent: parent_numeric,
      locked: lock != nil,
      lock: lock
    })
  end

  defp parse_numeric_id(id) when is_binary(id) do
    case String.split(id, "-") do
      parts when length(parts) >= 2 ->
        n = List.last(parts)

        case Integer.parse(n) do
          {num, ""} -> num
          _ -> id
        end

      _ ->
        id
    end
  end

  defp parse_numeric_id(id), do: id

  defp get_lock_info(conn, issue_id) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(conn, "SELECT * FROM locks WHERE issue_id = ?")

    :ok = Exqlite.Sqlite3.bind(stmt, [issue_id])

    result =
      case Exqlite.Sqlite3.step(conn, stmt) do
        {:row, row} ->
          {:ok, cols} = Exqlite.Sqlite3.columns(conn, stmt)
          map = Enum.zip(cols, row) |> Map.new()

          %{
            locked_by: map["locked_by"],
            locked_at: map["locked_at"],
            expires_at: map["expires_at"]
          }

        :done ->
          nil
      end

    Exqlite.Sqlite3.release(conn, stmt)
    result
  end

  defp maybe_set(sets, vals, attrs, key) do
    if Map.has_key?(attrs, key) do
      val = Map.get(attrs, key)
      {["#{key} = ?" | sets], [val | vals]}
    else
      {sets, vals}
    end
  end

  defp build_where(opts) do
    {clauses, params} =
      Enum.reduce([:status, :project_id, :assigned_to], {[], []}, fn key, {c, p} ->
        case Keyword.get(opts, key) do
          nil -> {c, p}
          v -> {["#{key} = ?" | c], [v | p]}
        end
      end)

    if clauses == [] do
      {"", []}
    else
      {" WHERE " <> (clauses |> Enum.reverse() |> Enum.join(" AND ")),
       Enum.reverse(params)}
    end
  end

  defp now_iso, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
