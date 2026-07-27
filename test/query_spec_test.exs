defmodule Bee.QuerySpecTest do
  use ExUnit.Case

  setup do
    db_path =
      Path.join(System.tmp_dir!(), "bee_query_#{:erlang.unique_integer([:positive])}.db")

    name = :"bee_query_#{:erlang.unique_integer([:positive])}"

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

  test "query executes a validated spec through the reader path", %{server: server} do
    {:ok, _} = Bee.create("Open", [priority: 1], server)
    {:ok, closed} = Bee.create("Closed", [priority: 2], server)
    :ok = Bee.update(closed.id, %{status: "closed"}, server)

    assert {:ok, %{issues: [issue], withheld: %{}, refine: []}} =
             Bee.query([status: "open", order_by: [priority: :desc]], server)

    assert issue.title == "Open"
  end

  test "query appends id as a deterministic tie-breaker", %{server: server} do
    {:ok, _} = Bee.create("First", [priority: 5], server)
    {:ok, _} = Bee.create("Second", [priority: 5], server)

    {:ok, %{issues: first}} = Bee.query([order_by: [priority: :desc]], server)
    {:ok, %{issues: second}} = Bee.query([order_by: [priority: :desc]], server)

    assert Enum.map(first, & &1.id) == [1, 2]
    assert first == second
  end

  test "structural spec failures raise from the facade but return from the message boundary", %{
    server: server
  } do
    assert_raise ArgumentError, ~r/invalid query spec field/, fn ->
      Bee.query([sql: "DROP TABLE issues"], server)
    end

    pid = Process.whereis(server)

    assert {:error, {:invalid_spec_field, :sql}} =
             GenServer.call(server, {:query, [sql: "DROP TABLE issues"]})

    assert Process.alive?(pid)
  end

  test "classifier accepts validated query specs", %{server: server} do
    spec = Bee.Query.Spec.new!(status: "open")
    assert Bee.Query.Classifier.classify(spec) == :fast

    {:ok, _} = Bee.create("Still available", [], server)
    assert {:ok, %{issues: [_]}} = Bee.query(spec, server)
  end
end
