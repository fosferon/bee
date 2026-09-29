defmodule Bee.TreeQueryTest do
  # GC-5834: ancestry, depth, fold, path, keep_ancestors, the new filters, keyset
  # pages and totals, all as fields of the one composable query.
  use ExUnit.Case

  setup do
    db_path = Path.join(System.tmp_dir!(), "bee_tree_#{:erlang.unique_integer([:positive])}.db")
    name = :"bee_tree_#{:erlang.unique_integer([:positive])}"

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

  # epic(1) ─┬─ story(2, closed) ── task(3) ── subtask(4)
  #          └─ story(5) ── task(6, closed)
  # other root(7)
  defp tree(server) do
    {:ok, epic} = Bee.create("Epic", [priority: 5, issue_type: "epic"], server)

    {:ok, closed_story} =
      Bee.create("Closed story", [parent: epic.id, issue_type: "story"], server)

    {:ok, task} = Bee.create("Task under closed", [parent: closed_story.id, priority: 7], server)
    {:ok, subtask} = Bee.create("Subtask", [parent: task.id, priority: 9], server)
    {:ok, story} = Bee.create("Open story", [parent: epic.id, issue_type: "story"], server)
    {:ok, done} = Bee.create("Done task", [parent: story.id, priority: 99], server)
    {:ok, other} = Bee.create("Other root", [], server)
    :ok = Bee.update(closed_story.id, %{status: "closed"}, server)
    :ok = Bee.update(done.id, %{status: "closed"}, server)

    %{
      epic: epic.id,
      closed_story: closed_story.id,
      task: task.id,
      subtask: subtask.id,
      story: story.id,
      done: done.id,
      other: other.id
    }
  end

  defp ids(%{issues: issues}), do: Enum.map(issues, & &1.id)
  defp by_id(%{issues: issues}), do: Map.new(issues, &{&1.id, &1})

  describe "under" do
    test "returns strict descendants over parent edges, any status", %{server: s} do
      t = tree(s)

      assert {:ok, result} = Bee.query([under: t.epic, order_by: [id: :asc]], s)
      assert ids(result) == [t.closed_story, t.task, t.subtask, t.story, t.done]
      assert result.total == 5

      depths = result |> by_id() |> Map.new(fn {id, issue} -> {id, issue.depth} end)

      assert depths == %{
               t.closed_story => 1,
               t.task => 2,
               t.subtask => 3,
               t.story => 1,
               t.done => 2
             }
    end

    test "accepts the prefixed id form and include_root adds the root at depth 0", %{server: s} do
      t = tree(s)

      assert {:ok, result} =
               Bee.query([under: "test-#{t.story}", include_root: true, order_by: [id: :asc]], s)

      assert [%{id: story, depth: 0}, %{id: done, depth: 1}] = result.issues
      assert {story, done} == {t.story, t.done}
    end

    test "with a status filter keeps literal parent distance", %{server: s} do
      t = tree(s)

      assert {:ok, result} = Bee.query([under: t.epic, status: "open"], s)
      depths = result |> by_id() |> Map.new(fn {id, issue} -> {id, issue.depth} end)
      assert depths == %{t.task => 2, t.subtask => 3, t.story => 1}
    end

    test "depth bounds the walk below the root", %{server: s} do
      t = tree(s)

      assert {:ok, result} = Bee.query([under: t.epic, depth: 1, order_by: [id: :asc]], s)
      assert ids(result) == [t.closed_story, t.story]

      assert {:ok, %{issues: [], total: 0}} = Bee.query([under: t.epic, depth: 0], s)

      assert {:ok, %{issues: [%{depth: 0}]}} =
               Bee.query([under: t.epic, depth: 0, include_root: true], s)
    end

    test "an unknown root is an error, not an empty subtree", %{server: s} do
      _ = tree(s)
      assert {:error, {:not_found, 999}} = Bee.query([under: 999], s)
      assert {:error, {:not_found, "test-999"}} = Bee.query([under: "test-999"], s)
      assert {:error, {:not_found, 999}} = Bee.count([under: 999], s)
    end
  end

  describe "depth without under" do
    test "an open issue under a closed parent is depth 0 in an open-only view", %{server: s} do
      t = tree(s)

      assert {:ok, result} = Bee.query([status: "open", depth: 10], s)
      depths = result |> by_id() |> Map.new(fn {id, issue} -> {id, issue.depth} end)

      assert depths == %{
               t.epic => 0,
               t.task => 0,
               t.subtask => 1,
               t.story => 1,
               t.other => 0
             }

      assert {:ok, shallow} = Bee.query([status: "open", depth: 0, order_by: [id: :asc]], s)
      assert ids(shallow) == [t.epic, t.task, t.other]
      assert shallow.total == 3
      assert {:ok, 3} = Bee.count([status: "open", depth: 0], s)
    end

    test "without a status filter depth is distance from the top", %{server: s} do
      t = tree(s)

      assert {:ok, result} = Bee.query([depth: 10], s)
      depths = result |> by_id() |> Map.new(fn {id, issue} -> {id, issue.depth} end)
      assert depths[t.task] == 2
      assert depths[t.subtask] == 3
      assert depths[t.other] == 0
    end
  end

  describe "fold" do
    test "roll-ups describe the whole real subtree and ignore the other filters", %{server: s} do
      t = tree(s)
      {:ok, blocker} = Bee.create("Blocker", [], s)
      :ok = Bee.block(t.subtask, blocker.id, s)
      :ok = Bee.update(t.task, %{status: "in_progress"}, s)

      assert {:ok, result} =
               Bee.query([status: "open", depth: 0, fold: true, issue_types: ["epic"]], s)

      assert [%{id: epic, rollup: rollup}] = result.issues
      assert epic == t.epic

      assert rollup == %{
               total: 5,
               open: 2,
               in_progress: 1,
               blocked: 1,
               closed: 2,
               cancelled: 0,
               max_open_priority: 9
             }
    end

    test "a leaf folds to zero", %{server: s} do
      t = tree(s)

      assert {:ok, %{issues: [%{rollup: rollup}]}} =
               Bee.query([under: t.story, depth: 1, fold: true], s)

      assert rollup.total == 0
      assert rollup.max_open_priority == nil
    end
  end

  describe "path and keep_ancestors" do
    test "path lists ancestors top down to the parent, closed ones included", %{server: s} do
      t = tree(s)

      assert {:ok, result} = Bee.query([under: t.epic, path: true], s)

      paths =
        result |> by_id() |> Map.new(fn {id, issue} -> {id, Enum.map(issue.path, & &1.id)} end)

      assert paths[t.subtask] == [t.epic, t.closed_story, t.task]
      assert paths[t.closed_story] == [t.epic]

      assert %{title: "Closed story", status: "closed"} =
               Enum.at(by_id(result)[t.subtask].path, 1)

      assert {:ok, %{issues: [%{path: []}]}} =
               Bee.query([under: t.epic, include_root: true, depth: 0, path: true], s)
    end

    test "keep_ancestors returns each match's path as context rows, uncounted", %{server: s} do
      t = tree(s)

      assert {:ok, result} =
               Bee.query([text: "Subtask", keep_ancestors: true, limit: 1], s)

      assert result.total == 1
      assert result.next == nil
      assert ids(result) == [t.epic, t.closed_story, t.task, t.subtask]
      assert Enum.map(result.issues, &Map.get(&1, :context)) == [true, true, true, nil]
    end

    test "under bounds the context at the root's children", %{server: s} do
      t = tree(s)

      assert {:ok, result} =
               Bee.query([under: t.epic, text: "Subtask", keep_ancestors: true], s)

      assert [
               %{id: closed_story, depth: 1, context: true},
               %{id: task, depth: 2, context: true},
               %{id: subtask, depth: 3}
             ] = result.issues

      assert {closed_story, task, subtask} == {t.closed_story, t.task, t.subtask}

      assert {:ok, with_root} =
               Bee.query(
                 [under: t.epic, include_root: true, text: "Subtask", keep_ancestors: true],
                 s
               )

      assert ids(with_root) == [t.epic, t.closed_story, t.task, t.subtask]
    end

    test "with depth only, context stops at the view's depth-0 ancestor", %{server: s} do
      t = tree(s)

      assert {:ok, result} =
               Bee.query([status: "open", depth: 5, text: "Subtask", keep_ancestors: true], s)

      assert [%{id: task, depth: 0, context: true}, %{id: subtask, depth: 1}] = result.issues
      assert {task, subtask} == {t.task, t.subtask}
    end
  end

  describe "filters" do
    test "labels_any is OR while labels stays AND", %{server: s} do
      {:ok, a} = Bee.create("A", [labels: ["ui", "api"]], s)
      {:ok, b} = Bee.create("B", [labels: ["ui"]], s)
      {:ok, _} = Bee.create("C", [labels: ["docs"]], s)

      assert {:ok, any} = Bee.query([labels_any: ["api", "ui"], order_by: [id: :asc]], s)
      assert ids(any) == [a.id, b.id]
      assert {:ok, all} = Bee.query([labels: ["api", "ui"]], s)
      assert ids(all) == [a.id]
    end

    test "issue_types, priority range, has_children", %{server: s} do
      t = tree(s)
      {:ok, unprioritised} = Bee.create("No priority", [], s)

      assert {:ok, stories} = Bee.query([issue_types: ["story", "epic"], order_by: [id: :asc]], s)
      assert ids(stories) == [t.epic, t.closed_story, t.story]

      assert {:ok, ranged} =
               Bee.query([priority_min: 6, priority_max: 9, order_by: [id: :asc]], s)

      assert ids(ranged) == [t.task, t.subtask]

      assert {:ok, low} = Bee.query([priority_max: 100], s)
      refute unprioritised.id in ids(low)

      assert {:ok, parents} = Bee.query([has_children: true, order_by: [id: :asc]], s)
      assert ids(parents) == [t.epic, t.closed_story, t.task, t.story]

      assert {:ok, leaves} = Bee.query([has_children: false, status: "open"], s)
      assert Enum.sort(ids(leaves)) == Enum.sort([t.subtask, t.other, unprioritised.id])
    end

    test "blocked is open with an unresolved gating dependency", %{server: s} do
      {:ok, blocker} = Bee.create("Blocker", [], s)
      {:ok, blocked} = Bee.create("Blocked", [], s)
      {:ok, cleared} = Bee.create("Cleared", [], s)
      {:ok, done_blocker} = Bee.create("Done blocker", [], s)
      {:ok, second_blocker} = Bee.create("Second blocker", [], s)
      :ok = Bee.block(blocked.id, blocker.id, s)
      :ok = Bee.block(blocked.id, second_blocker.id, s)
      :ok = Bee.block(cleared.id, done_blocker.id, s)
      :ok = Bee.update(done_blocker.id, %{status: "closed"}, s)

      assert {:ok, lane} = Bee.query([status: "open", blocked: true], s)
      assert ids(lane) == [blocked.id]
      assert {:ok, 1} = Bee.count([blocked: true], s)

      assert {:ok, free} = Bee.query([status: "open", blocked: false, order_by: [id: :asc]], s)
      assert ids(free) == [blocker.id, cleared.id, second_blocker.id]
    end
  end

  describe "keyset pages" do
    test "next walks the whole result, then goes nil", %{server: s} do
      for n <- 1..5, do: {:ok, _} = Bee.create("Issue #{n}", [priority: n * 10], s)
      spec = [order_by: [priority: :desc], limit: 2, detail: :minimal]

      assert {:ok, %{issues: page1, next: next1, total: 5} = first} = Bee.query(spec, s)
      assert Enum.map(page1, & &1.priority) == [50, 40]
      assert first.withheld.limit == 3

      assert {:ok, %{issues: page2, next: next2} = second} = Bee.query(spec ++ [after: next1], s)
      assert Enum.map(page2, & &1.priority) == [30, 20]
      assert second.withheld.limit == 1
      assert Keyword.fetch!(second.refine, :after) == next2
      refute Keyword.has_key?(second.refine, :offset)

      assert {:ok, %{issues: page3, next: nil, total: 5}} = Bee.query(spec ++ [after: next2], s)
      assert Enum.map(page3, & &1.priority) == [10]
    end

    test "a cursor stays stable while issues are created and closed between pages", %{
      server: s
    } do
      for n <- 1..5, do: {:ok, _} = Bee.create("Issue #{n}", [priority: n * 10], s)
      spec = [status: "open", order_by: [priority: :desc], limit: 2]

      {:ok, %{issues: [first, _], next: next}} = Bee.query(spec, s)

      # Churn between pages: a row already seen closes and new rows land on both
      # sides of the cursor. The cursor continues exactly where page 1 ended.
      :ok = Bee.update(first.id, %{status: "closed"}, s)
      {:ok, _} = Bee.create("Late but urgent", [priority: 45], s)
      {:ok, _} = Bee.create("Late and minor", [priority: 25], s)

      assert {:ok, %{issues: page2}} = Bee.query(spec ++ [after: next], s)
      assert Enum.map(page2, & &1.priority) == [30, 25]

      # The same churn under offset paging: page 1 showed 50 and 45, 50 closes, and
      # offset 2 now starts at 30. The 40 is never shown.
      :ok = Bee.update(first.id, %{status: "open"}, s)
      {:ok, %{issues: [seen, _]}} = Bee.query(spec, s)
      :ok = Bee.update(seen.id, %{status: "closed"}, s)
      assert {:ok, %{issues: offset_page2}} = Bee.query(spec ++ [offset: 2], s)
      assert Enum.map(offset_page2, & &1.priority) == [30, 25]
    end

    test "cursor order handles NULL priorities and id ties", %{server: s} do
      {:ok, _} = Bee.create("P", [priority: 1], s)
      for n <- 1..3, do: {:ok, _} = Bee.create("Null #{n}", [], s)
      spec = [order_by: [priority: :desc], limit: 2]

      {:ok, %{issues: page1, next: next}} = Bee.query(spec, s)
      {:ok, %{issues: page2, next: nil}} = Bee.query(spec ++ [after: next], s)
      assert Enum.map(page1 ++ page2, & &1.id) == [1, 2, 3, 4]
    end

    test "rejects tampered cursors and cursors from another order", %{server: s} do
      for n <- 1..3, do: {:ok, _} = Bee.create("Issue #{n}", [], s)
      {:ok, %{next: next}} = Bee.query([order_by: [id: :asc], limit: 1], s)

      assert {:error, {:invalid_cursor, "not-a-cursor"}} =
               GenServer.call(s, {:query, [after: "not-a-cursor"]})

      assert_raise ArgumentError, ~r/invalid after cursor/, fn ->
        Bee.query([order_by: [created_at: :asc], after: next], s)
      end

      forged = Base.url_encode64(~s({"o":[["id","asc"]],"v":[7]}), padding: false)

      assert_raise ArgumentError, ~r/invalid after cursor/, fn ->
        Bee.query([order_by: [id: :asc], after: forged], s)
      end
    end
  end

  describe "validation" do
    test "rejects fold without depth, after with offset, depth over 10, empty lists" do
      assert {:error, :fold_requires_depth} = Bee.Query.Spec.new(fold: true)
      assert {:error, :after_with_offset} = Bee.Query.Spec.new(after: "x", offset: 1)
      assert {:error, {:invalid_depth, 11}} = Bee.Query.Spec.new(depth: 11)
      assert {:error, {:invalid_depth, -1}} = Bee.Query.Spec.new(depth: -1)
      assert {:error, {:invalid_filter, :labels_any, []}} = Bee.Query.Spec.new(labels_any: [])
      assert {:error, {:invalid_filter, :issue_types, []}} = Bee.Query.Spec.new(issue_types: [])
      assert {:error, {:invalid_filter, :under, ""}} = Bee.Query.Spec.new(under: "")
      assert {:error, {:invalid_filter, :blocked, "yes"}} = Bee.Query.Spec.new(blocked: "yes")

      assert {:error, {:invalid_filter, :priority_min, "1"}} =
               Bee.Query.Spec.new(priority_min: "1")

      assert {:ok, _} = Bee.Query.Spec.new(fold: true, depth: 2)
    end

    test "count validates the shared filter fields", %{server: s} do
      assert_raise ArgumentError, ~r/invalid depth/, fn -> Bee.count([depth: 11], s) end

      assert {:error, {:invalid_filter, :labels_any, []}} =
               GenServer.call(s, {:count, [labels_any: []]})
    end
  end

  test "register_intent persists every new field", %{server: s} do
    t = tree(s)

    fields = [
      under: t.epic,
      include_root: true,
      depth: 3,
      fold: true,
      path: true,
      keep_ancestors: true,
      labels_any: ["ui"],
      issue_types: ["task"],
      priority_min: 1,
      priority_max: 9,
      has_children: false,
      blocked: false,
      order_by: [priority: :desc],
      limit: 10
    ]

    assert :ok = Bee.register_intent("board_lane", fields, s)
    conn = GenServer.call(s, :conn)
    assert {:ok, stored} = Bee.Intent.Registry.resolve(conn, "board_lane")
    assert stored == Bee.Query.Spec.new!(fields)

    {:ok, %{next: next}} = Bee.query([order_by: [id: :asc], limit: 1], s)
    assert :ok = Bee.register_intent("from_cursor", [order_by: [id: :asc], after: next], s)
    assert {:ok, %Bee.Query.Spec{after: ^next}} = Bee.Intent.Registry.resolve(conn, "from_cursor")

    assert :ok =
             Bee.register_intent(
               "parent_tasks",
               [
                 under: t.epic,
                 depth: 3,
                 fold: true,
                 path: true,
                 issue_types: ["task"],
                 has_children: true
               ],
               s
             )

    assert {:ok, %{issues: [%{id: task, rollup: %{total: 1}, path: [_, _]}], total: 1}} =
             Bee.ask("parent_tasks", [], s)

    assert task == t.task
  end

  describe "ancestors" do
    test "returns the chain root first, excluding the issue", %{server: s} do
      t = tree(s)

      assert {:ok, chain} = Bee.ancestors(t.subtask, s)

      assert [
               %{id: epic, title: "Epic", status: "open", issue_type: "epic", project_id: nil},
               %{id: closed_story, status: "closed"},
               %{id: task}
             ] = chain

      assert {epic, closed_story, task} == {t.epic, t.closed_story, t.task}
      assert {:ok, []} = Bee.ancestors(t.epic, s)
      assert {:ok, [_]} = Bee.ancestors("test-#{t.story}", s)
      assert {:error, :not_found} = Bee.ancestors(999, s)
      assert {:ok, [_, _, _]} = GenServer.call(s, {:ancestors, t.subtask})
    end

    test "terminates over a parent cycle", %{server: s} do
      {:ok, a} = Bee.create("A", [], s)
      {:ok, b} = Bee.create("B", [parent: a.id], s)
      conn = GenServer.call(s, :conn)

      :ok =
        Exqlite.Sqlite3.execute(
          conn,
          "UPDATE issues SET parent = 'test-#{b.id}' WHERE id = 'test-#{a.id}'"
        )

      assert {:ok, chain} = Bee.ancestors(b.id, s)
      assert length(chain) == 20
      assert {:ok, %{issues: issues}} = Bee.query([under: a.id], s)
      assert issues != []
    end
  end

  test "reads run on the pool in the caller, not behind the writer", %{server: s} do
    t = tree(s)
    pid = Process.whereis(s)
    :ok = :sys.suspend(pid)

    try do
      assert {:ok, %{total: 5}} = Bee.query([under: t.epic, fold: true, depth: 3, path: true], s)
      assert {:ok, 7} = Bee.count([], s)
      assert {:ok, [_, _, _]} = Bee.ancestors(t.subtask, s)
    after
      :sys.resume(pid)
    end
  end
end
