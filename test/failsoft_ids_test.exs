defmodule Bee.FailsoftIdsTest do
  @moduledoc """
  GC-4873: one unparseable id must not take down a whole read.

  `gc_work list` is the most-used call in the system. Before this, a single row
  whose id Bee.Id could not parse raised through the entire result set, so every
  caller got nothing. Anything writing to bee.db outside Bee's own id allocation
  can plant one — a migration, scripts/bee-merge, a manual repair, or (how this
  was found) a test inserting `gc-ticker-lock-<n>` directly.
  """
  use ExUnit.Case

  import ExUnit.CaptureLog

  setup do
    db_path =
      Path.join(System.tmp_dir!(), "bee_failsoft_#{:erlang.unique_integer([:positive])}.db")

    name = :"bee_failsoft_#{:erlang.unique_integer([:positive])}"

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

    %{server: name, db_path: db_path}
  end

  # Write straight to SQLite, bypassing Bee's id allocation — exactly what the
  # things that plant these rows do.
  defp plant_bad_row!(db_path, id) do
    {:ok, conn} = Exqlite.Sqlite3.open(db_path)

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "INSERT INTO issues (id, title, status, priority, created_at, updated_at) " <>
          "VALUES (?, ?, 'open', 50, datetime('now'), datetime('now'))"
      )

    :ok = Exqlite.Sqlite3.bind(stmt, [id, "planted by something that is not Bee"])
    :done = Exqlite.Sqlite3.step(conn, stmt)
    :ok = Exqlite.Sqlite3.release(conn, stmt)
    :ok = Exqlite.Sqlite3.close(conn)
  end

  test "one unparseable id does not take down the listing", %{server: s, db_path: db} do
    {:ok, a} = Bee.create("first real issue", [], s)
    {:ok, b} = Bee.create("second real issue", [], s)

    plant_bad_row!(db, "gc-ticker-lock-8677")

    log =
      capture_log(fn ->
        assert {:ok, issues} = Bee.list([], s)
        ids = Enum.map(issues, & &1.id)

        # Both real issues survive; the malformed row is simply absent.
        assert a.id in ids
        assert b.id in ids
        refute Enum.any?(issues, &(&1.title == "planted by something that is not Bee"))
      end)

    # Absent is not enough — it has to be reported, or a row silently vanishes.
    assert log =~ "gc-ticker-lock-8677"
    assert log =~ "GC-4873"
  end

  test "the surviving rows are complete, not degraded", %{server: s, db_path: db} do
    {:ok, real} = Bee.create("keeps its fields", [priority: 77], s)
    plant_bad_row!(db, "not-a-valid-id")

    capture_log(fn ->
      assert {:ok, issues} = Bee.list([], s)
      found = Enum.find(issues, &(&1.id == real.id))

      assert found.title == "keeps its fields"
      assert found.priority == 77
      assert found.labels == []
      assert found.blocked_by == []
    end)
  end

  test "a dangling dependency edge drops the edge, not the issue", %{server: s, db_path: db} do
    {:ok, real} = Bee.create("has a broken blocker", [], s)

    # A blocked_by pointing at an id that will not parse. The issue itself is
    # fine and must still be returned — losing real work over a broken pointer
    # would be a worse failure than the one being fixed.
    {:ok, conn} = Exqlite.Sqlite3.open(db)

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "INSERT INTO dependencies (issue_id, depends_on_id, dep_type, created_at) " <>
          "VALUES (?, ?, 'blocks', datetime('now'))"
      )

    :ok = Exqlite.Sqlite3.bind(stmt, [Bee.Id.to_prefixed(real.id, "test"), "gc-ticker-lock-99"])
    :done = Exqlite.Sqlite3.step(conn, stmt)
    :ok = Exqlite.Sqlite3.release(conn, stmt)
    :ok = Exqlite.Sqlite3.close(conn)

    log =
      capture_log(fn ->
        assert {:ok, issues} = Bee.list([], s)
        found = Enum.find(issues, &(&1.id == real.id))

        assert found, "the issue must survive a dangling reference"
        assert found.blocked_by == []
      end)

    assert log =~ "gc-ticker-lock-99"
  end

  test "get on a healthy issue is unaffected by a bad row elsewhere", %{server: s, db_path: db} do
    {:ok, real} = Bee.create("fetched by id", [], s)
    plant_bad_row!(db, "gc-ticker-lock-1")

    capture_log(fn ->
      assert {:ok, issue} = Bee.get(real.id, s)
      assert issue.title == "fetched by id"
    end)
  end

  test "get on an unparseable row reports not_found rather than raising", %{
    server: s,
    db_path: db
  } do
    plant_bad_row!(db, "gc-ticker-lock-42")

    # The caller asked for something Bee cannot represent. Before GC-4873 this
    # raised ArgumentError; the failure mode that replaced it must not be a
    # badarg from `hd([])`, which would name nothing.
    capture_log(fn ->
      assert {:error, :not_found} = Bee.get("gc-ticker-lock-42", s)
    end)
  end
end
