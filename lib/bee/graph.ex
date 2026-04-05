defmodule Bee.Graph do
  @moduledoc false

  @spec new() :: :digraph.graph()
  def new do
    :digraph.new([:acyclic, :protected])
  end

  @spec rebuild(:digraph.graph(), Exqlite.Sqlite3.db()) :: :ok
  def rebuild(graph, conn) do
    Enum.each(:digraph.vertices(graph), &:digraph.del_vertex(graph, &1))

    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT id FROM issues")
    ids = collect_scalars(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    Enum.each(ids, &:digraph.add_vertex(graph, &1))

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(conn, "SELECT issue_id, depends_on_id FROM dependencies")

    deps = collect_pairs(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)

    Enum.each(deps, fn {issue_id, depends_on_id} ->
      :digraph.add_edge(graph, depends_on_id, issue_id)
    end)

    :ok
  end

  @spec add_dependency(:digraph.graph(), String.t(), String.t()) :: :ok | {:error, :cycle}
  def add_dependency(graph, issue_id, depends_on_id) do
    :digraph.add_vertex(graph, issue_id)
    :digraph.add_vertex(graph, depends_on_id)

    case :digraph.add_edge(graph, depends_on_id, issue_id) do
      {:error, {:bad_edge, _}} -> {:error, :cycle}
      _ -> :ok
    end
  end

  @spec remove_dependency(:digraph.graph(), String.t(), String.t()) :: :ok
  def remove_dependency(graph, issue_id, depends_on_id) do
    edges = :digraph.edges(graph, depends_on_id)

    Enum.each(edges, fn edge ->
      case :digraph.edge(graph, edge) do
        {_, ^depends_on_id, ^issue_id, _} -> :digraph.del_edge(graph, edge)
        _ -> :ok
      end
    end)

    :ok
  end

  @spec add_vertex(:digraph.graph(), String.t()) :: :ok
  def add_vertex(graph, id) do
    :digraph.add_vertex(graph, id)
    :ok
  end

  @spec ready_issues(:digraph.graph(), Exqlite.Sqlite3.db()) :: [String.t()]
  def ready_issues(graph, conn) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT id FROM issues WHERE status = 'open'")
    open_ids = collect_scalars(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)

    open_set = MapSet.new(open_ids)

    Enum.filter(open_ids, fn id ->
      blockers = :digraph.in_neighbours(graph, id)
      not Enum.any?(blockers, fn b -> MapSet.member?(open_set, b) end)
    end)
  end

  @spec blocked_by(:digraph.graph(), String.t()) :: [String.t()]
  def blocked_by(graph, issue_id) do
    :digraph.in_neighbours(graph, issue_id)
  end

  @spec blocks(:digraph.graph(), String.t()) :: [String.t()]
  def blocks(graph, issue_id) do
    :digraph.out_neighbours(graph, issue_id)
  end

  @spec critical_path(:digraph.graph()) :: [String.t()]
  def critical_path(graph) do
    vertices = :digraph.vertices(graph)
    sources = Enum.filter(vertices, fn v -> :digraph.in_neighbours(graph, v) == [] end)

    sources
    |> Enum.map(fn s -> longest_path(graph, s) end)
    |> Enum.max_by(&length/1, fn -> [] end)
  end

  defp longest_path(graph, vertex) do
    outs = :digraph.out_neighbours(graph, vertex)

    if outs == [] do
      [vertex]
    else
      best =
        outs
        |> Enum.map(fn o -> longest_path(graph, o) end)
        |> Enum.max_by(&length/1)

      [vertex | best]
    end
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
end
