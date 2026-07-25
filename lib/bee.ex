defmodule Bee do
  @moduledoc """
  Lightweight work coordination library with dependency DAG and allocation tree.
  """

  @default_server Bee.Repo

  def get(id, server \\ @default_server), do: GenServer.call(server, {:get, id})
  def ready(opts \\ [], server \\ @default_server), do: GenServer.call(server, {:ready, opts})

  def list(opts \\ [], server \\ @default_server) do
    Bee.Store.validate_opts!(opts)
    GenServer.call(server, {:list, opts})
  end

  def count(opts \\ [], server \\ @default_server) do
    Bee.Store.validate_opts!(opts)
    GenServer.call(server, {:count, opts})
  end

  def tree_page(opts \\ [], server \\ @default_server) do
    Bee.Store.validate_opts!(opts)
    GenServer.call(server, {:tree_page, opts})
  end

  def create(title, opts \\ [], server \\ @default_server),
    do: GenServer.call(server, {:create, title, opts})

  def update(id, attrs, server \\ @default_server),
    do: GenServer.call(server, {:update, id, attrs})

  def comment(id, text, opts \\ [], server \\ @default_server),
    do: GenServer.call(server, {:comment, id, text, opts})

  def block(id, blocker_id, server \\ @default_server),
    do: GenServer.call(server, {:block, id, blocker_id})

  def unblock(id, blocker_id, server \\ @default_server),
    do: GenServer.call(server, {:unblock, id, blocker_id})

  def lock(id, opts \\ [], server \\ @default_server),
    do: GenServer.call(server, {:lock, id, opts})

  def unlock(id, server \\ @default_server), do: GenServer.call(server, {:unlock, id})

  # World operations
  def register_project(id, attrs \\ %{}, server \\ @default_server),
    do: GenServer.call(server, {:register_project, id, attrs})

  def register_agent(id, attrs \\ %{}, server \\ @default_server),
    do: GenServer.call(server, {:register_agent, id, attrs})

  def assign(issue_id, agent_id, server \\ @default_server),
    do: GenServer.call(server, {:assign, issue_id, agent_id})

  def join_project(agent_id, project_id, server \\ @default_server),
    do: GenServer.call(server, {:join_project, agent_id, project_id})

  def who_blocks_whom(server \\ @default_server), do: GenServer.call(server, :who_blocks_whom)

  def agent_load(agent_id, server \\ @default_server),
    do: GenServer.call(server, {:agent_load, agent_id})

  def bottlenecks(server \\ @default_server), do: GenServer.call(server, :bottlenecks)

  # Import/export
  def import_jsonl(path, server \\ @default_server),
    do: GenServer.call(server, {:import_jsonl, path})
end
