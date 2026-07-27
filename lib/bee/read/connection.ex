defmodule Bee.Read.Connection do
  @moduledoc false
  @behaviour NimblePool

  @impl true
  def init_pool(db_path) do
    {:ok, db_path}
  end

  @impl true
  def init_worker(db_path) do
    {:ok, conn} = Exqlite.Sqlite3.open(db_path)
    :ok = Bee.Store.configure_pragmas(conn)
    {:ok, conn, db_path}
  end

  @impl true
  def handle_checkout(_command, _from, conn, db_path) do
    {:ok, conn, conn, db_path}
  end

  @impl true
  def handle_checkin(_client_state, _from, conn, db_path) do
    {:ok, conn, db_path}
  end

  @impl true
  def handle_info(_msg, conn) do
    {:ok, conn}
  end

  @impl true
  def terminate_worker(_reason, conn, db_path) do
    Exqlite.Sqlite3.close(conn)
    {:ok, db_path}
  end
end
