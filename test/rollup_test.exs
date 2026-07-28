defmodule Bee.Graph.RollupTest do
  use ExUnit.Case

  setup do
    db_path = Path.join(System.tmp_dir!(), "bee_rollup_#{System.unique_integer([:positive])}.db")
    name = :"bee_rollup_#{System.unique_integer([:positive])}"

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

  test "tree sums latest actual effort for a node and its descendants", %{server: server} do
    create_issues(server, 3)
    assert :ok = Bee.update(2, %{parent: 1}, server)
    assert :ok = Bee.update(3, %{parent: 2}, server)
    measure(server, 1, 2)
    measure(server, 2, 5)
    measure(server, 3, 8)

    assert {:ok, %{total: 15.0, partial_total: 15.0, covered: 3, missing: 0}} =
             Bee.rollup(1, [], server)
  end

  test "closure follows only gating blockers and counts diamonds once", %{server: server} do
    create_issues(server, 4)
    assert :ok = Bee.block(1, 2, server)
    assert :ok = Bee.block(1, 3, server)
    assert :ok = Bee.block(2, 4, server)
    assert :ok = Bee.block(3, 4, server)
    measure(server, 1, 1)
    measure(server, 2, 2)
    measure(server, 3, 3)
    measure(server, 4, 4)

    assert {:ok, %{total: 10.0, covered: 4, missing: 0}} =
             Bee.rollup(1, [scope: :closure], server)
  end

  test "missing effort is honest while zero effort is complete", %{server: server} do
    create_issues(server, 2)
    assert :ok = Bee.update(2, %{parent: 1}, server)
    measure(server, 1, 0)

    assert {:ok, result} = Bee.rollup(1, [], server)
    assert result.total == nil
    assert result.partial_total == 0.0
    assert result.covered == 1
    assert result.missing == 1
    assert result.withheld == %{missing_measure: 1}
    assert result.refine == [record_effort: ["test-2"]]
  end

  test "latest measurement for the selected kind wins", %{server: server} do
    create_issues(server, 1)
    measure(server, 1, 3)
    measure(server, 1, 7)

    assert :ok =
             Bee.measure(
               1,
               %{measure: "effort", value: 11, dims: %{"kind" => "estimate"}},
               server
             )

    assert {:ok, %{total: 7.0}} = Bee.rollup(1, [kind: :actual], server)
    assert {:ok, %{total: 11.0}} = Bee.rollup(1, [kind: :estimate], server)
  end

  test "to_complete excludes cancelled nodes while spent retains them", %{server: server} do
    create_issues(server, 2)
    assert :ok = Bee.update(2, %{parent: 1, status: "cancelled"}, server)
    measure(server, 1, 3)
    measure(server, 2, 5)

    assert {:ok, %{total: 8.0}} = Bee.rollup(1, [meaning: :spent], server)
    assert {:ok, %{total: 3.0}} = Bee.rollup(1, [meaning: :to_complete], server)
  end

  test "critical_path selects the longest complete effort path", %{server: server} do
    create_issues(server, 4)
    assert :ok = Bee.block(1, 2, server)
    assert :ok = Bee.block(1, 3, server)
    assert :ok = Bee.block(2, 4, server)
    measure(server, 1, 1)
    measure(server, 2, 5)
    measure(server, 3, 8)
    measure(server, 4, 2)

    assert {:ok, %{total: 9.0, covered: 2, missing: 0}} =
             Bee.rollup(1, [scope: :critical_path], server)
  end

  test "unknown issue returns not_found", %{server: server} do
    assert {:error, :not_found} = Bee.rollup(99, [], server)
  end

  defp create_issues(server, count) do
    Enum.each(1..count, fn number ->
      assert {:ok, _} = Bee.create("issue #{number}", [], server)
    end)
  end

  defp measure(server, id, value) do
    assert :ok =
             Bee.measure(
               id,
               %{measure: "effort", value: value, dims: %{"kind" => "actual"}},
               server
             )
  end
end
