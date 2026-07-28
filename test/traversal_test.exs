defmodule Bee.TraversalTest do
  use ExUnit.Case

  setup do
    db_path =
      Path.join(System.tmp_dir!(), "bee_traversal_#{:erlang.unique_integer([:positive])}.db")

    name = :"bee_traversal_#{:erlang.unique_integer([:positive])}"

    {:ok, pid} =
      Bee.Repo.start_link(db_path: db_path, prefix: "test", jsonl_path: nil, name: name)

    on_exit(fn ->
      if Process.alive?(pid) do
        try do
          GenServer.stop(pid)
        catch
          :exit, _ -> :ok
        end
      end

      File.rm(db_path)
    end)

    %{server: name}
  end

  test "traverses blockers and dependents with depth bounds", %{server: server} do
    for title <- ["one", "two", "three"], do: {:ok, _} = Bee.create(title, [], server)
    :ok = Bee.block(2, 1, server)
    :ok = Bee.block(3, 2, server)

    assert {:ok, [2, 1]} = Bee.traverse(3, [direction: :blockers, depth: 3], server)
    assert {:ok, [2]} = Bee.traverse(3, [direction: :blockers, depth: 1], server)
    assert {:ok, [2, 3]} = Bee.traverse(1, [direction: :dependents], server)
  end

  test "typed non-gating edges do not affect ready state", %{server: server} do
    {:ok, _} = Bee.create("source", [], server)
    {:ok, _} = Bee.create("related", [], server)

    assert :ok = Bee.block(2, 1, [type: :related], server)
    assert {:ok, []} = Bee.traverse(2, [types: [:blocks]], server)
    assert {:ok, [1]} = Bee.traverse(2, [types: [:related]], server)

    {:ok, ready} = Bee.ready([], server)
    assert Enum.map(ready, & &1.id) |> Enum.sort() == [1, 2]
  end

  test "keeps typed edges independent and removes them selectively", %{server: server} do
    {:ok, _} = Bee.create("source", [], server)
    {:ok, _} = Bee.create("dependent", [], server)

    assert :ok = Bee.block(2, 1, server)
    assert :ok = Bee.block(2, 1, [type: :related], server)
    assert {:ok, [1]} = Bee.traverse(2, [types: [:blocks]], server)
    assert {:ok, [1]} = Bee.traverse(2, [types: [:related]], server)

    assert :ok = Bee.unblock(2, 1, [type: :related], server)
    assert {:ok, [1]} = Bee.traverse(2, [types: [:blocks]], server)
    assert {:ok, []} = Bee.traverse(2, [types: [:related]], server)

    assert :ok = Bee.unblock(2, 1, server)
    assert {:ok, ready} = Bee.ready([], server)
    assert Enum.map(ready, & &1.id) |> Enum.sort() == [1, 2]
  end

  test "rejects an empty dependency type filter", %{server: server} do
    {:ok, _} = Bee.create("source", [], server)

    assert {:error, :unknown_dep_type} = Bee.traverse(1, [types: []], server)
  end

  test "treats every dependency type as acyclic", %{server: server} do
    {:ok, _} = Bee.create("first", [], server)
    {:ok, _} = Bee.create("second", [], server)

    assert :ok = Bee.block(2, 1, [type: :related], server)
    assert {:error, :cycle} = Bee.block(1, 2, server)
  end

  test "round-trips typed dependencies through JSONL", %{server: server} do
    {:ok, _} = Bee.create("source", [], server)
    {:ok, _} = Bee.create("dependent", [], server)
    :ok = Bee.block(2, 1, [type: :related], server)

    export_path =
      Path.join(
        System.tmp_dir!(),
        "bee_typed_export_#{:erlang.unique_integer([:positive])}.jsonl"
      )

    :ok = Bee.Export.export(GenServer.call(server, :conn), export_path)

    db_path =
      Path.join(System.tmp_dir!(), "bee_typed_import_#{:erlang.unique_integer([:positive])}.db")

    name = :"bee_typed_import_#{:erlang.unique_integer([:positive])}"

    {:ok, pid} =
      Bee.Repo.start_link(db_path: db_path, prefix: "test", jsonl_path: nil, name: name)

    on_exit(fn ->
      if Process.alive?(pid) do
        try do
          GenServer.stop(pid)
        catch
          :exit, _ -> :ok
        end
      end

      File.rm(export_path)
      File.rm(db_path)
    end)

    assert {:ok, 2} = GenServer.call(name, {:import_jsonl, export_path})

    assert [%{depends_on_id: "test-1", type: "related"}] =
             Bee.Store.get_dependencies(GenServer.call(name, :conn), "test-2")
  end

  test "candidate edges are advisory and reasoned", %{server: server} do
    {:ok, _} = Bee.register_project("bee", %{}, server)
    {:ok, _} = Bee.create("Source", [project_id: "bee", labels: ["query"]], server)
    {:ok, _} = Bee.create("Related", [project_id: "bee"], server)

    assert {:ok, [%{issue_id: 2, reason: "same_project", confidence: 0.8}]} =
             Bee.candidates(1, server)
  end

  test "critical path is derived from persisted gating edges", %{server: server} do
    for title <- ["one", "two", "three"], do: {:ok, _} = Bee.create(title, [], server)
    :ok = Bee.block(2, 1, server)
    :ok = Bee.block(3, 2, server)

    assert {:ok, [1, 2, 3]} = Bee.critical_path(server)
  end

  test "bottlenecks are derived from critical-path assignments", %{server: server} do
    {:ok, _} = Bee.register_project("bee", %{}, server)
    {:ok, _} = Bee.register_agent("alice", %{}, server)
    {:ok, _} = Bee.register_agent("bob", %{}, server)
    :ok = Bee.join_project("alice", "bee", server)
    :ok = Bee.join_project("bob", "bee", server)

    {:ok, _} = Bee.create("first", [], server)
    {:ok, _} = Bee.create("second", [], server)
    :ok = Bee.assign(1, "alice", server)
    :ok = Bee.assign(2, "bob", server)
    :ok = Bee.block(2, 1, server)

    assert Enum.sort(Bee.bottlenecks(server)) == [
             {"alice", 1, ["bee"]},
             {"bob", 1, ["bee"]}
           ]
  end
end
