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
      if Process.alive?(pid), do: GenServer.stop(pid)
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
end
