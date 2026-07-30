# Bee

**A dependency-aware work-coordination engine for Elixir — over SQLite.**

Bee models units of work and the relationships between them: a dependency DAG that
knows what *blocks* what, an allocation tree of projects and agents, and a query
language that does not just return results but tells you **what it withheld and how to
ask again**. It is designed for programs and agents that need to track, query, and
reason about work — not just store it.

- **A real dependency graph.** Seven dependency types with distinct meaning — gating
  (`blocks`, `waits_for`, `conditional_blocks`), non-gating (`related`,
  `discovered_from`, `replies_to`), and structural (`parent_child`). Cycle detection
  happens at write time; `ready/0` honours every gating rule.
- **Describe intent, get answers.** `Bee.ask(:what_next, agent: "mercury", project: "api")`
  is a pre-composed query. Register your own intents (`Bee.register_intent/2`) and a
  string name resolves to the same engine — no drift.
- **Queries that report their omissions.** Every `Bee.query/1` returns the matching
  issues **plus** a `withheld` map (what was truncated or omitted, and why) and a
  `refine` hint (how to ask for it). Built for consumers that would otherwise choke on
  unbounded output.
- **Measurements × dimensions.** Capture opaque outside signal — cost, tokens,
  duration — against arbitrary dimensions (agent, model, branch). Schemaless but
  indexable. Roll effort up over a tree, a dependency closure, or the critical path.
- **An append-only event log.** Every mutation is recorded unconditionally — status
  changes, comments, blocks, assignments, locks. Bee's autobiography, captured with no
  opt-in.
- **Two first-class surfaces.** The in-process `Bee.*` API **and** a versioned GenServer
  message protocol. A consumer reaching bee across a node is as supported as one calling
  a function.
- **Honest concurrency.** A single writer serialises all mutations (so cycle checks and
  id allocation are correct); a two-lane reader pool serves reads from WAL snapshots.
  Durability promises state their conditions — no false absolutes.

Bee persists to its own SQLite database and **owns its schema**. No consumer creates,
alters, or drops objects in it. The boundary is the namespace.

---

## Installation

Bee is not yet on Hex.pm (the `bee` name is taken by another package; a
rename is pending). For now, depend on it directly from Git:

```elixir
def deps do
  [
    {:bee, git: "https://github.com/fosferon/bee.git", tag: "v0.1.0"}
  ]
end
```

Then fetch and compile:

```bash
mix deps.get
mix deps.compile
```

Bee requires Elixir 1.19+ and a working SQLite (bundled via [`exqlite`](https://hex.pm/packages/exqlite)).

---

## Quick start

Bee is a supervised process. Add it to your application's supervision tree:

```elixir
children = [
  {Bee.Supervisor,
   db_path: "priv/bee.db",
   prefix: "bee",
   jsonl_path: "priv/bee.jsonl"}   # optional — a derived, append-only export
]

Supervisor.start_link(children, strategy: :one_for_one)
```

`prefix` namespaces the internal ids (`bee-1`, `bee-2`, …) so several bee instances can
share analysis tooling without colliding. You address issues by their plain integer —
bee resolves the prefix for you.

### Create, block, and find ready work

```elixir
{:ok, auth} = Bee.create("Implement auth", priority: 2, project_id: "api")
# => {:ok, %{id: 1, title: "Implement auth", status: "open", ...}}

{:ok, billing} = Bee.create("Add billing", priority: 3, project_id: "api")
# billing depends on auth — billing is blocked until auth closes
:ok = Bee.block(billing.id, auth.id, type: :blocks)

{:ok, ready} = Bee.ready()
# => {:ok, [%{id: 1, title: "Implement auth", ...}]}   # billing is not ready

{:ok, [^auth | _]} = Bee.critical_path()
```

### Query, and read what was withheld

```elixir
{:ok, %{issues: issues, withheld: withheld, refine: refine}} =
  Bee.query(status: "open", project_id: "api", limit: 5, detail: :compact)

# withheld => %{limit: 42}            # 42 more issues exist beyond the limit
# refine  => [limit: nil]             # ask again like this to see them all
```

Four detail levels shape each result — `:minimal | :compact | :standard | :full` — so a
list view doesn't pay for full descriptions, and a detail view can.

### Ask in your own words

```elixir
# A built-in intent
{:ok, %{issues: top}} =
  Bee.ask(:what_next, agent: "mercury", project: "api", limit: 3)

# Register your own — a named, stored query spec
:ok = Bee.register_intent("stale-and-open", status: "open", order_by: [created_at: :asc])
{:ok, %{issues: stale}} = Bee.ask("stale-and-open")
```

### Measure, then roll up effort

```elixir
:ok = Bee.register_measure("effort", "hours", domain: :non_negative)

:ok = Bee.measure(auth.id, %{
  measure: "effort",
  value: 6.0,
  dims: %{"kind" => "estimate", "agent" => "mercury"}
})

# Sum declared effort across the whole subtree under a node
{:ok, rollup} = Bee.rollup(epic.id, scope: :tree, kind: :estimate, meaning: :to_complete)
# => {:ok, %{total: 22.0, covered: 18, missing: 0, ...}}
```

Rollup scopes: `:tree` (subtree by parent), `:closure` (dependency transitive closure),
`:critical_path` (the longest weighted path). If some nodes lack a measurement, bee
reports `total: nil`, a `partial_total`, and a `refine` hint listing exactly which ids
are missing — it never silently invents a number.

---

## Core concepts

### The dependency vocabulary

Not all relationships gate. Bee refuses meaningless dependency types at the boundary —
each one carries a distinct meaning:

| Type | Class | Meaning |
| --- | --- | --- |
| `:blocks` | gating | B can't start until A closes |
| `:waits_for` | gating | B waits for **all** of A's children |
| `:conditional_blocks` | gating | B runs only if A **fails** |
| `:parent_child` | structural | parent blocked ⇒ children blocked (derived from `parent:`) |
| `:related` | non-gating | loose "see also" |
| `:discovered_from` | non-gating | provenance |
| `:replies_to` | non-gating | threading |

Only gating edges feed `ready/0`, `critical_path/0`, and dependency rollups. Traversal
honours the direction you ask for:

```elixir
{:ok, blockers} = Bee.traverse(id, direction: :blockers)    # why is this gated?
{:ok, dependents} = Bee.traverse(id, direction: :dependents) # what does this gate?
```

### The allocation tree

Alongside the dependency DAG, bee tracks **who works on what**:

```elixir
:ok = Bee.register_project("api", name: "API service")
:ok = Bee.register_agent("mercury", name: "Mercury", type: "worker")
:ok = Bee.join_project("mercury", "api")
:ok = Bee.assign(auth.id, "mercury")

{:ok, load} = Bee.agent_load("mercury")          # how many open issues?
{:ok, pairs} = Bee.who_blocks_whom()              # which agents gate each other?
{:ok, bns} = Bee.bottlenecks()                    # overloaded agents + their projects
```

### Measurements: measures × dimensions

A **measure** is numeric and calibratable (`effort`, `tokens`, `cost`). A **dimension**
is categorical and groupable (`agent`, `model`, `branch`). Bee never interprets dimension
*values* — it partitions on them, which makes it simultaneously agnostic and useful.

```elixir
:ok = Bee.register_measure("tokens", "tokens")
:ok = Bee.measure(billing.id, %{
  measure: "tokens",
  value: 1840,
  dims: %{"kind" => "actual", "model" => "claude", "agent" => "mercury"}
})
```

Every measurement carries a `"kind"` dimension (`"estimate"` or `"actual"`) so declared
plans can later be measured against what was earned. Dimensions are schemaless JSON but
indexable on demand — arbitrary vocabulary, no migration, fast `GROUP BY`.

### The event log

Every mutation — create, update, comment, block, unblock, assign, lock, measure — is
written to an append-only `events` table with a per-issue monotonic sequence. It is
bee's autobiography, captured with nobody opting in. Tail it by the global id cursor, or
replay an issue's history by sequence.

### Locks

```elixir
{:ok, lock} = Bee.lock(auth.id, locked_by: "mercury", ttl: 30)   # 30-minute hold
{:error, :already_locked} = Bee.lock(auth.id, locked_by: "venus")
:ok = Bee.unlock(auth.id)
```

Locks carry a TTL and a holder. A background sweeper releases expired locks; each expiry
is recorded as an event. `force: true` takes the lock from its current holder.

---

## Two consumption surfaces

Bee supports two equal, disjoint interfaces:

1. **The `Bee.*` module API** — the in-process facade shown throughout this README.
   Structural errors raise `ArgumentError` in your process for good ergonomics.
2. **The `Bee.Repo` GenServer message protocol** — a versioned wire contract for
   node-crossing consumers (`{:create, title, opts}`, `{:ready, opts}`, …). Invalid
   messages return `{:error, reason}` and **never raise** inside the writer — a raise
   there would kill the single writer and every queued command behind it.

A change safe for one surface is proven safe for the other.

---

## Configuration

`Bee.Supervisor` accepts:

| Option | Required | Default | Notes |
| --- | --- | --- | --- |
| `:db_path` | yes | — | Path to the SQLite database file. |
| `:prefix` | no | `"bee"` | Namespace for internal ids. |
| `:jsonl_path` | no | `nil` | If set, bee maintains a derived JSONL export (debounced, flushed on orderly shutdown). |
| `:name` | no | `Bee.Supervisor` | Supervisor name. |
| `:repo_name` | no | `Bee.Repo` | Repo GenServer name — pass it to the `server` arg of any `Bee.*` call. |
| `:pool_name` | no | derived | Reader-pool supervisor name. |
| `:sweeper_name` | no | derived | Lock-sweeper name. |

You can also start a standalone `Bee.Repo` directly (handy in tests):

```elixir
{:ok, _pid} =
  Bee.Repo.start_link(db_path: db_path, prefix: "test", jsonl_path: nil, name: :my_bee)
```

---

## Architecture notes

- **Single writer, reader pool.** All writes go through one GenServer over one
  connection, inside `BEGIN IMMEDIATE` transactions. Reads are served by a two-lane
  NimblePool of read-only connections — a `:fast` lane for point lookups and lists, a
  `:compute` lane for traversals, critical paths, and rollups. Heavy compute never
  blocks `list/1`. WAL mode gives readers MVCC snapshots for free.
- **Versioned migrations.** Schema changes run at boot, in order, behind `PRAGMA
  user_version`. No ad-hoc DDL, ever.
- **Honest durability.** On an orderly stop or a trapped exit, bee flushes the JSONL
  export and runs a `TRUNCATE` checkpoint. On a brutal kill, neither runs — the WAL is
  recovered on the next boot and at most the last un-flushed event window is missing
  (re-exportable, since JSONL is derived from the database).
- **Raw SQL, by design.** The work DAG needs recursive CTEs, FTS5, expression indexes,
  and single-writer serialisation that an ORM would obscure. SQL is confined to the
  storage layer (`Bee.Store.*`); it never leaks above it.

---

## Import / export

```elixir
{:ok, count} = Bee.import_jsonl("priv/bee.jsonl")
```

The JSONL export is one object per issue (with its comments and measurements). On first
boot, if the database is empty and `jsonl_path` exists, bee seeds from it — so the file
is both a backup and a portability format.

---

## Testing & development

```bash
mix test         # 178 tests
mix docs         # build this README into HexDocs
mix hex.build    # build the package tarball
```

## License

MIT — see the [LICENSE](https://github.com/fosferon/bee/blob/master/LICENSE) file.
