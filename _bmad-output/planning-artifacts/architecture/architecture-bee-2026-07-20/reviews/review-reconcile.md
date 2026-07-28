# RECONCILE-INPUTS Review — bee ARCHITECTURE-SPINE.md

**Date:** 2026-07-20
**Reviewer lens:** input→spine traceability. What did the distillation drop, weaken, or invent?
**Inputs checked:**
1. `docs/plans/2026-07-20-bee-supercharger-design-brief.md`
2. `_bmad-output/planning-artifacts/architecture/architecture-bee-2026-07-20/.memlog.md` (58 lines, 51 substantive entries)

**Against:** `ARCHITECTURE-SPINE.md` (26 ADs, v2)

---

## Verdict

The spine is a **high-fidelity distillation of the structural decisions** and a **lossy distillation of the behavioural and rationale layers**. Every one of the twelve defects is traceable to something; the three operator decisions of 2026-07-20 all landed correctly; the corrected `labels` understanding is reflected, not the wrong one.

What was lost is a specific class: **decisions that describe how a thing is *fed* or *why a cost was accepted*, as opposed to how a thing is *shaped*.** Measurement intake, event retention, the two-lane accepted cost, post-hoc candidate detection, and the L0-first sequencing rationale all fell into that gap. Three of these are load-bearing enough that a builder following the spine literally would produce a system the operator did not ask for.

**Counts:** 87 traced items — **58 LANDED · 20 PARTIAL · 9 DROPPED**.
**Untraceable spine content:** 6 items (1 material, 1 internal contradiction, 4 benign).

---

## Part 1 — Design Brief

### 1.1 Mission (§1)

| # | Requirement | Status | Where |
|---|---|---|---|
| M1 | Bee becomes a self-contained intelligent work engine, not a CRUD store consumers compensate for | **LANDED** | Paradigm + layer table + Capability→Architecture Map (capability moves down into bee) |
| M2 | Operator framing: *"if a consumer wants something, they simply ask for it"* | **PARTIAL** | AD-4 + AD-5 serve it mechanically (`ask/2`, registry, one engine). But **the spine never states the mission**. There is no sentence anywhere telling a builder that the design goal is consumer-asks-bee-answers. A builder optimising AD-by-AD has no north star to resolve ambiguity against. See §4.1. |
| M3 | Envisioned scope: critical paths | **LANDED** | Structural seed `graph/critical_path.ex`, Capability map |
| M4 | Envisioned scope: duration/effort statistics | **PARTIAL** | AD-12 (effort rollups) landed; statistics deferred to L3 with justification. Acceptable deferral. |
| M5 | Envisioned scope: **full editing** | **PARTIAL** | Only trace is the Consistency Conventions row "Commands return `{:ok, report}` where the report names applied and rejected fields". No AD governs the editable surface. AD-8's `rejected: [...]` envelope implies fields *can* be rejected but nothing says which, or that the goal is full field coverage. |
| M6 | Envisioned scope: multiple levels of detail | **LANDED** | AD-10 + Detail levels vocabulary |
| M7 | Envisioned scope: eventual LP optimisation for best-sequence-to-goal | **LANDED** | Deferred table, with the ~13% density measurement as the stated revisit trigger |

### 1.2 Defect table (§2) — all twelve

| # | Defect | Status | AD / location |
|---|---|---|---|
| 1 | Consumer injected FTS5 + 3 triggers into bee.db; ALTERed `projects` with 19 columns | **LANDED** | AD-14 (no consumer DDL, `metadata` as sanctioned extension point), AD-15 (only `Bee.Store.Migrate` does DDL), migrations 001 + 002, Hard ordering constraint |
| 2 | Comments write-only — `Store.get_comments/2` never wired into `Bee.Repo` | **PARTIAL** | No AD names comment reads. Reachable only by inference: AD-10's `include:`-able relations + `store/comments.ex` in the seed. The brief listed "comment reads" as an explicit L1 deliverable; the spine's L1 row says "query spec, interpretation, projection, withheld accounting". A builder can satisfy every AD and still not wire `get_comments`. |
| 3 | `ready/1` discards opts; consumers filter the whole open set in Elixir | **PARTIAL** | AD-4 ("every read resolves to a `Bee.Query.Spec`") makes it structurally impossible to keep an opts-discarding `ready`, and AD-26 puts `ready` in the parity corpus. But the defect is never named, and no AD states that `ready` must accept filter/projection options. Fixed by side-effect, not by rule. |
| 4 | `tree` ≈ 105 round-trips (N+1 over `enrich_issue`) | **LANDED** | AD-10, with the measurement restated (2,687 × 4 = 10,748) and "a per-row query inside a result loop is a defect" as a hard rule |
| 5 | No projection/detail levels; consumer invented 3 ad-hoc output shapes | **LANDED** | AD-10 + Detail levels closed vocabulary |
| 6 | `critical_path/1` naive exponential recursion, no memoization | **LANDED (weakly)** | Structural seed: `critical_path.ex # topsort + longest-path DP`; Capability map row. **No AD binds it** — it is a filename comment. Everything else of this weight got an AD. |
| 7 | Scheduler FAKES DAG depth: `dag_bonus = min(base * 0.1, 5.0)` | **DROPPED** | Nothing in the spine provides real DAG depth or names this. Consumer-side, yes — but the *bee-side capability the consumer needs* (depth/reach as a queryable, or a `:what_next` core intent that ranks on real graph position) is not stated anywhere. `Bee.Graph.Traverse` lists "neighbourhood, ancestors, descendants, reach" — depth is not among them and nothing connects it to scheduling. See §4.2. |
| 8 | `dep_type` exists, hardcoded to `'blocks'` | **LANDED** | AD-13 (full truth table), AD-18 (`parent-child` projected/unwritable), migration 004 |
| 9 | `maybe_export/1` dumps whole table + per-issue comments on every write | **LANDED** | AD-17 |
| 10 | Single GenServer + single connection; reads serialize behind writes | **LANDED** | AD-2, AD-2b, AD-3, AD-23 |
| 11 | No migrations — `CREATE TABLE IF NOT EXISTS` only | **LANDED** | AD-15, including the explicit `IF NOT EXISTS is forbidden` clause |
| 12 | **(WRONG AS WRITTEN)** consumer joins `labels`; queries error into a silent fallback | **LANDED — corrected version, with one gap** | Memlog 47 + 57 corrected it: `labels` **exists** (219 rows, 69 issues, all 219 absent from `issue_labels`, 67/69 issues have no `issue_labels` rows). Queries do **not** error — they silently read an orphaned table. **Spine reflects the CORRECTED understanding**: AD-15 lists `a labels table` among tolerated additional objects; migration 001 merges the rows via `INSERT OR IGNORE` then drops. ✅ No trace of the wrong version survives. **Gap:** see §4.3 — the consumer-side consequence of the drop is not in the Hard ordering constraint. |

### 1.3 Decisions D1–D9 (§3)

| # | Decision | Status | AD |
|---|---|---|---|
| D1 | Reader pool + single writer; WAL; heavy compute never blocks `list` | **LANDED** | AD-2, AD-3, AD-23 |
| D1a | *"Also retires the stop-repo-to-snapshot hack in `gc_daemon/workflow/snapshot.ex:61-81`"* | **DROPPED** | Not mentioned anywhere in the spine. A stated deliverable of D1, with a file:line citation. Consumer-side, but so is the Hard ordering constraint, which *is* in the spine. |
| D2 | Composable core + intent shortcuts, one execution path | **LANDED** | AD-4, AD-5 |
| D3 | Domain boundary — bee never models work execution | **LANDED** | AD-6, verbatim in spirit |
| D4 | Measures × dimensions; bee partitions on dimension values, never interprets them | **LANDED** | AD-9 |
| D4a | *"Intake piggybacks on the `update`/`close` that already happens; standalone `measure/2` exists for retroactive/out-of-band. **Capture must be the default path, not a second call someone forgets.**"* | **DROPPED** | **Nothing in the spine describes measurement intake as riding on the existing write.** AD-9 governs validation; the Capability map says "Measurement intake → `Bee.Store.Measurements`". A builder reading the spine implements exactly the forgettable second call the brief forbade. See §4.4 — this is the most consequential drop. |
| D4b | Naming: `measurement` for raw intake; `observation` is taken | **LANDED** | Consistency Conventions, with the `promotion` verb too |
| D4c | "Benchmark" and "snapshot" are also overloaded (memlog 22) | **DROPPED** | Only `observation` is reserved in the spine. Minor. |
| D5 | Event log covers ALL mutations, not just status | **LANDED** | AD-7 |
| D5a | **Time-gated:** every day without the event log is lost training data; only `closed_at − created_at` is recoverable | **PARTIAL** | The *fact* survives in the Deferred table's L3 row ("training on data that does not exist"). The *urgency* — that L0 must ship early because history accrual is irreversible — does not. See §4.5. |
| D6 | Total effort is the base additive primitive; tree/closure/critical_path are scope selectors over ONE aggregator; rollup unit is the parent tree, cross-epic deps are external gates | **LANDED** | AD-12, both halves, plus the Go-ancestor "molecules are just epics" boundary |
| D7 | Migrations before L0: `user_version`, ordered idempotent steps, run inside the writer at boot | **LANDED** | AD-15, AD-22 |
| D7a | *"Migration 001 must ADOPT gc_daemon's injected objects, not collide with them"* | **DELIBERATELY REVERSED — correctly** | Memlog 42 reversed it (rebuild, not adopt, because a stop window exists). The spine's migration table **states the reversal and its reasoning explicitly**. Model traceability; no action. |
| D8 | Retrieval reports what it withheld + refine hint | **LANDED** | AD-11, closed reason vocabulary |
| D9 | Detail levels first-class; never enrich by default | **LANDED** | AD-10 |

### 1.4 L0 substrate schema (§4)

| # | Item | Status | Notes |
|---|---|---|---|
| S1 | `events` table exists | **LANDED** | Migration 003 |
| S2 | `events.id INTEGER PRIMARY KEY AUTOINCREMENT` — **"global cursor for tailing"** | **DROPPED** | The spine never mentions a cursor, tailing, or cursor reads. Brief §7 lists "monotonic-seq event log with **cursor reads**" as a steal-directly item. A consumer that wants to tail bee's autobiography has no stated mechanism. See §4.6. |
| S3 | `events.seq` per-issue monotonic + `UNIQUE(issue_id, seq)` | **DROPPED** | Not in any AD, not in migration 003 ("`events`, `measurements`, `intent_usage` tables"). AD-7 gives semantics (append-only, one event per command, single emitter) but not the ordering column. |
| S4 | `events.issue_id NOT NULL` | **LANDED** | AD-7, explicitly |
| S5 | Payload is JSON, never `term_to_binary` | **LANDED** | AD-8, with the DevMan anti-precedent |
| S6 | `measurements` table with `measure`/`value`/`unit`/`dims`/`source`/`recorded_at` | **PARTIAL** | AD-9 governs `measure`, `unit`, `dims`. **`source` and `recorded_at` appear nowhere.** `recorded_at` matters: AD-12 says "latest value per issue", which requires an ordering column the spine never names. |
| S7 | `measure TEXT NOT NULL -- caller-defined` | **CHANGED WITHOUT A LOGGED DECISION** | The spine makes measures a **closed compile-time registry** of four members with fixed units. Traceable in *kind* to memlog 45 ("closed sets for … registered measures+units") but the narrowing from *caller-defined* to *four members, adding one is a spine amendment* is a real reduction of D4's agnostic promise and is not recorded as a decision. See §4.7. |
| S8 | Dimensions schemaless but indexable on demand via `json_extract` expression index | **LANDED** | AD-9, tightened by memlog 51 (exact textual match, `->>` forbidden) |
| S9 | `issues.metadata` — arbitrary JSON, reserved prefixes `bee:` and `_` | **LANDED** | AD-14, migration 002 |
| S10 | `issues.estimate` — "so declared can later be measured against earned" | **PARTIAL / INTERNALLY TENSE** | Column is in migration 002. **No AD governs it**, and AD-12 says "**Effort is a registered measurement … `metadata` is never a source of numbers bee computes on**". Whether `estimate` is a number bee computes on — and how it relates to `measure: "effort"` — is undefined. See §4.8. |
| S11 | `dependencies.dep_type` real vocabulary (7 types, blocking/non-blocking split) | **LANDED** | AD-13 truth table |
| S12 | Index on `(depends_on_id, dep_type)` | **LANDED** | Migration 004 |
| S13 | `waits-for` and `conditional-blocks` **change what `ready` means** | **LANDED** | AD-13 gate table, incl. the zero-child `waits-for` edge case and the cancelled-blocker-satisfies rule |

### 1.5 Layering (§5)

| # | Layer / contents | Status |
|---|---|---|
| L0 | migrations, event log, measurements, metadata, dep_type vocab, native FTS5, reader pool | **LANDED** — layer table + ADs 14/15/7/9/13/2/3 |
| L1 | composable filters, projections/detail levels, batch fetch, aggregates, **time windows**, **comment reads**, withheld-reporting | **PARTIAL** — filters/projections/detail/batch/withheld ✅. **Time windows: DROPPED** (no AD, no spec field, no mention; brief listed it explicitly). Comment reads: see defect #2. Aggregates: partially via `stats:`/`rollup:` spec fields named in AD-3. |
| L2 | traversal, neighbourhood, transitive reach, memoized critical path, rollups with scope selectors | **LANDED** — layer table, seed, AD-12, AD-13 |
| L3 | cycle-time stats, estimate calibration ("earned vs declared"), forecasting, sequence optimisation | **LANDED as deferred** — Deferred table names all four with justification |
| L3a | *"Build L0 early so data accrues; land L3 incrementally. Do NOT scope L3 as one push."* | **PARTIAL** — "deferred" is not the same instruction as "incremental, never one push". The anti-big-bang guidance is gone. |

### 1.6 Consumers and constraints (§6)

| # | Item | Status | Notes |
|---|---|---|---|
| C1 | Two live consumers, not one | **LANDED** | Scope line, `binds: [GC-2691, GC-2693, GC-2694]` |
| C2 | gc_daemon primary; `work_handler.ex` collapses to a thin transport adapter | **PARTIAL** | Deferred table: "Consumer adaptation — GC-2694. The spine governs bee; consumer collapse follows API stabilisation." The *target* (thin transport adapter) is not restated, so there is no stated end-state to check the collapse against. |
| C3 | DevMan: `prefix: "dev_man"`, `.bee/bee.db`, **load-bearing JSONL mirror**, GC-2694 gate, operator authorised breaking it | **LANDED** | AD-17 ("The JSONL format is a consumer contract (DevMan, GC-2694)"), AD-24 (export uses prefixed strings), Deferred |
| C4 | **Test fixture: dev/mix-based daemon on a 2–3 day old snapshot of the real SQLite DBs; use for perf benchmarking AND migration testing against real messy state. "Prove improvements, don't claim them."** | **PARTIAL — became binding, but mutated** | It **did** become a binding rule, twice: AD-26 ("parity harness runs old and new against **a copy of the production database**… improvements are proven, not claimed") and AD-15 ("Migration 001 must be run and verified against **a copy of the live production database** before it is permitted to run against it"). ✅ The *rule* landed. **But the fixture itself did not**: "a copy of the production database" ≠ "the dev/mix daemon running off a 2–3 day snapshot". The operator specified an existing running rig; the spine specifies an ad-hoc file copy. The rehearsal-in-a-live-daemon property — that the new bee is exercised *through a real daemon*, not just through a test harness — is gone. See §4.9. |
| C5 | **Deployment path: all other work on hold → do the job properly → slide new bee into the mix-based dev daemon → test properly → stop live daemon and redeploy** | **PARTIAL** | Fragments survive: Deferred ("Deployment has a stop-the-world window"), AD-15 (boot-time, fail loud), migration table restore procedure ("stop the daemon, `mv` the backup, delete `-wal`/`-shm`, restart"), memlog 41's stop-the-world policy is reflected in AD-15. **Missing:** the ordered path as a stated invariant, and specifically the **dev-daemon rehearsal step between "done" and "redeploy"**. Also missing: memlog 21's operator quote *"don't want to be opening this up again any time soon"*, which is the rationale for the whole do-it-properly-once posture. |

### 1.7 Inherited wisdom (§7)

| # | Item | Status |
|---|---|---|
| W1 | **"Earned vs declared"** — DevMan's cold feedback loop; bee is the right place to close it because it owns both structure and history | **PARTIAL — thread survives, framing does not.** Traces: `issues.estimate` (migration 002), AD-12 effort measurements, L3 "calibration", `promotion` reserved in Consistency Conventions, AD-20 preserving AD-5's pruning-by-evidence. **The phrase and the strategic claim appear nowhere.** See §4.10. |
| W2 | Steal: monotonic-seq event log with cursor reads | **DROPPED** (see S2/S3) |
| W3 | Steal: ETS hot buffer → SQLite two-speed writes | **DROPPED** — not adopted and not recorded as rejected |
| W4 | Steal: progressive compaction as LOD ladder | **CORRECTLY REJECTED** in memlog 38 — but the rejection is not recorded in the spine (see §4.11) |
| W5 | Steal: size-tiered content storage | **LANDED** — AD-8's 2 KB threshold + hash/preview envelope |
| W6 | Steal: parity-test harness for de-risking a storage swap | **LANDED** — AD-26 |
| W7 | Improve on: FTS5 — DevMan's is manually synced, silently rescued, **no `bm25()` ranking** | **PARTIAL** — AD-15 fixes sync (trigger-maintained, exclusive) and silence (no-silent-failure convention). **`bm25()` ranking is not mentioned.** AD-3 has a `search:` spec field and AD-11 a `:rank_cutoff` withheld key, both implying ranking exists, but nothing specifies relevance ranking as a requirement. |
| W8 | Improve on: where-clause builder (closed-set, O(n²) via `++`) | **DROPPED** — not mentioned; `Bee.Query.Spec`/`Interpreter` implicitly replace it, but the O(n²) trap is not flagged for the builder |
| W9 | Improve on: pagination (LIMIT only) | **PARTIAL** — `limit` and `withheld[:limit]` exist; offset/cursor pagination is not addressed, despite `tree_page`/pagination having just landed in the codebase (commits 57d219f, 833ee6a) |
| W10 | Do not repeat: hand-rolled Jaro-Winkler | **DROPPED** — minor |
| W11 | Do not repeat: open-per-query with full `init_db` each time | **LANDED** — AD-2 ("no module opens its own connection"), AD-22, AD-23 |
| W12 | Do not repeat: blanket `rescue _ -> {:ok, []}` | **LANDED** — Consistency Conventions "Silent failure: Forbidden", with all three instances cited and AD-17's ordering constraint |

### 1.8 Open items (§8) — all six

| # | Open item | Status |
|---|---|---|
| O1 | Exact `Bee.ask/2` intent catalogue | **LANDED** — AD-5 (resolved as two classes rather than a list; correct answer to the question asked) |
| O2 | Reader-pool sizing and checkout strategy | **LANDED** — AD-3 (sizing pinned); checkout via NimblePool in Stack + seed |
| O3 | Rollups on demand vs materialised | **LANDED** — AD-12 ("Computed on demand — no materialisation, no cache") + Deferred row with the 69-node measurement |
| O4 | Event-log retention/compaction policy | **PARTIAL — the answer is missing from the spine** — see §4.11 |
| O5 | Export/JSONL semantics; must not silently break DevMan | **LANDED** — AD-17 |
| O6 | FTS handover sequencing with a LIVE gc_daemon | **LANDED** — migration 001 + Hard ordering constraint |

---

## Part 2 — Memlog (51 entries)

Entries fully covered by Part 1 are marked `↑`. Only divergences are expanded.

| Line | Entry | Status |
|---|---|---|
| 8 | Mission / operator framing | **PARTIAL** ↑ M2 |
| 9 | MEASURED baseline (1971 / 1473 LOC; injection because no extension point existed) | **PARTIAL** — the *causal claim* landed (AD-14 "Prevents: a repeat of the consumer adding…"). The LOC baseline is absent; AD-26's success criterion is parity, not collapse, so there is no number to measure the supercharger against. |
| 10 | D1 concurrency [ADOPTED] | **LANDED** (D1a dropped ↑) |
| 11 | D2 API shape [ADOPTED] | **LANDED** |
| 12 | D3 domain boundary [ADOPTED] | **LANDED** — AD-6 |
| 13 | D4 measures × dimensions [ADOPTED] | **PARTIAL** — intake piggyback dropped ↑ D4a |
| 14 | D5 all-mutation event log; time-gated | **PARTIAL** ↑ D5a |
| 15 | D6 rollups | **LANDED** — AD-12 |
| 16 | D7 migrations | **LANDED** (adopt→rebuild reversal recorded) |
| 17 | D8 withheld reporting | **LANDED** — AD-11 |
| 18 | D9 detail levels | **LANDED** — AD-10 |
| 19 | Two live consumers; DevMan gate GC-2694 | **LANDED** |
| 20 | Test fixture (snapshot dev daemon) | **PARTIAL** ↑ C4 |
| 21 | Deployment path + *"don't want to be opening this up again"* | **PARTIAL** ↑ C5 |
| 22 | Naming: measurement / observation / benchmark / snapshot / promotion | **PARTIAL** — measurement, observation, promotion ✅; benchmark, snapshot ✗ |
| 23 | `labels` vs `issue_labels` bug (as originally understood) | **SUPERSEDED by line 47/57** — correctly ↑ defect #12 |
| 24 | Run opened; deliverables spine + HTML walkthrough + epic/story split | **N/A** (process) |
| 25 | **OPEN-1 RESOLVED — intents are two structurally separate classes** | **LANDED** — AD-5 carries every element: core = code/compiled/versioned/arbitrary Elixir/atoms/closed; registered = data/name+spec/runtime/no release/strings/open; lookup core-then-registry; core names reserved, never shadowable. Also the *criterion* for core membership ("knowledge a consumer cannot reasonably reproduce") survived verbatim in spirit. Only loss: the operator's driving requirement — *intents DISCOVERED on the job after thousands of commits* — is not stated, so AD-5's Prevents reads as tidiness rather than as a response to a stated need. |
| 26 | **Pruning is BY EVIDENCE, not ritual; "this is earned-vs-declared applied to bee's own API surface"** | **PARTIAL** — the mechanism landed, relocated: memlog said "every ask/2 call is an event; intent name is a dimension", which AD-7 then **forbade** (events are mutations only). AD-20 correctly re-homed it in `intent_usage` and explicitly names the risk ("AD-5's pruning-by-evidence never being implemented"). ✅ Handled well. **Lost:** the *self-referential earned-vs-declared framing*, and the concrete usage-count example that made registration-is-reversible legible. |
| 27 | **CONSEQUENCE ACCEPTED** — registered intents are per-database, not portable | **LANDED** — Deferred row "Registered-intent portability across databases: Per-database by design; catalogues legitimately differ." Cost still applies to the current spine. ✅ |
| 28 | OPEN-2 RESOLVED — two auto-classified lanes; bee classifies from the spec, consumers cannot get it wrong | **LANDED** — AD-3, strengthened (shape-only total function, compile-time exhaustiveness). Note: memlog said compute lane "1-2"; spine pins 2 without a decision (benign, §4.13). |
| 29 | **ACCEPTED COST** of two lanes — under an all-analytics burst a heavy query queues behind another heavy query while fast connections sit idle; strictly slower than one shared pool in that case | **DROPPED** | **The accepted cost is nowhere in the spine, and it is still true of the current design.** See §4.12. |
| 30 | WAL: readers never block writer; neither lane contends with writes; readers open read-only | **LANDED** — AD-2, AD-23 |
| 31 | VERIFIED nimble_pool 1.1.0 | **LANDED** — Stack table |
| 32 | VERIFIED exqlite 0.39.0; mix.exs pins ~> 0.34, BEHIND | **LANDED** — Stack table, marked **bump** |
| 33 | MEASURED production DB (2686 issues, 357 edges, 2632 comments, 7718 labels, 89 projects, 1349 parented, largest subtree 69) | **LANDED** — figures reused throughout (AD-10, AD-12 deferred row, AD-18, migration 004, Deferred) |
| 34 | OPEN-3 RESOLVED BY MEASUREMENT — on-demand rollups; **"the snapshot benchmark is the arbiter"** | **LANDED** — AD-12 + Deferred. (The arbiter clause folds into C4's fixture drift ↑) |
| 35 | Sparse-graph finding; operator diagnosis (LLM laziness + impoverished vocabulary); expectation density rises | **LANDED** — Deferred LP row states the density, names both remedies (AD-13 vocabulary, AD-16 candidates) and sets the revisit trigger. Well preserved. |
| 36 | **NEW DIMENSION — write path proposes candidate edges; NEVER MANDATORY; rationale: required fields make lazy models fabricate; LLMs are poor at unprompted recall, good at judging a concrete proposal** | **LANDED** — AD-16 carries the rule, the sources (FTS + labels + project + comment references), reason+confidence, advisory, `No structural field is ever mandatory`, and the fabricated-edges rationale ("trading visibly-missing data for silently-wrong data"). **The positive half of the rationale — LLMs judge proposals well — is not stated**, only the negative half. Minor; AD-16's *shape* is fully intact. |
| 37 | Reinforcements: (1) immediate payoff — edges start mattering once `ready`/`:why_blocked` respond to them; (2) **POST-HOC DETECTION** — with the event log, bee flags *probable missing edges* (closed in sequence, same actor, overlapping labels, comments naming each other) as candidates for confirmation, never silent guesses | **DROPPED (2), PARTIAL (1)** | AD-16's candidate sources are **write-time only**: "FTS + labels + project + comment references". The event-log-driven retrospective candidate detector — the thing that makes the event log pay for itself in the write path — is absent. See §4.14. |
| 38 | **OPEN-4 RESOLVED — KEEP FOREVER, no compaction ladder** (~20k events / ~7MB; deleting history destroys the asset L3 exists to consume) + payload discipline (a) after-values only, (b) hash+length+preview above a cap, (c) comment events reference `comment_id`, never the body | **PARTIAL** — payload discipline (a)(b)(c) landed **exactly** in AD-8. **The retention decision itself did not land.** No AD, no Deferred row, no convention says events are kept forever or that compaction is rejected. AD-7 says "append-only" — which does not forbid a compactor. See §4.11. |
| 39 | MEASURED: `jsonl_path` nil for gc_daemon ⇒ export disabled; per-write dump is a **landmine not an active fire**; DevMan is the only writer (53 issues, 19KB) | **PARTIAL** — AD-17 fixes the landmine without recording that it is currently dormant, so an implementer cannot judge urgency or ordering risk. Informational. |
| 40 | OPEN-5 RESOLVED — export debounced, explicit `Bee.export/1`, flush on terminate | **LANDED** — AD-17, plus AD-22's shutdown ordering to make the terminate flush correct |
| 41 | **OPEN-6 RESOLVED — standing migration policy: STOP-THE-WORLD, FAIL LOUDLY; assume exclusive access; refuse to boot on unexpected schema; rejected online expand/contract** | **LANDED** — AD-15 (boot-gated, verified, `ROLLBACK` on mismatch, dry-run), AD-22 (pool refuses to start below target version), Deferred ("Online (expand/contract) migrations"). The *exclusive-access assumption* is implicit rather than stated. |
| 42 | Migration 001 exploits the window: DROP consumer FTS + 5 shadow tables + 3 triggers, REBUILD bee's own; delete `SearchIndex` in the same release; chosen over adopt-in-place **because a stop window exists** | **LANDED** — migration table row 001 states the reversal *and* the reasoning; Hard ordering constraint covers `SearchIndex`. Exemplary. |
| 43 | All 6 open items resolved | **N/A** (process) — but see O4 (§4.11) |
| 44 | REVIEWER GATE: 5 lenses; data-integrity BLOCK; 20 adversarial pairs; spine v1 not fit to build from | **N/A** (process); outputs listed in `sources:` |
| 45 | ROOT CAUSE 1 — ADs name a concept and delegate its wire format; FIX: Shared Vocabularies with closed sets | **LANDED** — the section exists and names its own origin ("14 of 20 adversarial findings were one failure"). Members: event names, withheld keys, error atoms, measures+units, detail levels — all five delivered. |
| 46 | ROOT CAUSE 2 — bridge under-specified; 4 modules had no destination; **cycle detection lost its owner** | **LANDED** — AD-21 (both edge types, mandatory test before the digraph is removed), full module→destination map in the seed incl. `Bee.World`→`graph/allocation.ex`, `Bee.Agents`→`store/projects.ex`, `Bee.Id`→`store/id.ex`, `tree_page` as a `:tree` scope |
| 47 | **CORRECTION — defect #12 was WRONG**; `labels` exists, 219 rows, orphaned, "worse than dead because it looks functional"; corrected via issue comment | **LANDED — verified** ↑ defect #12. Spine carries the corrected model only. **Gap:** the "looks functional" consequence for `engagement.ex` post-drop is not carried into the Hard ordering constraint (§4.3). |
| 48 | **THREE OPERATOR DECISIONS** | **ALL THREE LANDED — verified individually below** |
| 48.1 | Adopt useful `projects` columns as first-class, fold the rest into `projects.metadata`; gc_daemon keeps reading the same names and stops ALTERing; **sequenced into 002 so 001 stays FTS-focused** | **LANDED** — migration 002 verbatim, marked "Operator decision"; migration 001 explicitly "Touches **none** of the 19 `projects` columns" ✅ sequencing honoured |
| 48.2 | Ghost `labels` → MERGE 219 rows into `issue_labels` via `INSERT OR IGNORE`, verify, then drop | **LANDED** — migration 001, exact mechanism, and AD-15's post-migration verification names `issue_labels` in the parity set ✅ |
| 48.3 | events/measurements FK → **`ON DELETE RESTRICT`**, not CASCADE | **LANDED** — migration 003 with the rationale ("no hard delete exists today, so it costs nothing"), reinforced by the Deferred row "Hard delete semantics — AD-15's RESTRICT forces an explicit decision if one is ever added" ✅. **Note a residual inconsistency:** the brief's L0 DDL declared both tables `ON DELETE CASCADE`; the spine reverses this correctly, but the brief remains the only place the full DDL lives, so anyone building from §4 of the brief gets CASCADE. Cite migration 003 as authoritative. |
| 49 | Spine v2: 17 → 26 ADs (2b, 18–26 enumerated) | **LANDED** — all ten present and matching their memlog descriptions |
| 50 | `Bee.Repo` KEEPS ITS NAME | **LANDED** — stated in the seed with the full reasoning |
| 51 | AD-9 expression-index rule TIGHTENED (exact textual match; `->>` forbidden; one canonical form) | **LANDED** — AD-9 verbatim |
| 52 | AD-23 added — readers starve the checkpointer; PRAGMA foreign_keys per-connection (live DB reports 0); WAL cannot work over a network FS | **LANDED** — AD-23, all three |
| 53 | MEASURED live WAL 4.0MB uncheckpointed; backup MUST use `VACUUM INTO`; only backup artifact 17 days stale | **LANDED** — AD-15 mandatory pre-migration `VACUUM INTO`, "never a filesystem copy", integrity check, abort on failure. (17-day-stale artifact not mentioned; informational.) |
| 54 | AD-15 "unexpected schema" DEFINED as additive-tolerant | **LANDED** — AD-15, with the full list of what the live DB carries and the "a stricter reading refuses to boot against production" justification |
| 55 | Assertions COMPUTED AT RUNTIME, never hardcoded (measured drift within the session: 2686→2687, 7718→7722) | **LANDED** — AD-15, bolded |
| 56 | Spine v2 written; lint clean; pending reconcile + adversarial re-run + renderings | **N/A** (process — this document is the reconcile pass) |
| 57 | CORRECTION to line 47: the table is `labels` (singular) | **LANDED** ↑ |
| 58 | CORRECTION to line 53: the unsafe method is a filesystem copy (`cp`) | **LANDED** ↑ AD-15 |

---

## Part 3 — Accepted costs and consequences: still true?

| Memlog | Accepted cost / consequence | Still true of the current spine? | In the spine? |
|---|---|---|---|
| 27 | Registered intents are per-database, not portable without an explicit export | **YES — unchanged.** AD-5 keeps registered intents as stored data. | ✅ Deferred table |
| 29 | Two lanes are strictly slower than one shared pool under an all-analytics burst | **YES — and *more* so.** AD-3 pinned the compute lane at **2** (memlog said 1–2) and added `stats:` as a third `:compute` trigger, so the queueing surface widened. | ❌ **absent** — see §4.12 |
| 35 | LP/sequencing has little to chew on today (~13% density) | **YES** | ✅ Deferred |
| 38 | Keep-forever costs ~7MB of history | **YES** | ⚠️ cost implied, decision absent — §4.11 |
| 19 | DevMan will be broken; operator authorised it | **PARTIALLY CHANGED.** AD-17 now says "The JSONL format is a consumer contract (DevMan, GC-2694) and **does not change** without updating it", and AD-24 pins export to prefixed strings — i.e. the design evolved *toward preserving* DevMan's contract. Meanwhile the Consistency Conventions row declares `agent_load/2`, `who_blocks_whom/1`, `bottlenecks/1` return-shape changes as "a declared breaking change per GC-2694". So the authorisation is still needed, but for a **different and much smaller** breakage than the one authorised. Worth re-confirming with the operator that the reduced blast radius is understood. | ⚠️ shifted |
| 44/46 | Removing the `:digraph` risks silent cycle acceptance | **YES** | ✅ AD-21, with a mandatory test |

---

## Part 4 — Findings, by severity

### §4.1 — MEDIUM: the mission is not in the spine
`M2`. The operator's framing — *"a super-intelligent, self-contained powerhouse; if a consumer wants something, they simply ask for it"* — is the sentence that adjudicates every judgement call the ADs do not cover ("should bee do this, or the consumer?"). AD-6 gives the *negative* boundary (bee does not model work execution); nothing gives the positive one. A builder resolving ambiguity has only "don't absorb gc_time's domain" to reason with, which biases every close call toward *less* capability in bee — the exact opposite of the brief.
**Fix:** one paragraph under Design Paradigm stating the mission and the ask-don't-compensate test.

### §4.2 — MEDIUM: defect #7 (faked DAG depth) has no bee-side answer
The scheduler's `dag_bonus = min(base * 0.1, 5.0)` is a consumer symptom of a bee gap: bee never exposed real graph position. The spine adds traversal ("neighbourhood, ancestors, descendants, reach") but never connects it to the defect, never names depth, and never states that scheduling-grade graph position is a bee capability. Defect #7 is the only one of twelve with no traceable destination.
**Fix:** either add depth/position to `Bee.Graph.Traverse`'s stated surface (and to a `:what_next`-class core intent under AD-5), or record explicitly that #7 is deferred to consumer adaptation.

### §4.3 — HIGH: dropping `labels` breaks `engagement.ex`, and the ordering constraint does not say so
The spine's Hard ordering constraint names two consumer removals that must ship with 001/002: `SearchIndex` and `project_registry`'s `ALTER TABLE`. It does **not** name `engagement.ex:1296,1336`, which joins `labels` — the table migration 001 **drops**. Per memlog 47, those queries currently succeed silently against the orphaned table. After 001 they will fail against a table that no longer exists. That is a live consumer regression shipped by bee's own migration, in the same release, and it is not in the release checklist.
**Fix:** add `engagement.ex` to the Hard ordering constraint — it must be repointed at `issue_labels` in the same release as 001.

### §4.4 — HIGH: measurement intake has no path (D4a)
The brief was explicit: *"Intake piggybacks on the `update`/`close` that already happens; standalone `measure/2` exists for retroactive/out-of-band correction. **Capture must be the default path, not a second call someone forgets.**"* The spine describes measurement *validation* (AD-9) and measurement *consumption* (AD-12) and never describes measurement *arrival*. There is no `measure/2` in the spine, no measurement parameter on the write path, and no AD binding intake to commands.

This compounds with AD-12: effort must be a registered measurement, a node without one contributes `0` and increments `withheld[:missing_measure]`, and a rollup with any missing effort is never reported as a bare number. With no default capture path, **every rollup on day one is a withheld-qualified non-answer** — the failure mode the brief pre-emptively legislated against.
**Fix:** a new AD, or a clause in AD-9: measurements ride on `create`/`update`/`close` as an optional parameter recorded inside the same command transaction (AD-19); `Bee.measure/2` exists for retroactive correction only.

### §4.5 — MEDIUM: the time-gating urgency is gone (D5a)
The brief's sharpest sequencing argument — *every day without the event log is lost training data; only `closed_at − created_at` is recoverable; time-in-status, rework and blocked duration are gone forever* — appears in the spine only as the Deferred table's mild "Building now would train on data that does not exist." That reads as "L3 is not urgent". The brief's point was the opposite: **L0 is urgent precisely because L3 is not yet possible.**
**Fix:** state it in the Deferred L3 row or in the migration plan: 003 is time-critical; each day it slips is permanently unrecoverable history.

### §4.6 — MEDIUM: the event table's ordering and cursor design vanished (S2, S3, W2)
The brief's L0 DDL specified `id INTEGER PRIMARY KEY AUTOINCREMENT` as a **global cursor for tailing**, `seq` as a per-issue monotonic counter (explicitly justified as "safe: single writer"), and `UNIQUE(issue_id, seq)`. §7 lists "monotonic-seq event log with cursor reads" as a steal-directly item. The spine's migration 003 says only "`events`, `measurements`, `intent_usage` tables". Two independent implementers will produce two different orderings, and the tailing capability has no stated existence. The same applies to `measurements.recorded_at`, which AD-12's "latest value per issue" silently depends on.
**Fix:** put the L0 column-level contract for `events` and `measurements` in migration 003 or in a schema block, as the brief did.

### §4.7 — MEDIUM: measures narrowed from caller-defined to a closed four-member registry, without a logged decision
Brief D4/§4: `measure TEXT NOT NULL -- caller-defined: cost|tokens|duration_ms`, alongside "bee never interprets dimension VALUES… this is what makes it simultaneously agnostic and useful". The spine (AD-9 + Registered measures vocabulary) makes measures a compile-time registry of exactly four, one unit each, "adding a member is a spine amendment", rejected at write.

AD-9's justification is sound (bee does arithmetic on measures, so it must constrain units). But the *degree* is a policy choice the operator never made: a consumer wanting to record `review_latency` must now ship a bee release. Memlog 45 authorised "closed sets for … registered measures+units" as a wire-format fix, not as a shift of the agnostic boundary.
**Fix:** either confirm with the operator, or soften to a runtime measure registry (register name+unit once, then write freely) — which preserves the unit guarantee without a release gate.

### §4.8 — MEDIUM: `issues.estimate` is orphaned and tense with AD-12
Migration 002 adds `issues.estimate`. No AD mentions it. The brief's reason for it — *"so declared can later be measured against earned"* — is the entire earned-vs-declared thread. Meanwhile AD-12 mandates that effort come from a registered measurement and that "`metadata` is never a source of numbers bee computes on". Is `estimate` the declared side (a number bee computes on) or is it superseded by `measure: "effort"`? Two implementers will answer differently, and one of them makes the calibration loop unbuildable.
**Fix:** one clause in AD-12 or a new AD: `issues.estimate` is the *declared* value; `measure: "effort"` is the *earned* value; L3 calibration is the comparison. That single sentence also rescues §4.10.

### §4.9 — MEDIUM: the snapshot dev-daemon fixture became "a copy of the database"
`C4`. The rule landed (AD-26, AD-15) — proving over claiming is now binding, which was the operator's core intent. But the operator named a specific rig: *the mix-based dev daemon running off a 2–3 day old snapshot*, used for **both** benchmarking and migration testing, and — per the deployment path (C5) — as the **rehearsal environment before the live cutover**. The spine's "a copy of the production database" is a file, not a daemon. Nothing in the spine says the new bee must run inside a real daemon before the live one is stopped.
**Fix:** name the dev-daemon snapshot fixture in AD-26, and add the rehearsal step to the migration plan's deployment notes.

### §4.10 — MEDIUM: "earned vs declared" survives only as sediment
`W1`. Four fragments carry it — `issues.estimate`, AD-12's effort measurements, `promotion` reserved in the conventions, AD-20's intent-usage counting. None names the thread, and the strategic claim (*"agents are routed by declared capability, not earned performance… the feedback loop closure is the moat"*, and that bee is the right place to close it because it alone owns structure and history) appears nowhere. This is the *reason L3 exists*. Without it, L3 is an undifferentiated "statistics" box in a Deferred table, and the first person to prune scope will prune it.
**Fix:** one line in the Deferred L3 row naming earned-vs-declared as L3's purpose, plus §4.8's clause.

### §4.11 — MEDIUM-HIGH: OPEN-4's answer (keep forever) is not in the spine
Memlog 38 resolved retention decisively: **KEEP FOREVER, no compaction ladder**, with the volume estimate (~20k events / ~7MB) and the reason (deleting history destroys the exact asset L3 exists to consume). DevMan's progressive-compaction ladder was explicitly rejected.

The spine carries the *payload discipline* that came with that decision (AD-8's after-values-only, 2 KB hash+preview, comment-by-reference) — all three, precisely — but **not the retention decision itself**. AD-7's "append-only derived record" does not forbid a compactor or a retention window. Since AD-8's payload rules read as size-management, a well-meaning implementer facing a growing table will read them as licence to add the ladder and destroy L3's input. One of the six open items therefore has no answer in the document that answers the open items.
**Fix:** add to AD-7: events are retained indefinitely; compaction, deletion and retention windows are forbidden without a spine amendment. Cite the ~7MB estimate.

### §4.12 — MEDIUM: the two-lane accepted cost is not recorded (memlog 29)
The operator was shown and accepted a specific cost: under an all-analytics burst a heavy query queues behind another heavy query while fast connections sit idle — strictly worse than one shared pool in that case. The spine states AD-3's benefit and none of its cost. It is still true, and *more* true: the compute lane is now pinned at 2 (memlog said 1–2) and `stats:` was added as a third `:compute` trigger. The predictable outcome is that the first person to hit rollup queueing "fixes" it by merging the pools, silently reverting an operator decision.
**Fix:** add the accepted cost to AD-3's body, with "this is accepted, not a defect".

### §4.13 — LOW-MEDIUM: post-hoc candidate detection dropped (memlog 37)
AD-16's candidate sources are write-time only: FTS + labels + project + comment references. Memlog 37's second reinforcement — bee mining the **event log** for probable missing edges (closed in sequence, same actor, overlapping labels, comments naming each other), surfaced as candidates and never as silent guesses — is absent. It is the mechanism that turns the event log into a structural-quality flywheel and directly addresses the sparse-graph finding (memlog 35).
**Fix:** if intentionally deferred, add a Deferred row; it should not simply evaporate.

### §4.14 — LOW: L1 "time windows" dropped
Brief §5's L1 list includes time-window queries. No spec field, no AD, no mention. Cycle-time statistics (L3) and any "what changed this week" query need them.

---

## Part 5 — Untraceable spine content

Content in the spine with no decision behind it in either input.

| # | Spine content | Assessment |
|---|---|---|
| U1 | **Structural seed lists `write/events.ex` AND `store/events.ex`; AD-7 binds `Bee.Store.Events` as sole emitter; the Capability map says `Bee.Write.Events`** | **INTERNAL CONTRADICTION — must be resolved.** Three names for one responsibility in one document. AD-7 is the invariant ("`Bee.Store.Events` is the only emitter"), so the seed's `write/events.ex` and the Capability map row are both wrong. Two implementers will create two emitters, and AD-7's own Prevents clause is "(b) two emitters double-writing". |
| U2 | **Registered measures = `effort` (minutes), `cost` (cents), `tokens` (count), `duration` (milliseconds)** | Member list and unit choices are invented in distillation. The *existence* of a closed set traces to memlog 45; the *contents* and the release-gated policy do not. See §4.7. Note also that the brief's example was `duration_ms`, and the spine's `duration` in milliseconds is a rename nobody logged. |
| U3 | **AD-3 classifies `search:` → `:fast`** | Memlog 28 assigned traversal/rollups/stats to compute and "point reads and filtered lists" to fast; FTS search was never classified. Defensible, but an FTS query over 2,687 rows with `bm25()` ranking is not obviously a fast-lane read. Invented; flag for confirmation. |
| U4 | **AD-3 pins the compute lane at exactly 2** | Memlog 28 said "1–2". Pinning is fine and desirable; note it was chosen, not decided. |
| U5 | **Consistency Conventions: microsecond-precision `Z` ISO8601 with migration normalisation (one bad row `GC-1182`); `priority` NULLs-last in both directions, 843 NULL rows not normalised to 0** | Not in the brief and not in the memlog — traceable only to `reviews/review-data-integrity.md`, which *is* declared in `sources:`. Legitimate provenance, but these are **data-affecting decisions** (date normalisation rewrites rows) of the same class as the three the operator was consulted on in memlog 48, and no operator sign-off is logged. Recommend an explicit confirmation. |
| U6 | **AD-10: "When a core intent needs a relation the caller didn't request, the intent loads it internally but the caller's `detail:`/`include:` governs the output"** | Not in either input; a distillation-time refinement. Sound and useful — noting for completeness, no action. |

---

## Part 6 — Recommended actions, ranked

1. **§4.3** — add `engagement.ex` to the Hard ordering constraint (live consumer breaks on migration 001).
2. **§4.4** — give measurement intake a path; without it AD-12 produces withheld-qualified non-answers from day one.
3. **§4.11** — put OPEN-4's keep-forever answer into AD-7.
4. **U1** — resolve `Bee.Store.Events` vs `Bee.Write.Events` (AD-7 wins).
5. **§4.6** — restore the `events`/`measurements` column-level contract (cursor, `seq`, `recorded_at`).
6. **§4.12** — record the two-lane accepted cost in AD-3.
7. **§4.8 + §4.10** — one clause defining `issues.estimate` as declared vs `measure: "effort"` as earned; name earned-vs-declared as L3's purpose.
8. **§4.7 + U2 + U5** — confirm with the operator: closed measure registry, and the date/priority normalisation decisions.
9. **§4.1, §4.9, §4.5** — restore the mission statement, the dev-daemon fixture and rehearsal step, and the time-gating urgency.
10. **§4.2, §4.13, §4.14** — give defect #7, post-hoc candidate detection, and time-window queries either a destination or an explicit Deferred row.
