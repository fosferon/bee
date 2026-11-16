defmodule Bee.ExternalKeyTest do
  use ExUnit.Case, async: false

  alias Bee.Test.Baseline

  # The baseline fixture records ids under this prefix.
  @prefix "base"
  @debounce_ms 5_000
  # The control's flush arrives after the debounce plus the export itself, which Bee
  # bounds at 10 s; leave room for both and for scheduling.
  @flush_budget_ms 20_000

  setup do
    dir = Path.join(System.tmp_dir!(), "bee_extkey_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp start_repo(%{dir: dir}, opts \\ []) do
    n = System.unique_integer([:positive])
    name = Keyword.get(opts, :name, :"bee_extkey_#{n}")
    db_path = Keyword.get(opts, :db_path, Path.join(dir, "bee_#{n}.db"))

    jsonl_path =
      if Keyword.get(opts, :export, false), do: Path.join(dir, "export_#{n}.jsonl"), else: nil

    repo_opts =
      [db_path: db_path, prefix: @prefix, jsonl_path: jsonl_path, name: name] ++
        Keyword.drop(opts, [:name, :db_path, :export])

    pid = start_supervised!(Supervisor.child_spec({Bee.Repo, repo_opts}, id: name))
    %{repo: name, pid: pid, db_path: db_path, jsonl_path: jsonl_path}
  end

  defp next_counter(%{db_path: db_path}) do
    Baseline.with_conn(db_path, fn conn ->
      Baseline.rows(conn, "SELECT next_id FROM id_counter WHERE prefix = ?", [@prefix])
    end)
  end

  defp totals(%{db_path: db_path}) do
    Baseline.with_conn(db_path, fn conn ->
      for table <- ~w(issues issue_labels events), into: %{} do
        {table, Baseline.rows(conn, "SELECT COUNT(*) FROM #{table}")}
      end
    end)
  end

  defp rows_for(%{db_path: db_path}, raw_id) do
    Baseline.with_conn(db_path, fn conn ->
      %{
        issue: Baseline.rows(conn, "SELECT id FROM issues WHERE id = ?", [raw_id]),
        labels:
          Baseline.rows(conn, "SELECT label FROM issue_labels WHERE issue_id = ?", [raw_id]),
        events: Baseline.rows(conn, "SELECT seq FROM events WHERE issue_id = ?", [raw_id])
      }
    end)
  end

  defp keyed_rows(%{db_path: db_path}, key) do
    Baseline.with_conn(db_path, fn conn ->
      Baseline.rows(conn, "SELECT id FROM issues WHERE external_key = ?", [key])
    end)
  end

  defp stored_key(%{db_path: db_path}, raw_id) do
    Baseline.with_conn(db_path, fn conn ->
      Baseline.rows(conn, "SELECT external_key FROM issues WHERE id = ?", [raw_id])
    end)
  end

  # --- The no-side-effect control (export enabled, test-only observer) ---

  # Settles a successful create only through its own debounce timer, barriers on the
  # Repo mailbox, and records what a later refused create must leave unchanged.
  defp settle_control(ctx) do
    assert {:ok, _} = Bee.create("Control", [], ctx.repo)
    assert_receive {:bee_test_export, :scheduled}, 1_000
    assert_receive {:bee_test_export, :flushed}, @flush_budget_ms
    assert %{export_timer: nil} = :sys.get_state(ctx.pid)
    assert File.exists?(ctx.jsonl_path)
    observed = side_effects(ctx)
    drain_observer()
    observed
  end

  defp side_effects(ctx) do
    state = :sys.get_state(ctx.pid)
    {:ok, stat} = File.stat(ctx.jsonl_path, time: :posix)

    %{
      export_timer: state.export_timer,
      bytes: File.read!(ctx.jsonl_path),
      mtime: stat.mtime,
      inode: stat.inode,
      dep_vertices: state.dep_graph |> :digraph.vertices() |> Enum.sort(),
      alloc_vertices: state.alloc_graph |> :digraph.vertices() |> Enum.sort()
    }
  end

  defp drain_observer do
    receive do
      {:bee_test_export, _} -> drain_observer()
    after
      0 -> :ok
    end
  end

  # No export is forced after the refused create: wait past the debounce window, then
  # barrier, then require silence and unchanged state.
  defp assert_no_side_effects(ctx, control) do
    Process.sleep(@debounce_ms + 500)
    _ = :sys.get_state(ctx.pid)
    refute_received {:bee_test_export, _}
    after_refusal = side_effects(ctx)
    assert after_refusal.export_timer == nil
    assert after_refusal == control
  end

  defp export_ctx(ctx, opts \\ []),
    do: start_repo(ctx, [export: true, export_observer: self()] ++ opts)

  describe "create with a key" do
    test "stores the key, finds the issue by it, and keeps it out of other payloads", ctx do
      r = start_repo(ctx)

      assert {:ok, issue} =
               Bee.create("Keyed", [external_key: "receipt:0001", labels: ["a"]], r.repo)

      refute Map.has_key?(issue, :external_key)

      assert {:ok, found} = Bee.get_by_external_key("receipt:0001", r.repo)
      assert {:ok, got} = Bee.get(issue.id, r.repo)
      refute Map.has_key?(got, :external_key)
      assert found == Map.put(got, :external_key, "receipt:0001")

      assert {:ok, listed} = Bee.list([], r.repo)
      assert Enum.all?(listed, &(not Map.has_key?(&1, :external_key)))

      assert {:ok, %{issues: queried}} = Bee.query([status: "open"], r.repo)
      assert Enum.all?(queried, &(not Map.has_key?(&1, :external_key)))

      assert [[%{fields: fields}]] =
               Baseline.with_conn(r.db_path, &[Baseline.events(&1, "#{@prefix}-#{issue.id}")])

      assert fields["external_key"] == "receipt:0001"
      assert [["receipt:0001"]] = stored_key(r, "#{@prefix}-#{issue.id}")
    end

    test "a 200-byte key is accepted", ctx do
      r = start_repo(ctx)
      key = String.duplicate("k", 200)
      assert {:ok, issue} = Bee.create("Long key", [external_key: key], r.repo)
      assert {:ok, %{id: id}} = Bee.get_by_external_key(key, r.repo)
      assert id == issue.id
    end
  end

  describe "create without a key matches 0.3.0 (absent and nil paired)" do
    for {name, _} <- Bee.Test.Baseline.scenarios() do
      @scenario name
      test "scenario #{name}", ctx do
        baseline = Baseline.scenario(@scenario)

        for extra <- [[], [external_key: nil]] do
          r = start_repo(ctx)
          actual = Baseline.run(baseline, r.repo, r.db_path, extra)
          Baseline.assert_matches_baseline(actual, baseline)
          assert actual.stored_external_key == [[nil]], "extra opts #{inspect(extra)}"
        end
      end
    end
  end

  describe "labels without a key stay pinned to 0.3.0" do
    test "nil, empty-string and duplicate labels behave as in 0.3.0", ctx do
      for name <- [:nil_label, :empty_string_label, :duplicate_labels],
          extra <- [[], [external_key: nil]] do
        baseline = Baseline.scenario(name)
        r = start_repo(ctx)
        actual = Baseline.run(baseline, r.repo, r.db_path, extra)
        Baseline.assert_matches_baseline(actual, baseline)
      end

      # Spelled out: the nil label is skipped silently, the empty string is stored and
      # duplicates collapse to one row.
      assert [["base-1", "kept"]] = Baseline.scenario(:nil_label).labels
      assert [["base-1", ""]] = Baseline.scenario(:empty_string_label).labels

      assert [["base-1", "dup"], ["base-1", "other"]] =
               Baseline.scenario(:duplicate_labels).labels
    end
  end

  describe "nil is not a key" do
    test "stores NULL, is invisible to the lookup, and never conflicts", ctx do
      r = start_repo(ctx)
      assert {:ok, a} = Bee.create("First nil", [external_key: nil], r.repo)
      assert {:ok, b} = Bee.create("Second nil", [external_key: nil], r.repo)
      assert a.id != b.id
      assert [[nil]] = stored_key(r, "#{@prefix}-#{a.id}")
      assert [[nil]] = stored_key(r, "#{@prefix}-#{b.id}")

      assert {:error, {:invalid_external_key, :not_a_binary}} =
               Bee.get_by_external_key(nil, r.repo)

      assert [[0]] =
               Baseline.with_conn(
                 r.db_path,
                 &Baseline.rows(&1, "SELECT COUNT(*) FROM issues WHERE external_key IS NOT NULL")
               )
    end
  end

  describe "a key already in use" do
    test "is a typed conflict that writes nothing and schedules nothing", ctx do
      r = export_ctx(ctx)
      assert {:ok, holder} = Bee.create("Holder", [external_key: "dup-key"], r.repo)
      control = settle_control(r)
      counter = next_counter(r)
      totals = totals(r)
      [[last_issued]] = counter

      assert {:error, :external_key_conflict} =
               Bee.create("Second", [external_key: "dup-key", labels: ["x"]], r.repo)

      assert next_counter(r) == counter
      assert totals(r) == totals
      assert %{issue: [], labels: [], events: []} = rows_for(r, "#{@prefix}-#{last_issued + 1}")
      assert [["#{@prefix}-#{holder.id}"]] == keyed_rows(r, "dup-key")
      assert {:ok, %{id: id}} = Bee.get_by_external_key("dup-key", r.repo)
      assert id == holder.id
      assert_no_side_effects(r, control)
    end

    test "two creates with one key through one server: exactly one succeeds", ctx do
      r = start_repo(ctx)

      results =
        1..2
        |> Enum.map(fn n ->
          Task.async(fn -> Bee.create("Racer #{n}", [external_key: "race"], r.repo) end)
        end)
        |> Task.await_many(10_000)

      assert [{:error, :external_key_conflict}, {:ok, winner}] = Enum.sort(results)
      assert [["#{@prefix}-#{winner.id}"]] == keyed_rows(r, "race")
    end

    test "the index decides across two writers on one file", ctx do
      first = start_repo(ctx)
      second = start_repo(ctx, db_path: first.db_path)

      assert {:ok, _} = Bee.create("First writer", [external_key: "shared"], first.repo)

      assert {:error, :external_key_conflict} =
               Bee.create("Second writer", [external_key: "shared"], second.repo)

      results =
        [first.repo, second.repo]
        |> Enum.map(fn repo ->
          Task.async(fn -> Bee.create("Concurrent", [external_key: "both"], repo) end)
        end)
        |> Task.await_many(15_000)

      assert [{:error, :external_key_conflict}, {:ok, _}] = Enum.sort(results)
      assert [[_]] = keyed_rows(first, "both")
    end
  end

  describe "invalid keys" do
    test "are refused before the transaction, with no id allocated", ctx do
      r = start_repo(ctx)

      cases = [
        {"", :empty},
        {String.duplicate("k", 201), :too_long},
        {"has space", :invalid_characters},
        {"has\nnewline", :invalid_characters},
        {"tab\there", :invalid_characters},
        {"κλειδί", :invalid_characters},
        {"del\x7F", :invalid_characters},
        {123, :not_a_binary},
        {:atom_key, :not_a_binary}
      ]

      for {key, reason} <- cases do
        assert {:error, {:invalid_external_key, ^reason}} =
                 Bee.create("Invalid", [external_key: key], r.repo)

        assert {:error, {:invalid_external_key, ^reason}} = Bee.get_by_external_key(key, r.repo)
      end

      assert [] == next_counter(r)
      assert %{"issues" => [[0]], "events" => [[0]]} = totals(r)
    end
  end

  describe "the key is immutable" do
    test "update naming the key is refused and changes nothing", ctx do
      r = start_repo(ctx)
      assert {:ok, issue} = Bee.create("Receipt", [external_key: "fixed"], r.repo)
      assert {:ok, before} = Bee.get_by_external_key("fixed", r.repo)
      totals = totals(r)

      for attrs <- [
            %{external_key: "other"},
            %{"external_key" => "other"},
            %{external_key: nil, title: "Renamed"},
            [external_key: "other", title: "Renamed"]
          ] do
        assert {:error, {:immutable_field, :external_key}} = Bee.update(issue.id, attrs, r.repo)
      end

      assert {:ok, ^before} = Bee.get_by_external_key("fixed", r.repo)
      assert totals(r) == totals
      assert {:error, :not_found} = Bee.get_by_external_key("other", r.repo)
      assert :ok = Bee.update(issue.id, %{title: "Renamed"}, r.repo)
      assert {:ok, %{title: "Renamed"}} = Bee.get_by_external_key("fixed", r.repo)
    end

    test "JSONL import over a keyed issue keeps its key", ctx do
      r = start_repo(ctx)
      assert {:ok, issue} = Bee.create("Imported over", [external_key: "kept"], r.repo)
      path = Path.join(ctx.dir, "import.jsonl")
      raw_id = "#{@prefix}-#{issue.id}"

      File.write!(
        path,
        Jason.encode!(%{id: raw_id, title: "Changed by import", external_key: "forged"}) <> "\n"
      )

      assert {:ok, 1} = Bee.import_jsonl(path, r.repo)
      assert [["kept"]] = stored_key(r, raw_id)

      assert {:ok, %{id: id, title: "Changed by import"}} =
               Bee.get_by_external_key("kept", r.repo)

      assert id == issue.id
      assert {:error, :not_found} = Bee.get_by_external_key("forged", r.repo)
    end

    test "an issue newly inserted by import has no key", ctx do
      r = start_repo(ctx)
      path = Path.join(ctx.dir, "fresh.jsonl")

      File.write!(
        path,
        Jason.encode!(%{id: "#{@prefix}-7", title: "Fresh", external_key: "forged"}) <> "\n"
      )

      assert {:ok, 1} = Bee.import_jsonl(path, r.repo)
      assert [[nil]] = stored_key(r, "#{@prefix}-7")
      assert {:error, :not_found} = Bee.get_by_external_key("forged", r.repo)
    end

    test "the export of a keyed issue is the 0.3.0 export of the same row", ctx do
      baseline = Baseline.scenario(:plain)
      r = start_repo(ctx)
      actual = Baseline.run(baseline, r.repo, r.db_path, external_key: "export-check")

      for {a_raw, b_raw} <- Enum.zip(actual.export_raw, baseline.export_raw) do
        refute a_raw =~ "external_key"
        assert Map.keys(Jason.decode!(a_raw)) == Map.keys(Jason.decode!(b_raw))
      end

      # Everything but the creation event (which records the key) is 0.3.0's.
      Baseline.assert_matches_baseline(actual, baseline, except: [:events])
      assert [%{fields: %{"external_key" => "export-check"}}] = actual.events
    end
  end

  describe "lookup on a named, fenced server" do
    test "found, not found, and a create queued ahead of the lookup", ctx do
      r =
        start_repo(ctx,
          name: :"bee_extkey_named_#{System.unique_integer([:positive])}",
          lane_write_fence: true
        )

      assert {:ok, :enabled} = Bee.lane_write_fence_status(r.repo)
      assert {:error, :not_found} = Bee.get_by_external_key("absent", r.repo)
      assert {:ok, issue} = Bee.create("Found", [external_key: "present"], r.repo)

      assert {:ok, %{id: id, external_key: "present"}} =
               Bee.get_by_external_key("present", r.repo)

      assert id == issue.id

      # Hold the Repo, queue a create and then a lookup in its mailbox, release it.
      :ok = :sys.suspend(r.pid)
      create = Task.async(fn -> Bee.create("Queued", [external_key: "queued"], r.repo) end)
      wait_for_queue(r.pid, 1)
      lookup = Task.async(fn -> Bee.get_by_external_key("queued", r.repo) end)
      wait_for_queue(r.pid, 2)
      :ok = :sys.resume(r.pid)

      assert {:ok, created} = Task.await(create)
      assert {:ok, looked_up} = Task.await(lookup)
      assert looked_up.id == created.id
    end

    for mode <- [:prepare, :step] do
      @mode mode
      test "a #{mode} failure in the lookup is a store error, never :not_found", ctx do
        r = fenced_fault_repo(ctx, {:lookup, @mode})
        assert {:ok, _} = Bee.create("Present", [external_key: "present"], r.repo)

        for key <- ["present", "absent"] do
          assert {:error, {:store_error, reason}} = Bee.get_by_external_key(key, r.repo)
          assert reason =~ driver_error(@mode)
        end

        assert_alive(r)
      end

      test "a #{mode} failure hydrating the found row is a store error", ctx do
        r = fenced_fault_repo(ctx, {:hydration, @mode})
        # The key is written through a second, fault-free writer on the same file.
        clean = start_repo(ctx, db_path: r.db_path)
        assert {:ok, _} = Bee.create("Present", [external_key: "present"], clean.repo)

        assert {:error, {:store_error, reason}} = Bee.get_by_external_key("present", r.repo)
        assert reason =~ driver_error(@mode)
        assert {:error, :not_found} = Bee.get_by_external_key("absent", r.repo)
        assert_alive(r)
      end
    end
  end

  describe "labels with a key (strict)" do
    test "nil, empty and non-binary labels are refused before the transaction", ctx do
      r = start_repo(ctx)

      for {opts, index} <- [
            {[labels: ["ok", nil]], 1},
            {[labels: [""]], 0},
            {[labels: ["ok", :atom]], 1},
            {[labels: [1]], 0},
            {[labels: ["ok"], label: ""], 1}
          ] do
        assert {:error, {:invalid_label, ^index}} =
                 Bee.create("Strict", [external_key: "strict"] ++ opts, r.repo)
      end

      assert [] == next_counter(r)
      assert %{"issues" => [[0]]} = totals(r)
    end

    test "an invalid label leaves no side effects against the control", ctx do
      r = export_ctx(ctx)
      control = settle_control(r)
      counter = next_counter(r)
      totals = totals(r)

      assert {:error, {:invalid_label, 1}} =
               Bee.create("Strict", [external_key: "strict", labels: ["ok", nil]], r.repo)

      assert next_counter(r) == counter
      assert totals(r) == totals
      assert [] == keyed_rows(r, "strict")
      assert_no_side_effects(r, control)
    end

    test "duplicate valid labels succeed with one row each", ctx do
      r = start_repo(ctx)

      assert {:ok, issue} =
               Bee.create(
                 "Duplicates",
                 [external_key: "dups", labels: ["a", "a", "b"], label: "b"],
                 r.repo
               )

      assert Enum.sort(issue.labels) == ["a", "b"]
      assert %{labels: [["a"], ["b"]]} = rows_for(r, "#{@prefix}-#{issue.id}")
    end

    # Each fault makes the real statement fail inside the SQLite driver, at prepare
    # or at step, after the transaction has begun; the writer must survive and roll
    # the whole create back.
    for point <- [
          :id_allocation,
          :issue_insert,
          :label_insert,
          :event_sequence,
          :event_insert,
          :hydration
        ],
        mode <- [:prepare, :step] do
      @point point
      @mode mode
      test "a #{mode} failure at #{point} rolls the whole create back", ctx do
        r = export_ctx(ctx, store_fault: {@point, @mode})
        control = settle_control(r)
        counter = next_counter(r)
        totals = totals(r)
        [[last_issued]] = counter

        assert {:error, reason} =
                 Bee.create("Faulty", [external_key: "faulty", labels: ["a", "b"]], r.repo)

        assert is_binary(reason) and reason =~ driver_error(@mode)
        assert_alive(r)
        assert next_counter(r) == counter
        assert totals(r) == totals
        assert %{issue: [], labels: [], events: []} = rows_for(r, "#{@prefix}-#{last_issued + 1}")
        assert [] == keyed_rows(r, "faulty")
        assert {:error, :not_found} = Bee.get_by_external_key("faulty", r.repo)
        assert_no_side_effects(r, control)
      end
    end
  end

  defp driver_error(:prepare), do: "syntax error"
  defp driver_error(:step), do: "integer overflow"

  defp fenced_fault_repo(ctx, fault) do
    start_repo(ctx,
      name: :"bee_extkey_fault_#{System.unique_integer([:positive])}",
      lane_write_fence: true,
      store_fault: fault
    )
  end

  # The same Repo process is still registered and answers a later call.
  defp assert_alive(r) do
    assert GenServer.whereis(r.repo) == r.pid
    assert Process.alive?(r.pid)
    assert {:ok, _} = Bee.list([], r.repo)
  end

  defp wait_for_queue(pid, n) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, len} when len >= n ->
        :ok

      _ ->
        Process.sleep(5)
        wait_for_queue(pid, n)
    end
  end
end
