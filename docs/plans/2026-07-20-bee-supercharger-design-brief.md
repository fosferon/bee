# Bee Supercharger — Design Brief

**Date:** 2026-07-20
**Epic:** GC-2691
**Status:** Design decisions settled in session; input to `bmad-architecture`.

This brief is the INPUT to architecture, not the architecture itself. It records the
diagnosis, the decisions already taken (with reasoning), and the open items. Do not
re-run discovery — it is captured here.

---

## 1. Mission

Bee is a work-coordination library with a dependency DAG over SQLite. Today it is a thin
CRUD store; consumers compensate for it. Make it a self-contained intelligent work engine:
consumers describe intent, bee decides how to answer.

Operator's framing (verbatim intent): *"Bee is a super-intelligent, self-contained powerhouse
of an engine. If a consumer wants something, they simply ask for it."* Envisioned scope
includes critical paths, duration/effort statistics, full editing, multiple levels of detail,
and eventually linear-programming optimisation for best-sequence path to a goal.

---

## 2. Diagnosis (measured, not asserted)

Bee is 1,971 LOC. `gc_daemon/lib/gc_daemon/api/work_handler.ex` is 1,473 LOC of compensation,
plus a separate `SearchIndex` module and a 463-LOC scheduler.

| # | Defect | Evidence |
|---|---|---|
| 1 | Consumer injected FTS5 table + 3 triggers INTO bee.db; ALTERed `projects` with 19 columns | `gc_daemon/lib/gc_daemon/bee/search_index.ex:43-71`; `project_registry.ex:614-655` |
| 2 | Comments are write-only — `Store.get_comments/2` never wired into `Bee.Repo` | `lib/bee/store.ex:404`; no `handle_call` in `repo.ex` |
| 3 | `ready/1` discards opts; consumers filter the whole open set in Elixir | `lib/bee/repo.ex:96` |
| 4 | `tree` ≈ 105 SQLite round-trips for a 20-neighbour node (N+1 over `enrich_issue`) | `work_handler.ex:393-440` + `store.ex:694` |
| 5 | No projection/detail levels; consumer invented 3 ad-hoc output shapes | `work_handler.ex:1123`, `:882` |
| 6 | `critical_path/1` is naive exponential recursion, no memoization | `lib/bee/graph.ex:96-118` |
| 7 | Scheduler FAKES DAG depth: `dag_bonus = min(base * 0.1, 5.0)` | `gc_daemon/lib/gc_daemon/scheduler.ex:311` |
| 8 | `dep_type` column exists, hardcoded to `'blocks'` everywhere | `store.ex:435` |
| 9 | `maybe_export/1` dumps whole table + per-issue comments on EVERY write | `repo.ex` + `export.ex:11` |
| 10 | Single GenServer + single connection: all reads serialize behind all writes | `repo.ex` |
| 11 | No migrations — `CREATE TABLE IF NOT EXISTS` only, no versioning | `store.ex:8-109` |
| 12 | **BUG:** consumer joins table `labels`; bee's table is `issue_labels`. Queries error into a silent fallback — bee engagement signal is DEAD | `gc_daemon/lib/gc_daemon/engagement.ex:1296,1336` vs `store.ex:64` |

---

## 3. Decisions taken (with reasoning)

### D1 — Concurrency: reader pool + single writer
Writes stay serialized through the GenServer (preserves DAG cycle checks and id allocation).
Reads get a pool of read-only connections. WAL is already enabled (`store.ex:9`), so readers
get MVCC snapshots free. Heavy compute (critical path, rollups, LP) must never block `list`.
Also retires the stop-repo-to-snapshot hack in `gc_daemon/workflow/snapshot.ex:61-81`.

### D2 — API shape: composable core + intent shortcuts
One execution path, two altitudes:
```elixir
Bee.ask(:what_next, agent: "claude", project: "bee", detail: :compact)
Bee.ask(:why_blocked, 2691)
Bee.ask(:rollup, 2691)

Bee.query(select: :issues, where: [...], via: [...], rank: ..., detail: ..., limit: ...)
```
`ask` intents are pre-composed `query` specs. No drift, because there is one engine.

### D3 — Domain boundary (operator-defined, important)
Bee does **not** model work execution. Timers, resource capacity, hourly rates, what "work"
means — all gc_time's domain, and bee must never learn those words.

Bee DOES:
- capture its **own** events unconditionally (self-observation, in-domain)
- accept **opaque outside signal** to calibrate its own outputs

Operator's test: *"that's outside its domain, is it not? What is arguably in its domain though
is to have the ability to collect such intelligence so that it can do its own job better."*

### D4 — Measurements: measures × dimensions
- **Measures** — numeric, arithmetic-calibratable (cost, tokens, duration).
- **Dimensions** — categorical, group-by-able (model, methodology, agent, branch).

Bee never interprets dimension VALUES; it partitions on them. This is what makes it
simultaneously agnostic and useful. Precedent: DevMan's Performance ETS already tracks
`success rate per primitive × agent` — measure × 2 dimensions.

Intake piggybacks on the `update`/`close` that already happens; standalone `measure/2`
exists for retroactive/out-of-band correction. Capture must be the default path, not a
second call someone forgets.

**Naming:** use `measurement` for raw intake. "Observation" is TAKEN in this ecosystem —
VaultWise uses it for *a generalised rule derived from many experiences*
(`~/Sites/DevMan/plans/integration_forecast.md`). Collision would be real.

### D5 — Event log covers ALL mutations, not just status
Comment cadence, edit velocity, churn, status flapping, reopen count, time-to-first-touch,
blocked duration are all signal. Rework is typically the best cost predictor and is
currently invisible. Events are bee's autobiography — captured with nobody opting in.

**Time-gated:** every day without the event log is lost training data for L3. From the
existing production DB only `closed_at - created_at` is recoverable; time-in-status,
rework, and blocked duration are gone forever.

### D6 — Rollups: "total effort" is the base primitive
Effort is additive over any node set, so one aggregator + pluggable scope selectors beats
three separate features. Scope selectors: `tree`, `closure`, `critical_path`.

**Boundary resolved by the Go ancestor:** "Molecules are just epics." The rollup unit IS the
parent tree; cross-epic dependencies are explicit **bonds**, reported separately as external
gates. (`~/Sites/DevMan/devman_beads/docs/MOLECULES.md`)

### D7 — Migrations required before L0
`PRAGMA user_version`, ordered idempotent steps, run inside the writer at boot.
**Migration 001 must ADOPT gc_daemon's injected objects, not collide with them:**
`issues_fts` + 3 triggers, 19 ALTERed `projects` columns, `issue_project_backfill_log`.

### D8 — Retrieval reports what it withheld
Stolen from CommBus, which emits `[:comm_bus, :context, :plan]` telemetry with inclusion/
exclusion counts AND exclusion reasons. Applied to bee, this is the actual cure for agents
choking on output — a query doesn't just return less, it says what it held back and how to
ask for it:
```elixir
%{issues: [...],
  withheld: %{truncated_descriptions: 14, below_rank_cutoff: 340,
              outside_scope: %{project: 12}},
  refine: [limit: 50, detail: :full]}
```

### D9 — Detail levels are a first-class query parameter
`:minimal | :compact | :standard | :full`. Consistent with DevMan's existing CLI density
modes. Never enrich by default — enrichment is opt-in per query.

---

## 4. L0 substrate schema (settled)

```sql
CREATE TABLE events (                    -- bee's autobiography, append-only
  id         INTEGER PRIMARY KEY AUTOINCREMENT,   -- global cursor for tailing
  issue_id   TEXT NOT NULL REFERENCES issues(id) ON DELETE RESTRICT,
  seq        INTEGER NOT NULL,           -- per-issue monotonic (safe: single writer)
  kind       TEXT NOT NULL,              -- created|status_changed|assigned|commented|
                                         -- blocked|unblocked|reparented|…
  actor      TEXT,
  payload    TEXT NOT NULL,              -- JSON, NOT term_to_binary
  created_at TEXT NOT NULL,
  UNIQUE(issue_id, seq)
);

CREATE TABLE measurements (              -- opaque outside signal
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  issue_id    TEXT NOT NULL REFERENCES issues(id) ON DELETE RESTRICT,
  measure     TEXT NOT NULL,             -- caller-defined: cost|tokens|duration_ms
  value       REAL NOT NULL,
  unit        TEXT,
  dims        TEXT NOT NULL DEFAULT '{}',-- JSON: {model:…, methodology:…, agent:…}
  source      TEXT,
  recorded_at TEXT NOT NULL
);
```

**JSON payloads, not `:erlang.term_to_binary`.** DevMan's `execution_events` base64-encodes
Erlang terms, making the blob opaque to SQL — no filtering or aggregation over payloads.
JSON keeps `json_extract` available. (`dev_man/lib/dev_man/executor/stepwise/persistence.ex:455`)

**Dimensions stay schemaless but become indexable on demand** — the key trick that resolves
agnostic-vs-fast:
```sql
CREATE INDEX idx_m_model ON measurements(json_extract(dims, '$.model'));
```
Arbitrary dimensions, no vocabulary, no migrations — yet indexed `GROUP BY model` at speed.

**Column additions:**
- `issues.metadata` — arbitrary JSON, reserved prefixes `bee:` and `_` (Beads convention).
  Its ABSENCE is the direct cause of the `ALTER TABLE projects` incident. Sanctioned
  extension point.
- `issues.estimate` — so declared can later be measured against earned.

**`dependencies.dep_type` gets its real vocabulary** (from Beads upstream) plus an index on
`(depends_on_id, dep_type)` which the current schema entirely lacks despite every reverse-edge
lookup needing it:

| Blocking | Non-blocking |
|---|---|
| `blocks` — B can't start until A closes | `related` — loose "see also" |
| `parent-child` — parent blocked ⇒ children blocked | `discovered-from` — provenance |
| `conditional-blocks` — B runs only if A **fails** | `replies-to` — threading |
| `waits-for` — B waits for ALL of A's children | |

`waits-for` and `conditional-blocks` CHANGE WHAT `ready` MEANS. Current `ready_issues/2`
checks direct in-neighbours only and cannot express a fanout gate or an error path.

---

## 5. Layering

- **L0 Substrate** — migrations, event log, measurements, metadata, dep_type vocabulary,
  native FTS5 (adopting existing objects), reader pool.
- **L1 Query** — composable filters, projections/detail levels, batch fetch, aggregates,
  time windows, comment reads, withheld-reporting.
- **L2 Graph** — real traversal, neighbourhood, transitive reach, memoized critical path
  (topsort + longest-path DP, replacing exponential recursion), rollups with scope selectors.
- **L3 Intelligence** — cycle-time statistics, estimate calibration ("earned vs declared"),
  forecasting, sequence optimisation.

**L3 requires accumulated history.** Build L0 early so data accrues; land L3 incrementally
once there is something real to learn from. Do NOT scope L3 as one push.

---

## 6. Consumers and constraints

**Two live consumers, not one.**

1. **gc_daemon** (`~/Sites/ex_libs/gc_daemon`) — primary. `work_handler.ex` should collapse
   to a thin transport adapter as capability moves down into bee.
2. **DevMan** (`~/Sites/DevMan/dev_man`) — `{:bee, git: ...}`, `prefix: "dev_man"`,
   `.bee/bee.db` **plus a load-bearing JSONL mirror**. Tracked as GC-2694 (gate issue:
   must be done before dev_man development resumes; operator has authorised breaking it).

**Testing fixture:** a dev/mix-based daemon runs off a 2–3 day old snapshot of the real
SQLite DBs. Use it for realistic performance benchmarking AND for migration testing against
the real messy state (including the injected FTS objects). Prove improvements, don't claim them.

**Deployment path (operator-specified):** everything on hold elsewhere → do the job properly
→ slide new bee into the mix-based dev daemon → test properly → stop live daemon and redeploy.

---

## 7. Inherited wisdom worth honouring

From `~/Sites/DevMan` (mined 2026-07-20):

- **"Earned vs declared"** — DevMan's `ENHANCEMENT_ROADMAP.md` §5. Performance data is
  collected but the loop is COLD: *"Agents are routed by declared capability, not earned
  performance… the feedback loop closure is the moat."* Bee is the right place to close it —
  it is the only component owning both structure and history.
- **Steal directly:** monotonic-seq event log with cursor reads; ETS hot buffer → SQLite
  two-speed writes; progressive compaction as an LOD ladder (`0 full → 1 → 2 → delete`);
  size-tiered content storage; parity-test harness for de-risking a storage swap.
- **Improve on:** FTS5 (DevMan's is manually synced, silently rescued, no `bm25()` ranking);
  where-clause builder (closed-set, O(n²) via `++`); pagination (LIMIT only).
- **Do not repeat:** hand-rolled Jaro-Winkler when `String.jaro_distance/2` exists;
  open-per-query with full `init_db` each time; blanket `rescue _ -> {:ok, []}`.

**Terminology cautions:** "observation", "benchmark", and "snapshot" are all taken with
specific ecosystem meanings. "Promotion" is the universal verb for "this earned its trust" —
use it for calibrated estimates.

---

## 8. Open items for architecture

1. Exact `Bee.ask/2` intent catalogue (which shortcuts ship in v1).
2. Reader-pool sizing and checkout strategy.
3. Whether rollups are computed on demand or materialised + invalidated on write.
4. Event-log retention/compaction policy (LOD ladder vs. keep-forever).
5. Export/JSONL semantics — current per-write full dump must go; replacement must not
   silently break DevMan (GC-2694).
6. FTS ownership handover sequencing with a LIVE gc_daemon (adopt-in-place vs. rebuild).
