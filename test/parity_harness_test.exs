defmodule BeeParityHarnessTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Behaviour-parity harness over both consumer surfaces (Story 1.5, NFR6, G30).

  Replays a fixed corpus against the module API (Bee.* facade) and the GenServer
  message protocol ({verb, args}) and asserts identical behaviour for every read
  operation. Declared intentional differences are listed in
  docs/contracts/parity-exceptions.json and asserted separately.

  This is a standing check: it runs with `mix test` on every epic release, not
  just Epic 1. Any later epic that changes a reply shape on one surface but not
  the other fails here.

  id is appended to every ordered spec for deterministic pagination (AC).
  """

  @exceptions_path Path.expand("docs/contracts/parity-exceptions.json", File.cwd!())
  @external_resource @exceptions_path

  setup do
    db_path =
      Path.join(System.tmp_dir!(), "bee_parity_#{:erlang.unique_integer([:positive])}.db")

    name = :"bee_parity_#{:erlang.unique_integer([:positive])}"

    {:ok, pid} =
      Bee.Repo.start_link(db_path: db_path, prefix: "test", jsonl_path: nil, name: name)

    # Fixed corpus: three issues with labels, priority, hierarchy, comments, a
    # dependency edge, and a lock. Enough to exercise every read path.
    {:ok, alpha} = Bee.create("Alpha", [labels: ["x"], priority: 5], name)
    {:ok, beta} = Bee.create("Beta", [labels: ["y"], priority: 3, parent: alpha.id], name)
    {:ok, gamma} = Bee.create("Gamma", [labels: ["x", "z"], priority: 8], name)

    :ok = Bee.comment(alpha.id, "first", [author: "agent1"], name)
    :ok = Bee.comment(alpha.id, "second", [author: "agent2"], name)
    :ok = Bee.comment(beta.id, "beta note", [], name)

    :ok = Bee.block(gamma.id, alpha.id, name)
    {:ok, _} = Bee.lock(alpha.id, [locked_by: "ops"], name)

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

    %{server: name, alpha: alpha, beta: beta, gamma: gamma}
  end

  # --- Helpers ---

  defp read_exceptions do
    File.read!(@exceptions_path) |> Jason.decode!()
  end

  defp assert_parity({module_result, msg_result}, label) do
    assert module_result == msg_result,
           "parity mismatch for #{label}:\n  module:  #{inspect(module_result)}\n  message: #{inspect(msg_result)}"
  end

  # --- Read parity ---

  describe "get parity" do
    test "module and message get return identical issues", %{server: s, alpha: a} do
      assert_parity({Bee.get(a.id, s), GenServer.call(s, {:get, a.id})}, "get/2 vs {:get, id}")
    end

    test "module and message get with include comments return identical issues", %{
      server: s,
      alpha: a
    } do
      assert_parity(
        {Bee.get(a.id, [include: [:comments]], s),
         GenServer.call(s, {:get, a.id, [include: [:comments]]})},
        "get/3 vs {:get, id, opts} with comments"
      )
    end

    test "get on a missing issue returns identical not_found", %{server: s} do
      assert_parity(
        {Bee.get(999, s), GenServer.call(s, {:get, 999})},
        "get missing"
      )
    end
  end

  describe "get_comments parity" do
    test "module and message get_comments return identical lists", %{server: s, alpha: a} do
      assert_parity(
        {Bee.get_comments(a.id, s), GenServer.call(s, {:get_comments, a.id})},
        "get_comments/2 vs {:get_comments, id}"
      )
    end

    test "get_comments on an issue with no comments returns identical empty list", %{
      server: s,
      gamma: g
    } do
      assert_parity(
        {Bee.get_comments(g.id, s), GenServer.call(s, {:get_comments, g.id})},
        "get_comments empty"
      )
    end
  end

  describe "list parity" do
    test "module and message list return identical issues", %{server: s} do
      opts = [order_by: [priority: :desc, id: :asc]]

      assert_parity(
        {Bee.list(opts, s), GenServer.call(s, {:list, opts})},
        "list with ordered opts"
      )
    end

    test "module and message list with include comments return identical issues", %{server: s} do
      opts = [include: [:comments], order_by: [id: :asc]]

      assert_parity(
        {Bee.list(opts, s), GenServer.call(s, {:list, opts})},
        "list with comments"
      )
    end

    test "module and message list with status filter return identical issues", %{server: s} do
      opts = [status: "open", order_by: [id: :asc]]

      assert_parity(
        {Bee.list(opts, s), GenServer.call(s, {:list, opts})},
        "list filtered by status"
      )
    end
  end

  describe "count parity" do
    test "module and message count return identical counts", %{server: s} do
      assert_parity(
        {Bee.count([], s), GenServer.call(s, {:count, []})},
        "count unfiltered"
      )
    end

    test "module and message count with status filter return identical counts", %{server: s} do
      opts = [status: "open"]

      assert_parity(
        {Bee.count(opts, s), GenServer.call(s, {:count, opts})},
        "count filtered"
      )
    end
  end

  describe "tree_page parity" do
    test "module and message tree_page return identical pages", %{server: s} do
      opts = [limit: 10, order_by: [id: :asc]]

      assert_parity(
        {Bee.tree_page(opts, s), GenServer.call(s, {:tree_page, opts})},
        "tree_page"
      )
    end

    test "module and message tree_page with include comments return identical pages", %{
      server: s
    } do
      opts = [limit: 10, include: [:comments], order_by: [id: :asc]]

      assert_parity(
        {Bee.tree_page(opts, s), GenServer.call(s, {:tree_page, opts})},
        "tree_page with comments"
      )
    end
  end

  describe "ready parity" do
    test "module and message ready return identical issues", %{server: s} do
      assert_parity(
        {Bee.ready([], s), GenServer.call(s, {:ready, []})},
        "ready"
      )
    end
  end

  # --- Deterministic pagination: id appended to ordered specs ---

  describe "deterministic pagination (id appended to ordered specs)" do
    test "list ordered by priority desc, id asc is deterministic across two calls", %{
      server: s
    } do
      opts = [order_by: [priority: :desc, id: :asc]]
      {:ok, first} = Bee.list(opts, s)
      {:ok, second} = Bee.list(opts, s)
      assert first == second, "non-deterministic ordering with id in sort key"

      ids = Enum.map(first, & &1.id)

      assert ids == Enum.sort_by(ids, &{-get_priority(first, &1), &1}),
             "priority desc then id asc not respected"
    end

    test "list ordered by id asc alone is deterministic", %{server: s} do
      opts = [order_by: [id: :asc]]
      {:ok, first} = Bee.list(opts, s)
      {:ok, second} = Bee.list(opts, s)
      assert first == second

      ids = Enum.map(first, & &1.id)
      assert ids == Enum.sort(ids)
    end
  end

  defp get_priority(issues, id) do
    Enum.find(issues, &(&1.id == id)).priority
  end

  # --- Declared exceptions ---

  describe "declared exception: validation error surface" do
    test "the exception list is machine-readable and declares validation_error_surface" do
      exceptions = read_exceptions()
      assert exceptions["version"] == "1.0.0"
      names = Enum.map(exceptions["exceptions"], & &1["name"])
      assert "validation_error_surface" in names
    end

    test "module API raises ArgumentError on invalid limit; message boundary returns tagged error",
         %{server: s} do
      assert_raise ArgumentError, fn -> Bee.list([limit: -1], s) end

      assert {:error, {:invalid_limit, -1}} = GenServer.call(s, {:list, [limit: -1]})
    end

    test "module API raises ArgumentError on invalid include; message boundary returns tagged error",
         %{server: s} do
      assert_raise ArgumentError, fn -> Bee.get(1, [include: [:labels]], s) end

      assert {:error, {:invalid_include, [:labels]}} =
               GenServer.call(s, {:get, 1, [include: [:labels]]})
    end

    test "the writer process survives the message-boundary validation error", %{server: s} do
      pid = Process.whereis(s)
      assert {:error, _} = GenServer.call(s, {:list, [limit: -1]})
      assert Process.alive?(pid)
    end
  end

  # --- Write parity (trivially identical: both route through the same handle_call) ---

  describe "write parity" do
    test "create returns identical issue via both surfaces", %{server: s} do
      {:ok, module_issue} = Bee.create("Parity create", [priority: 1], s)
      {:ok, msg_issue} = GenServer.call(s, {:create, "Parity create 2", [priority: 1]})

      assert module_issue.title == "Parity create"
      assert msg_issue.title == "Parity create 2"
      assert module_issue.priority == msg_issue.priority
    end

    test "comment returns identical :ok via both surfaces", %{server: s, gamma: g} do
      assert Bee.comment(g.id, "via module", [], s) ==
               GenServer.call(s, {:comment, g.id, "via message", []})
    end

    test "comment on missing issue returns identical not_found via both surfaces", %{server: s} do
      assert Bee.comment("GC-9999", "orphan test", [], s) ==
               GenServer.call(s, {:comment, "GC-9999", "orphan test", []})
    end
  end
end
