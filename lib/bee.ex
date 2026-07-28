defmodule Bee do
  @moduledoc """
  Lightweight work coordination library with dependency DAG and allocation tree.
  """

  @default_server Bee.Repo

  def get(id), do: GenServer.call(@default_server, {:get, id})

  def get(id, opts) when is_list(opts), do: get(id, opts, @default_server)
  def get(id, server), do: GenServer.call(server, {:get, id})

  def get(id, opts, server) when is_list(opts) do
    Bee.Store.validate_opts!(opts)
    GenServer.call(server, {:get, id, opts})
  end

  def get_comments(id, server \\ @default_server),
    do: GenServer.call(server, {:get_comments, id})

  def ready(opts \\ [], server \\ @default_server), do: GenServer.call(server, {:ready, opts})

  def list(opts \\ [], server \\ @default_server) do
    Bee.Store.validate_opts!(opts)
    GenServer.call(server, {:list, opts})
  end

  def count(opts \\ [], server \\ @default_server) do
    Bee.Store.validate_opts!(opts)
    GenServer.call(server, {:count, opts})
  end

  def query(spec, server \\ @default_server) do
    spec = Bee.Query.Spec.new!(spec)
    GenServer.call(server, {:query, spec})
  end

  def ask(intent, opts \\ [], server \\ @default_server)

  def ask(intent, opts, server) when is_atom(intent) and is_list(opts) do
    unless Bee.Intent.Core.known?(intent) do
      raise ArgumentError, "unknown core intent: #{inspect(intent)}"
    end

    GenServer.call(server, {:ask, intent, opts})
  end

  def ask(intent, opts, server) when is_binary(intent) and is_list(opts),
    do: GenServer.call(server, {:ask, intent, opts})

  def ask(_intent, _opts, _server), do: raise(ArgumentError, "invalid intent request")

  def register_intent(name, spec, server \\ @default_server),
    do: GenServer.call(server, {:register_intent, name, spec})

  def remove_intent(name, server \\ @default_server),
    do: GenServer.call(server, {:remove_intent, name})

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

  def block(id, blocker_id, server \\ @default_server)
  def block(id, blocker_id, opts) when is_list(opts), do: block(id, blocker_id, opts, @default_server)
  def block(id, blocker_id, server), do: GenServer.call(server, {:block, id, blocker_id})

  def block(id, blocker_id, opts, server) when is_list(opts),
    do: GenServer.call(server, {:block, id, blocker_id, opts})

  def unblock(id, blocker_id, server \\ @default_server),
    do: GenServer.call(server, {:unblock, id, blocker_id})

  def traverse(id, opts \\ [], server \\ @default_server) when is_list(opts),
    do: GenServer.call(server, {:traverse, id, opts})

  def candidates(id, server \\ @default_server),
    do: GenServer.call(server, {:candidates, id})

  def critical_path(server \\ @default_server), do: GenServer.call(server, :critical_path)

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
