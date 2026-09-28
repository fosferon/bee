defmodule Bee.LaneAssociationTest do
  use ExUnit.Case

  setup do
    db_path = Path.join(System.tmp_dir!(), "bee_lane_#{System.unique_integer([:positive])}.db")
    name = :"bee_lane_#{System.unique_integer([:positive])}"

    {:ok, pid} =
      Bee.Repo.start_link(db_path: db_path, prefix: "GC", jsonl_path: nil, name: name)

    on_exit(fn ->
      if Process.alive?(pid) do
        try do
          GenServer.stop(pid)
        catch
          :exit, _ -> :ok
        end
      end

      File.rm(db_path)
      File.rm(db_path <> "-wal")
      File.rm(db_path <> "-shm")
    end)

    %{server: name, db_path: db_path, pid: pid}
  end

  defp command(issue_id, overrides \\ %{}) do
    Map.merge(
      %{
        command_id: "command-1",
        lane_id: "wl_123",
        issue_id: issue_id,
        role: "root",
        project_id: nil
      },
      overrides
    )
  end

  test "writer transaction stores a durable replayable receipt without changing project", %{
    server: s,
    db_path: path,
    pid: pid
  } do
    {:ok, issue} = Bee.create("Root", [], s)
    attrs = command("GC-#{issue.id}")

    assert {:ok, receipt} = Bee.associate_lane_issue(attrs, s)
    assert Map.take(receipt, Map.keys(attrs)) == attrs
    assert is_integer(receipt.event_seq)
    assert {:ok, ^receipt} = GenServer.call(s, {:associate_lane_issue, attrs})

    assert {:ok, %{receipt: ^receipt, current: :matching}} =
             Bee.reconcile_lane_issue(attrs.command_id, s)

    assert {:ok, %{project_id: nil}} = Bee.get(issue.id, s)
    GenServer.stop(pid)
    {:ok, _} = Bee.Repo.start_link(db_path: path, prefix: "GC", jsonl_path: nil, name: s)

    assert {:ok, ^receipt} = Bee.associate_lane_issue(attrs, s)

    assert {:ok, %{receipt: ^receipt, current: :matching}} =
             Bee.reconcile_lane_issue(attrs.command_id, s)
  end

  test "competing roots serialize to one receipt and one link", %{server: s} do
    {:ok, first} = Bee.create("First", [], s)
    {:ok, second} = Bee.create("Second", [], s)
    a = command("GC-#{first.id}")
    b = command("GC-#{second.id}", %{command_id: "command-2"})

    results =
      [a, b]
      |> Task.async_stream(&Bee.associate_lane_issue(&1, s), max_concurrency: 2)
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :association_conflict})) == 1

    for {attrs, result} <- Enum.zip([a, b], results) do
      case result do
        {:ok, receipt} ->
          assert {:ok, %{receipt: ^receipt, current: :matching}} =
                   Bee.reconcile_lane_issue(attrs.command_id, s)

        {:error, :association_conflict} ->
          assert {:error, :not_found} = Bee.reconcile_lane_issue(attrs.command_id, s)
      end
    end
  end

  test "conflicting replay, second root, changed role, and wrong project do not write", %{
    server: s
  } do
    {:ok, first} = Bee.create("First", [], s)
    {:ok, second} = Bee.create("Second", [], s)
    attrs = command("GC-#{first.id}")
    other = command("GC-#{second.id}", %{command_id: "command-2"})

    assert {:ok, _} = Bee.associate_lane_issue(attrs, s)

    assert {:error, :association_conflict} =
             Bee.associate_lane_issue(%{attrs | role: "member"}, s)

    assert {:error, :association_conflict} = Bee.associate_lane_issue(other, s)
    assert {:error, :not_found} = Bee.reconcile_lane_issue(other.command_id, s)

    assert {:error, :association_conflict} =
             Bee.associate_lane_issue(%{attrs | command_id: "command-3", project_id: "wrong"}, s)

    assert {:ok, _} =
             Bee.associate_lane_issue(%{other | role: "member"}, s)

    assert {:error, :association_conflict} =
             Bee.associate_lane_issue(
               %{other | command_id: "command-4", issue_id: attrs.issue_id, role: "member"},
               s
             )
  end

  test "reconciliation detects project drift but preserves historical receipt", %{server: s} do
    {:ok, issue} = Bee.create("Root", [], s)
    attrs = command("GC-#{issue.id}")
    assert {:ok, receipt} = Bee.associate_lane_issue(attrs, s)

    assert {:ok, _} = Bee.register_project("project-one", %{name: "Project one"}, s)
    assert :ok = Bee.update(issue.id, %{project_id: "project-one"}, s)

    assert {:ok, %{receipt: ^receipt, current: :stale}} =
             Bee.reconcile_lane_issue(attrs.command_id, s)

    assert {:ok, ^receipt} = Bee.associate_lane_issue(attrs, s)

    assert {:error, :association_conflict} =
             Bee.associate_lane_issue(%{attrs | command_id: "command-new"}, s)
  end

  test "invalid messages and unknown issues are rejected without killing writer", %{server: s} do
    assert {:error, :invalid_lane_association} =
             GenServer.call(s, {:associate_lane_issue, %{command_id: "bad"}})

    assert_raise ArgumentError, fn -> Bee.associate_lane_issue(%{command_id: "bad"}, s) end

    assert {:error, :invalid_lane_association} =
             Bee.associate_lane_issue(command("other-1"), s)

    assert {:error, :issue_not_found} = Bee.associate_lane_issue(command("GC-9999"), s)
    assert {:error, :not_found} = Bee.reconcile_lane_issue("command-1", s)

    assert {:error, :invalid_lane_association} =
             GenServer.call(s, {:reconcile_lane_issue, nil})

    assert {:ok, _} = Bee.create("Still alive", [], s)
  end
end
