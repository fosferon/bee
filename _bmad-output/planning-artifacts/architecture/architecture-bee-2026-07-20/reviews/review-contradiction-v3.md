---
review: contradiction sweep (round 3)
target: ARCHITECTURE-SPINE.md (bee, 2026-07-20, v3)
prior: reviews/review-adversarial-v2.md
reviewer: contradiction-hunter
date: '2026-07-20'
method: 'Job A — per-AD assertion extraction, then all-pairs cross-check of every assertion against every other AD, Shared Vocabularies, Consistency Conventions, Structural Seed, Stack, Migration Plan and Deferred. Re-verification of v2 criticals N1/N2/N3/N5/N7 for genuine resolution vs relocation. Job B — targeted attack on v3-only material: Mission, AD-9b, migration 000, runtime measure registration, the Ordering-authority convention, AD-3 accepted-cost.'
---

# Contradiction Review v3 — bee Architecture Spine

## Verdict

**NEEDS ANOTHER PASS.**

The authoring rule (line 28) worked *for the specific defects it was aimed at*. Deleting the Capability→Architecture map genuinely killed N3. AD-21's mandate genuinely killed N5. `issues.estimate` is genuinely gone, so N7 is dead. Those three are closed and I will not re-litigate them.

But the rule closed a **class of duplication**, not the **class of contradiction**. v2's fault was "the same fact stated twice, disagreeing." v3's fault is one turn of the screw further in:

> **v3's fault class: a fact is now stated in exactly one place, and it contradicts a *different* fact stated in exactly one *other* place.**

Deduplication cannot detect this. Two ADs that each say something once, where one makes the other impossible, are fully compliant with the authoring rule. Six of my five criticals are of exactly this shape: AD-17 mandates SQL in a module AD-4 forbids it in; the Ordering-authority convention forbids the sole ordering key AD-12 depends on; AD-15's tolerance rule makes AD-15's own detection undecidable. Every one of these passes the "stated once" test.

Worse, two of the five v2 criticals **moved rather than resolved**:

- **N1 (shutdown)** relocated the flush from `Bee.Export.terminate/2` to `Bee.Repo.terminate/2` and then declared victory ("shutdown ordering is deliberately not load-bearing"). The two preconditions that make a `terminate/2` flush actually run — the writer trapping exits, and a shutdown timeout large enough for a full-table JSONL dump — are stated nowhere. The torn-JSONL failure v2 described as Unit B's outcome is now reachable from the *sanctioned* implementation. And v2's N1 *secondary* finding (backup before version check) was not addressed at all.
- **N2 (event granularity)** was fixed by deleting the per-facet names — and thereby inverted. The vocabulary now collapses *every* issue mutation to `issue.updated`, so AD-7's rule "names are per **command**" is contradicted by AD-7's own vocabulary, which is per **entity**. And AD-9b immediately reintroduced a facet-shaped name (`measurement.recorded`) on the one path AD-9b declares to be the *default* path.

**New contradictions found: 27** (5 CRITICAL, 10 HIGH, 12 MEDIUM), plus **9 v2 findings still open** and not re-counted.

Severity key: **CRITICAL** = silently wrong answers in production, or a rule that is unsatisfiable as written; **HIGH** = incompatible artefacts requiring rework of a landed epic; **MEDIUM** = divergence caught at integration; **LOW** = cosmetic.

---

# JOB A — Re-verification of the five v2 criticals

| v2 | Claim | Status in v3 |
| --- | --- | --- |
| **N1** shutdown ordering | AD-17 moves flush to `Bee.Repo.terminate/2`; AD-22 declares ordering non-load-bearing | **RELOCATED, NOT CLOSED** — see C4, X1, X2, X10 |
| **N2** event granularity | AD-7 pins one-event-per-command; vocabulary purged of facet names | **NOT CLOSED — inverted** — see C5, C1 |
| **N3** two sole emitters | Capability map deleted; `write/events.ex` deleted; AD-4 permits `Bee.Store.*` | **GENUINELY CLOSED** ✅ |
| **N5** in-memory digraph | AD-21 mandates recursive CTE; forbids maintained graph | **GENUINELY CLOSED** ✅ (one layering residue, X6) |
| **N7** effort's second home | `issues.estimate` deleted from migration 002; AD-18 restated | **GENUINELY CLOSED** ✅ (one residue, X13) |

### N3 — closed. Verification trail

- Line 134: "**`Bee.Store.Events` is the sole emitter** — the only module that inserts into `events`. It is a `Bee.Store.*` module precisely so AD-4 permits it to write SQL. No `Bee.Write.Events` exists."
- Line 115 (AD-4): SQL permitted in `Bee.Query.Interpreter`, `Bee.Store.*`, `Bee.Store.Migrate`. `Bee.Store.Events` ⊂ `Bee.Store.*` ✅.
- Line 372 (seed): `events.ex # SOLE event emitter — AD-7`, under `store/`. No `write/events.ex` anywhere ✅.
- Line 246 (AD-19) binds `Bee.Store.*`, which now includes the emitter ✅.

Three independent statements, all consistent. This is the model the rest of the document should follow. Note in passing that AD-4 line 115 lists `Bee.Store.Migrate` separately from `Bee.Store.*` although the former is a member of the latter — harmless redundancy, but by line 28's own standard it is a defect (LOW, not counted).

### N5 — closed. Verification trail

Searched every site that could imply a maintained graph:

- Line 261: "**The check must be a recursive CTE against the database — never a maintained in-memory graph.**" ✅
- Line 44 (paradigm, L2): "traversal, readiness, acyclicity, critical path, rollups, allocation" — no graph structure named ✅
- Line 85 (AD-2 rationale): "concurrent writers corrupting id allocation and cycle checks" — consistent with a DB-side check ✅
- Line 377 (seed): `acyclic.ex # recursive-CTE cycle prevention — AD-21` ✅
- Line 262: pre-removal test mandated ✅

One near-miss that is **not** a violation: line 380, `critical_path.ex # topsort + longest-path DP`. A topological sort plus longest-path DP requires an in-memory adjacency structure. AD-21's prohibition is scoped to a *maintained* graph (one that outlives a transaction), and a per-query transient built from spec results is outside it. This is correct as written, but it is one word away from being read as licence to keep `graph.ex:6`. **Recommend AD-21 add: "a transient adjacency structure built inside one query and discarded is not a maintained graph."**

### N7 — closed. Verification trail

`estimate` now appears at exactly three sites, none of them a column:
- Line 181 (AD-12 prevents-clause): "60 nodes lack estimates" — prose.
- Line 183: "**There is no `issues.estimate` column**" — the explicit negation ✅
- Line 293: `@order_columns` — unrelated.

Migration 002 (line 399) adds only `issues.metadata`, `projects.metadata` ✅. Migration Plan contains no `estimate` ✅. AD-18 line 242 restates the prohibition ✅. Closed. (See X13 for a residual number-home risk that is *not* N7.)

---

# CRITICAL findings

## C1 — CRITICAL — AD-9b: an update carrying a measurement emits one event or two, and the spine argues both

**This is the H5/N2 failure mode reconstituted on brand-new material, one section after the rule that was supposed to prevent it.**

The three statements, each in exactly one place:

- Line 135 (AD-7): "**One accepted command emits exactly one event**, whatever it touched."
- Line 164 (AD-9b): "`update/3` and the close path accept a `measure:` option recorded **in the same command transaction** (AD-19) as the mutation that carried it."
- Line 307 (vocabulary): `measurement.recorded` is a sanctioned event name.
- Line 248 (AD-19): "The mutation, **its event** (AD-7), and any `measure:` carried with it (AD-9b) commit together or not at all."

`Bee.update("GC-1", status: :closed, measure: {"effort", 90})` is one accepted command. Which event?

- **Unit A** — one event, `issue.updated`, measurement in the payload. Reasoning: AD-7 line 135 is unconditional ("whatever it touched"), and AD-19 line 248 says "its event", singular. Fully compliant. **Consequence:** `measurement.recorded` is then emitted *only* by `Bee.measure/3` — which AD-9b line 163 explicitly characterises as the *retroactive and out-of-band* path. So `SELECT * FROM events WHERE event_type='measurement.recorded'` returns exactly the corrections and none of the primary intake. L3 — whose only input is the event log (line 138) — reconstructs measurement history from the exception set. This is the precise inverse of AD-9b's stated purpose.
- **Unit B** — two events, `issue.updated` + `measurement.recorded`, both inside the one transaction. Reasoning: the vocabulary would not enumerate `measurement.recorded` if the default path never emitted it, and AD-19 line 248 says the measure "commits together" with the mutation, implying it is a first-class recorded thing. Violates AD-7 line 135 by the letter, satisfies the vocabulary's evident intent.

**Both readings are load-bearing for L3 and they produce disjoint event streams.** Note also that `measurement.recorded` is *by construction a facet name* — a measurement is one facet of the composite update that carried it. AD-7 line 135 says "Names are per *command*, never per *facet*." The vocabulary contains a facet name. AD-7 contradicts AD-7.

**Tightening.** Pick one and say it in AD-7, not AD-9b: either (a) "a `measure:` carried on a command appears in that command's single event under `fields.measure`; `measurement.recorded` is emitted only by `Bee.measure/3`, which is itself a command" — and then rename it `measurement.corrected` so its meaning is not a lie; or (b) amend AD-7 to "one accepted command emits exactly one event **per entity it wrote**", enumerate the entities (issue, dependency, lock, measurement), and accept that composite commands emit N events with a shared correlation id — which then needs a correlation column in AD-7's column contract.

## C2 — CRITICAL — the new Ordering-authority convention forbids the ordering key AD-12 and AD-9 depend on

**New material contradicting existing ADs.** The convention (line 326):

> "**Timestamps are never the sole ordering key where correctness matters.** `events.seq` (per-issue) and `events.id` (global) are authoritative; timestamps serve human reading and time-window queries."

Now the two dependents:

- Line 158 (AD-9, column contract): "`recorded_at` **is what 'latest value per issue' (AD-12) resolves against.**"
- Line 183 (AD-12): "Effort is a measurement (`measure: "effort"`), **latest by `recorded_at`**."

"Latest value per issue" selects *which number the rollup sums*. There is no correctness-critical ordering in this spine more load-bearing than that one, and it is resolved by a timestamp, alone. `measurements` has no `seq`; its column contract (line 158) declares `id` but does not declare it monotonic or authoritative — that property is asserted only for `events.id` (line 137).

This is not theoretical. Line 325, in the very row above the convention, states the motivating fact: "**agents emit multiple events per issue within a millisecond**", which is why 6-digit precision was chosen. AD-9b then makes the collision likely by design: a command carrying `measure:` and a `Bee.measure/3` correction can land in the same microsecond, as can two agents recording `effort` on the same issue. On a tie, `ORDER BY recorded_at DESC LIMIT 1` is nondeterministic in SQLite, and **the rollup silently returns a different total on different runs against identical data.**

Compounding, in the same clause: line 183 says "**Declared and earned are one measure separated by a dimension:** `dims.kind = "estimate" | "actual"`", but "latest by `recorded_at`" does not state the grouping. Latest per `(issue_id, measure)` means a recorded `actual` permanently shadows the `estimate` and an estimate rollup becomes impossible. Latest per `(issue_id, measure, dims.kind)` is presumably intended but is stated nowhere. Two implementers, two rollups, both citing line 183.

**Tightening.** Add `seq` to the `measurements` column contract with the same `UNIQUE(issue_id, seq)` guarantee as `events`, and rewrite line 183 as "latest by `seq` per `(issue_id, measure, dims.kind)`; `recorded_at` is descriptive only." Otherwise the Ordering-authority convention must carve out an explicit exception and own the tie-break rule.

## C3 — CRITICAL — migration 000: "unconditional and produces one schema" is unsatisfiable given what 000 and 002 are told to do

Four statements, each in one place, jointly unsatisfiable.

1. Line 214 (AD-15): "Migration `000` **detects** which known state a `user_version = 0` database is in and stamps the matching version. Only then does the ladder apply. **After baseline, every migration is unconditional and produces one schema.**"
2. Line 216 (AD-15): "Idempotency lives at the **migration level via `user_version`**; individual statements are strict and unconditional. `IF NOT EXISTS` is forbidden."
3. Line 399 (Migration 002): "Fold the consumer `projects` columns' data into `projects.metadata` where it duplicates `metadata_json`; retain the rest as first-class bee columns. **Baseline (000) makes this unconditional per starting state.**"
4. Line 397 (Migration 000): three known states — gc_daemon-live / DevMan / fresh.

**The pincer.** "Unconditional **per starting state**" (statement 3) is a contradiction in terms against "unconditional and produces **one** schema" (statement 1). DevMan's `.bee/bee.db` has none of the 19 consumer `projects` columns; gc_daemon's live database has all of them. 002's fold is a full rebuild on one and a no-op on the other. Both end stamped at the same `user_version`, with **different column sets**. That is the exact defect AD-15's prevents-clause names: "one migration producing different schemas on different starting databases" (line 212).

There are only two escapes and both break something else:

- **Escape A: 000 stamps all three states to the *same* version.** Then 000 itself must perform the divergent normalisation — making 000 the one migration with per-state branches, violating statement 2 ("individual statements are strict and unconditional") in the migration that statement 2 exists to enable.
- **Escape B: 000 stamps different versions per state** (fresh→0, DevMan→1, live→2, or similar). Then different databases skip different ladder rungs, and the rungs they skip are not equivalent to having run them — which is statement 1's negation. It also means the ladder's numbering is a *partial order over three lineages*, not the linear ladder the Migration Plan table depicts.

**The spine picks neither.** Two implementers pick differently and produce two incompatible production schemas from the same document.

**Tightening.** State which escape. If A, add a fourth row to the Migration Plan for the normalisation and explicitly exempt 000 from statement 2 with the reason. If B, publish the stamp table (state → stamped version) and per-migration applicability, and delete statement 1's "one schema" claim as false.

## C4 — CRITICAL — AD-17 mandates SQL construction in a module AD-4 forbids it in

- Line 115 (AD-4): "**SQL string construction occurs only in `Bee.Query.Interpreter`, `Bee.Store.*`, and `Bee.Store.Migrate`.**"
- Line 236 (AD-17): "`import_jsonl/3`'s blanket `rescue` (`export.ex:106`) is the **only** current idempotency mechanism — replace it with **`INSERT … ON CONFLICT DO NOTHING` in `insert_issue`** before removing it, never after."
- Line 384 (seed): `export.ex # debounce + idempotent import` — at the top level of `bee/`, **not** under `store/`.

`Bee.Export` is not `Bee.Query.Interpreter`, is not `Bee.Store.*`, is not `Bee.Store.Migrate`. AD-17 orders a specific SQL statement to be written in it. **One AD orders what another AD forbids, in a mandatory sequencing clause the spine flags as safety-critical ("never after").**

This is not resolvable by reading. Unit A obeys AD-4, puts the upsert in `Bee.Store.Issues.insert_issue/1`, and now `Bee.Export`'s import loop dispatches per-issue writes — which raises C11 (is an import a command?). Unit B obeys AD-17 literally and writes SQL in `export.ex`, defeating AD-4's confinement on the one path that touches every row in the database.

Compounding, same module, same problem: line 287 (AD-24) declares "Export JSONL ... carries prefixed strings", and line 236 declares the JSONL format "a consumer contract" — so `Bee.Export` both reads and writes rows, on a path that AD-4, AD-2 (line 86, "No module opens its own connection"), AD-19 (one transaction per command) and AD-1 all describe as if it did not exist. **`Bee.Export` is assigned to no layer** (see X6).

**Tightening.** Move `export.ex` under `store/` as `store/export.ex` (it is a serialisation of storage), or add `Bee.Export` to AD-4's SQL list with a stated reason, or route import through `Bee.Store.Issues` and say so in AD-17.

## C5 — CRITICAL — AD-7's "names are per command" is contradicted by AD-7's own vocabulary, which is per entity

- Line 135 (AD-7): "**Names are per *command*, never per *facet*;** see the event vocabulary."
- Line 307 (vocabulary): `issue.created`, `issue.updated`, `issue.commented`, `dep.added`, `dep.removed`, `lock.acquired`, `lock.released`, `lock.expired`, `measurement.recorded`.
- Line 387: "`@default_server Bee.Repo` (`bee.ex:6`) is the default for **all 19 public functions**."

The vocabulary is per-command for dependencies and locks (`dep.added`/`dep.removed`, `lock.acquired`/`lock.released`), and **per-entity for issues** — every issue-mutating command that is not create or comment collapses to `issue.updated`. bee has 19 public functions. The spine names at least `Bee.update/3`, `Bee.close/2` (line 164, "the close path"), `Bee.block/3` (line 242), `Bee.measure/3` (line 164), `Bee.export/1` (line 236). If names are per command, `Bee.close/2` needs a name and there is not one; if `Bee.close/2` emits `issue.updated`, then names are **not** per command and line 135 is false.

Two implementers:

- **Unit A** — `Bee.close/2` emits `issue.updated` with `fields.status = "closed"`. Compliant with the vocabulary, contradicts line 135. Consequence: nothing in the event log distinguishes "the caller closed this issue" from "the caller ran a composite update that happened to set status", which is fine for L3, but the vocabulary's own per-command members (`lock.acquired` vs `lock.released`) prove the document does not consistently believe that.
- **Unit B** — reads line 135 as binding, observes the vocabulary is incomplete, and adds `issue.closed` — which line 303 makes a **spine amendment**. So Unit B is blocked on governance for a name the rule requires and the vocabulary omits.

v2's N2 recommended publishing "the mapping as a table — public function → event name — in Shared Vocabularies". v3 adopted the rule and **not** the table, which is why the rule and the set can now disagree. The table is the only artefact that makes line 135 checkable.

**Tightening.** Publish the function → event-name table. Nine names against 19 public functions means most functions map to a shared name; that is fine, but it must be *written*, because "per command" and a 9-member set are only reconcilable by an explicit many-to-one mapping. Also resolve: does a command whose accepted delta is empty emit an event? Line 135 says "one **accepted** command"; "accepted" is still undefined (open from v2 N2, not counted separately).

---

# HIGH findings

## X1 — HIGH — `Bee.Repo.terminate/2` has no stated precondition, so AD-17's guarantee may never execute

Line 236 (AD-17): "**The final flush is performed synchronously by `Bee.Repo.terminate/2`.**"

`terminate/2` on a GenServer is invoked on a supervisor-ordered shutdown **only if the process traps exits**. A `GenServer` that does not `Process.flag(:trap_exit, true)` receives the supervisor's exit signal and dies immediately; `terminate/2` never runs. Nothing in AD-22 (lines 264–275), AD-2 (line 86) or the seed (line 353) states that `Bee.Repo` traps exits.

Under the sanctioned implementation with no `trap_exit`, **AD-17's entire guarantee is a no-op** and DevMan's mirror is stale after every restart — the exact outcome AD-17's prevents-clause names ("a shutdown race that leaves DevMan's mirror stale", line 235).

**Tightening.** AD-22 must state: `Bee.Repo` traps exits; it is the only child that does.

## X2 — HIGH — a synchronous full-table dump in `terminate/2` under an unstated shutdown timeout is v2's torn-JSONL outcome, relocated

Even granting X1, the second precondition is missing. A supervisor gives each child a bounded `:shutdown` timeout (default 5000 ms for a worker) and **brutally kills** it on expiry. AD-17 line 235 characterises the export as "an O(n) full-table dump plus per-issue comment queries" over a database with 2,687 issues and 7,722 label rows (line 220). That does not reliably complete in 5 seconds, and it now runs *inside the writer's own terminate*, so a brutal kill leaves a **half-written JSONL file** — v2's N1 Unit B outcome verbatim ("a torn JSONL file, which is worse than a stale one"), now produced by the *recommended* design rather than a misreading of it.

It is worse than in v2, because in v2 the torn write killed `Bee.Export` only. Now it kills the writer mid-terminate, so any other terminate-time obligation (WAL checkpoint per AD-23 line 281, lock release, `intent_usage` flush per AD-20 line 254) is also skipped.

**Tightening.** AD-22 must pin `Bee.Repo`'s `:shutdown` value (`:infinity` for a permanent worker that must drain, with the reason stated), and AD-17 must state that the terminate-time export writes to a temp path and atomically renames, so a kill can never produce a torn consumer contract.

## X3 — HIGH — AD-22's "shutdown ordering is deliberately not load-bearing" is still false

Line 275: "**Shutdown ordering is deliberately not load-bearing** — AD-17 removes the only dependency that needed it."

Two dependencies survive:

1. **`Bee.Export` (child 4) must terminate before `Bee.Repo` (child 2).** It does — reverse start order — but only *incidentally*. If `Bee.Export` still holds a pending debounced flush at terminate (line 236: "JSONL export coalesces after a quiet interval"), and it terminated *after* the writer, its flush would need a read connection from a dead `Bee.Read.Pool` (child 3, also dead) or the dead writer. The property "Export dies first" is therefore load-bearing; AD-22 asserts it is not, and then relies on it.
2. **`Bee.Store.Locks.Sweeper` (child 5) must terminate before `Bee.Repo`.** The sweeper emits `lock.expired` (line 307), so it dispatches writes to `Bee.Repo`. If it outlived the writer it would fail every sweep; if it is mid-dispatch when the writer terminates, its write is lost silently — and the Consistency Conventions forbid silent failure (line 330).
3. **`Bee.Read.Pool` (child 3) must terminate before `Bee.Repo`.** AD-23 line 281 makes the writer responsible for `wal_checkpoint(TRUNCATE)`, which cannot succeed while readers hold the WAL. A terminate-time checkpoint requires the pool to already be gone.

All three hold under the listed order. **None of them is stated, and AD-22 explicitly denies that any of them exists** — so a future reorder ("move the Sweeper earlier so it starts before the pool") is licensed by AD-22's own text and breaks two of them.

**Tightening.** Replace line 275 with the actual invariant: "OTP terminates children in reverse start order. `Bee.Repo` must be the last stateful child to terminate; every child that dispatches to it or holds a read connection is listed after it and therefore dies first. Reordering children is a spine amendment."

## X4 — HIGH — the backup-before-version-check hazard (v2 N1 secondary) was not addressed

Line 218 (AD-15): "**Mandatory pre-migration backup via `VACUUM INTO`** to a timestamped path."

Line 269 (AD-22): `Bee.Store.Migrate` is child 1 of a `:rest_for_one` supervisor.

v2's N1 secondary stated this precisely and recommended: "Pin the order: version check first, backup only if steps are pending." v3 contains no such sentence. "Mandatory pre-migration backup" reads naturally as unconditional, and a `:rest_for_one` supervisor restarting on a `Bee.Repo` crash re-runs child 1 — writing a full `VACUUM INTO` copy of the database on **every restart**, including every iteration of a crash loop. The database is ~7 MB of events plus 2,687 issues plus a 4.0 MB uncheckpointed WAL (line 218); a tight crash loop fills the disk, which takes the daemon down harder.

Note this also interacts with C3: if 000's detection is ambiguous and it refuses boot with `:schema_unexpected` (line 214), the tree fails to start (line 269), the supervisor retries, and each retry backs up first.

**Tightening.** AD-15: "the `user_version` gate is evaluated first; the backup is taken only if at least one step is pending. A boot with nothing to do performs no I/O."

## X5 — HIGH — AD-13's `parent-child` row has "blocking: yes" and no ready-when predicate, and overlaps `waits-for`

Line 191–199, the gate truth table:

| `parent-child` | blocking **yes** | "projected, never written (AD-18)" |
| `waits-for` | blocking yes | "**all** children of `depends_on_id` are closed or cancelled; zero children ⇒ satisfied" |

The `parent-child` row's third column answers *where the edge is stored*, not *when the gate is satisfied* — in the one column of the one table the spine calls "the single most safety-critical table" (v2 line 18). AD-13 line 201 then says "Readiness is **one-hop**: a node is ready when its **direct blockers** are satisfied."

- **Unit A** — `parent-child` blocks, so a node is not ready while any projected `parent-child` blocker is unsatisfied. Direction per line 191: the row `(issue_id, depends_on_id)` means `issue_id` depends on `depends_on_id`, so under a projection where a parent depends on its children, **no parent is ever ready until every child is terminal**. That is exactly `waits-for`'s semantics, making `waits-for` redundant. Under the opposite projection (a child depends on its parent), **no child is ready until its parent closes**, which is backwards for every real hierarchy and would render the entire 69-node tree permanently unready.
- **Unit B** — reads "projected, never written" as meaning `parent-child` never appears in the readiness computation at all, and treats `blocking: yes` as descriptive of the *conceptual* relationship. Then the column says "yes" and the implementation says "no".

Both cite AD-13. The three resulting ready-sets are disjoint. `Bee.ready/1` is in AD-26's parity corpus (line 299), so the harness will assert whichever one lands first is correct.

**Tightening.** Either give `parent-child` an explicit ready-when predicate and a direction (and then justify why `waits-for` still exists), or set `blocking: no` and state that hierarchy never gates readiness — which appears to be the intent, given `waits-for` exists precisely to express "wait for my children".

## X6 — HIGH — `Bee.Write.*` and `Bee.Export` belong to no layer, so AD-1 cannot be evaluated for them; and the paradigm diagram violates AD-1 four times

Line 80 (AD-1): "a module depends **only on its own layer or one below**."

The layer table (lines 40–45) assigns namespaces: L0 = `Bee.Store`, `Bee.Read`, `Bee.Repo`; L1 = `Bee.Query`, `Bee.Intent`; L2 = `Bee.Graph`; L3 = `Bee.Stats`. **`Bee.Write` and `Bee.Export` appear in neither column.** Both exist in the seed (lines 366–367, 384) and both are bound by ADs (AD-16, AD-17, AD-24). AD-1 is unevaluable for them: `Bee.Write.Candidates` reads FTS, labels, projects and comments (line 230) — legal or not depends entirely on a layer assignment that does not exist.

Separately, the mermaid diagram the document calls authoritative ("No upward edges", line 72) contains four edges that skip a layer, each of which AD-1's text forbids:

- Line 64: `L3 --> L1` (skips L2)
- Line 61: `API --> L2`, line 62: `API --> L1`, line 62: `API --> L0W` (the facade reaches three layers deep)

Either AD-1 means "downward, any distance" — in which case line 80's "or one below" is wrong and must be deleted — or it means strictly adjacent, in which case the diagram is wrong. The document contains both.

A third case makes it concrete: AD-21 line 260 requires `Bee.Repo` (L0) to invoke `Bee.Graph.Acyclic` (L2) inside the command transaction. That is an **upward** edge, which line 72 says does not exist and the diagram does not draw. AD-2b line 90 binds all three modules without noticing.

**Tightening.** Assign `Bee.Write` and `Bee.Export` to layers. Restate AD-1 as "downward only, any distance" (which the diagram and AD-21 both need). Add the `L0W --> L2` edge for the acyclicity check, or relocate `Bee.Graph.Acyclic` to L0 as `Bee.Store.Acyclic` — it constructs a recursive CTE, which is L0 work by AD-4's own confinement list.

## X7 — HIGH — AD-4's two clauses contradict each other for every non-issue read

AD-4 line 115 makes two assertions:

1. "**every read** resolves to a `Bee.Query.Spec` executed by `Bee.Query.Interpreter`."
2. "SQL string construction occurs only in `Bee.Query.Interpreter`, `Bee.Store.*`, and `Bee.Store.Migrate`."

Assertion 2 permits `Bee.Store.*` to construct SQL. Assertion 1 forbids any of it from being a read. So `Bee.Store.*` may construct write-only SQL — a constraint stated nowhere, and unsatisfiable for at least four modules the spine mandates:

- **`Bee.Store.Locks.Sweeper`** (line 273) must `SELECT` expired locks to expire them. Nothing in `Bee.Query.Spec` (whose known fields are `via:`, `rollup:`, `stats:`, `search:` and "anything else", line 100–106) is shown to address the `locks` table.
- **`Bee.Store.Measurements`** (line 373) is the "measure registry" — registry lookup on every measurement write is a read.
- **`Bee.Intent.Registry`** (line 363) must read stored specs to resolve a registered intent, and read `intent_usage` for AD-5's "pruning by evidence" (line 121). It is `Bee.Intent`, not `Bee.Store`, so it is not even in assertion 2's list — meaning under both clauses it may neither construct SQL nor be exempt.
- **`Bee.Store.Locks`** must read current lock state to return `:locked` (line 311).

Every one of these is a read that cannot be a `Bee.Query.Spec` as the spine describes the Spec, and must therefore construct SQL somewhere assertion 1 forbids.

**Tightening.** Scope assertion 1 to what it means: "every read **of issue-domain data on behalf of a caller** resolves to a `Bee.Query.Spec`. Internal reads of bee's own control tables (`locks`, `intent_usage`, measure registry, migration state) are performed by their owning `Bee.Store.*` module and never leave the library." Then say whether `Bee.Intent.Registry` owns its own SQL or delegates to a `Bee.Store.Intents`.

## X8 — HIGH — AD-23's checkpointing duty is made unachievable by AD-3's pools

- Line 281 (AD-23): "The writer owns checkpointing: **continuous overlapping readers prevent checkpointing and the WAL grows without bound**, which AD-3's `:compute` lane makes likely — so the writer runs `PRAGMA wal_checkpoint(TRUNCATE)` on a timer and logs when the WAL exceeds a threshold."
- Line 98 (AD-3): `:fast` pool sized `System.schedulers_online()` capped 8, `:compute` pool sized 2 — up to **10 persistent read connections**.

AD-23 correctly diagnoses the failure and then prescribes a remedy that the diagnosis rules out. `wal_checkpoint(TRUNCATE)` requires **no other connection to be reading the WAL**; it returns busy otherwise. With ten pooled connections serving "overwhelmingly cheap agent reads" (line 109) continuously, TRUNCATE will essentially never succeed. The AD's fallback is "logs when the WAL exceeds a threshold" — a log line is not a remedy, and AD-3's accepted-cost clause (line 109) discusses only latency, not this.

This is a rule that makes another rule impossible, which is in scope for this sweep even though it is not a two-statement disagreement.

**Tightening.** Either state a quiescence protocol (the writer signals the pool to drain before checkpointing, with a bounded wait), or downgrade to `wal_checkpoint(PASSIVE)` on a timer plus TRUNCATE at terminate only — and if the latter, note that terminate-time TRUNCATE depends on the pool having terminated first, which contradicts line 275 (see X3).

## X9 — HIGH — AD-2's "No module opens its own connection" is violated by `Bee.Store.Migrate`, by necessity

- Line 86 (AD-2, **Binds: every database access**): "all mutations go through the single `Bee.Repo` GenServer, owning the only read-write connection. All external reads go through `Bee.Read` pooled read-only connections. **No module opens its own connection.**"
- Line 269 (AD-22): `Bee.Store.Migrate` is child **1**; `Bee.Repo` is child **2**; the pool is child **3**.

`Bee.Store.Migrate` runs to completion *before* either connection owner exists. It must open its own connection — and per AD-15 it opens one that runs `VACUUM INTO` (line 218), sets and unsets `PRAGMA foreign_keys` (line 221), and runs DDL. AD-2 states its rule with no exception and binds "every database access."

This is a clean single-place-vs-single-place contradiction: neither AD repeats the other, and they are incompatible.

Secondary, same shape: line 271 requires `Bee.Read.Pool` to read `PRAGMA user_version` before serving — which it does on its own connections, arguably fine — and line 389 retires `Bee.Repo.handle_call(:conn, …)` because it "hands out a raw write connection and violates AD-2", showing the document does treat AD-2's phrasing as absolute.

**Tightening.** AD-2: "…except `Bee.Store.Migrate`, which owns a connection that exists only before `Bee.Repo` starts and is closed before it returns `:ok`."

## X10 — HIGH — `intent_usage` is named by a module the Consistency Conventions forbid from naming tables

- Line 323 (Consistency Conventions): "**No module outside `Bee.Store` names a table.**"
- Line 254 (AD-20): "Intent usage is counted in `intent_usage(name, kind, count, last_used_at)`" — AD-20 **Binds:** `Bee.Intent.Registry`, `Bee.Query`.
- Line 363 (seed): `intent/registry.ex # strings + intent_usage — AD-5, AD-20`.
- The seed's `store/` directory (lines 368–375) contains **no** module for `intent_usage` and none for the registered-intent catalogue.

`Bee.Intent.Registry` is `Bee.Intent`, outside `Bee.Store`, and the seed explicitly assigns `intent_usage` to it. The convention forbids exactly that. And per X7, `Bee.Intent` is not in AD-4's SQL list either — so the module the seed makes responsible for a table may neither name it nor query it.

**Tightening.** Add `store/intent_usage.ex` (or fold into a `store/intents.ex` that also owns the registered-intent catalogue — see X11) and make `intent/registry.ex` a pure resolution layer over it.

## X11 — HIGH — the registered-intent catalogue and the measure registry have no table, and no migration creates one

- Line 121 (AD-5): "**Registered** intents are data — a name plus a **stored spec**, added/removed at runtime with no release."
- Line 155 (AD-9): "**Measures are registered at runtime, exactly as AD-5 registers intents** — an open set, added without a release. Registration binds exactly one unit to the name."
- Line 400 (Migration 003): "`events`, `measurements`, `intent_usage` tables; FKs `ON DELETE RESTRICT`."
- Line 224 (AD-15): "**Only `Bee.Store.Migrate` creates, alters, or drops any database object.** This binds bee's own modules, not just consumers."

Two runtime registries are mandated. **Neither has a table in the Migration Plan.** And AD-15 forbids either registry from creating its own. As written, `Bee.Intent.Registry.register/2` and measure registration have nowhere to persist, and the only compliant path is a spine amendment adding tables.

Follow-on questions the reviewer was asked to check, all unanswered by the spine:

- **Is registering a measure a command?** If yes, AD-19 gives it a transaction and AD-7 demands exactly one event — but the vocabulary (line 307) has no `measure.registered`, and `events.issue_id` is **`NOT NULL`** (line 136) with no issue in sight. The command reading is *structurally impossible*, exactly as v2's N4 showed for `intent_usage`.
- **If no, under what exemption?** AD-20 line 254 carves out precisely one non-command write ("A usage write is not a command"). v2's N4 tightening recommended adding "this is the only sanctioned non-command write, and adding another is a spine amendment"; **v3 adopted the carve-out and dropped the exclusivity clause.** So there is now a template for unexempted non-command writes and no rule limiting them. I count four live instances: `intent_usage` (exempted), measure registration (not), intent registration (not), and `effort`'s boot registration (not — see X12).

**Tightening.** Add `intents(name, spec_json, created_at)` and `measures(name, unit, registered_at)` to migration 003. State in AD-19: "the sanctioned non-command writes are exactly: intent-usage counting (AD-20), intent registration (AD-5), measure registration (AD-9). Each emits no event. Adding a fourth is a spine amendment."

---

# MEDIUM findings

## X12 — MEDIUM — `effort` "registered at boot" has no owner and no idempotency rule

Line 317: "Bee ships `effort` (minutes) **registered at boot** because AD-12 depends on it."

Registration is DML into a table that (per X11) does not exist. `Bee.Store.Migrate` is DDL-only by AD-15 line 224 and runs before the writer. `Bee.Repo` starts second, so boot-registration is presumably a `Bee.Repo.init/1` side effect — an unmodelled non-command write. And AD-9 line 155 says "an unregistered measure, **or a value whose unit disagrees with the registration**, is rejected at write (`:unit_mismatch`)". On the second boot, `effort` is already registered as minutes: is re-registration a silent no-op, or `{:error, :unit_mismatch}` that fails the writer's init and, under `:rest_for_one`, takes down children 3–5? Undefined.

## X13 — MEDIUM — migration 002 "retains the rest as first-class bee columns" while AD-14 says that decision is made in the spine

- Line 207 (AD-14): "a field bee needs **is a column or a measurement, decided here**."
- Line 399 (Migration 002): "Fold the consumer `projects` columns' data into `projects.metadata` where it duplicates `metadata_json`; **retain the rest as first-class bee columns.**"

Which of the 19 consumer-injected columns become bee columns is decided nowhere. AD-14's whole point is that bee, not a consumer and not an implementer, decides what is a column. 002 delegates that decision to whoever writes the migration. If any retained column holds a number, it becomes a second home for a number bee might compute on — **not** N7 (which was about `estimate` specifically) but the same shape, reachable through an unenumerated list.

Additionally, AD-15 line 217 *tolerates* extra columns. So if gc_daemon's de-injection release slips — which the Hard ordering constraint (line 406) flags as a live risk — gc_daemon re-`ALTER`s a column 002 just folded into `metadata`, bee boots fine (tolerated), and the datum lives in a column and in `metadata` simultaneously, with bee reading one and gc_daemon writing the other. Silent.

**Tightening.** Enumerate the retained columns in AD-14 (not in the migration table).

## X14 — MEDIUM — `close_reason` still has no home; v2 H2(b) is open and is now a contradiction with the Migration Plan

Line 197 (AD-13, `conditional-blocks`): "`depends_on_id` is `cancelled`, or `closed` with **a failure `close_reason`**."

`close_reason` appears nowhere else in v3: no column contract, no migration (001–004 add none), no vocabulary of failure reasons. AD-14 line 207 forbids `metadata` as a home for a field bee needs ("a field bee needs is a column or a measurement, decided here"), so `close_reason` **must** be a column — and no migration creates it. AD-13 mandates a gate predicate over a column the Migration Plan does not produce.

v2 flagged this and recommended "Add `close_reason` to migration 002 explicitly." Not done. Note this also has the same shape as C3's escape-B problem: whichever migration adds it must define which values count as failure, or two implementers get two different `ready` sets.

## X15 — MEDIUM — `SAVEPOINT` is still absent from AD-19's prohibition (v2 H4 open)

Line 248: "**`Bee.Store.*` functions never issue `BEGIN`/`COMMIT`/`ROLLBACK`.**" `SAVEPOINT` / `RELEASE` / `ROLLBACK TO` remain unmentioned, so a `Bee.Store.Labels.sync/2` that wraps its diff in `SAVEPOINT … RELEASE` violates no word of AD-19 and produces a partial command commit — the outcome AD-19 exists to prevent. v2's recommended grep test was not reinstated.

## X16 — MEDIUM — `:not_loaded` is still both a withheld reason key and a sentinel value (v2 H10 open)

- Line 170 (AD-10): "**A relation not loaded is `:not_loaded`**, never `[]`, never `nil`" — a value inside a result field.
- Line 309 (vocabulary): `:not_loaded` is a **withheld reason key** — a key inside the `withheld` map.

Same atom, two positions, two meanings. And the case v2 identified is still unhandled: when a core intent loads a relation internally and Projection strips it per the caller's `detail:` (line 170), the honest withheld key would be "loaded but not projected" — the vocabulary has no such member, and `:not_loaded` is factually false. Unit A reports `:not_loaded` (wrong), Unit B reports nothing (AD-11's purpose silently defeated).

## X17 — MEDIUM — `via:` still has no grammar, and `:depth_cap` asserts a cap with no default (v2 H12 open)

`via:` is referenced at line 101 (classifier row) and implied by line 115 ("L2 expresses traversal as spec fields"). Its shape is defined nowhere. `:depth_cap` (line 309) is a sanctioned withheld reason, which asserts a cap exists; no default is stated. Two traversals of the same graph return different node sets and both report `:depth_cap` honestly. AD-3's exhaustive struct match (line 108) does not help — both shapes satisfy "the field exists".

## X18 — MEDIUM — the error-atom vocabulary is still incomplete for rejections the spine mandates (v2 N12 open)

- Line 191 (AD-13): "**Unknown types are rejected at write.**" No atom exists. `:unwritable_dep_type` (line 311) means something else — a *known* type that is projected. A consumer cannot distinguish a typo from `parent-child`.
- Line 156 (AD-9): dimension keys must match `^[a-z][a-z0-9_]*$`. No rejection atom.

Under AD-25 line 293, an implementer may reasonably `raise ArgumentError` for both (closed-vocabulary typo = programmer error) or return a tuple; the AD does not distinguish rejecting a value against a closed **data** vocabulary from a malformed **structure**. v2 recommended exactly that sentence; not added.

## X19 — MEDIUM — the rollup result shape is still not stated, and `refine` is meaningless for it (v2 N8 open)

- Line 176 (AD-11): every result "including rollups and stats" carries `withheld` and "`refine`, a keyword list of options that would return more, **always present**".
- Line 184 (AD-12): "A rollup with any missing effort is **never reported as a bare number**."

No option cures a missing measurement — the cure is to record one. So `refine` on a rollup is always `[]`, which trains consumers to ignore it. And "never reported as a bare number" is an intent, not a shape: Unit A returns `%{total: 1440, withheld: %{missing_measure: 60}, refine: []}` (a bare number with a footnote, satisfying the envelope and defeating AD-12) and Unit B returns `{:partial, …}` (satisfying AD-12 and breaking the universal contract). v2's recommended fix — `total: nil` with a separate `partial_total:` — was not adopted.

Also unadopted: `withheld[:missing_measure]` counts **nodes** while every other withheld key counts **rows**, so a telemetry handler summing `withheld` values across queries (line 331 mandates emitting withheld counts) sums two different units. And AD-12's "external gates reported separately" (line 182) names no key and no home.

## X20 — MEDIUM — AD-8's `fields` keys are still unpinned, and the spine's own two names for one field are still both present (v2 H7 open)

- Line 146 (AD-8): the envelope example uses `{"fields": {"status": "closed"}}`. Nothing states keys are exactly column names.
- Line 313 (Detail levels): `:compact` includes "**assignee**".
- Line 293/line 191 and the live schema (line 217) use `assigned_to`.

Unit A emits `fields.assigned_to`, Unit B emits `fields.assignee` — and AD-8 line 148 exists precisely so L3 can `json_extract` on these. Half the data is invisible to either query. Same AD, still unaddressed: `rejected` as a bare array (line 146) versus the Return-shapes convention's report "naming applied and rejected fields" (line 328) with AD-25 owning a closed reason vocabulary; and `actor`/`at` still have no stated home.

## X21 — MEDIUM — AD-16 and AD-19 still disagree on when candidates are computed (v2 N11 open)

- Line 230 (AD-16): candidates "computed **via AD-2b**" — and AD-2b line 92 scopes itself to "any read needed **during** a command".
- Line 248 (AD-19): "Side effects — export debounce, telemetry, **candidate computation**, usage counting — fire **after** commit, never inside."

A read that fires after commit is not "during a command", so AD-16's citation of AD-2b is either wrong or means only "on the writer's connection". The weaker reading is probably intended, but the spine never says so, and the two units v2 described (in-transaction vs post-commit) still both have textual support. The post-commit reading also has an unaddressed cost — an FTS query plus label and project scans on the writer, with the pool idle — which AD-3's accepted-cost clause (line 109) does not cover and no timeout bounds.

## X22 — MEDIUM — `import_jsonl/3` is a write path no AD governs

Line 236 makes `Bee.Export.import_jsonl/3` a first-class, contract-bearing path. Importing 2,687 issues is 2,687 mutations. Under AD-2 (line 86) they must go through `Bee.Repo`; under AD-19 (line 244) each is one transaction; under AD-7 (line 135) each emits one event. So a full import writes 2,687 transactions and 2,687 `issue.created` events into a log AD-7 line 138 says is kept forever and is L3's only input — meaning **an import is indistinguishable in the event log from 2,687 real creations**, permanently skewing every L3 statistic. Alternatively import is a bulk non-command write, which is the fourth unexempted one (X11). Neither is stated.

## X23 — MEDIUM — Deferred's "No migration adds `NOT NULL`" is contradicted by migrations 003's own column contracts

Line 419 (Deferred): "**No migration adds `NOT NULL`.**" Stated unqualified, in a row about `project_id` and `closed_at`.

Migration 003 (line 400) creates `events` and `measurements`, whose column contracts mandate `events.issue_id NOT NULL` (line 136), `events.seq INTEGER NOT NULL` (line 137), and `measurements(… issue_id NOT NULL …)` (line 158). Read literally, Deferred forbids the constraints AD-7 and AD-9 require. Trivially fixable, but by the authoring rule's own standard a blanket sentence in one section is a fact, and it disagrees with two column contracts.

## X24 — MEDIUM — the deferred timestamp normalisation makes AD-26's parity harness nondeterministic

- Line 402 (Deferred): historical timestamp normalisation deferred; ~700 rows across 4 formats remain mixed until after the writer emits canonical form.
- Line 325: mixed widths break lexical comparison — **measured: 8 mis-ordered pairs in `issues`, 57 in `comments`**.
- Line 299 (AD-26): the harness asserts identical results for `list`, `count`, `tree_page` over a fixed corpus.

`list` and `tree_page` are ordered and paginated. If any corpus spec orders on a timestamp, the comparison runs against 65 known mis-ordered pairs, and pagination over a mis-ordered key skips or duplicates rows. Both old and new implementations see the same bad data, so results may agree — but any change in tie-breaking (and AD-25 line 293 introduces an `order_by` whitelist that did not exist as a Spec field before) flips rows across page boundaries and the harness reports a regression that is not one. Nothing pins a secondary sort key for pagination stability.

## X25 — MEDIUM — the Mission's presumption is contradicted by a Deferred entry that subordinates bee's integrity to a consumer

Line 32 (Mission): "Bee is a self-contained intelligent work engine, **not a store its consumers compensate for**." Line 207 (AD-14): "**No consumer creates, alters or drops objects in bee's database.**"

Line 418 (Deferred): "Restoring missing FKs on `issues.project_id`/`assigned_to` — **deliberately not done: it would turn today's silent orphaning of project deletion into `RESTRICT`, a behaviour change for gc_daemon's registry.** Recorded as a decision, not an oversight."

bee declines to enforce its own referential integrity because a consumer relies on the absence of enforcement. That is precisely "a store its consumers compensate for", inverted — bee compensating for the consumer. It also sits awkwardly beside AD-23 line 280, which turns `foreign_keys=ON` on every connection specifically because "FK enforcement [is] silently absent" today, and beside the Consistency Conventions' "Silent failure: **Forbidden**" (line 330) — silent orphaning is a silent failure, sanctioned by name.

I do not think the decision is wrong; I think the Mission's absolute framing and the Deferred entry cannot both stand unqualified. Mission says AD-6 is "**the one boundary** that overrides this"; here a Deferred row overrides it too.

## X26 — MEDIUM — AD-6's "opaque signal" and AD-9's unit enforcement describe the same interface incompatibly

- Line 127 (AD-6): "bee has **no concept of timers, resource capacity, availability, or rates**. It captures its own events unconditionally and accepts **opaque** outside signal to calibrate itself."
- Line 155 (AD-9): registration "binds exactly one unit to the name"; a unit mismatch is rejected at write. Line 317: "Bee ships `effort` (**minutes**) registered at boot."
- Line 182 (AD-12): "total effort is the base additive primitive over a node set."

A signal whose unit bee validates, whose name bee reserves at boot, and over which bee performs summation, is not opaque. Line 155 attempts the reconciliation — "Bee constrains the *unit*, never the *meaning*" — and it is a reasonable line, but *minutes* is a unit of elapsed work time, which is the domain AD-6 line 126 exists to keep out ("bee absorbing the time-tracking domain"). Shipping `effort`-in-minutes at boot is bee taking a position on what work-time means.

Not fatal, and I would not block on it. But Mission line 34 says AD-6's negative boundary is the tiebreaker for close calls, and this is the closest call in the document — so the tiebreaker needs to actually resolve it. **Tightening:** state in AD-6 that unit *validation* is not domain modelling, and in AD-12 that `effort`'s unit is a bee-internal arithmetic convention with no semantic claim about human time.

## X27 — MEDIUM — the Structural Seed and AD-22 both restate responsibilities the authoring rule says must live in one place

Line 346: "The single source for module → responsibility. **Nothing else in this document restates it.**"

Yet:
- Line 353 (seed): `repo.ex # single writer; **owns final export flush** — AD-2, AD-17, AD-19` restates AD-17's line 236.
- Line 270 (AD-22): "`Bee.Repo` — writer; **owns the final export flush** (AD-17)" restates it again.
- Line 273 (AD-22) and line 375 (seed) both locate the Sweeper at `repo.ex:219`.
- Line 387 restates the `Bee.Repo` naming rationale that line 354's comment also carries.

All four currently **agree**, so this is a latent risk rather than an active contradiction — but it is exactly the mechanism that produced v2's five criticals, appearing in the section that declares itself the sole source and in the AD immediately above it. If the flush owner ever moves, three sites need editing and the authoring rule promises there is one.

---

# Summary table

| # | Finding | Severity | Sites |
| --- | --- | --- | --- |
| C1 | Update-carrying-a-measure: one event or two; `measurement.recorded` is a facet name AD-7 forbids | CRITICAL | 135, 164, 248, 307 |
| C2 | Ordering-authority convention forbids `recorded_at` as sole key; AD-12/AD-9 use exactly that | CRITICAL | 326, 158, 183, 325 |
| C3 | Migration 000/002: "unconditional per starting state" vs "one schema"; both escapes break a rule | CRITICAL | 214, 216, 397, 399 |
| C4 | AD-17 mandates SQL in `Bee.Export`; AD-4 forbids it | CRITICAL | 236, 115, 384 |
| C5 | AD-7 "names are per command" vs a per-entity 9-member vocabulary over 19 public functions | CRITICAL | 135, 307, 387 |
| X1 | `Bee.Repo.terminate/2` requires `trap_exit`, stated nowhere; AD-17's guarantee may never run | HIGH | 236, 264–275 |
| X2 | Synchronous full dump in terminate under an unstated shutdown timeout ⇒ torn JSONL (v2 N1 relocated) | HIGH | 235–236, 268–275 |
| X3 | "Shutdown ordering is deliberately not load-bearing" is false — three live dependencies | HIGH | 275, 236, 273, 281 |
| X4 | Backup-before-version-check unpinned; `:rest_for_one` restart backs up every time (v2 N1 secondary) | HIGH | 218, 269 |
| X5 | AD-13's `parent-child` row: blocking=yes, no ready-when predicate, overlaps `waits-for` | HIGH | 191–201 |
| X6 | `Bee.Write.*`/`Bee.Export` unlayered; diagram violates AD-1's "one below" four times; AD-21 needs L0→L2 | HIGH | 40–45, 61–72, 80, 260 |
| X7 | AD-4 clause 1 ("every read is a Spec") vs clause 2 (Store may write SQL) — unsatisfiable for locks/registries | HIGH | 115, 273, 363, 373 |
| X8 | AD-23's `wal_checkpoint(TRUNCATE)` cannot succeed against AD-3's 10 persistent readers | HIGH | 281, 98 |
| X9 | AD-2 "No module opens its own connection" vs `Bee.Store.Migrate` running before `Bee.Repo` | HIGH | 86, 269, 218 |
| X10 | `intent_usage` assigned to `Bee.Intent.Registry`; conventions forbid non-`Bee.Store` naming a table | HIGH | 323, 254, 363 |
| X11 | No table for registered intents or registered measures; registration is an unexempted non-command write | HIGH | 121, 155, 224, 400 |
| X12 | `effort` "registered at boot": no owner, no idempotency rule, may `:unit_mismatch` on second boot | MEDIUM | 317, 155 |
| X13 | 002's "retain the rest as first-class bee columns" vs AD-14's "decided here" | MEDIUM | 207, 399, 217 |
| X14 | `close_reason` has no column and no migration; AD-13 gates on it (v2 H2b) | MEDIUM | 197, 398–401 |
| X15 | `SAVEPOINT` absent from AD-19's prohibition (v2 H4) | MEDIUM | 248 |
| X16 | `:not_loaded` double duty; no key for loaded-but-not-projected (v2 H10) | MEDIUM | 170, 309 |
| X17 | `via:` has no grammar; `:depth_cap` has no default (v2 H12) | MEDIUM | 101, 115, 309 |
| X18 | No `:unknown_dep_type`, no `:invalid_dimension_key` (v2 N12) | MEDIUM | 191, 156, 311 |
| X19 | Rollup shape unstated; `refine` vacuous; `:missing_measure` counts nodes not rows (v2 N8) | MEDIUM | 176, 182–184 |
| X20 | AD-8 `fields` keys unpinned; `assignee` vs `assigned_to` both live (v2 H7) | MEDIUM | 146, 313 |
| X21 | AD-16 (via AD-2b, in-command) vs AD-19 (post-commit) on candidates (v2 N11) | MEDIUM | 230, 92, 248 |
| X22 | `import_jsonl/3` is an ungoverned write path; poisons the event log or is a 4th exemption | MEDIUM | 236, 86, 244 |
| X23 | Deferred's "No migration adds `NOT NULL`" vs AD-7/AD-9 column contracts in migration 003 | MEDIUM | 419, 136–137, 158, 400 |
| X24 | Deferred timestamp normalisation makes AD-26's ordered/paginated parity nondeterministic | MEDIUM | 402, 325, 299 |
| X25 | Mission "not a store consumers compensate for" vs the deliberate FK non-restoration | MEDIUM | 32, 207, 330, 418 |
| X26 | AD-6 "opaque signal" vs AD-9 unit enforcement and `effort`-in-minutes at boot | MEDIUM | 127, 155, 317, 182 |
| X27 | Seed and AD-22 both restate AD-17's flush owner, against the authoring rule | MEDIUM | 28, 346, 353, 270 |

**New: 27 (5 CRITICAL, 10 HIGH, 12 MEDIUM).** Still open from v2 and folded into the above rather than counted twice: H2(b) `close_reason`, H4 `SAVEPOINT`, H7 `fields` keys / `actor`+`at`, H10 `:not_loaded` + missing withheld key, H12 `via:` grammar, N4 exclusivity clause, N8 rollup shape, N11 candidates, N12 error atoms — **9**.

---

# Recommended amendment set (v3)

Ordered by what unblocks the most.

1. **Publish the function → event-name table** in Shared Vocabularies, and decide C1 in AD-7 (not AD-9b). This closes C1, C5, and the residue of v2's N2/H5 in one edit. Define "accepted".
2. **Add `seq` to the `measurements` column contract** and rewrite AD-12's "latest by `recorded_at`" as "latest by `seq` per `(issue_id, measure, dims.kind)`" (C2).
3. **Pick and state migration 000's escape** — one stamped version with 000 owning the normalisation, or a published state→version stamp table with per-migration applicability. Delete the false claim (C3).
4. **Move `export.ex` under `store/`** or add `Bee.Export` to AD-4's SQL list (C4).
5. **Rewrite AD-22's shutdown paragraph**: `Bee.Repo` traps exits, its `:shutdown` is `:infinity`, and the three ordering dependencies are named as invariants rather than denied (X1, X2, X3). Add version-check-before-backup to AD-15 (X4).
6. **Fix AD-13's `parent-child` row** — give it a ready-when predicate and a direction, or set blocking to no (X5).
7. **Assign every namespace to a layer**, restate AD-1 as "downward, any distance", and either add `L0W → L2` or relocate `Bee.Graph.Acyclic` into `Bee.Store` (X6).
8. **Scope AD-4's "every read" clause** to caller-facing issue-domain reads, and name the owner of bee's control-table reads (X7, X10).
9. **Add `intents` and `measures` tables to migration 003**, and add the exclusivity clause AD-20 dropped: the sanctioned non-command writes are exactly three (X11, X12, X22).
10. **Give AD-23 an achievable checkpoint protocol** (quiescence signal, or PASSIVE-on-timer + TRUNCATE-at-terminate) (X8).
11. **Add the `Bee.Store.Migrate` exception to AD-2** (X9).
12. **Add `close_reason`** to a migration and to Shared Vocabularies, with its failure set (X14).
13. **Carry over the v2 amendments v3 skipped**: `SAVEPOINT` in AD-19; a withheld key for loaded-but-not-projected and disambiguation of `:not_loaded`; `via:` grammar with a depth default; `:unknown_dep_type` and `:invalid_dimension_key`; the verbatim rollup shape with `total: nil`; `fields` keys as column names and `rejected` as an object (X15–X20).
14. **Enumerate 002's retained columns in AD-14** (X13).

---

# Cross-cutting observation

The authoring rule at line 28 is the right instrument aimed one notch too low. It says *"every fact is stated in exactly ONE place"* and treats redundancy as the defect. Redundancy was v2's *symptom*. The disease is that the spine has enough interacting rules that **satisfying all of them simultaneously is no longer obviously possible**, and nothing in the document checks that.

Every one of my five criticals is fully compliant with line 28. C4 is a single AD ordering a single thing that a different single AD forbids. C2 is a brand-new one-line convention that silently invalidated a two-line rule eight sections earlier. C3 is a rule that contradicts itself across two sections that never repeat a word. Deduplication is blind to all of these, because contradiction between *distinct* facts is not duplication.

What v3 needs is the complement of line 28:

> **Second authoring rule.** Every rule that constrains another rule's subject names that rule. Every absolute ("only", "never", "no module", "always") carries its exception list inline, or it has none. A new convention is checked against every AD it could bind before it is added.

Concretely: AD-2's "**No** module opens its own connection" needed its Migrate exception (X9). AD-4's "**only** three modules" needed Export (C4). AD-23's "the writer **owns** checkpointing" needed to be checked against AD-3's pool size (X8). The Ordering-authority convention needed to be checked against every `ORDER BY` in the spine (C2). Four criticals and three highs, all from unqualified absolutes added without a sweep.

The spine is close. The material is unusually well-reasoned and the prevents-clauses are doing real work — several of my findings were *found by* a prevents-clause that correctly names the failure and then prescribes something that does not prevent it (AD-23 is the purest example). One more pass focused on absolutes and their exception lists, plus the nine carried-over v2 items, and this is buildable.
