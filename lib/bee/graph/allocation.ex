defmodule Bee.Graph.Allocation do
  @moduledoc false

  @spec agent_load(Exqlite.Sqlite3.db(), String.t()) :: non_neg_integer()
  def agent_load(conn, agent_id) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT COUNT(*) FROM issues WHERE assigned_to = ? AND status = 'open'"
      )

    :ok = Exqlite.Sqlite3.bind(stmt, [agent_id])

    try do
      case Exqlite.Sqlite3.step(conn, stmt) do
        {:row, [count]} -> count
        :done -> 0
      end
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  @spec who_blocks_whom(Exqlite.Sqlite3.db()) :: [{String.t(), String.t()}]
  def who_blocks_whom(conn) do
    types = Bee.Dependency.Type.gating() |> Enum.map(&Bee.Dependency.Type.storage_name/1)
    placeholders = Enum.map_join(types, ", ", fn _ -> "?" end)

    sql = """
    SELECT DISTINCT blocker.assigned_to, blocked.assigned_to
    FROM dependencies dep
    INNER JOIN issues blocker ON blocker.id = dep.depends_on_id
    INNER JOIN issues blocked ON blocked.id = dep.issue_id
    WHERE dep.dep_type IN (#{placeholders})
      AND blocker.assigned_to IS NOT NULL
      AND blocked.assigned_to IS NOT NULL
      AND blocker.assigned_to != blocked.assigned_to
    ORDER BY blocker.assigned_to, blocked.assigned_to
    """

    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    :ok = Exqlite.Sqlite3.bind(stmt, types)

    try do
      collect(conn, stmt)
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  @spec bottlenecks(Exqlite.Sqlite3.db()) :: [{String.t(), non_neg_integer(), [String.t()]}]
  def bottlenecks(conn) do
    conn
    |> Bee.Store.Deps.critical_path()
    |> Enum.reduce([], fn issue_id, agents ->
      case assigned_agent(conn, issue_id) do
        nil -> agents
        agent_id -> [agent_id | agents]
      end
    end)
    |> Enum.uniq()
    |> Enum.map(fn agent_id ->
      {agent_id, agent_load(conn, agent_id), agent_projects(conn, agent_id)}
    end)
    |> Enum.sort_by(fn {_agent_id, load, _projects} -> -load end)
  end

  defp collect(conn, stmt) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [blocker, blocked]} -> [{blocker, blocked} | collect(conn, stmt)]
      :done -> []
    end
  end

  defp assigned_agent(conn, issue_id) do
    scalar(conn, "SELECT assigned_to FROM issues WHERE id = ?", [issue_id])
  end

  defp agent_projects(conn, agent_id) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT project_id FROM project_agents WHERE agent_id = ?")
    :ok = Exqlite.Sqlite3.bind(stmt, [agent_id])

    try do
      collect_scalars(conn, stmt)
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  defp scalar(conn, sql, params) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    :ok = Exqlite.Sqlite3.bind(stmt, params)

    try do
      case Exqlite.Sqlite3.step(conn, stmt) do
        {:row, [value]} -> value
        :done -> nil
      end
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  defp collect_scalars(conn, stmt) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [value]} -> [value | collect_scalars(conn, stmt)]
      :done -> []
    end
  end
end
