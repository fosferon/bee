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
