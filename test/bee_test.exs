defmodule BeeTest do
  use ExUnit.Case

  setup do
    db_path = Path.join(System.tmp_dir!(), "bee_test_#{:erlang.unique_integer([:positive])}.db")

    name = :"bee_test_#{:erlang.unique_integer([:positive])}"

    {:ok, pid} =
      Bee.Repo.start_link(
        db_path: db_path,
        prefix: "test",
        jsonl_path: nil,
        name: name
      )

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

  test "create and get issue", %{server: s} do
    {:ok, issue} = Bee.create("Test issue", [description: "desc", labels: ["bug"]], s)
    assert issue.title == "Test issue"
    assert issue.description == "desc"
    assert issue.labels == ["bug"]
    assert issue.status == "open"
    assert issue.id == 1

    {:ok, fetched} = Bee.get(1, s)
    assert fetched.title == "Test issue"
  end

  test "Repo boot runs the registered migration plan" do
    dir = Path.join(System.tmp_dir!(), "bee_migration_boot_#{System.unique_integer([:positive])}")
    db_path = Path.join(dir, "bee.db")
    name = :"bee_migration_boot_#{System.unique_integer([:positive])}"
    File.mkdir_p!(dir)

    {:ok, pid} =
      Bee.Repo.start_link(db_path: db_path, prefix: "test", jsonl_path: nil, name: name)

    {:ok, conn} = Exqlite.Sqlite3.open(db_path)
    assert {:ok, 2} = Bee.Store.Migrate.user_version(conn)
    assert sqlite_table_exists?(conn, "issues_fts")
    refute sqlite_table_exists?(conn, "labels")
    Exqlite.Sqlite3.close(conn)
    GenServer.stop(pid)
    File.rm_rf!(dir)
  end

  test "list and ready issues", %{server: s} do
    {:ok, _} = Bee.create("Issue 1", [], s)
    {:ok, _} = Bee.create("Issue 2", [], s)

    {:ok, all} = Bee.list([], s)
    assert length(all) == 2

    {:ok, ready} = Bee.ready([], s)
    assert length(ready) == 2
  end

  test "update issue", %{server: s} do
    {:ok, _} = Bee.create("Original", [], s)
    :ok = Bee.update(1, %{title: "Updated", status: "closed"}, s)

    {:ok, issue} = Bee.get(1, s)
    assert issue.title == "Updated"
    assert issue.status == "closed"
  end

  test "create and update issue type", %{server: s} do
    {:ok, issue} = Bee.create("Epic", [type: "epic"], s)
    assert issue.issue_type == "epic"

    :ok = Bee.update(1, %{issue_type: "objective"}, s)
    {:ok, updated} = Bee.get(1, s)
    assert updated.issue_type == "objective"

    :ok = Bee.update(1, %{type: "bug"}, s)
    {:ok, aliased} = Bee.get(1, s)
    assert aliased.issue_type == "bug"
  end

  test "update issue parent and clear parent", %{server: s} do
    {:ok, parent} = Bee.create("Parent", [], s)
    {:ok, child} = Bee.create("Child", [], s)

    assert is_nil(child.parent)

    :ok = Bee.update(child.id, %{parent: parent.id}, s)
    {:ok, reparented} = Bee.get(child.id, s)
    assert reparented.parent == parent.id

    :ok = Bee.update(child.id, %{parent: nil}, s)
    {:ok, cleared} = Bee.get(child.id, s)
    assert is_nil(cleared.parent)
  end

  test "reject parent cycles", %{server: s} do
    {:ok, parent} = Bee.create("Parent", [], s)
    {:ok, child} = Bee.create("Child", [parent: parent.id], s)

    assert {:error, :self_parent} = Bee.update(parent.id, %{parent: parent.id}, s)
    assert {:error, :parent_cycle} = Bee.update(parent.id, %{parent: child.id}, s)
  end

  test "updating missing issue returns not found", %{server: s} do
    assert {:error, :not_found} = Bee.update(999, %{title: "Missing"}, s)
  end

  test "comment on issue", %{server: s} do
    {:ok, _} = Bee.create("With comments", [], s)
    :ok = Bee.comment(1, "First comment", [author: "tester"], s)
    :ok = Bee.comment(1, "Second comment", [], s)

    conn = GenServer.call(s, :conn)
    comments = Bee.Store.get_comments(conn, "test-1")
    assert length(comments) == 2
    assert hd(comments).body == "First comment"
  end

  test "blocking dependencies", %{server: s} do
    {:ok, _} = Bee.create("Task A", [], s)
    {:ok, _} = Bee.create("Task B", [], s)

    :ok = Bee.block(2, 1, s)

    {:ok, issue} = Bee.get(2, s)
    assert 1 in issue.blocked_by

    {:ok, ready} = Bee.ready([], s)
    ready_ids = Enum.map(ready, & &1.id)
    assert 1 in ready_ids
    refute 2 in ready_ids

    :ok = Bee.unblock(2, 1, s)
    {:ok, ready2} = Bee.ready([], s)
    assert length(ready2) == 2
  end

  test "cycle detection", %{server: s} do
    {:ok, _} = Bee.create("A", [], s)
    {:ok, _} = Bee.create("B", [], s)

    :ok = Bee.block(2, 1, s)
    assert {:error, :cycle} = Bee.block(1, 2, s)
  end

  test "locking", %{server: s} do
    {:ok, _} = Bee.create("Lockable", [], s)

    {:ok, lock} = Bee.lock(1, [locked_by: "agent-1", ttl: 5], s)
    assert lock.locked_by == "agent-1"

    assert {:error, :already_locked} = Bee.lock(1, [locked_by: "agent-2"], s)

    :ok = Bee.unlock(1, s)
    {:ok, _} = Bee.lock(1, [locked_by: "agent-2"], s)
  end

  test "projects and agents", %{server: s} do
    {:ok, _} = Bee.register_project("proj-1", %{name: "Project One"}, s)
    {:ok, _} = Bee.register_agent("agent-1", %{name: "Worker One"}, s)

    :ok = Bee.join_project("agent-1", "proj-1", s)

    {:ok, _} = Bee.create("Task in project", [project_id: "proj-1"], s)
    :ok = Bee.assign(1, "agent-1", s)

    load = Bee.agent_load("agent-1", s)
    assert load == 1
  end

  test "who_blocks_whom", %{server: s} do
    {:ok, _} = Bee.register_agent("alice", %{}, s)
    {:ok, _} = Bee.register_agent("bob", %{}, s)

    {:ok, _} = Bee.create("Alice's task", [], s)
    {:ok, _} = Bee.create("Bob's task", [], s)

    :ok = Bee.assign(1, "alice", s)
    :ok = Bee.assign(2, "bob", s)
    :ok = Bee.block(2, 1, s)

    pairs = Bee.who_blocks_whom(s)
    assert {"alice", "bob"} in pairs
  end

  test "JSONL export and import", %{server: s} do
    {:ok, _} = Bee.create("Exported issue", [labels: ["test"]], s)
    :ok = Bee.comment(1, "A comment", [author: "bot"], s)

    export_path =
      Path.join(System.tmp_dir!(), "bee_export_test_#{:erlang.unique_integer([:positive])}.jsonl")

    conn = GenServer.call(s, :conn)
    :ok = Bee.Export.export(conn, export_path)

    content = File.read!(export_path)
    assert String.contains?(content, "Exported issue")
    assert String.contains?(content, "A comment")

    File.rm(export_path)
  end

  # --- GC-2682: Pagination tests ---

  describe "list_issues pagination (GC-2682)" do
    test "limit/offset slices are disjoint, ordered, and cover the set", %{server: s} do
      for i <- 1..6, do: {:ok, _} = Bee.create("Issue #{i}", [], s)

      {:ok, page1} = Bee.list([limit: 2, offset: 0], s)
      {:ok, page2} = Bee.list([limit: 2, offset: 2], s)
      {:ok, page3} = Bee.list([limit: 2, offset: 4], s)

      assert length(page1) == 2
      assert length(page2) == 2
      assert length(page3) == 2

      p1_ids = Enum.map(page1, & &1.id)
      p2_ids = Enum.map(page2, & &1.id)
      p3_ids = Enum.map(page3, & &1.id)

      # Disjoint
      assert MapSet.disjoint?(MapSet.new(p1_ids), MapSet.new(p2_ids))
      assert MapSet.disjoint?(MapSet.new(p1_ids), MapSet.new(p3_ids))
      assert MapSet.disjoint?(MapSet.new(p2_ids), MapSet.new(p3_ids))

      # Cover the full set
      all = Enum.sort(p1_ids ++ p2_ids ++ p3_ids)
      assert all == [1, 2, 3, 4, 5, 6]

      # Ordered within each page (default created_at ASC = insertion order)
      assert p1_ids == [1, 2]
      assert p2_ids == [3, 4]
      assert p3_ids == [5, 6]
    end

    test "offset without limit works", %{server: s} do
      for i <- 1..5, do: {:ok, _} = Bee.create("Issue #{i}", [], s)

      {:ok, rest} = Bee.list([offset: 3], s)
      assert length(rest) == 2
      assert Enum.map(rest, & &1.id) == [4, 5]
    end

    test "limit larger than result set returns all", %{server: s} do
      for i <- 1..3, do: {:ok, _} = Bee.create("Issue #{i}", [], s)

      {:ok, all} = Bee.list([limit: 100], s)
      assert length(all) == 3
    end
  end

  describe "count_issues (GC-2682)" do
    test "count == length of full list for same opts", %{server: s} do
      for i <- 1..5, do: {:ok, _} = Bee.create("Issue #{i}", [], s)
      :ok = Bee.update(3, %{status: "closed"}, s)

      {:ok, count} = Bee.count([status: "open"], s)
      {:ok, open} = Bee.list([status: "open"], s)
      assert count == length(open)

      {:ok, all_count} = Bee.count([], s)
      {:ok, all_list} = Bee.list([], s)
      assert all_count == length(all_list)
    end

    test "count respects scope filters", %{server: s} do
      {:ok, _} = Bee.register_project("p1", %{}, s)
      {:ok, _} = Bee.register_project("p2", %{}, s)
      for i <- 1..4, do: {:ok, _} = Bee.create("Issue #{i}", [project_id: "p1"], s)
      for i <- 1..2, do: {:ok, _} = Bee.create("Other #{i}", [project_id: "p2"], s)

      {:ok, count} = Bee.count([project_id: "p1"], s)
      assert count == 4
    end
  end

  describe "order_by (GC-2682)" do
    test "order_by whitelist honored", %{server: s} do
      {:ok, _} = Bee.create("Low", [priority: 1], s)
      {:ok, _} = Bee.create("High", [priority: 9], s)
      {:ok, _} = Bee.create("Mid", [priority: 5], s)

      {:ok, issues} = Bee.list([order_by: [priority: :desc]], s)
      assert Enum.map(issues, & &1.title) == ["High", "Mid", "Low"]

      {:ok, issues_asc} = Bee.list([order_by: [priority: :asc]], s)
      assert Enum.map(issues_asc, & &1.title) == ["Low", "Mid", "High"]
    end

    test "order_by with id column", %{server: s} do
      for i <- 1..3, do: {:ok, _} = Bee.create("Issue #{i}", [], s)

      {:ok, desc} = Bee.list([order_by: [id: :desc]], s)
      assert Enum.map(desc, & &1.id) == [3, 2, 1]
    end

    test "order_by rejects non-whitelisted column", %{server: s} do
      {:ok, _} = Bee.create("Issue", [], s)

      assert_raise ArgumentError, ~r/invalid order_by/, fn ->
        Bee.list([order_by: [evil_column: :asc]], s)
      end
    end

    test "order_by rejects bad direction", %{server: s} do
      {:ok, _} = Bee.create("Issue", [], s)

      assert_raise ArgumentError, ~r/invalid order_by/, fn ->
        Bee.list([order_by: [priority: :sideways]], s)
      end
    end

    test "order_by respects limit for paging", %{server: s} do
      for i <- 1..5, do: {:ok, _} = Bee.create("P#{i}", [priority: i], s)

      {:ok, p1} = Bee.list([order_by: [priority: :desc], limit: 2, offset: 0], s)
      {:ok, p2} = Bee.list([order_by: [priority: :desc], limit: 2, offset: 2], s)

      assert Enum.map(p1, & &1.title) == ["P5", "P4"]
      assert Enum.map(p2, & &1.title) == ["P3", "P2"]
    end
  end

  describe "backward compatibility (GC-2682)" do
    test "list without opts is byte-for-byte unchanged behavior", %{server: s} do
      for i <- 1..3, do: {:ok, _} = Bee.create("Issue #{i}", [], s)

      {:ok, issues} = Bee.list([], s)

      # Same as before: ORDER BY created_at ASC, no LIMIT, enriched
      assert Enum.map(issues, & &1.id) == [1, 2, 3]
      assert Enum.map(issues, & &1.title) == ["Issue 1", "Issue 2", "Issue 3"]

      # Enrichment is present (labels, blocks, parent)
      issue = hd(issues)
      assert issue.labels == []
      assert issue.blocked_by == []
      assert issue.parent == nil
    end
  end

  describe "tree_page (GC-2682)" do
    test "returns complete subtrees for roots", %{server: s} do
      # Root1 → Child1 → Grandchild1
      # Root2 (standalone)
      {:ok, root1} = Bee.create("Root1", [], s)
      {:ok, root2} = Bee.create("Root2", [], s)
      {:ok, child1} = Bee.create("Child1", [parent: root1.id], s)
      {:ok, grandchild1} = Bee.create("Grandchild1", [parent: child1.id], s)

      {:ok, result} = Bee.tree_page([], s)

      assert result.total_roots == 2
      assert result.roots |> Enum.sort() == [root1.id, root2.id]

      # Must include root + descendants = all 4 issues
      all_ids = result.issues |> Enum.map(& &1.id) |> MapSet.new()

      assert MapSet.subset?(
               MapSet.new([root1.id, root2.id, child1.id, grandchild1.id]),
               all_ids
             )
    end

    test "roots-only pagination returns complete subtrees", %{server: s} do
      # Create 3 roots, each with a child
      for r <- 1..3 do
        {:ok, root} = Bee.create("Root#{r}", [], s)
        {:ok, _} = Bee.create("Child#{r}", [parent: root.id], s)
      end

      # Page 1: first root only
      {:ok, page1} = Bee.tree_page([limit: 1, offset: 0], s)

      assert page1.total_roots == 3
      assert length(page1.roots) == 1
      # The subtree is complete: root + child
      assert length(page1.issues) == 2
      root_id = hd(page1.roots)
      child_id = Enum.find(page1.issues, fn i -> i.id != root_id end).id

      assert Enum.any?(page1.issues, fn i ->
               i.id == child_id and i.parent == root_id
             end)
    end

    test "cross-scope parent makes child a root", %{server: s} do
      # Parent in project-a, child in project-b → child is a root in project-b scope
      {:ok, _} = Bee.register_project("pa", %{}, s)
      {:ok, _} = Bee.register_project("pb", %{}, s)
      {:ok, parent} = Bee.create("Parent", [project_id: "pa"], s)
      {:ok, child} = Bee.create("Child", [project_id: "pb", parent: parent.id], s)

      # Scope to project-b: child should surface as root (parent is out of scope)
      {:ok, result} = Bee.tree_page([project_id: "pb"], s)

      assert result.total_roots == 1
      assert hd(result.roots) == child.id
      assert length(result.issues) == 1
    end

    test "total_roots correct", %{server: s} do
      {:ok, _} = Bee.create("Root1", [], s)
      {:ok, r2} = Bee.create("Root2", [], s)
      {:ok, _} = Bee.create("Child of R2", [parent: r2.id], s)
      {:ok, _} = Bee.create("Root3", [], s)

      {:ok, result} = Bee.tree_page([], s)
      assert result.total_roots == 3
    end

    test "page N roots disjoint from page N+1", %{server: s} do
      for i <- 1..5, do: {:ok, _} = Bee.create("Root#{i}", [], s)

      {:ok, page1} = Bee.tree_page([limit: 2, offset: 0], s)
      {:ok, page2} = Bee.tree_page([limit: 2, offset: 2], s)

      assert MapSet.disjoint?(MapSet.new(page1.roots), MapSet.new(page2.roots))
    end

    test "honor order_by for roots", %{server: s} do
      {:ok, _} = Bee.create("Low", [priority: 1], s)
      {:ok, _} = Bee.create("High", [priority: 9], s)

      # Default order: priority DESC → High first
      {:ok, result} = Bee.tree_page([], s)
      assert result.roots == [2, 1]

      # Explicit asc: Low first
      {:ok, result_asc} = Bee.tree_page([order_by: [priority: :asc]], s)
      assert result_asc.roots == [1, 2]
    end

    test "empty result when no issues match scope", %{server: s} do
      {:ok, _} = Bee.register_project("pa", %{}, s)
      {:ok, _} = Bee.register_project("pb", %{}, s)
      {:ok, _} = Bee.create("Issue", [project_id: "pa"], s)

      {:ok, result} = Bee.tree_page([project_id: "pb"], s)
      assert result.total_roots == 0
      assert result.roots == []
      assert result.issues == []
    end
  end

  # GC-3353 item 4: missing-issue writes must fail soft (return :not_found)
  # rather than crash Bee.Repo via a `:done = step(...)` badmatch on the
  # FOREIGN KEY violation. Regression for the 2026-07-23 bee.db wipe fallout.
  describe "fail-soft writes against a missing issue (GC-3353)" do
    test "comment on a missing issue returns :not_found and keeps Bee.Repo alive", %{server: s} do
      pid = Process.whereis(s)

      assert {:error, :not_found} = Bee.comment(999, "orphan", [], s)

      # The GenServer did not crash/restart — same pid, still alive — and a
      # subsequent valid create/get succeeds.
      assert Process.whereis(s) == pid
      assert Process.alive?(pid)

      {:ok, issue} = Bee.create("After orphan comment", [], s)
      {:ok, fetched} = Bee.get(issue.id, s)
      assert fetched.title == "After orphan comment"

      # A real comment on an existing issue still works.
      assert :ok = Bee.comment(issue.id, "real note", [], s)
    end

    test "lock/claim on a missing issue returns :not_found and keeps Bee.Repo alive", %{
      server: s
    } do
      pid = Process.whereis(s)

      assert {:error, :not_found} = Bee.lock(999, [locked_by: "agent-x"], s)

      assert Process.whereis(s) == pid
      assert Process.alive?(pid)

      {:ok, issue} = Bee.create("Lockable", [], s)
      assert {:ok, _lock} = Bee.lock(issue.id, [locked_by: "agent-x"], s)
    end

    test "update/done on a missing issue returns :not_found", %{server: s} do
      assert {:error, :not_found} = Bee.update(999, %{status: "closed"}, s)
    end
  end

  # Story 1.1 — shared validator: module API raises, server boundary returns.
  # The live bug this closes: a bad order_by arriving by message raised inside
  # handle_call and killed the writer with every queued command behind it.
  describe "opts validation (Story 1.1)" do
    test "module API raises on invalid order_by", %{server: s} do
      assert_raise ArgumentError, fn -> Bee.list([order_by: :bogus], s) end
    end

    test "module API raises on invalid limit and offset", %{server: s} do
      assert_raise ArgumentError, fn -> Bee.list([limit: 0], s) end
      assert_raise ArgumentError, fn -> Bee.list([offset: -1], s) end
    end

    test "message path returns a tagged error and does NOT kill the writer", %{server: s} do
      pid = Process.whereis(s)

      assert {:error, {:invalid_order_by, :bogus}} =
               GenServer.call(s, {:list, [order_by: :bogus]})

      # the writer must still be the same living process, serving the queue
      assert Process.whereis(s) == pid
      assert Process.alive?(pid)

      {:ok, _} = Bee.create("survives", [], s)
      assert {:ok, all} = GenServer.call(s, {:list, []})
      assert length(all) == 1
    end

    test "message path errors are from the closed vocabulary", %{server: s} do
      assert {:error, {:invalid_limit, 0}} = GenServer.call(s, {:list, [limit: 0]})
      assert {:error, {:invalid_offset, -1}} = GenServer.call(s, {:count, [offset: -1]})
      assert {:error, {:invalid_order_by, _}} = GenServer.call(s, {:tree_page, [order_by: 123]})
    end

    test "valid opts pass both the module and message paths", %{server: s} do
      {:ok, _} = Bee.create("a", [], s)
      assert {:ok, _} = Bee.list([order_by: [priority: :desc], limit: 10], s)
      assert {:ok, _} = GenServer.call(s, {:list, [order_by: [:created_at]]})
      assert Bee.Store.validate_opts(limit: 5, offset: 0) == :ok
    end
  end

  describe "comment relations (Story 1.4)" do
    test "dedicated comment reads return ordered issue comments", %{server: s} do
      {:ok, issue} = Bee.create("With comments", [], s)
      :ok = Bee.comment(issue.id, "First", [], s)
      :ok = Bee.comment(issue.id, "Second", [], s)

      assert {:ok, module_comments} = Bee.get_comments(issue.id, s)
      assert Enum.map(module_comments, & &1.body) == ["First", "Second"]

      assert {:ok, message_comments} = GenServer.call(s, {:get_comments, issue.id})
      assert message_comments == module_comments
    end

    test "module and message get return requested comments", %{server: s} do
      {:ok, issue} = Bee.create("With comments", [], s)
      :ok = Bee.comment(issue.id, "First", [author: "one"], s)
      :ok = Bee.comment(issue.id, "Second", [author: "two"], s)

      assert {:ok, module_issue} = Bee.get(issue.id, [include: [:comments]], s)

      assert Enum.map(module_issue.comments, & &1.body) == ["First", "Second"]
      assert Enum.map(module_issue.comments, & &1.author) == ["one", "two"]

      assert {:ok, message_issue} =
               GenServer.call(s, {:get, issue.id, [include: [:comments]]})

      assert message_issue.comments == module_issue.comments
    end

    test "omitted comments use the not_loaded relation sentinel", %{server: s} do
      {:ok, issue} = Bee.create("With comments", [], s)
      :ok = Bee.comment(issue.id, "Hidden", [], s)

      assert {:ok, module_issue} = Bee.get(issue.id, s)
      assert module_issue.comments == :not_loaded

      assert {:ok, message_issue} = GenServer.call(s, {:get, issue.id})
      assert message_issue.comments == :not_loaded
    end

    test "list groups requested comments and preserves empty relations", %{server: s} do
      {:ok, first} = Bee.create("First", [], s)
      {:ok, second} = Bee.create("Second", [], s)
      {:ok, third} = Bee.create("Third", [], s)

      :ok = Bee.comment(first.id, "First one", [], s)
      :ok = Bee.comment(first.id, "First two", [], s)
      :ok = Bee.comment(second.id, "Second one", [], s)

      assert {:ok, unloaded_issues} = Bee.list([], s)
      assert Enum.all?(unloaded_issues, &(&1.comments == :not_loaded))

      assert {:ok, issues} = Bee.list([include: [:comments]], s)
      issues_by_id = Map.new(issues, &{&1.id, &1})

      assert Enum.map(issues_by_id[first.id].comments, & &1.body) == ["First one", "First two"]
      assert Enum.map(issues_by_id[second.id].comments, & &1.body) == ["Second one"]
      assert issues_by_id[third.id].comments == []
    end

    test "tree_page propagates requested comments", %{server: s} do
      {:ok, root} = Bee.create("Root", [], s)
      {:ok, child} = Bee.create("Child", [parent: root.id], s)
      :ok = Bee.comment(root.id, "Root comment", [], s)
      :ok = Bee.comment(child.id, "Child comment", [], s)

      assert {:ok, %{issues: issues}} = Bee.tree_page([include: [:comments]], s)
      issues_by_id = Map.new(issues, &{&1.id, &1})

      assert Enum.map(issues_by_id[root.id].comments, & &1.body) == ["Root comment"]
      assert Enum.map(issues_by_id[child.id].comments, & &1.body) == ["Child comment"]

      assert {:ok, %{issues: unloaded_issues}} = Bee.tree_page([], s)
      assert Enum.all?(unloaded_issues, &(&1.comments == :not_loaded))
    end

    test "invalid include raises at the module API and returns at the message boundary", %{
      server: s
    } do
      assert_raise ArgumentError, fn -> Bee.get(1, [include: [:labels]], s) end

      pid = Process.whereis(s)

      assert {:error, {:invalid_include, [:labels]}} =
               GenServer.call(s, {:get, 1, [include: [:labels]]})

      assert Process.whereis(s) == pid
      assert Process.alive?(pid)
    end
  end

  defp sqlite_table_exists?(conn, table_name) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?"
      )

    :ok = Exqlite.Sqlite3.bind(stmt, [table_name])

    try do
      Exqlite.Sqlite3.step(conn, stmt) == {:row, [1]}
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end
end
