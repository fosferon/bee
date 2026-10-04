defmodule Bee.LaneMutationTest do
  use ExUnit.Case, async: false
  @lane "lane_0123456789abcdef01234567"
  @principal "principal-fixture"

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "bee-command-" <> Base.encode16(:crypto.strong_rand_bytes(8)) <> ".db"
      )

    repo =
      start_supervised!(
        {Bee.Repo,
         db_path: path, prefix: "GC", jsonl_path: nil, name: __MODULE__, lane_write_fence: true}
      )

    {:ok, issue} = Bee.create("Fixture", [], repo)
    id = "GC-#{issue.id}"

    {:ok, _} =
      Bee.associate_lane_issue(
        %{command_id: "link", lane_id: @lane, issue_id: id, role: "root", project_id: nil},
        repo
      )

    on_exit(fn -> Enum.each([path, path <> "-wal", path <> "-shm"], &File.rm/1) end)
    %{server: repo, issue_id: id, path: path}
  end

  defp attrs(ctx, body \\ %{"text" => "Owner command"}),
    do: %{
      command_id: "original-key",
      lane_id: @lane,
      principal_ref: @principal,
      issue_id: ctx.issue_id,
      action: "comment",
      body: body
    }

  defp admitted, do: {:ok, %{principal_ref: @principal, lane_id: @lane}}

  defp command(ctx, request \\ nil, check \\ &admitted/0),
    do: Bee.mutate_lane_issue(request || attrs(ctx), check, ctx.server)

  defp query(ctx),
    do: Bee.reconcile_lane_mutation("original-key", @principal, @lane, &admitted/0, ctx.server)

  test "one admitted effect, exact replay, owner receipt and current-state reconciliation", ctx do
    assert {:ok, %{receipt: receipt, replayed: false}} = command(ctx)
    assert {:ok, %{receipt: ^receipt, replayed: true}} = command(ctx)
    assert {:ok, %{receipt: ^receipt, current: :matching}} = query(ctx)
    assert {:ok, [comment]} = Bee.get_comments(ctx.issue_id, ctx.server)
    assert comment.body == "Owner command" and comment.author == @principal
    assert {:error, :lane_mutation_conflict} = command(ctx, attrs(ctx, %{"text" => "changed"}))
    assert {:ok, [^comment]} = Bee.get_comments(ctx.issue_id, ctx.server)
  end

  test "receipt replay survives owner restart without repeating effect", ctx do
    assert {:ok, %{receipt: receipt}} = command(ctx)
    stop_supervised!(Bee.Repo)

    restarted =
      start_supervised!(
        {Bee.Repo,
         db_path: ctx.path,
         prefix: "GC",
         jsonl_path: nil,
         name: __MODULE__,
         lane_write_fence: true}
      )

    ctx = %{ctx | server: restarted}
    assert {:ok, %{receipt: ^receipt, replayed: true}} = command(ctx)
    assert {:ok, [_]} = Bee.get_comments(ctx.issue_id, restarted)
  end

  test "admission is current inside the acquired owner transaction and denies all effects", ctx do
    owner = ctx.server

    checker = fn ->
      assert self() == owner
      {:error, :credential_revoked}
    end

    assert {:error, :credential_revoked} = command(ctx, nil, checker)
    assert {:ok, []} = Bee.get_comments(ctx.issue_id, owner)
    assert {:error, :receipt_not_found} = query(ctx)
    assert {:error, :lane_mutation_not_admitted} = command(ctx, nil, fn -> :ok end)
  end

  test "caller and lane mismatches never reveal another command receipt", ctx do
    assert {:ok, _} = command(ctx)
    other = %{attrs(ctx) | principal_ref: "other-principal"}
    other_check = fn -> {:ok, %{principal_ref: "other-principal", lane_id: @lane}} end
    assert {:error, :non_disclosing_conflict} = command(ctx, other, other_check)

    assert {:error, :non_disclosing_conflict} =
             Bee.reconcile_lane_mutation(
               "original-key",
               "other-principal",
               @lane,
               other_check,
               ctx.server
             )

    assert {:error, :non_disclosing_conflict} =
             Bee.reconcile_lane_mutation(
               "original-key",
               @principal,
               "other-lane",
               fn -> {:ok, %{principal_ref: @principal, lane_id: "other-lane"}} end,
               ctx.server
             )
  end

  test "a later owned event reports stale rather than pretending the receipt is current", ctx do
    assert {:ok, _} = command(ctx)

    later = %{
      attrs(ctx)
      | command_id: "later-key",
        action: "update",
        body: %{"title" => "Later state"}
    }

    assert {:ok, _} = command(ctx, later)
    assert {:ok, %{current: :stale}} = query(ctx)
    assert {:ok, %{title: "Later state"}} = Bee.get(ctx.issue_id, ctx.server)
  end

  test "concurrent exact-key delivery records one effect", ctx do
    results =
      1..6 |> Task.async_stream(fn _ -> command(ctx) end) |> Enum.map(fn {:ok, r} -> r end)

    assert Enum.all?(results, &match?({:ok, _}, &1))
    assert Enum.count(results, &match?({:ok, %{replayed: false}}, &1)) == 1
    assert {:ok, [_]} = Bee.get_comments(ctx.issue_id, ctx.server)
  end

  test "database failure rolls back issue state, event and receipt", ctx do
    # Fault injection in the disposable owner fixture; no production connection borrowing.
    conn = :sys.get_state(ctx.server).conn

    assert :ok =
             Exqlite.Sqlite3.execute(
               conn,
               "CREATE TRIGGER deny_receipt BEFORE INSERT ON lane_mutation_receipts BEGIN SELECT RAISE(ABORT, 'fixture failure'); END"
             )

    assert {:error, _} = command(ctx)
    assert {:ok, []} = Bee.get_comments(ctx.issue_id, ctx.server)
    assert {:error, :receipt_not_found} = query(ctx)
    assert Process.alive?(ctx.server)
  end

  test "SQL write failure cannot produce a success receipt", ctx do
    # Existing Store.update_issue swallows certain SQL errors; the owner command
    # uses a typed write instead and proves rollback explicitly.
    conn = :sys.get_state(ctx.server).conn

    assert :ok =
             Exqlite.Sqlite3.execute(
               conn,
               "CREATE TRIGGER deny_update BEFORE UPDATE OF title ON issues BEGIN SELECT RAISE(ABORT, 'fixture failure'); END"
             )

    request = %{attrs(ctx) | action: "update", body: %{"title" => "must fail"}}
    assert {:error, _} = command(ctx, request)
    assert {:error, :receipt_not_found} = query(ctx)
    assert {:ok, %{title: "Fixture"}} = Bee.get(ctx.issue_id, ctx.server)
  end

  test "shared issue targets require admission for every lane before any mutation", ctx do
    assert {:ok, _} =
             Bee.associate_lane_issue(
               %{
                 command_id: "another-link",
                 lane_id: "other-lane",
                 issue_id: ctx.issue_id,
                 role: "member",
                 project_id: nil
               },
               ctx.server
             )

    assert {:error, :cross_lane_mutation_requires_gateway} = command(ctx)
    assert {:ok, []} = Bee.get_comments(ctx.issue_id, ctx.server)
    assert {:error, :receipt_not_found} = query(ctx)
  end

  test "invalid reconciliation and scalar requests deny without owner loss", ctx do
    assert {:error, :invalid_lane_mutation} =
             Bee.reconcile_lane_mutation(nil, @principal, @lane, &admitted/0, ctx.server)

    request = %{attrs(ctx) | action: "update", body: %{"priority" => Integer.pow(2, 100)}}
    assert {:error, :invalid_lane_mutation} = command(ctx, request)
    assert Process.alive?(ctx.server)
  end
end
