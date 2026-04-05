defmodule Bee.World do
  @moduledoc false

  @spec new() :: :digraph.graph()
  def new do
    :digraph.new([:protected])
  end

  @spec rebuild(:digraph.graph(), Exqlite.Sqlite3.db()) :: :ok
  def rebuild(graph, conn) do
    Enum.each(:digraph.vertices(graph), &:digraph.del_vertex(graph, &1))

    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT id FROM projects")
    project_ids = collect_scalars(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    Enum.each(project_ids, &:digraph.add_vertex(graph, {:project, &1}))

    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT id FROM agents")
    agent_ids = collect_scalars(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    Enum.each(agent_ids, &:digraph.add_vertex(graph, {:agent, &1}))

    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT id, project_id, assigned_to FROM issues")
    issues = collect_triples(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)

    Enum.each(issues, fn {issue_id, project_id, assigned_to} ->
      :digraph.add_vertex(graph, {:issue, issue_id})
      if project_id, do: :digraph.add_edge(graph, {:project, project_id}, {:issue, issue_id})
      if assigned_to, do: :digraph.add_edge(graph, {:agent, assigned_to}, {:issue, issue_id})
    end)

    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT agent_id, project_id FROM project_agents")
    memberships = collect_pairs(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)

    Enum.each(memberships, fn {agent_id, project_id} ->
      :digraph.add_edge(graph, {:agent, agent_id}, {:project, project_id})
    end)

    :ok
  end

  @spec add_project(:digraph.graph(), String.t()) :: :ok
  def add_project(graph, project_id) do
    :digraph.add_vertex(graph, {:project, project_id})
    :ok
  end

  @spec add_agent(:digraph.graph(), String.t()) :: :ok
  def add_agent(graph, agent_id) do
    :digraph.add_vertex(graph, {:agent, agent_id})
    :ok
  end

  @spec add_issue(:digraph.graph(), String.t(), String.t() | nil) :: :ok
  def add_issue(graph, issue_id, project_id) do
    :digraph.add_vertex(graph, {:issue, issue_id})
    if project_id, do: :digraph.add_edge(graph, {:project, project_id}, {:issue, issue_id})
    :ok
  end

  @spec assign(:digraph.graph(), String.t(), String.t()) :: :ok
  def assign(graph, issue_id, agent_id) do
    edges = :digraph.in_edges(graph, {:issue, issue_id})

    Enum.each(edges, fn edge ->
      case :digraph.edge(graph, edge) do
        {_, {:agent, _}, {:issue, ^issue_id}, _} -> :digraph.del_edge(graph, edge)
        _ -> :ok
      end
    end)

    :digraph.add_edge(graph, {:agent, agent_id}, {:issue, issue_id})
    :ok
  end

  @spec join_project(:digraph.graph(), String.t(), String.t()) :: :ok
  def join_project(graph, agent_id, project_id) do
    :digraph.add_edge(graph, {:agent, agent_id}, {:project, project_id})
    :ok
  end

  @spec agent_load(:digraph.graph(), String.t(), Exqlite.Sqlite3.db()) :: integer()
  def agent_load(graph, agent_id, conn) do
    :digraph.out_neighbours(graph, {:agent, agent_id})
    |> Enum.count(fn
      {:issue, issue_id} ->
        case Bee.Store.get_issue(conn, issue_id) do
          {:ok, %{status: "open"}} -> true
          _ -> false
        end

      _ ->
        false
    end)
  end

  @spec who_blocks_whom(:digraph.graph(), :digraph.graph()) :: [{String.t(), String.t()}]
  def who_blocks_whom(dep_graph, alloc_graph) do
    :digraph.edges(dep_graph)
    |> Enum.flat_map(fn edge ->
      case :digraph.edge(dep_graph, edge) do
        {_, blocker_id, blocked_id, _} ->
          blocker_agent = find_assigned_agent(alloc_graph, blocker_id)
          blocked_agent = find_assigned_agent(alloc_graph, blocked_id)

          if blocker_agent && blocked_agent && blocker_agent != blocked_agent do
            [{blocker_agent, blocked_agent}]
          else
            []
          end

        _ ->
          []
      end
    end)
    |> Enum.uniq()
  end

  @spec bottlenecks(:digraph.graph(), :digraph.graph(), Exqlite.Sqlite3.db()) :: [
          {String.t(), integer(), [String.t()]}
        ]
  def bottlenecks(dep_graph, alloc_graph, conn) do
    critical = Bee.Graph.critical_path(dep_graph)

    agent_map =
      Enum.reduce(critical, %{}, fn issue_id, acc ->
        case find_assigned_agent(alloc_graph, issue_id) do
          nil -> acc
          agent_id -> Map.update(acc, agent_id, [issue_id], &[issue_id | &1])
        end
      end)

    agent_map
    |> Enum.map(fn {agent_id, _} ->
      load = agent_load(alloc_graph, agent_id, conn)
      projects = agent_projects(alloc_graph, agent_id)
      {agent_id, load, projects}
    end)
    |> Enum.sort_by(fn {_, load, _} -> -load end)
  end

  @spec available_in_project(:digraph.graph(), String.t(), Exqlite.Sqlite3.db()) :: [String.t()]
  def available_in_project(graph, project_id, conn) do
    :digraph.vertices(graph)
    |> Enum.filter(fn
      {:agent, agent_id} ->
        outs = :digraph.out_neighbours(graph, {:agent, agent_id})
        member = Enum.member?(outs, {:project, project_id})
        member and agent_load(graph, agent_id, conn) == 0

      _ ->
        false
    end)
    |> Enum.map(fn {:agent, id} -> id end)
  end

  # --- Helpers ---

  defp find_assigned_agent(alloc_graph, issue_id) do
    in_edges = :digraph.in_edges(alloc_graph, {:issue, issue_id})

    Enum.find_value(in_edges, fn edge ->
      case :digraph.edge(alloc_graph, edge) do
        {_, {:agent, agent_id}, {:issue, ^issue_id}, _} -> agent_id
        _ -> nil
      end
    end)
  end

  defp agent_projects(alloc_graph, agent_id) do
    :digraph.out_neighbours(alloc_graph, {:agent, agent_id})
    |> Enum.flat_map(fn
      {:project, pid} -> [pid]
      _ -> []
    end)
  end

  defp collect_scalars(conn, stmt) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [val]} -> [val | collect_scalars(conn, stmt)]
      :done -> []
    end
  end

  defp collect_pairs(conn, stmt) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [a, b]} -> [{a, b} | collect_pairs(conn, stmt)]
      :done -> []
    end
  end

  defp collect_triples(conn, stmt) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [a, b, c]} -> [{a, b, c} | collect_triples(conn, stmt)]
      :done -> []
    end
  end
end
