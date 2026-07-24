defmodule Bee.Store do
  @moduledoc false

  @order_columns ~w(created_at updated_at priority id)a
  @order_directions [:asc, :desc]

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

  @spec update_issue(Exqlite.Sqlite3.db(), String.t(), map()) :: :ok | {:error, :not_found}
  def update_issue(conn, id, attrs) do
    case get_issue(conn, id) do
      {:ok, _issue} -> do_update_issue(conn, id, attrs)
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp do_update_issue(conn, id, attrs) do
    sets = []
    vals = []

    {sets, vals} = maybe_set(sets, vals, attrs, :title)
    {sets, vals} = maybe_set(sets, vals, attrs, :description)
    {sets, vals} = maybe_set(sets, vals, attrs, :status)
    {sets, vals} = maybe_set(sets, vals, attrs, :priority)
    {sets, vals} = maybe_set(sets, vals, attrs, :issue_type)
    {sets, vals} = maybe_set(sets, vals, attrs, :assigned_to)
    {sets, vals} = maybe_set(sets, vals, attrs, :project_id)
    {sets, vals} = maybe_set(sets, vals, attrs, :parent)
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

  @spec issue_parent(Exqlite.Sqlite3.db(), String.t()) ::
          {:ok, String.t() | nil} | {:error, :not_found}
  def issue_parent(conn, id) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT parent FROM issues WHERE id = ?")
    :ok = Exqlite.Sqlite3.bind(stmt, [id])

    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [parent]} ->
        Exqlite.Sqlite3.release(conn, stmt)
        {:ok, parent}

      :done ->
        Exqlite.Sqlite3.release(conn, stmt)
        {:error, :not_found}
    end
  end

  @doc """
  Validates pagination opts (:order_by, :limit, :offset).
  Raises ArgumentError on invalid input. Called from the public API before
  dispatching to GenServer so errors surface in the caller's process.
  """
  @spec validate_opts!(keyword()) :: :ok
  def validate_opts!(opts) do
    validate_order_by!(Keyword.get(opts, :order_by))
    validate_limit!(Keyword.get(opts, :limit))
    validate_offset!(Keyword.get(opts, :offset))
    :ok
  end

  defp validate_order_by!(nil), do: :ok

  defp validate_order_by!(order_by) when is_list(order_by) do
    Enum.each(order_by, fn
      {col, dir} when col in @order_columns and dir in @order_directions ->
        :ok

      col when col in @order_columns ->
        :ok

      other ->
        raise ArgumentError, "invalid order_by: #{inspect(other)}"
    end)
  end

  defp validate_order_by!(other) do
    raise ArgumentError, "invalid order_by: #{inspect(other)}"
  end

  defp validate_limit!(nil), do: :ok

  defp validate_limit!(limit) when is_integer(limit) and limit > 0, do: :ok

  defp validate_limit!(limit), do: raise(ArgumentError, "invalid limit: #{inspect(limit)}")

  defp validate_offset!(nil), do: :ok

  defp validate_offset!(offset) when is_integer(offset) and offset >= 0, do: :ok

  defp validate_offset!(offset), do: raise(ArgumentError, "invalid offset: #{inspect(offset)}")

  @spec list_issues(Exqlite.Sqlite3.db(), keyword()) :: {:ok, [map()]}
  def list_issues(conn, opts \\ []) do
    {where, params} = build_where(opts)
    {order_sql, order_params} = build_order(opts, default_order())
    {limit_sql, limit_params} = build_limit_offset(opts)
    sql = "SELECT * FROM issues#{where}#{order_sql}#{limit_sql}"
    run_query(conn, sql, params ++ order_params ++ limit_params, &enrich_issue(&1, conn))
  end

  @spec list_issues_raw(Exqlite.Sqlite3.db(), keyword()) :: {:ok, [map()]}
  def list_issues_raw(conn, opts \\ []) do
    {where, params} = build_where(opts)
    {order_sql, order_params} = build_order(opts, default_order())
    {limit_sql, limit_params} = build_limit_offset(opts)
    sql = "SELECT * FROM issues#{where}#{order_sql}#{limit_sql}"
    run_query(conn, sql, params ++ order_params ++ limit_params, & &1)
  end

  @spec count_issues(Exqlite.Sqlite3.db(), keyword()) :: {:ok, non_neg_integer()}
  def count_issues(conn, opts \\ []) do
    {where, params} = build_where(opts)
    sql = "SELECT COUNT(*) FROM issues#{where}"
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    unless params == [], do: :ok = Exqlite.Sqlite3.bind(stmt, params)

    count =
      case Exqlite.Sqlite3.step(conn, stmt) do
        {:row, [val]} -> val
        :done -> 0
      end

    Exqlite.Sqlite3.release(conn, stmt)
    {:ok, count}
  end

  @spec count_roots(Exqlite.Sqlite3.db(), keyword()) :: {:ok, non_neg_integer()}
  def count_roots(conn, opts \\ []) do
    {where, params} = build_where(opts)

    sql = """
    WITH scope AS (SELECT id, parent FROM issues#{where})
    SELECT COUNT(*) FROM scope
    WHERE scope.parent IS NULL
       OR NOT EXISTS (SELECT 1 FROM scope AS parent_check WHERE parent_check.id = scope.parent)
    """

    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    unless params == [], do: :ok = Exqlite.Sqlite3.bind(stmt, params)

    count =
      case Exqlite.Sqlite3.step(conn, stmt) do
        {:row, [val]} -> val
        :done -> 0
      end

    Exqlite.Sqlite3.release(conn, stmt)
    {:ok, count}
  end

  @doc """
  Returns a page of in-scope root issues plus their complete subtrees.

  Returns `{:ok, %{roots: [id], issues: [enriched], total_roots: n}}`.

  Roots are in-scope issues whose parent is NULL or whose parent is outside scope.
  Descendants are gathered via recursive CTE over the parent edge — a subtree stays
  whole even if a descendant falls outside the scope filter.

  Opts (in addition to scope filters in build_where):
    - :limit, :offset — applied to ROOTS
    - :order_by — ordering of ROOTS (default: priority DESC NULLs last, created_at DESC)
  """
  @spec list_tree_page(Exqlite.Sqlite3.db(), keyword()) ::
          {:ok, %{roots: [non_neg_integer()], issues: [map()], total_roots: non_neg_integer()}}
  def list_tree_page(conn, opts \\ []) do
    {:ok, total_roots} = count_roots(conn, opts)
    root_rows = fetch_root_page(conn, opts)

    case root_rows do
      [] ->
        {:ok, %{roots: [], issues: [], total_roots: total_roots}}

      _ ->
        root_ids = Enum.map(root_rows, &Map.get(&1, :raw_id))
        descendant_ids = gather_descendants(conn, root_ids)
        all_raw_ids = root_ids ++ descendant_ids
        issues = fetch_and_enrich_by_ids(conn, all_raw_ids)
        root_enriched_ids = root_ids |> Enum.map(&parse_numeric_id/1)
        {:ok, %{roots: root_enriched_ids, issues: issues, total_roots: total_roots}}
    end
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

  @spec insert_comment(Exqlite.Sqlite3.db(), String.t(), String.t(), keyword()) ::
          :ok | {:error, term()}
  def insert_comment(conn, issue_id, body, opts \\ []) do
    now = now_iso()
    author = Keyword.get(opts, :author)

    exec(conn, "INSERT INTO comments (issue_id, body, author, created_at) VALUES (?, ?, ?, ?)", [
      issue_id,
      body,
      author,
      now
    ])
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

  # --- Query builders ---

  defp default_order, do: [created_at: :asc]

  defp root_default_order, do: [priority: :desc, created_at: :desc]

  defp build_order(opts, default) do
    case Keyword.get(opts, :order_by) do
      nil ->
        build_order_clause(default)

      order_by when is_list(order_by) ->
        validated =
          Enum.map(order_by, fn
            {col, dir} when col in @order_columns and dir in @order_directions ->
              {col, dir}

            col when col in @order_columns ->
              {col, :asc}

            other ->
              raise ArgumentError, "invalid order_by: #{inspect(other)}"
          end)

        build_order_clause(validated)

      other ->
        raise ArgumentError, "invalid order_by: #{inspect(other)}"
    end
  end

  defp build_order_clause([]), do: {"", []}

  defp build_order_clause(order_spec) do
    parts =
      Enum.map(order_spec, fn {col, dir} ->
        col_str = Atom.to_string(col)
        dir_str = String.upcase(Atom.to_string(dir))

        case col do
          :priority ->
            "priority IS NULL, #{col_str} #{dir_str}"

          _ ->
            "#{col_str} #{dir_str}"
        end
      end)

    {" ORDER BY " <> Enum.join(parts, ", "), []}
  end

  defp build_limit_offset(opts) do
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset)

    case {limit, offset} do
      {nil, nil} ->
        {"", []}

      {nil, offset} when is_integer(offset) and offset >= 0 ->
        {" LIMIT -1 OFFSET ?", [offset]}

      {limit, nil} when is_integer(limit) and limit > 0 ->
        {" LIMIT ?", [limit]}

      {limit, offset} when is_integer(limit) and limit > 0 and is_integer(offset) and offset >= 0 ->
        {" LIMIT ? OFFSET ?", [limit, offset]}

      {limit, _} when not is_nil(limit) ->
        raise ArgumentError, "invalid limit: #{inspect(limit)}"

      {_, offset} when not is_nil(offset) ->
        raise ArgumentError, "invalid offset: #{inspect(offset)}"
    end
  end

  defp run_query(conn, sql, params, enrich_fn) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    unless params == [], do: :ok = Exqlite.Sqlite3.bind(stmt, params)
    rows = collect_rows(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    {:ok, Enum.map(rows, fn {cols, row} -> row_to_issue(cols, row) |> enrich_fn.() end)}
  end

  # --- Tree page internals ---

  defp fetch_root_page(conn, opts) do
    {where, params} = build_where(opts)
    {order_sql, order_params} = build_order(opts, root_default_order())
    {limit_sql, limit_params} = build_limit_offset(opts)

    sql = """
    WITH scope AS (SELECT * FROM issues#{where})
    SELECT scope.* FROM scope
    WHERE scope.parent IS NULL
       OR NOT EXISTS (SELECT 1 FROM scope AS p WHERE p.id = scope.parent)
    #{order_sql}#{limit_sql}
    """

    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)

    all_params = params ++ order_params ++ limit_params
    unless all_params == [], do: :ok = Exqlite.Sqlite3.bind(stmt, all_params)

    rows = collect_rows(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)

    Enum.map(rows, fn {cols, row} ->
      map = Enum.zip(cols, row) |> Map.new()
      %{raw_id: map["id"], title: map["title"]}
    end)
  end

  defp gather_descendants(conn, root_ids) do
    placeholders = root_ids |> Enum.map(fn _ -> "?" end) |> Enum.join(", ")

    sql = """
    WITH RECURSIVE subtree(id) AS (
      SELECT id FROM issues WHERE parent IN (#{placeholders})
      UNION ALL
      SELECT i.id FROM issues i
      INNER JOIN subtree s ON i.parent = s.id
    )
    SELECT DISTINCT id FROM subtree
    """

    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    :ok = Exqlite.Sqlite3.bind(stmt, root_ids)
    ids = collect_scalars(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    ids
  end

  defp fetch_and_enrich_by_ids(conn, raw_ids) do
    case raw_ids do
      [] ->
        []

      _ ->
        placeholders = raw_ids |> Enum.map(fn _ -> "?" end) |> Enum.join(", ")
        sql = "SELECT * FROM issues WHERE id IN (#{placeholders})"

        {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
        :ok = Exqlite.Sqlite3.bind(stmt, raw_ids)
        rows = collect_rows(conn, stmt)
        Exqlite.Sqlite3.release(conn, stmt)

        rows
        |> Enum.map(fn {cols, row} -> row_to_issue(cols, row) |> enrich_issue(conn) end)
        |> sort_by_root_order(conn, raw_ids)
    end
  end

  defp sort_by_root_order(issues, _conn, raw_ids) do
    # Build position map keyed by numeric id (roots first, then descendants in CTE order)
    order_map =
      raw_ids
      |> Enum.with_index()
      |> Map.new(fn {raw_id, idx} -> {parse_numeric_id(raw_id), idx} end)

    Enum.sort_by(issues, fn issue ->
      Map.get(order_map, issue.id, 999_999)
    end)
  end

  # --- Helpers ---

  # Fail soft: a hard `:done = step(...)` match turned a SQLite constraint
  # error (e.g. a FOREIGN KEY violation from a comment/lock/dependency
  # referencing a missing issue) into a `{:badmatch}` that crashed the owning
  # `Bee.Repo` GenServer and surfaced as HTTP 500 (GC-3353). We now surface the
  # error to the caller and always release the statement.
  @spec exec(Exqlite.Sqlite3.db(), String.t(), list()) :: :ok | {:error, term()}
  defp exec(conn, sql, params) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    :ok = Exqlite.Sqlite3.bind(stmt, params)
    result = Exqlite.Sqlite3.step(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)

    case result do
      :done -> :ok
      {:error, reason} -> {:error, reason}
    end
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

    # Label filtering via EXISTS subquery on issue_labels junction table.
    # Accepts a single label string or a list (AND — issue must have ALL).
    {clauses, params} =
      case Keyword.get(opts, :labels) do
        nil ->
          {clauses, params}

        label when is_binary(label) ->
          clause =
            "EXISTS (SELECT 1 FROM issue_labels il WHERE il.issue_id = issues.id AND il.label = ?)"

          {[clause | clauses], [label | params]}

        labels when is_list(labels) and labels != [] ->
          label_clauses =
            Enum.map(labels, fn _label ->
              "EXISTS (SELECT 1 FROM issue_labels il WHERE il.issue_id = issues.id AND il.label = ?)"
            end)

          {Enum.reverse(label_clauses) ++ clauses, Enum.reverse(labels) ++ params}

        _ ->
          {clauses, params}
      end

    if clauses == [] do
      {"", []}
    else
      {" WHERE " <> (clauses |> Enum.reverse() |> Enum.join(" AND ")), Enum.reverse(params)}
    end
  end

  defp now_iso, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
