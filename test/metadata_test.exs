defmodule Bee.MetadataTest do
  use ExUnit.Case

  setup do
    db_path =
      Path.join(System.tmp_dir!(), "bee_metadata_#{System.unique_integer([:positive])}.db")

    name = :"bee_metadata_#{System.unique_integer([:positive])}"

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

  test "issue metadata is persisted, projected, and evented", %{server: server} do
    assert {:ok, _} = Bee.create("subject", [metadata: %{"consumer:key" => "value"}], server)
    assert {:ok, %{metadata: %{"consumer:key" => "value"}}} = Bee.get(1, server)

    assert :ok = Bee.update(1, %{metadata: %{"consumer:key" => "updated"}}, server)

    assert {:ok, %{issues: [%{metadata: %{"consumer:key" => "updated"}}]}} =
             Bee.query([detail: :standard], server)

    conn = GenServer.call(server, :conn)

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(conn, "SELECT payload FROM events WHERE issue_id = ? AND seq = 2")

    :ok = Exqlite.Sqlite3.bind(stmt, ["test-1"])
    assert {:row, [payload]} = Exqlite.Sqlite3.step(conn, stmt)
    :ok = Exqlite.Sqlite3.release(conn, stmt)
    assert %{"fields" => %{"metadata" => %{"consumer:key" => "updated"}}} = Jason.decode!(payload)
  end

  test "metadata rejects reserved bee keys without writes", %{server: server} do
    assert {:error, :reserved_metadata_key} =
             Bee.create("subject", [metadata: %{"bee:future" => "reserved"}], server)

    assert {:ok, _} = Bee.create("subject", [], server)

    assert {:error, :reserved_metadata_key} =
             Bee.update(1, %{metadata: %{"bee:future" => "reserved"}}, server)

    assert {:ok, 1} = Bee.count([], server)
  end

  test "project metadata is attached through the writer without events", %{server: server} do
    assert {:ok, project} =
             Bee.register_project("project", %{metadata: %{"consumer:key" => "value"}}, server)

    assert %{"consumer:key" => "value"} = project["metadata"]
    conn = GenServer.call(server, :conn)
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT COUNT(*) FROM events")
    assert {:row, [0]} = Exqlite.Sqlite3.step(conn, stmt)
    :ok = Exqlite.Sqlite3.release(conn, stmt)
  end
end
