defmodule Bee do
  @moduledoc """
  A dependency-aware work-coordination engine over SQLite.

  Model units of work as issues, link them with a typed dependency DAG, and query the
  result through a composable spec or a named *intent*. Bee computes ready sets,
  critical paths, and effort rollups; records every mutation to an append-only event
  log; and accepts opaque measurements (cost, tokens, duration) to calibrate its own
  outputs.

  ## Setup

  Add `Bee.Supervisor` to your supervision tree:

      children = [
        {Bee.Supervisor, db_path: "priv/bee.db", prefix: "bee"}
      ]

  ## A first workflow

      {:ok, a} = Bee.create("Implement auth", priority: 2)
      {:ok, b} = Bee.create("Add billing")
      :ok = Bee.block(b.id, a.id, type: :blocks)
      {:ok, ready} = Bee.ready()                  # => [%{id: 1, ...}]  (billing is gated)

      {:ok, %{issues: top, withheld: withheld}} =
        Bee.query(status: "open", limit: 5)        # `withheld` reports what was truncated

  ## Two surfaces

  This module is the in-process facade. Bee also publishes a versioned GenServer
  message protocol (`{:create, title, opts}`, `{:ready, opts}`, ...) for node-crossing
  consumers — a change safe for one surface is proven safe for the other.

  The full guide — dependency vocabulary, the allocation tree, measurements ×
  dimensions, the event log, and configuration — lives in the README, which is the
  HexDocs landing page.
  """

  @default_server Bee.Repo

  @doc "Owner cutover status; diagnostic only, never an admission permit."
  def lane_write_fence_status(server \\ Bee.Repo),
    do: GenServer.call(server, :lane_write_fence_status)

  @doc "Internal admitted lane issue mutation; caller admission is rechecked inside the owner transaction."
  def mutate_lane_issue(attrs, admission_check, server \\ Bee.Repo),
    do: GenServer.call(server, {:mutate_lane_issue, attrs, admission_check}, :infinity)

  @doc "Authenticated owner receipt/current-state read; missing receipt is not an abandonment proof."
  def reconcile_lane_mutation(command, principal, lane, admission_check, server \\ Bee.Repo),
    do:
      GenServer.call(
        server,
        {:reconcile_lane_mutation, command, principal, lane, admission_check},
        :infinity
      )

  @doc "Bee-owned diagnostic target classification; not a mutation permit."
  def classify_lane_write(request, server \\ Bee.Repo),
    do: GenServer.call(server, {:classify_lane_write, request})

  @doc """
  Fetches a single issue by id. Returns `{:ok, issue}` or `{:error, :not_found}`.

  By default relations are not loaded (`comments: :not_loaded`). Pass `include:`
  to load them:

      {:ok, issue} = Bee.get(1, include: [:comments])

  """
  def get(id), do: GenServer.call(@default_server, {:get, id})

  def get(id, opts) when is_list(opts), do: get(id, opts, @default_server)
  def get(id, server), do: GenServer.call(server, {:get, id})

  def get(id, opts, server) when is_list(opts) do
    Bee.Store.validate_opts!(opts)
    GenServer.call(server, {:get, id, opts})
  end

  def get_comments(id, server \\ @default_server),
    do: GenServer.call(server, {:get_comments, id})

  @doc """
  Atomically links an existing Bee issue to a Work Lane as `"root"` or
  `"member"`. `attrs` has exactly `:command_id`, `:lane_id`, `:issue_id`
  (a full Bee issue ID), `:role`, and `:project_id` (the expected Bee
  project, or `nil`). A matching command replays its durable receipt.
  Conflicts and missing issues return tagged errors without changing a link.
  This command never changes `issues.project_id`.
  """
  def associate_lane_issue(attrs, server \\ @default_server) do
    unless Bee.Store.LaneAssociation.valid?(attrs) do
      raise ArgumentError, "invalid lane association"
    end

    GenServer.call(server, {:associate_lane_issue, attrs})
  end

  @doc """
  Reads a Bee-owned receipt and its *current* issue/link state on the writer.
  `:matching` proves the recorded link and project still match; `:stale`
  means they have drifted. `:not_found` is a snapshot, not proof that an
  earlier queued or uncertain command can never commit.
  """
  def reconcile_lane_issue(command_id, server \\ @default_server) do
    unless is_binary(command_id) and byte_size(command_id) in 1..256 do
      raise ArgumentError, "invalid lane association command ID"
    end

    GenServer.call(server, {:reconcile_lane_issue, command_id})
  end

  @doc """
  Returns `{:ok, issues}` — every open issue with no *gating* dependency still
  outstanding. Honours `:blocks`, `:waits_for`, and `:conditional_blocks`.
  """
  def ready(opts \\ [], server \\ @default_server), do: GenServer.call(server, {:ready, opts})

  def list(opts \\ [], server \\ @default_server) do
    Bee.Store.validate_opts!(opts)
    GenServer.call(server, {:list, opts})
  end

  @doc """
  Counts issues matching `opts`: the `list/2` filters plus the query spec's filter
  fields (`:under`, `:include_root`, `:depth`, `:labels_any`, `:issue_types`,
  `:priority_min`, `:priority_max`, `:has_children`, `:blocked`). An unknown
  `:under` returns `{:error, {:not_found, id}}`.

  Runs on a pooled reader in the caller's process, not through the writer.
  """
  def count(opts \\ [], server \\ @default_server) do
    Bee.Store.validate_opts!(opts)

    lane = Bee.Query.Classifier.classify(:count)

    case Bee.Repo.read(server, lane, &Bee.Repo.count(&1, opts, &2)) do
      {:ok, result} -> result
      :unavailable -> GenServer.call(server, {:count, opts})
    end
  end

  @doc """
  Runs a composable query. Returns
  `{:ok, %{issues: [...], withheld: map, refine: keyword}}`.

  `withheld` reports omissions (a truncated `limit`, omitted relations) and `refine`
  suggests how to ask for what was held back. Filter by plain-text `:text`, `:status`,
  one `:project_id` or any of `:project_ids`, `:ready`, `:blocked`, `:assigned_to`,
  `:labels` (all of) or `:labels_any` (any of), `:issue_types`, `:priority_min` /
  `:priority_max`, and `:has_children`; sort with `:order_by`; page with `:limit` and
  either `:offset` or an `:after` cursor; load relations with `:include`; and shape
  each result with `:detail` (`:minimal | :compact | :standard | :full`).

  The result also carries `total` (the match count without `limit`/`after`) and
  `next`, a keyset cursor for the following page (or nil). Pass it back as `:after`
  with the same spec: unlike an offset it stays stable while issues are created or
  closed between pages.

  ## Parent trees

    * `:under` — only strict descendants of that issue over parent edges
      (`include_root: true` adds the issue itself at depth 0). An unknown id returns
      `{:error, {:not_found, id}}`.
    * `:depth` (0..10) — the deepest level returned; each issue then carries `depth`.
      With `:under`, children are depth 1. Without it, depth counts from the nearest
      ancestor that passes the `:status` filter, so an open issue under a closed
      parent is depth 0 in an open-only view.
    * `fold: true` (requires `:depth`) — each issue carries `rollup`, counts over its
      whole real subtree whatever the other filters say.
    * `path: true` — each issue carries `path`, its ancestors from the top down to its
      parent, closed ones included.
    * `keep_ancestors: true` — the ancestors of each match come back too, marked
      `context: true` and listed first; they do not count toward `limit` or `total`.

  Runs on a pooled reader in the caller's process, not through the writer.
  """
  def query(spec, server \\ @default_server) do
    spec = Bee.Query.Spec.new!(spec)
    lane = Bee.Query.Classifier.classify(spec)

    case Bee.Repo.read(server, lane, &Bee.Query.Interpreter.execute(&1, spec, &2)) do
      {:ok, result} -> result
      :unavailable -> GenServer.call(server, {:query, spec})
    end
  end

  @doc """
  Returns `{:ok, [%{id, title, status, issue_type, project_id}]}`: the parent chain
  of `id`, root first, excluding `id` itself (`[]` for a root). `{:error,
  :not_found}` for an unknown id. The walk is bounded, so it terminates even over a
  corrupted parent cycle.
  """
  def ancestors(id, server \\ @default_server) do
    case Bee.Repo.read(server, :fast, &Bee.Repo.ancestors(&1, id, &2)) do
      {:ok, result} -> result
      :unavailable -> GenServer.call(server, {:ancestors, id})
    end
  end

  @doc """
  Resolves an intent — an atom for a built-in (`:what_next`) or a binary name
  registered via `register_intent/3` — into a query spec and runs it.

  Returns the same shape as `query/2`. Intents are pre-composed queries: one engine,
  no drift between a shortcut and the spec it stands for.
  """
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

  @doc """
  Stores a named query spec (persisted in the database). Resolve it later with
  `ask("name", ...)`.
  """
  def register_intent(name, spec, server \\ @default_server),
    do: GenServer.call(server, {:register_intent, name, spec})

  def remove_intent(name, server \\ @default_server),
    do: GenServer.call(server, {:remove_intent, name})

  def list_intents(server \\ @default_server), do: GenServer.call(server, :list_intents)

  @doc """
  Registers a numeric measure (e.g. `"effort"`, `"tokens"`) with a unit and an
  optional value `:domain` (`:any` or `:non_negative`). Required before `measure/3`.
  """
  def register_measure(name, unit),
    do: GenServer.call(@default_server, {:register_measure, name, unit, []})

  def register_measure(name, unit, opts) when is_list(opts),
    do: GenServer.call(@default_server, {:register_measure, name, unit, opts})

  def register_measure(name, unit, server),
    do: GenServer.call(server, {:register_measure, name, unit, []})

  def register_measure(name, unit, opts, server) when is_list(opts),
    do: GenServer.call(server, {:register_measure, name, unit, opts})

  @doc """
  Records an opaque measurement against an issue. `attrs` carries `:measure`,
  `:value`, optional `:source`, and `:dims` — a map whose keys must match
  `[a-z][a-z0-9_]*` and which **must** include `"kind"` (`"estimate"` or `"actual"`).
  """
  def measure(id, attrs, server \\ @default_server),
    do: GenServer.call(server, {:measure, id, attrs})

  def list_measures(server \\ @default_server), do: GenServer.call(server, :list_measures)

  def tree_page(opts \\ [], server \\ @default_server) do
    Bee.Store.validate_opts!(opts)
    GenServer.call(server, {:tree_page, opts})
  end

  @doc """
  Creates an issue. Returns `{:ok, issue}`.

  Supported options: `:description`, `:priority` (integer), `:issue_type` (or `:type`,
  default `"task"`), `:labels` / `:label`, `:parent` (an issue id), `:project_id`,
  `:actor` (the creator), and `:metadata` (a map; reserved prefixes are `bee:` and `_`).
  """
  def create(title, opts \\ [], server \\ @default_server),
    do: GenServer.call(server, {:create, title, opts})

  @doc """
  Updates an issue with a map of attributes. Returns `:ok` or
  `{:error, :not_found | :self_parent | :parent_cycle}`.

  A `:measure` key may be folded into the update to record a measurement atomically
  with the status change that earned it.
  """
  def update(id, attrs, server \\ @default_server),
    do: GenServer.call(server, {:update, id, attrs})

  def comment(id, text, opts \\ [], server \\ @default_server),
    do: GenServer.call(server, {:comment, id, text, opts})

  @doc """
  Adds a dependency: `id` is gated by `blocker_id`. `type:` selects the dependency
  type (default `:blocks`; see the README for the full vocabulary). Returns `:ok` or
  `{:error, :cycle}` if the edge would create a cycle. Only gating types feed
  `ready/0` and rollups.
  """
  def block(id, blocker_id, server \\ @default_server)

  def block(id, blocker_id, opts) when is_list(opts),
    do: block(id, blocker_id, opts, @default_server)

  def block(id, blocker_id, server), do: GenServer.call(server, {:block, id, blocker_id})

  def block(id, blocker_id, opts, server) when is_list(opts),
    do: GenServer.call(server, {:block, id, blocker_id, opts})

  def unblock(id, blocker_id, server \\ @default_server)

  def unblock(id, blocker_id, opts) when is_list(opts),
    do: unblock(id, blocker_id, opts, @default_server)

  def unblock(id, blocker_id, server), do: GenServer.call(server, {:unblock, id, blocker_id})

  def unblock(id, blocker_id, opts, server) when is_list(opts),
    do: GenServer.call(server, {:unblock, id, blocker_id, opts})

  @doc """
  Walks the dependency graph from `id`. `direction: :blockers` (default) follows
  gating edges toward what gates `id`; `:dependents` follows them toward what `id`
  gates. Returns `{:ok, [ids]}`.
  """
  def traverse(id, opts \\ [], server \\ @default_server) when is_list(opts),
    do: GenServer.call(server, {:traverse, id, opts})

  def candidates(id, server \\ @default_server),
    do: GenServer.call(server, {:candidates, id})

  @doc """
  Returns `{:ok, [ids]}` — the longest dependency path through the gating DAG,
  computed with a memoized topsort rather than exponential recursion. Pass `:root`
  for the blocker-to-goal chain ending at one issue, or scope the global path with
  `:project_id` and/or `:status`. `:types` selects dependency types and `:depth`
  bounds rooted traversal (maximum 100).
  """
  def critical_path(), do: GenServer.call(@default_server, :critical_path)
  def critical_path(opts) when is_list(opts), do: critical_path(opts, @default_server)
  def critical_path(server), do: GenServer.call(server, :critical_path)

  def critical_path(opts, server) when is_list(opts),
    do: GenServer.call(server, {:critical_path, opts})

  @doc """
  Aggregates effort (`measure: "effort"`) over a scope rooted at `id`.

  Options: `:scope` (`:tree` | `:closure` | `:critical_path`, default `:tree`),
  `:kind` (`:estimate` | `:actual`, default `:actual`), `:meaning` (`:spent` |
  `:to_complete`, default `:spent`). If any node lacks a measurement, `total` is
  `nil`, a `partial_total` is given, and `refine` lists the missing ids — bee never
  silently invents a sum.
  """
  def rollup(id, opts \\ [], server \\ @default_server) when is_list(opts),
    do: GenServer.call(server, {:rollup, id, opts})

  @doc """
  Acquires a lock on an issue. Options: `:locked_by` (holder id), `:ttl` (minutes,
  default 30), `:force` (take the lock from its current holder).

  Returns `{:ok, lock}` or `{:error, :already_locked | :not_found}`. Expired locks
  are released by a background sweeper.
  """
  def lock(id, opts \\ [], server \\ @default_server),
    do: GenServer.call(server, {:lock, id, opts})

  def unlock(id, server \\ @default_server), do: GenServer.call(server, {:unlock, id})

  # World operations
  def register_project(id, attrs \\ %{}, server \\ @default_server),
    do: GenServer.call(server, {:register_project, id, attrs})

  def register_agent(id, attrs \\ %{}, server \\ @default_server),
    do: GenServer.call(server, {:register_agent, id, attrs})

  def list_projects(server \\ @default_server), do: GenServer.call(server, :list_projects)
  def list_agents(server \\ @default_server), do: GenServer.call(server, :list_agents)

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
