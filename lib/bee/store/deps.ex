defmodule Bee.Store.Deps do
  @moduledoc false

  @directions [:blockers, :dependents]
  @max_traversal_depth 10
  @max_critical_path_depth 100

  @spec traverse(Exqlite.Sqlite3.db(), String.t(), keyword()) ::
          {:ok, [String.t()]} | {:error, term()}
  def traverse(conn, start_id, opts) do
    with {:ok, direction} <- direction(opts),
         {:ok, depth} <- depth(opts),
         {:ok, types} <- types(opts) do
      {from, to} =
        case direction do
          :blockers -> {"issue_id", "depends_on_id"}
          :dependents -> {"depends_on_id", "issue_id"}
        end

      placeholders = Enum.map_join(types, ", ", fn _ -> "?" end)

      sql = """
      WITH RECURSIVE walk(id, depth) AS (
        SELECT #{to}, 1 FROM dependencies WHERE #{from} = ? AND dep_type IN (#{placeholders})
        UNION
        SELECT d.#{to}, walk.depth + 1
        FROM dependencies d
        INNER JOIN walk ON d.#{from} = walk.id
        WHERE walk.depth < ? AND d.dep_type IN (#{placeholders})
      )
      SELECT DISTINCT id FROM walk
      """

      params = [start_id] ++ types ++ [depth] ++ types
      {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
      :ok = Exqlite.Sqlite3.bind(stmt, params)

      try do
        {:ok, collect_scalars(conn, stmt)}
      after
        Exqlite.Sqlite3.release(conn, stmt)
      end
    end
  end

  @spec critical_path(Exqlite.Sqlite3.db()) :: [String.t()]
  def critical_path(conn) do
    types = Bee.Dependency.Type.gating() |> Enum.map(&Bee.Dependency.Type.storage_name/1)
    placeholders = Enum.map_join(types, ", ", fn _ -> "?" end)

    sql = """
    WITH RECURSIVE paths(id, path, depth) AS (
      SELECT depends_on_id, depends_on_id, 1
      FROM dependencies
      WHERE dep_type IN (#{placeholders})
      UNION ALL
      SELECT dep.issue_id, paths.path || ',' || dep.issue_id, paths.depth + 1
      FROM dependencies dep
      INNER JOIN paths ON dep.depends_on_id = paths.id
      WHERE paths.depth < ? AND dep.dep_type IN (#{placeholders})
    )
    SELECT path FROM paths ORDER BY depth DESC, path ASC LIMIT 1
    """

    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    :ok = Exqlite.Sqlite3.bind(stmt, types ++ [@max_critical_path_depth] ++ types)

    try do
      case Exqlite.Sqlite3.step(conn, stmt) do
        {:row, [path]} -> String.split(path, ",")
        :done -> []
      end
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  @doc false
  @spec critical_path(Exqlite.Sqlite3.db(), keyword()) ::
          {:ok, [String.t()]} | {:error, term()}
  def critical_path(conn, opts) when is_list(opts) do
    with :ok <- validate_critical_path_opts(opts),
         {:ok, types} <- types(opts),
         {:ok, depth} <- critical_path_depth(opts) do
      case Keyword.get(opts, :root) do
        nil -> {:ok, global_critical_path(conn, types, depth, opts)}
        root -> {:ok, rooted_critical_path(conn, root, types, depth, opts)}
      end
    end
  end

  def critical_path(_conn, _opts), do: {:error, :invalid_spec}

  defp global_critical_path(conn, types, depth, opts) do
    placeholders = Enum.map_join(types, ", ", fn _ -> "?" end)
    {start_filter, start_params} = issue_filter("start_issue", opts)
    {blocker_filter, blocker_params} = issue_filter("start_blocker", opts)
    {next_filter, next_params} = issue_filter("next_issue", opts)

    sql = """
    WITH RECURSIVE paths(id, path, depth) AS (
      SELECT dep.depends_on_id, dep.depends_on_id, 1
      FROM dependencies dep
      INNER JOIN issues start_issue ON start_issue.id = dep.issue_id
      INNER JOIN issues start_blocker ON start_blocker.id = dep.depends_on_id
      WHERE dep.dep_type IN (#{placeholders})#{start_filter}#{blocker_filter}
      UNION ALL
      SELECT dep.issue_id, paths.path || ',' || dep.issue_id, paths.depth + 1
      FROM dependencies dep
      INNER JOIN paths ON dep.depends_on_id = paths.id
      INNER JOIN issues next_issue ON next_issue.id = dep.issue_id
      WHERE dep.dep_type IN (#{placeholders}) AND paths.depth < ?#{next_filter}
    )
    SELECT path FROM paths ORDER BY depth DESC, path ASC LIMIT 1
    """

    params =
      types ++ start_params ++ blocker_params ++ types ++ [depth] ++ next_params

    critical_path_query(conn, sql, params)
  end

  defp rooted_critical_path(conn, root, types, depth, opts) do
    placeholders = Enum.map_join(types, ", ", fn _ -> "?" end)
    {root_filter, root_params} = issue_filter("root_issue", opts)
    {next_filter, next_params} = issue_filter("next_issue", opts)

    sql = """
    WITH RECURSIVE paths(id, path, depth) AS (
      SELECT root_issue.id, root_issue.id, 0
      FROM issues root_issue
      WHERE root_issue.id = ?#{root_filter}
      UNION ALL
      SELECT dep.depends_on_id, dep.depends_on_id || ',' || paths.path, paths.depth + 1
      FROM dependencies dep
      INNER JOIN paths ON dep.issue_id = paths.id
      INNER JOIN issues next_issue ON next_issue.id = dep.depends_on_id
      WHERE dep.dep_type IN (#{placeholders}) AND paths.depth < ?#{next_filter}
    )
    SELECT path FROM paths ORDER BY depth DESC, path ASC LIMIT 1
    """

    params = [root] ++ root_params ++ types ++ [depth] ++ next_params
    critical_path_query(conn, sql, params)
  end

  defp critical_path_query(conn, sql, params) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    :ok = Exqlite.Sqlite3.bind(stmt, params)

    try do
      case Exqlite.Sqlite3.step(conn, stmt) do
        {:row, [path]} -> String.split(path, ",")
        :done -> []
      end
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  defp issue_filter(alias_name, opts) do
    filters =
      [
        {"project_id", Keyword.get(opts, :project_id)},
        {"status", Keyword.get(opts, :status)}
      ]
      |> Enum.reject(fn {_field, value} -> is_nil(value) end)

    sql = Enum.map_join(filters, "", fn {field, _value} -> " AND #{alias_name}.#{field} = ?" end)
    params = Enum.map(filters, &elem(&1, 1))
    {sql, params}
  end

  defp validate_critical_path_opts(opts) do
    allowed = [:root, :project_id, :status, :types, :depth]

    cond do
      not Keyword.keyword?(opts) -> {:error, :invalid_spec}
      Keyword.keys(opts) -- allowed != [] -> {:error, :invalid_spec}
      not valid_optional_binary?(Keyword.get(opts, :root)) -> {:error, :invalid_spec}
      not valid_optional_binary?(Keyword.get(opts, :project_id)) -> {:error, :invalid_spec}
      not valid_optional_binary?(Keyword.get(opts, :status)) -> {:error, :invalid_spec}
      true -> :ok
    end
  end

  defp valid_optional_binary?(nil), do: true
  defp valid_optional_binary?(value), do: is_binary(value) and value != ""

  defp critical_path_depth(opts) do
    case Keyword.get(opts, :depth, @max_critical_path_depth) do
      value when is_integer(value) and value > 0 and value <= @max_critical_path_depth ->
        {:ok, value}

      _ ->
        {:error, :invalid_spec}
    end
  end

  defp direction(opts) do
    case Keyword.get(opts, :direction, :blockers) do
      value when value in @directions -> {:ok, value}
      _ -> {:error, :invalid_spec}
    end
  end

  defp depth(opts) do
    case Keyword.get(opts, :depth, 3) do
      value when is_integer(value) and value > 0 and value <= @max_traversal_depth -> {:ok, value}
      _ -> {:error, :invalid_spec}
    end
  end

  defp types(opts) do
    types = Keyword.get(opts, :types, Bee.Dependency.Type.gating())

    if is_list(types) and types != [] and
         Enum.all?(types, &(Bee.Dependency.Type.validate(&1) == :ok)) do
      {:ok, Enum.map(types, &Bee.Dependency.Type.storage_name/1)}
    else
      {:error, :unknown_dep_type}
    end
  end

  defp collect_scalars(conn, stmt) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [id]} -> [id | collect_scalars(conn, stmt)]
      :done -> []
    end
  end
end
