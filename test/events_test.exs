defmodule Bee.Store.EventsTest do
  use ExUnit.Case

  setup do
    db_path =
      Path.join(System.tmp_dir!(), "bee_events_#{:erlang.unique_integer([:positive])}.db")

    name = :"bee_events_#{:erlang.unique_integer([:positive])}"

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

  test "records one typed event with a canonical payload", %{server: server} do
    {:ok, _} = Bee.create("subject", [], server)
    conn = GenServer.call(server, :conn)

    assert {:ok, 2} =
             Bee.Store.Events.record(conn, "test-1", "issue.updated",
               actor: "agent",
               fields: %{status: "closed"},
               refs: %{comment_id: 3}
             )

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT event_type, payload, actor FROM events WHERE issue_id = ? AND seq = 2"
      )

    :ok = Exqlite.Sqlite3.bind(stmt, ["test-1"])

    assert {:row, ["issue.updated", payload, "agent"]} = Exqlite.Sqlite3.step(conn, stmt)
    :ok = Exqlite.Sqlite3.release(conn, stmt)

    assert %{
             "fields" => %{"status" => "closed"},
             "refs" => %{"comment_id" => 3},
             "rejected" => %{}
           } = Jason.decode!(payload)
  end

  test "create commits one issue.created event", %{server: server} do
    assert {:ok, _} = Bee.create("subject", [actor: "agent"], server)
    conn = GenServer.call(server, :conn)

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT event_type, actor, payload FROM events WHERE issue_id = ? AND seq = 1"
      )

    :ok = Exqlite.Sqlite3.bind(stmt, ["test-1"])
    assert {:row, ["issue.created", "agent", payload]} = Exqlite.Sqlite3.step(conn, stmt)
    :ok = Exqlite.Sqlite3.release(conn, stmt)
    assert %{"fields" => %{"title" => "subject"}} = Jason.decode!(payload)
  end

  test "update commits one issue.updated event", %{server: server} do
    assert {:ok, _} = Bee.create("subject", [], server)
    assert :ok = Bee.update(1, %{status: "closed"}, server)
    conn = GenServer.call(server, :conn)

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT event_type, payload FROM events WHERE issue_id = ? AND seq = 2"
      )

    :ok = Exqlite.Sqlite3.bind(stmt, ["test-1"])
    assert {:row, ["issue.updated", payload]} = Exqlite.Sqlite3.step(conn, stmt)
    :ok = Exqlite.Sqlite3.release(conn, stmt)
    assert %{"fields" => %{"status" => "closed"}} = Jason.decode!(payload)
  end

  test "comment commits one issue.commented event", %{server: server} do
    assert {:ok, _} = Bee.create("subject", [], server)
    assert :ok = Bee.comment(1, "note", [author: "agent"], server)
    conn = GenServer.call(server, :conn)

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT event_type, actor, payload FROM events WHERE issue_id = ? AND seq = 2"
      )

    :ok = Exqlite.Sqlite3.bind(stmt, ["test-1"])
    assert {:row, ["issue.commented", "agent", payload]} = Exqlite.Sqlite3.step(conn, stmt)
    :ok = Exqlite.Sqlite3.release(conn, stmt)
    assert %{"fields" => %{"body" => "note"}} = Jason.decode!(payload)
  end

  test "block commits one dep.added event", %{server: server} do
    assert {:ok, _} = Bee.create("blocker", [], server)
    assert {:ok, _} = Bee.create("dependent", [], server)
    assert :ok = Bee.block(2, 1, server)
    conn = GenServer.call(server, :conn)

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT event_type, payload FROM events WHERE issue_id = ? AND seq = 2"
      )

    :ok = Exqlite.Sqlite3.bind(stmt, ["test-2"])
    assert {:row, ["dep.added", payload]} = Exqlite.Sqlite3.step(conn, stmt)
    :ok = Exqlite.Sqlite3.release(conn, stmt)

    assert %{"fields" => %{"depends_on_id" => "test-1", "dep_type" => "blocks"}} =
             Jason.decode!(payload)
  end

  test "unblock emits only when it removes a dependency", %{server: server} do
    assert {:ok, _} = Bee.create("blocker", [], server)
    assert {:ok, _} = Bee.create("dependent", [], server)
    assert :ok = Bee.block(2, 1, server)
    assert :ok = Bee.unblock(2, 1, server)
    assert :ok = Bee.unblock(2, 1, server)
    conn = GenServer.call(server, :conn)

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT event_type FROM events WHERE issue_id = ? ORDER BY seq"
      )

    :ok = Exqlite.Sqlite3.bind(stmt, ["test-2"])
    assert {:row, ["issue.created"]} = Exqlite.Sqlite3.step(conn, stmt)
    assert {:row, ["dep.added"]} = Exqlite.Sqlite3.step(conn, stmt)
    assert {:row, ["dep.removed"]} = Exqlite.Sqlite3.step(conn, stmt)
    assert :done = Exqlite.Sqlite3.step(conn, stmt)
    :ok = Exqlite.Sqlite3.release(conn, stmt)
  end

  test "lock and unlock emit events only for state changes", %{server: server} do
    assert {:ok, _} = Bee.create("subject", [], server)
    assert {:ok, _} = Bee.lock(1, [locked_by: "agent"], server)
    assert :ok = Bee.unlock(1, server)
    assert :ok = Bee.unlock(1, server)
    conn = GenServer.call(server, :conn)

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT event_type FROM events WHERE issue_id = ? ORDER BY seq"
      )

    :ok = Exqlite.Sqlite3.bind(stmt, ["test-1"])
    assert {:row, ["issue.created"]} = Exqlite.Sqlite3.step(conn, stmt)
    assert {:row, ["lock.acquired"]} = Exqlite.Sqlite3.step(conn, stmt)
    assert {:row, ["lock.released"]} = Exqlite.Sqlite3.step(conn, stmt)
    assert :done = Exqlite.Sqlite3.step(conn, stmt)
    :ok = Exqlite.Sqlite3.release(conn, stmt)
  end

  test "assign emits only when it changes the assignee", %{server: server} do
    assert {:ok, _} = Bee.register_agent("agent", %{}, server)
    assert {:ok, _} = Bee.create("subject", [], server)
    assert :ok = Bee.assign(1, "agent", server)
    assert :ok = Bee.assign(1, "agent", server)
    conn = GenServer.call(server, :conn)

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT event_type, payload FROM events WHERE issue_id = ? ORDER BY seq"
      )

    :ok = Exqlite.Sqlite3.bind(stmt, ["test-1"])
    assert {:row, ["issue.created", _]} = Exqlite.Sqlite3.step(conn, stmt)
    assert {:row, ["issue.updated", payload]} = Exqlite.Sqlite3.step(conn, stmt)
    assert :done = Exqlite.Sqlite3.step(conn, stmt)
    :ok = Exqlite.Sqlite3.release(conn, stmt)
    assert %{"fields" => %{"assigned_to" => "agent"}} = Jason.decode!(payload)
  end

  test "measure registration is unit-bound, idempotent, and event-free", %{server: server} do
    assert :ok = Bee.register_measure("cost", "eur", server)
    assert :ok = Bee.register_measure("cost", "eur", server)
    assert {:error, :unit_mismatch} = Bee.register_measure("cost", "usd", server)
    assert {:error, :invalid_measure} = Bee.register_measure("", "eur", server)
    assert {:error, :invalid_measure} = Bee.register_measure("weight", "", server)
    conn = GenServer.call(server, :conn)

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(conn, "SELECT unit FROM measures WHERE name = ?")

    :ok = Exqlite.Sqlite3.bind(stmt, ["cost"])
    assert {:row, ["eur"]} = Exqlite.Sqlite3.step(conn, stmt)
    assert :done = Exqlite.Sqlite3.step(conn, stmt)
    :ok = Exqlite.Sqlite3.release(conn, stmt)

    {:ok, event_stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT COUNT(*) FROM events")
    assert {:row, [0]} = Exqlite.Sqlite3.step(conn, event_stmt)
    :ok = Exqlite.Sqlite3.release(conn, event_stmt)
  end

  test "truncates oversized payload values with digest metadata", %{server: server} do
    {:ok, _} = Bee.create("subject", [], server)
    conn = GenServer.call(server, :conn)
    body = String.duplicate("a", 2_100)

    assert {:ok, 2} =
             Bee.Store.Events.record(conn, "test-1", "issue.updated", fields: %{body: body})

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(conn, "SELECT payload FROM events WHERE issue_id = ? AND seq = 2")

    :ok = Exqlite.Sqlite3.bind(stmt, ["test-1"])
    assert {:row, [payload]} = Exqlite.Sqlite3.step(conn, stmt)
    :ok = Exqlite.Sqlite3.release(conn, stmt)

    assert %{"fields" => %{"body" => %{"_truncated" => true, "bytes" => bytes}}} =
             Jason.decode!(payload)

    assert bytes > 2_000
  end

  test "keeps truncation previews valid UTF-8", %{server: server} do
    {:ok, _} = Bee.create("subject", [], server)
    conn = GenServer.call(server, :conn)
    body = String.duplicate("😀", 600)

    assert {:ok, 2} =
             Bee.Store.Events.record(conn, "test-1", "issue.updated", fields: %{body: body})

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(conn, "SELECT payload FROM events WHERE issue_id = ? AND seq = 2")

    :ok = Exqlite.Sqlite3.bind(stmt, ["test-1"])
    assert {:row, [payload]} = Exqlite.Sqlite3.step(conn, stmt)
    :ok = Exqlite.Sqlite3.release(conn, stmt)

    assert %{"fields" => %{"body" => %{"preview" => preview}}} = Jason.decode!(payload)
    assert String.valid?(preview)
    assert byte_size(preview) <= 2_048
  end

  test "sequences events per issue", %{server: server} do
    {:ok, _} = Bee.create("first", [], server)
    {:ok, _} = Bee.create("second", [], server)
    conn = GenServer.call(server, :conn)

    assert {:ok, 2} = Bee.Store.Events.record(conn, "test-1", "issue.updated")
    assert {:ok, 3} = Bee.Store.Events.record(conn, "test-1", "issue.updated")
    assert {:ok, 2} = Bee.Store.Events.record(conn, "test-2", "issue.updated")
  end
end
