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

    export_path = Path.join(System.tmp_dir!(), "bee_export_test_#{:erlang.unique_integer([:positive])}.jsonl")

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
end
