# Brownfield Ratification Review — ARCHITECTURE-SPINE.md (bee)

**Reviewer mandate:** does this spine ratify the existing codebase's real conventions, or invent new ones that will cause needless churn and half-migrated code?

**Scope reviewed:** `ARCHITECTURE-SPINE.md` (284 lines) against the complete implementation — `lib/bee.ex` (43), `lib/bee/store.ex` (811), `lib/bee/repo.ex` (345), `lib/bee/graph.ex` (124), `lib/bee/world.ex` (200), `lib/bee/agents.ex` (171), `lib/bee/export.ex` (145), `lib/bee/id.ex` (47), `lib/bee/lock.ex` (85), `test/bee_test.exs` (437), `mix.exs` (26). Total 1,997 LOC lib + test.

---

## Verdict

**The spine is a strong greenfield design and a weak brownfield ratification.** Its diagnoses are accurate and evidence-backed — the N+1 enrichment (AD-10), the per-write JSONL dump (AD-17), the `CREATE TABLE IF NOT EXISTS` schema drift (AD-15), the missing extension point (AD-14) are all real defects visible in the code at the exact places the spine implies. Where it fails is the other direction: it does not enumerate what the existing code gets *right*, and its structural seed **has no destination for four of the nine existing modules** — `Bee.World`, `Bee.Agents`, `Bee.Id`, and (as a name) `Bee.Repo` itself. Three public API functions (`who_blocks_whom/1`, `agent_load/2`, `bottlenecks/1`) and four more (`register_project/3`, `register_agent/3`, `assign/3`, `join_project/3`) route through modules the new tree does not contain. Cycle detection — a correctness guarantee currently provided free by `:digraph.new([:acyclic])` — is mentioned only in passing as a rationale in AD-2 and has no owner anywhere in the target structure.

An implementer following only this document will produce a system that is architecturally cleaner and behaviourally wrong in at least eleven specific ways catalogued below, and will break every one of the 24 existing tests without a stated parity strategy.

The recommendation is not to rewrite the spine. It is to add a **Ratified Conventions** section, a **Module Disposition** table, and one new invariant (**AD-18, parity**) before any implementer touches code.

---

## 1. Conventions the code already has that the spine ignores or contradicts

### 1.1 Opts validation — the code already implements the spine's stated rule, and the spine does not credit it

Spine, Consistency Conventions, "Errors": *"Argument validation raises `ArgumentError` in the **caller's** process, before any dispatch."*

This is not aspirational. It is implemented, deliberately, and documented in the code:

- `Bee.Store.validate_opts!/1` — `lib/bee/store.ex:236-242`
- its docstring, `lib/bee/store.ex:231-235`: *"Raises ArgumentError on invalid input. Called from the public API before dispatching to GenServer so errors surface in the caller's process."*
- call sites in the facade, before `GenServer.call`: `lib/bee.ex:11`, `lib/bee.ex:16`, `lib/bee.ex:21`

There is also **deliberate double validation**: `build_order/2` re-validates the same whitelist at `lib/bee/store.ex:493-508`, as defence for callers reaching `Bee.Store` directly with a raw conn. Both layers must survive the move. An implementer who reads AD-4 ("every read resolves to a `Bee.Query.Spec`") and puts validation inside `Spec.validate!` called *by the interpreter* — i.e. inside the pool process — silently breaks this convention while believing they implemented it. The spec must be validated **in the caller**, before lane classification and checkout.

**Also:** the spine locates the id parse function in `Bee.Store` (Ids row) but the structural seed contains **no `bee/store.ex` file** — only `bee/store/*.ex`. `validate_opts!` and `parse_numeric_id` are named as living in a module the seed deletes.

### 1.2 Ids — the spine states a convention the code violates in four places, without saying so

Spine: *"One parse function in `Bee.Store` — never reimplemented."*

Currently reimplemented **four times**, none sharing code:

| Function | Location | Direction |
| --- | --- | --- |
| `Bee.Store.parse_numeric_id/1` | `store.ex:717-732` | prefixed → integer |
| `Bee.Repo.resolve_id/2` | `repo.ex:251-264` | integer/string → prefixed |
| `Bee.Repo.format_parent/2` | `repo.ex:266-272` | same, but with `nil`/`""` handling |
| `Bee.Export.extract_num/1` | `export.ex:131-144` | prefixed → integer, returns `0` on failure |

Consolidating is correct. But three behaviours must be preserved, and the spine's phrasing would destroy each:

1. **`parse_numeric_id` returns the original string on failure** (`store.ex:726`, `store.ex:732`). The return type is `integer() | String.t()`, not `integer()`. The spine says flatly "returns integers". Any consumer holding a non-numeric-suffixed id relies on the passthrough.
2. **`resolve_id` treats *any* binary containing `-` as already-prefixed** (`repo.ex:254-255`). Passing `"GC-2691"` to a `prefix: "test"` repo silently addresses a foreign row rather than erroring. Behaviour, not necessarily desired — but a consumer may depend on cross-prefix addressing. Decide explicitly; do not change by accident.
3. `parse_numeric_id` uses `List.last(String.split(id, "-"))` (`store.ex:718-721`), so a prefix containing a dash works accidentally. A "cleaner" `String.split(id, "-", parts: 2)` rewrite inverts this.

### 1.3 Errors and return shapes — the spine mandates a total break with no acknowledgement

Spine: *"Query results: Always a map with `withheld` and, where bounded, `total`. **Never a bare list.**"* and *"Update results: Mutations report which fields were applied and which rejected. **Never report bare `:ok`.**"*

Both are correct designs. Both are **total breaking changes to the entire public API**, and the spine never says so, never offers a shim, and never states a deprecation window. Present shapes:

| Function | Present return | `bee.ex` | Under spine |
| --- | --- | --- | --- |
| `list/3`, `ready/3` | `{:ok, [map]}` | :10, :9 | map w/ `withheld` — **breaks** |
| `count/3` | `{:ok, integer}` | :15 | ambiguous |
| `tree_page/3` | `{:ok, %{roots:, issues:, total_roots:}}` | :20 | reshaped |
| `update/3` | `:ok` \| `{:error, atom}` | :25 | applied/rejected report — **breaks** |
| `comment/4`, `block/3`, `unblock/3`, `unlock/2` | `:ok` | :26-30 | **breaks** |
| `assign/3`, `join_project/3` | `:ok` | :35-36 | **breaks** |
| `agent_load/2` | **bare integer** (`repo.ex:198-201`) | :38 | **breaks** |
| `who_blocks_whom/1` | **bare list of tuples** (`repo.ex:193-196`) | :37 | **breaks** |
| `bottlenecks/1` | **bare list of 3-tuples** (`repo.ex:203-206`) | :39 | **breaks** |

The last three are the clearest example of the spine stating a convention the code contradicts without noticing: three public functions return naked values with no `{:ok, _}` wrapper at all.

### 1.4 Enrichment — the diagnosis is right, the migration path is missing

AD-10's diagnosis is exact. `enrich_issue/2` (`store.ex:694-715`) fires four queries per row — `get_labels` (:377), `get_blocked_by` (:453), `get_blocks` (:467), `get_lock_info` (:734) — and is applied unconditionally in `list_issues` (:281), `get_issue` (:155) and `fetch_and_enrich_by_ids` (:628). On the measured production DB that is 2,686 × 4 = 10,744 queries for an unfiltered list.

What AD-10 does not specify, and what determines whether the change is safe or catastrophic: **what a non-included relation looks like in the returned map.**

- **absent key** → `issue.labels` raises `KeyError` — loud, survivable
- **`nil`** → `Enum.count(issue.labels)` raises `Protocol.UndefinedError` — loud, survivable
- **`[]`** → **silently reports "this issue has no labels / no blockers / is not locked"** — wrong data, indistinguishable from truth

The third is the natural default a careless implementer picks, and it is the single most dangerous outcome in this whole migration: `blocked_by: []` on a blocked issue silently corrupts every readiness and path computation downstream. AD-11's `withheld` map is result-set-level accounting; it does not cover per-issue relation absence.

**Required:** an explicit rule. Recommend a sentinel (`:not_loaded`) or absent-key, never an empty collection, plus a note in AD-10.

Note also that `enrich_issue` performs the **id integerisation** (`store.ex:699-703`) — ids, `blocked_by`, `blocks` and `parent` are converted from prefixed strings to integers there. That is not enrichment, it is projection, and it must happen at **every** detail level including `:minimal`, or `detail: :minimal` silently returns `"test-1"` where `:compact` returns `1`.

### 1.5 Ordering — `priority` NULLs-last is load-bearing and invisible to the spine

`build_order_clause/1`, `store.ex:519-522`:

```elixir
case col do
  :priority -> "priority IS NULL, #{col_str} #{dir_str}"
  _ -> "#{col_str} #{dir_str}"
end
```

`priority` is nullable (`store.ex:48`), and SQLite sorts NULLs **first** by default. This special case forces NULL-priority issues to the bottom in both directions. It is asserted by `test/bee_test.exs:413-424` (via `root_default_order` = `[priority: :desc, created_at: :desc]`, `store.ex:484`).

Nothing in the spine mentions NULL ordering. A clean-slate `Bee.Query.Interpreter` emitting `ORDER BY priority DESC` silently reorders every priority-sorted list every consumer displays. This is the kind of change that is never traced back to the refactor.

Related: the order whitelist `@order_columns ~w(created_at updated_at priority id)a` (`store.ex:4`) is a **closed set**, tested at `bee_test.exs:293-305`, and is the only thing preventing SQL injection through `order_by` (the column name is interpolated into the SQL string, `store.ex:516-524`). The spine's `Spec` must carry an equivalent whitelist; it never says so.

### 1.6 Silent failure — the spine forbids it; the code has three instances, one of which is load-bearing

Spine: *"Silent failure: Forbidden. No blanket `rescue _ -> {:ok, []}`."*

Three violations exist:

1. `Bee.Repo.maybe_export/1` — `rescue e -> Logger.warning(...)`, `repo.ex:240-245`. Safe to remove once AD-17's debounce lands.
2. `Bee.Repo.maybe_seed_from_jsonl/3` — `else _ -> :ok`, `repo.ex:341`. Safe to make explicit.
3. **`Bee.Export.import_jsonl/3` — `try do Bee.Store.insert_issue(...) rescue _ -> :ok end`, `export.ex:106-110`.** This one is load-bearing. It is the *only* thing making import idempotent: a re-import of an existing id violates the `issues` primary key, the rescue swallows it, and the loop continues to that row's comments and dependencies (which use `INSERT OR IGNORE`, `store.ex:370`, `store.ex:435`). Deleting the rescue in the name of AD-"no silent failure" **breaks boot-time seeding and re-import** with a raise.

Correct fix: replace the rescue with an explicit `INSERT ... ON CONFLICT DO NOTHING` / upsert in `insert_issue`, then remove the rescue. Do not remove the rescue alone.

### 1.7 `metadata` does not exist

AD-14 is written in the present tense: *"`issues.metadata` and `projects.metadata` hold arbitrary consumer JSON."* `grep -rn metadata lib/` returns **zero results**. The schema at `store.ex:43-58` (issues) and `store.ex:15-22` (projects) has no such column. This is new work requiring a migration, not a ratified convention. Reword to future tense so no implementer assumes it is already there.

(The commit `f613ee6 "feat: support mutable issue metadata"` is misleadingly named — it added `issue_type`/`parent` mutability, not a metadata column.)

### 1.8 Dates — ratified, with one hazard the spine should name

Spine: *"ISO8601 UTC strings in storage. Comparisons are SQL-side."* Code matches: `now_iso/0` at `store.ex:810`, `agents.ex:170`, and `Bee.Lock.sweep_expired/1` compares SQL-side at `lock.ex:70`.

**Hazard:** `DateTime.to_iso8601/1` emits the `+00:00` offset form (`2026-07-20T11:00:00.123456+00:00`), while `Bee.Export` writes a literal `"0001-01-01T00:00:00Z"` for synthesised dependency timestamps (`export.ex:38`). The JSONL contract therefore already carries two lexically-incomparable formats. Since AD-15/AD-9 push more comparison into SQL, the spine should fix one canonical form (`Z` suffix, fixed precision) at migration time — string comparison across `+00:00` and `Z` is silently wrong.

---

## 2. Module → destination map

Legend: **✅ placed** · **⚠️ placed but under-specified** · **❌ no destination in the spine**

| Existing | LOC | Destination in spine's tree | Status |
| --- | --- | --- | --- |
| `Bee` (`lib/bee.ex`) | 43 | `lib/bee.ex` facade | ✅ (signatures change wholesale — §1.3) |
| `Bee.Repo` — mutating handlers | ~180 | `bee/write/server.ex` | ⚠️ **module name is a consumer contract** — see 2.1 |
| `Bee.Repo` — read handlers (`:get` :72, `:list` :77, `:count` :81, `:tree_page` :85, `:ready` :89) | ~35 | `bee/query/interpreter.ex` via `bee/read/pool.ex` | ✅ |
| `Bee.Repo` — lock sweep timer (`repo.ex:219-224`, `@lock_sweep_interval_ms` :6) | ~10 | — | ❌ no owner |
| `Bee.Repo` — `handle_call(:conn, ...)` (`repo.ex:48`) | 1 | — | ❌ and see 3.9 |
| `Bee.Repo` — boot JSONL seed (`repo.ex:27`, `:333-344`) | ~12 | — | ❌ (AD-17 covers export only) |
| `Bee.Repo` — `terminate/2` (`repo.ex:227-232`) | 6 | `bee/export.ex` flush + writer shutdown | ⚠️ split across two homes |
| `Bee.Repo` — `parent_cycle?/3`, `validate_parent_update/3` (`repo.ex:296-327`) | 32 | — | ❌ see 3.2 |
| `Bee.Repo` — `normalize_update_attrs/3` `type`→`issue_type` (`repo.ex:274-294`) | 21 | — | ❌ see 3.4 |
| `Bee.Store` — `init_schema/1` (:8-109) | 102 | `bee/store/migrate.ex` + `store/migrations/` | ✅ (AD-15) |
| `Bee.Store` — issue CRUD (:113-229) | 117 | `bee/store/issues.ex` | ✅ |
| `Bee.Store` — `validate_opts!/1` (:236-273) | 38 | `bee/query/spec.ex` | ⚠️ must stay caller-process (§1.1) |
| `Bee.Store` — `build_where/1` (:769-808), `build_order/2` (:486-529), `build_limit_offset/1` (:531-554), `run_query/4` (:556-562) | ~110 | `bee/query/interpreter.ex` | ✅ |
| `Bee.Store` — `enrich_issue/2` (:694-715), `row_to_issue/2` (:673-692) | 42 | `bee/query/projection.ex` | ⚠️ id integerisation must not be optional (§1.4) |
| `Bee.Store` — labels (:369-385) | 17 | `bee/store/labels.ex` | ✅ |
| `Bee.Store` — comments (:389-427) | 39 | `bee/store/comments.ex` | ✅ |
| `Bee.Store` — dependencies (:431-478) | 48 | `bee/store/deps.ex` | ✅ (must gain `dep_type` filter — see 3.3) |
| `Bee.Store` — `count_roots/2` (:310-332), `list_tree_page/2` (:349-365), `fetch_root_page/2` (:566-591), `gather_descendants/2` (:593-611), `fetch_and_enrich_by_ids/2` (:613-631), `sort_by_root_order/3` (:633-643) | ~120 | — | ❌ **see 2.2** |
| `Bee.Store` — `parse_numeric_id/1` (:717-732) | 16 | "`Bee.Store`" per Ids convention | ❌ that file does not exist in the seed |
| `Bee.Store` — `list_issues_raw/2` (:284-291) | 8 | `detail: :minimal` | ⚠️ see 3.8 |
| `Bee.Graph` — `ready_issues/2` (:63-74) | 12 | `bee/graph/ready.ex` | ✅ (semantics change — 3.3) |
| `Bee.Graph` — `critical_path/1`, `longest_path/2` (:87-109) | 23 | `bee/graph/critical_path.ex` | ⚠️ results change — 3.6 |
| `Bee.Graph` — `new/0` `:acyclic` (:5-7), `add_dependency/3` (:32-40), `remove_dependency/3`, `rebuild/2`, `add_vertex/2` | ~50 | — | ❌ **cycle detection has no owner — see 3.1** |
| `Bee.Graph` — `blocked_by/2` (:77-79), `blocks/2` (:82-84) | 6 | — | **dead code** (no callers in lib or test) |
| **`Bee.World`** (entire module) | **200** | — | ❌ **absent from seed, capability map, and Deferred — see 2.3** |
| **`Bee.Agents`** (entire module) | **171** | — | ❌ **absent — see 2.4** |
| **`Bee.Id`** (entire module) | **47** | — | ❌ **absent — see 2.5** |
| `Bee.Lock` — `acquire/3`, `release/2`, `get/2` | ~60 | `bee/store/locks.ex` | ✅ (`force:` is read-then-write — must stay in the writer) |
| `Bee.Lock` — `sweep_expired/1` (:68-76) | 9 | `bee/store/locks.ex` (data) but the **timer** has no owner | ⚠️ |
| `Bee.Export` — `export/2` (:5-70) | 66 | `bee/export.ex` | ✅ (AD-17) |
| `Bee.Export` — `import_jsonl/3` (:73-129) | 57 | — | ❌ AD-17 mentions export only; `Bee.import_jsonl/2` is public API (`bee.ex:42`) |
| — | — | `bee/application.ex` / supervisor | ❌ **does not exist and is not in the seed — see 2.6** |

### 2.1 `Bee.Repo` is a name, not just a module

`@default_server Bee.Repo` (`bee.ex:6`) is the default for all 19 public functions. Consumers supervise the process **by that module name** and pass it as the `server` argument. `test/bee_test.exs:9-15` starts it directly. Renaming it to `Bee.Write.Server` per the seed breaks:

- every consumer supervision-tree child spec
- every explicit `server` argument in gc_daemon and DevMan
- all 24 tests

The spine must state the disposition explicitly: either `Bee.Repo` is retained as the supervisor/entry name with the writer underneath, or the rename is a declared breaking change gated on GC-2694. Silence here guarantees a half-migrated result.

### 2.2 `tree_page` has no destination

~120 LOC implementing the roots-plus-complete-subtrees paged query, added five days ago (commits `57d219f`, `833ee6a`, GC-2682), with **seven dedicated tests** (`bee_test.exs:336-436`). It is public API (`bee.ex:20`).

It is neither a rollup (AD-12 / `graph/rollup.ex` — it aggregates nothing) nor a plain list (it paginates roots while returning whole subtrees). The nearest homes are `graph/traverse.ex` or a `query/` tree-mode. **The spine has no slot for it and never mentions it.** Two non-obvious rules inside it must be preserved verbatim:

- **"parent out of scope ⇒ node is a root"** — `store.ex:317-318` and `store.ex:574-575`, tested at `bee_test.exs:379-392`
- **"a subtree stays whole even if a descendant falls outside the scope filter"** — documented at `store.ex:340-342`, implemented by `gather_descendants/2` querying `issues` unfiltered (`store.ex:596-604`)

These two rules are in tension with each other and were clearly arrived at deliberately. An implementer re-deriving tree paging from AD-12 will not reproduce them.

### 2.3 `Bee.World` — the largest hole

200 LOC. Owns the **allocation graph** (`:digraph` of `{:project, id}` / `{:agent, id}` / `{:issue, id}` vertices, `world.ex:5-42`), constructed at boot (`repo.ex:24`, `:30`) and mutated on every create/assign/register/join (`repo.ex:67`, `:169`, `:176`, `:182`, `:189`).

It backs **three public API functions**:

- `Bee.who_blocks_whom/1` → `world.ex:100-119` (joins dep_graph edges to assigned agents)
- `Bee.agent_load/2` → `world.ex:85-97`
- `Bee.bottlenecks/1` → `world.ex:124-142` (consumes `Bee.Graph.critical_path/1`)

**None of these appear anywhere in the spine** — not in the structural seed, not in the Capability → Architecture Map, not in Deferred. The word "agent" appears in the ER diagram (`AGENTS ||--o{ ISSUES : assigned`) and nowhere else.

This is not a small omission. `who_blocks_whom` and `bottlenecks` are exactly the "knowledge a consumer cannot reasonably reproduce: traversal, ranking, aggregation" that AD-5 says Core intents exist for — they are the *strongest* existing evidence for the spine's own thesis, and the spine drops them. They should be Core intents (`:who_blocks_whom`, `:bottlenecks`, `:agent_load`) implemented over SQL in L2, with the alloc-graph deleted.

`Bee.World.available_in_project/3` (`world.ex:145-157`) has **no callers** — dead code, delete rather than migrate.

### 2.4 `Bee.Agents` — no destination

171 LOC. Owns `projects`, `agents`, `project_agents` — three of the eight tables in `init_schema`. Backs four public API functions: `register_project/3` (`bee.ex:33`), `register_agent/3` (:34), `assign/3` (:35), `join_project/3` (:36).

The seed's `store/` directory lists `issues.ex deps.ex comments.ex labels.ex locks.ex events.ex measurements.ex` — **no `projects.ex`, no `agents.ex`**. Yet the ER diagram declares both entities and AD-14 names `projects.metadata` as an extension point. Direct internal contradiction.

Roughly half the module is uncalled inside bee (`list_projects`, `get_project` as a public entry, `update_agent`, `list_agents`, `remove_project_agent`, `unassign_issue`, `project_agents`) — but these are plausibly reached by gc_daemon through the `:conn` escape hatch (§3.9). **Verify against gc_daemon before deleting any of it.**

### 2.5 `Bee.Id` — no destination, despite AD-2 citing it

47 LOC. The id allocator: `next/2` (`id.ex:5-17`) is an atomic `INSERT ... ON CONFLICT DO UPDATE ... RETURNING` against `id_counter`, called on every create (`repo.ex:51`). `set/3` (`id.ex:35-46`) resets the high-water mark after import (`export.ex:122`) — without it, a post-import create collides with an imported id.

AD-2 explicitly names the risk this module manages: *"Prevents: concurrent writers corrupting **id allocation** and DAG cycle checks."* So the spine knows about it and still gives it no file. Place it at `bee/store/id.ex` or `bee/write/ids.ex` and state that allocation happens **inside the writer**, in the same transaction as the insert.

`Bee.Id.current/2` (`id.ex:19-32`) is dead code.

### 2.6 There is no supervisor, and the spine does not add one

`mix.exs:14-18` declares `extra_applications: [:logger]` with **no `mod:`**. bee has no application callback and no supervision tree today — consumers start `Bee.Repo` themselves.

The target architecture needs, at minimum: a writer GenServer, a `:fast` NimblePool (up to 8 connections), a `:compute` NimblePool (1–2), the migration runner gating all of it at boot (AD-15: *"run inside the writer at boot, before anything serves"*), and the export debounce timer (AD-17). That is a supervision tree with a mandatory start ordering. **The seed contains no `application.ex` or `supervisor.ex`,** and no invariant governs the boot sequence or what happens when the writer crashes with pooled readers still checked out.

Also: `mix.exs:22` pins `exqlite ~> 0.34`; the spine's Stack table says `~> 0.39`. `nimble_pool` is absent from deps entirely. Both are trivially fixed but neither is called out as a required change.

---

## 3. Existing behaviour that would silently break

Ordered by how quietly it fails.

### 3.1 Cycle detection loses its enforcement mechanism — SEVERITY: CRITICAL

`Bee.Graph.new/0` (`graph.ex:5-7`) creates `:digraph.new([:acyclic, :protected])`. The `:acyclic` flag is the *entire* implementation of DAG cycle prevention: `add_dependency/3` (`graph.ex:32-40`) simply attempts `:digraph.add_edge/3` and maps `{:error, {:bad_edge, _}}` → `{:error, :cycle}`. `Bee.Repo` refuses the DB write when that fires (`repo.ex:126-134`). Tested at `bee_test.exs:134-140`.

**The spine deletes the digraph** (its L2 is SQL traversal) and **never mentions cycle prevention anywhere** — not in AD-13 (which governs `dep_type` and readiness), not in `graph/`, not in `write/`. The only mention in the entire document is as a passing rationale inside AD-2.

An implementer following the spine will move dependency writes into `Bee.Write.Server` writing to `store/deps.ex`, and **`Bee.block/3` will begin accepting cycles**. The failure is silent and permanent: once a cycle is in `dependencies`, `ready` (which only looks at direct in-neighbours) still answers plausibly, but any transitive traversal or the critical-path DP either loops forever or returns nonsense. This is the single most dangerous omission in the document.

**Required:** an invariant stating that acyclicity is enforced at write time via a recursive-CTE reachability check inside the writer's transaction, before the insert commits.

### 3.2 Parent-cycle validation has no home — SEVERITY: HIGH

`validate_parent_update/3` (`repo.ex:296-311`) and `parent_cycle?/3` (`repo.ex:313-327`) walk the parent chain and return `{:error, :self_parent}` / `{:error, :parent_cycle}`. Added deliberately in `f613ee6`; tested at `bee_test.exs:92-98`.

Note the parent tree is a **separate** structure from `dependencies` — it lives in the `issues.parent` column (`store.ex:52`) and is *not* in the `:acyclic` digraph. So parent cycles need their own check regardless of 3.1. The spine's `Bee.Write` has no validation section. Fails identically silently: a reparent creating a loop makes `gather_descendants`' recursive CTE (`store.ex:596-604`) spin forever.

### 3.3 `dep_type` opening the vocabulary silently corrupts `blocked_by` / `blocks` — SEVERITY: HIGH

Today the `dependencies.dep_type` column exists (`store.ex:74`) but is **write-locked to `'blocks'`** — `insert_dependency/3` hardcodes it (`store.ex:435`). Consequently three readers correctly ignore it:

- `get_blocked_by/2` — `store.ex:452-464`, no `dep_type` filter
- `get_blocks/2` — `store.ex:466-478`, no filter
- `Bee.Graph.rebuild/2` — `graph.ex:19`, `SELECT issue_id, depends_on_id FROM dependencies`, no filter

AD-13 opens the vocabulary to seven types including `parent-child`, `related`, `discovered-from`, `replies-to`. **The moment a non-`blocks` row is written, all three readers silently start reporting non-blocking edges as blockers.** `issue.blocked_by` would include `related` and `replies-to` links; `ready` would gate on them.

AD-13 says *"Readiness is computed from edge type, never assumed"* — correct, and it covers `Bee.Graph.Ready`. It does **not** cover the enrichment readers, which are in a different layer. The spine must state that **every** dependency read filters on `dep_type`, and must decide what `issue.blocked_by` means once the vocabulary is open (blocking types only? a map keyed by type? a breaking rename?).

Additional trap: if `parent-child` starts being written into `dependencies` while `issues.parent` also exists, there are two sources of truth for the parent tree. AD-13 does not say which wins.

### 3.4 The `type` → `issue_type` alias — SEVERITY: MEDIUM

`normalize_update_attrs/3` (`repo.ex:277-281`) accepts `:type` on update, maps it to `:issue_type`, and *deletes* `:type` when both are present. Create does the same (`repo.ex:58`: `Keyword.get(opts, :issue_type) || Keyword.get(opts, :type, "task")`). Tested at `bee_test.exs:64-75` including the both-present case.

This is deliberate consumer back-compat and appears nowhere in the spine. Dropping it makes `Bee.update(id, %{type: "bug"})` a silent no-op (unknown key → `maybe_set` skips it → `sets == []` → `:ok` returned, `store.ex:193`). **Returns success, changes nothing.**

### 3.5 Undocumented create options — SEVERITY: MEDIUM

Two opts on `create/3` are implemented, untested, and absent from the spine:

- **`:label`** (singular) — merged into `:labels` via `label_list/1`, `repo.ex:59` + `repo.ex:329-331`. Accepts a string *or* a list.
- **`:actor`** — maps to the `created_by` column, `repo.ex:62`. Not `:created_by`.

Both fail silently if dropped: the value is ignored, create succeeds, the data is gone.

### 3.6 `critical_path` results change, and `bottlenecks` changes with it — SEVERITY: MEDIUM

Current implementation (`graph.ex:87-109`) is a naive recursive longest-path with **no memoization**, run from every source vertex, selecting by `Enum.max_by(&length/1)` — i.e. **most vertices**, ties broken by enumeration order, effort and priority ignored entirely. It is exponential in the worst case and survives production only because the graph is sparse (357 edges / 2,686 issues; paths are 1–2 hops, per the memlog).

The spine's `critical_path.ex` — "topsort + longest-path DP (memoized)" — is the right fix, but AD-12 places critical path under the rollup invariant where "total effort is the base additive primitive". **If the new critical path is weighted by effort rather than hop count, it returns a different path**, and `Bee.bottlenecks/1` (`world.ex:124-142`), which consumes it directly (`world.ex:125`), returns a different answer with no error and no signal. State explicitly whether the metric changes.

### 3.7 The lock write-path's FK side-effect — SEVERITY: MEDIUM

`handle_call({:lock, id, opts}, ...)` (`repo.ex:146-158`) inserts the agent row **before** acquiring:

```elixir
if locked_by = Keyword.get(opts, :locked_by) do
  Bee.Agents.insert_agent(state.conn, locked_by)
  Bee.World.add_agent(state.alloc_graph, locked_by)
end
```

This is required because `locks.locked_by` has `REFERENCES agents(id)` (`store.ex:91`) and `PRAGMA foreign_keys=ON` (`store.ex:10`). `bee_test.exs:142-152` locks with `"agent-1"` and `"agent-2"`, neither ever registered — the test passes **only** because of this auto-insert.

Moving `Bee.Lock` into `store/locks.ex` per the seed, without carrying the agent upsert, turns `Bee.lock/3` with an unregistered agent into an FK constraint failure. And `Bee.Agents` (which does the insert) has no destination (§2.4), making this exactly the kind of dependency that gets dropped in a restructure.

### 3.8 `list_issues_raw`'s empty-check breaks on the AD-11 result shape — SEVERITY: MEDIUM (internal)

`maybe_seed_from_jsonl/3` (`repo.ex:335-344`) decides whether to seed via:

```elixir
with true <- File.exists?(jsonl_path),
     {:ok, []} <- Bee.Store.list_issues_raw(conn) do
```

Under AD-11 ("never a bare list"), `list_issues_raw`'s successor returns a map. `{:ok, []}` stops matching, falls to `else _ -> :ok`, and **seeding silently never runs**. DevMan boots against an empty DB with a populated JSONL beside it and no error.

(Separately: this is a full unfiltered table scan of 2,686 rows to answer "is it empty". Replace with `count` + `limit: 1` while you are in there.)

### 3.9 The `:conn` escape hatch — SEVERITY: HIGH (contract), MEDIUM (mechanical)

`handle_call(:conn, _from, state), do: {:reply, state.conn, state}` — `repo.ex:48`.

This hands the **raw read-write SQLite connection** to any caller. It is a direct violation of AD-2 (*"No module opens its own connection"*) — worse, it lets any process bypass the writer entirely. It is used by the test suite at `bee_test.exs:109` and `bee_test.exs:189`, and — given how much of `Bee.Agents` and `Bee.Store` has no facade entry point (§2.4) — is very likely how gc_daemon reaches functions like `Bee.Agents.list_agents/1` and `Bee.Store.get_comments/2`.

The spine must close it, and closing it is a breaking change for whatever is using it. **Audit gc_daemon and DevMan for `GenServer.call(_, :conn)` before assuming this is test-only.** Every direct `Bee.Store.*`/`Bee.Agents.*` call a consumer makes with a borrowed conn needs a facade equivalent, or it becomes an unmigrated caller pointing at a deleted module.

### 3.10 `updated_at` is not bumped on a labels-only update — SEVERITY: LOW

`do_update_issue/3`, `store.ex:193-208`: when `sets == []` but `:labels` is present, the `UPDATE issues` statement is skipped entirely and only `issue_labels` is rewritten. So changing labels does not touch `updated_at`. Arguably a bug — but export and any `updated_at`-based sync depend on the current behaviour. Decide deliberately; do not "fix" it silently during the move.

### 3.11 `agent_load` is quadratically enriched — SEVERITY: LOW (perf)

`Bee.World.agent_load/3` (`world.ex:85-97`) calls `Bee.Store.get_issue/2` per assigned issue **purely to read `status`** — and `get_issue` enriches (`store.ex:155`), so each costs 5 queries. An agent with 40 issues costs 200 queries to compute a count that is one `SELECT COUNT(*) WHERE assigned_to = ? AND status = 'open'`. Worth noting as an easy win, and as evidence for AD-10.

---

## 4. The test suite

**Shape.** One file, 437 lines, 24 tests. Setup (`bee_test.exs:4-30`) gives each test its own temp SQLite file and a uniquely-named `Bee.Repo` process, with `on_exit` teardown. All tests exercise the **public `Bee.*` facade**, which is the right level and is the main reason a parity strategy is even feasible here.

**Coverage present:**

| Area | Tests | Lines |
| --- | --- | --- |
| create / get / enriched shape | 1 | :32-42 |
| list + ready | 1 | :44-53 |
| update (title, status) | 1 | :55-62 |
| `issue_type` + `type` alias | 1 | :64-75 |
| parent set / clear | 1 | :77-90 |
| parent cycle rejection | 1 | :92-98 |
| not_found | 1 | :100-102 |
| comments | 1 | :104-113 |
| block / unblock / ready interaction | 1 | :115-132 |
| **cycle detection** | 1 | :134-140 |
| locking + already_locked + release | 1 | :142-152 |
| projects/agents/assign/agent_load | 1 | :154-165 |
| who_blocks_whom | 1 | :167-180 |
| JSONL **export** | 1 | :182-197 |
| pagination (GC-2682) | 3 | :201-246 |
| count | 2 | :248-271 |
| order_by (incl. 2 rejection tests) | 5 | :273-316 |
| backward compatibility | 1 | :318-334 |
| tree_page | 7 | :336-436 |

**Coverage absent** — every one of these is behaviour identified above as load-bearing:

- `import_jsonl` round-trip (export is tested, import is not) — and therefore the rescue-based idempotency of §1.6 and the `Bee.Id.set` high-water reset are **completely untested**
- **label filtering** — `build_where`'s AND-across-a-list semantics (`store.ex:791-798`) has zero tests. A rewrite to `label IN (...)` gives OR. Silent semantic inversion, no test catches it.
- `bottlenecks/1` — public API, zero tests
- `Bee.Id` — zero tests
- lock TTL expiry / `sweep_expired`
- the `:label` singular and `:actor` opts (§3.5)
- `assigned_to` scope filter (`store.ex:771`)
- `close_reason` / `closed_at`
- concurrency of any kind — no test would notice a lost writer serialisation

**Would it survive the restructure? No — and the breakage is mostly mechanical, which is the good case.** Enumerated by invariant:

| Invariant | Assertions broken | Lines |
| --- | --- | --- |
| AD-11 (results are maps, never bare lists) | ~15 | :48-49, :51-52, :205-207, :235, :243, :254-259, :279-282, :289, :310-311, :322-325 |
| AD-10 (enrichment opt-in) | 5 | :35, :122, :328-332 |
| "never bare `:ok`" for mutations | ~12 | :57, :68, :72, :83, :87, :106-107, :119, :129, :150, :158, :161, :174-176 |
| `:conn` hatch removed (§3.9) | 2 | :109, :189 |
| bare-value returns wrapped (§1.3) | 2 | :163-164, :178-179 |
| `Bee.Repo` renamed / supervisor added (§2.1, §2.6) | **all 24** | :9-15 |

The last row is the important one: **a `Bee.Repo` rename or a supervision-tree change breaks the setup block and takes the entire suite with it in one move.**

**Is a parity strategy implied anywhere? No.**

- The spine has **no test section at all**. `test/` does not appear in the structural seed. No invariant governs migration verification.
- The memlog records the necessary constraint and it **did not make it into the spine**: *"Test fixture: a dev/mix-based daemon runs off a 2-3 day old snapshot of the real SQLite DBs. Use for realistic perf benchmarking AND migration testing against real messy state incl. injected FTS objects. **Prove improvements, don't claim them.**"*
- The design brief mentions "parity-test harness" exactly once (`docs/plans/2026-07-20-bee-supercharger-design-brief.md:239`) and only for a hypothetical storage swap.

**Recommendation — add AD-18 (Parity):**

1. The 24 existing tests are **frozen** and renamed `test/legacy_api_test.exs`, running against a thin compatibility shim that preserves today's return shapes. They stay green through the entire restructure and are deleted only when GC-2694 lands consumer migration. This converts ~35 silent breakages into a single explicit, reviewable shim.
2. A **migration test** against a copy of the production snapshot (`~/.local/share/gc/bee.db`, 16MB, 2,686 issues, with gc_daemon's injected `issues_fts` + 5 shadow tables + 3 triggers + `issue_project_backfill_log` present) asserting AD-15's boot-refuses-on-unexpected-schema and migration 001's FTS drop-and-rebuild.
3. **Characterisation tests written before the restructure** for the untested load-bearing behaviours above: label AND-filtering, import idempotency, `Bee.Id.set` high-water, priority NULLs-last, the `:label`/`:actor` opts, cycle detection under the new SQL implementation.

---

## 5. Correct and load-bearing — do not let a naive implementer destroy these

A checklist for whoever executes the restructure. Every item is currently correct; every item is invisible in the spine.

| # | Behaviour | Location | Destroyed by |
| --- | --- | --- | --- |
| 1 | `:acyclic` digraph = the only cycle prevention | `graph.ex:6`, `:36-38` | deleting the digraph without a SQL replacement |
| 2 | Parent-chain cycle walk, `:self_parent` / `:parent_cycle` | `repo.ex:296-327` | no home in the seed |
| 3 | `validate_opts!` raising in the **caller's** process | `store.ex:236-242`, `bee.ex:11,16,21` | validating inside the pool process |
| 4 | Double validation in `build_order` for direct-conn callers | `store.ex:493-508` | "deduplicating" it away |
| 5 | `priority IS NULL` prefix — NULLs last in both directions | `store.ex:519-522` | plain `ORDER BY priority DESC` |
| 6 | Closed `@order_columns` whitelist (injection barrier) | `store.ex:4` | a permissive `Spec` |
| 7 | `parse_numeric_id` returns the string on parse failure | `store.ex:726,732` | typing the return as `integer()` |
| 8 | Id integerisation happens for *all* reads, not just enriched ones | `store.ex:699-703` | tying it to `detail:` levels |
| 9 | `blocked_by`/`blocks` currently correct **only because** all rows are `'blocks'` | `store.ex:435` vs `:452,:466` | opening `dep_type` without adding filters |
| 10 | `type` → `issue_type` alias on create and update | `repo.ex:58`, `:277-281` | dropping it (silent no-op update) |
| 11 | `:label` singular and `:actor` opts | `repo.ex:59,62`, `:329-331` | dropping them (silent data loss) |
| 12 | Lock path upserts the agent for FK integrity | `repo.ex:150-153` + `store.ex:91` + `:10` | moving `Lock` without `Agents` |
| 13 | `import_jsonl` rescue = the only idempotency mechanism | `export.ex:106-110` | removing it per "no silent failure" without an upsert |
| 14 | `Bee.Id.set` high-water reset after import | `export.ex:122`, `id.ex:35-46` | `Bee.Id` having no destination |
| 15 | Atomic id allocation (`ON CONFLICT DO UPDATE ... RETURNING`) | `id.ex:5-17` | reimplementing as SELECT-then-UPDATE |
| 16 | `tree_page`: out-of-scope parent ⇒ node is a root | `store.ex:317-318`, `:574-575` | re-deriving tree paging from AD-12 |
| 17 | `tree_page`: subtree completeness overrides scope filter | `store.ex:340-342`, `:596-604` | applying the scope filter to descendants |
| 18 | `sort_by_root_order` — roots first, then descendants in CTE order | `store.ex:633-643` | returning rows in `IN (...)` order |
| 19 | `LIMIT -1 OFFSET ?` for offset-without-limit | `store.ex:540` | omitting the SQLite-specific `-1` |
| 20 | Pragma order: WAL → foreign_keys → synchronous, before any DDL | `store.ex:9-11` | reordering; FK enforcement is per-connection and must be set on **every pooled reader too** |
| 21 | `update` returns `:ok` (not an error) when nothing changed | `store.ex:193-194` | treating no-op as a rejection under "report applied vs rejected" |
| 22 | `insert_issue` returns the fully-enriched issue via `get_issue` | `store.ex:142` | AD-16 changing create's return to candidates without preserving the issue |

**Item 20 deserves emphasis:** `PRAGMA foreign_keys` is **per-connection** in SQLite, defaulting to OFF. Today there is exactly one connection and it is set at `store.ex:10`. Under AD-2/AD-3 there will be up to eleven. Every pooled reader **and** the writer must set it in its own open path, or referential integrity silently varies by which connection served the query. The spine's `Bee.Read.Pool` description says nothing about per-connection pragmas.

---

## Recommended additions to the spine

1. **AD-18 — Acyclicity is enforced at write time.** Recursive-CTE reachability check inside the writer's transaction, for both `dependencies` edges and `issues.parent`. Replaces `:digraph`'s `:acyclic` guarantee explicitly.
2. **AD-19 — Parity.** Freeze the existing 24 tests behind a compat shim; migration-test against the production snapshot; characterise the untested load-bearing behaviours *before* restructuring.
3. **A "Ratified Conventions" section** listing what the current code does correctly and must be preserved — items 1–22 above. Without this the spine reads as a licence to rewrite everything.
4. **A "Module Disposition" table** covering all nine existing modules, including explicit dispositions for `Bee.World`, `Bee.Agents`, `Bee.Id`, `Bee.Repo`-as-a-name, `tree_page`, `import_jsonl`, the lock sweep timer, and the `:conn` escape hatch.
5. **A slot for `bee/store/agents.ex` + `projects.ex`,** and Core intents `:who_blocks_whom` / `:bottlenecks` / `:agent_load` replacing the alloc-graph.
6. **`bee/application.ex` in the seed**, plus a boot-ordering invariant (migrate → open writer → open pools → serve) and a crash-semantics note.
7. **Amend AD-10** with the not-loaded representation rule (never an empty collection).
8. **Amend AD-13** to state that every dependency read filters `dep_type`, and to resolve `parent-child`-in-`dependencies` versus `issues.parent`.
9. **Reword AD-14** to future tense — `metadata` does not exist yet.
10. **Note the `exqlite` bump and the `nimble_pool` addition** as required `mix.exs` changes.
