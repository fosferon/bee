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

    assert {:ok, %{issues: [issue], withheld: %{relation_omitted: [:comments]}}} =
             Bee.query([status: "open", order_by: [priority: :desc]], server)

    assert issue.title == "Open"
  end

  test "query reports limit truncation and a refinement", %{server: server} do
    for number <- 1..3, do: {:ok, _} = Bee.create("Issue #{number}", [], server)

    assert {:ok,
            %{
              issues: issues,
              withheld: %{limit: 2},
              refine: [offset: 1]
            }} =
             Bee.query([limit: 1, include: [:comments]], server)

    assert length(issues) == 1
  end

  test "query appends id as a deterministic tie-breaker", %{server: server} do
    {:ok, _} = Bee.create("First", [priority: 5], server)
    {:ok, _} = Bee.create("Second", [priority: 5], server)

    {:ok, %{issues: first}} = Bee.query([order_by: [priority: :desc]], server)
    {:ok, %{issues: second}} = Bee.query([order_by: [priority: :desc]], server)

    assert Enum.map(first, & &1.id) == [1, 2]
    assert first == second
  end

  test "coordination events advance issue recency ordering", %{server: server} do
    {:ok, first} = Bee.create("First", [], server)
    {:ok, second} = Bee.create("Second", [], server)

    :ok = Bee.comment(first.id, "new coordination evidence", [], server)

    assert {:ok, %{issues: issues}} =
             Bee.query([order_by: [updated_at: :desc], detail: :minimal], server)

    assert Enum.map(issues, & &1.id) == [first.id, second.id]
  end

  test "query combines plain-text FTS, multiple projects, recency, and minimal detail", %{
    server: server
  } do
    {:ok, _} = Bee.register_project("mobus", %{}, server)
    {:ok, _} = Bee.register_project("mobus_umbrella", %{}, server)
    {:ok, _} = Bee.register_project("other", %{}, server)

    {:ok, first} = Bee.create("FameLine foundation", [project_id: "mobus"], server)
    {:ok, second} = Bee.create("FameLine cutover", [project_id: "mobus_umbrella"], server)
    {:ok, _} = Bee.create("FameLine unrelated", [project_id: "other"], server)
    {:ok, _} = Bee.create("Different track", [project_id: "mobus"], server)

    assert {:ok, %{issues: issues}} =
             Bee.query(
               [
                 text: "FameLine /",
                 project_ids: ["mobus", "mobus_umbrella"],
                 order_by: [id: :desc],
                 detail: :minimal
               ],
               server
             )

    assert issues == [
             %{
               id: second.id,
               title: "FameLine cutover",
               status: "open",
               priority: nil,
               labels: [],
               blocked_by: []
             },
             %{
               id: first.id,
               title: "FameLine foundation",
               status: "open",
               priority: nil,
               labels: [],
               blocked_by: []
             }
           ]

    :ok = Bee.block(second.id, first.id, server)

    assert {:ok, %{issues: [%{id: ready_id}]}} =
             Bee.query(
               [
                 text: "FameLine",
                 project_ids: ["mobus", "mobus_umbrella"],
                 ready: true,
                 detail: :minimal
               ],
               server
             )

    assert ready_id == first.id
  end

  test "ready honours query filters and pagination inside Bee", %{server: server} do
    {:ok, _} = Bee.register_project("one", %{}, server)
    {:ok, _} = Bee.register_project("two", %{}, server)
    {:ok, first} = Bee.create("First", [project_id: "one", priority: 1], server)
    {:ok, _} = Bee.create("Second", [project_id: "one", priority: 2], server)
    {:ok, _} = Bee.create("Other", [project_id: "two", priority: 3], server)
    :ok = Bee.block(2, first.id, server)

    assert {:ok, [%{id: id}]} =
             Bee.ready([project_id: "one", order_by: [priority: :desc], limit: 1], server)

    assert id == first.id
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

  test "query rejects a limit above the bounded public maximum", %{server: server} do
    assert_raise ArgumentError, ~r/invalid limit/, fn ->
      Bee.query([limit: 501], server)
    end
  end

  test "classifier accepts validated query specs", %{server: server} do
    spec = Bee.Query.Spec.new!(status: "open")
    assert Bee.Query.Classifier.classify(spec) == :fast
    assert :ok = Bee.Query.Classifier.assert_spec_coverage!()

    {:ok, _} = Bee.create("Still available", [], server)
    assert {:ok, %{issues: [_]}} = Bee.query(spec, server)
  end

  test "core and registered intents resolve through the query interpreter", %{server: server} do
    {:ok, _} = Bee.register_agent("alice", %{}, server)
    {:ok, _} = Bee.register_agent("bob", %{}, server)
    {:ok, alice_issue} = Bee.create("Alice", [], server)
    {:ok, bob_issue} = Bee.create("Bob", [], server)
    :ok = Bee.assign(alice_issue.id, "alice", server)
    :ok = Bee.assign(bob_issue.id, "bob", server)

    assert {:ok, %{issues: [%{title: "Alice"}]}} = Bee.ask(:what_next, [agent: "alice"], server)

    assert :ok = Bee.register_intent("bob_open", [assigned_to: "bob"], server)
    assert {:ok, %{issues: [%{title: "Bob"}]}} = Bee.ask("bob_open", [], server)
    assert :ok = Bee.remove_intent("bob_open", server)
    assert {:error, :unknown_intent} = Bee.ask("bob_open", [], server)
  end

  test "registered intents and measures are discoverable", %{server: server} do
    assert :ok = Bee.register_intent("recent", [order_by: [updated_at: :desc], limit: 5], server)
    assert :ok = Bee.register_measure("tokens", "token", [domain: :non_negative], server)

    assert {:ok, [%{name: "recent", spec: %{"limit" => 5}, usage_count: 0}]} =
             Bee.list_intents(server)

    assert {:ok, measures} = Bee.list_measures(server)

    assert Enum.any?(
             measures,
             &match?(%{name: "tokens", unit: "token", domain: "non_negative"}, &1)
           )

    assert Enum.any?(measures, &(&1.name == "effort" and &1.unit == "minutes"))
  end

  test "successful intents record usage asynchronously", %{server: server} do
    {:ok, _} = Bee.create("Open", [], server)
    assert {:ok, _} = Bee.ask(:what_next, [], server)

    Process.sleep(25)
    conn = GenServer.call(server, :conn)

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(conn, "SELECT count FROM intent_usage WHERE name = ? AND kind = ?")

    :ok = Exqlite.Sqlite3.bind(stmt, ["what_next", "core"])
    assert {:row, [1]} = Exqlite.Sqlite3.step(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
  end

  test "what_next excludes work with an outstanding gating dependency", %{server: server} do
    {:ok, blocker} = Bee.create("Blocker", [priority: 1], server)
    {:ok, blocked} = Bee.create("Blocked but higher priority", [priority: 100], server)
    :ok = Bee.block(blocked.id, blocker.id, server)

    assert {:ok, %{issues: issues}} = Bee.ask(:what_next, [limit: 5], server)
    assert Enum.map(issues, & &1.id) == [blocker.id]
  end

  test "external transforms use the compute lane and fail soft", %{server: server} do
    {:ok, _} = Bee.create("  padded  ", [], server)
    assert :ok = Bee.Query.Transform.register(:strip, &String.trim/1)

    assert {:ok, %{issues: [%{title: "padded"}], withheld: %{transformed: [_]}}} =
             Bee.query([transforms: %{title: {:external, :strip}}], server)

    assert :ok = Bee.Query.Transform.remove(:strip)

    assert {:ok, %{issues: [%{title: "  padded  "}], withheld: %{}}} =
             Bee.query([transforms: %{title: {:external, :strip}}], server)
  end

  test "registered intents preserve transforms and can include labels", %{server: server} do
    {:ok, _} = Bee.create("  padded  ", [labels: ["query"]], server)
    assert :ok = Bee.Query.Transform.register(:strip, &String.trim/1)

    assert :ok =
             Bee.register_intent(
               "trimmed_labeled",
               [include: [:labels], transforms: %{title: {:external, :strip}}],
               server
             )

    assert {:ok, %{issues: [%{title: "padded", labels: ["query"]}]}} =
             Bee.ask("trimmed_labeled", [], server)

    assert :ok = Bee.Query.Transform.remove(:strip)
  end
end
