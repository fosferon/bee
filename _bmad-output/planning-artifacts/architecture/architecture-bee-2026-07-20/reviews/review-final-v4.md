---
review: contradiction sweep (round 4, final)
target: ARCHITECTURE-SPINE.md (bee, 2026-07-20, v4)
prior: reviews/review-contradiction-v3.md
reviewer: contradiction-hunter
date: '2026-07-20'
method: 'Job A — closure audit of C1–C5 and X1–X27 against v4 text, with resolved-vs-relocated discrimination. Job B — independent enumeration of every absolute in the document (205 absolute-bearing tokens across 75 lines), classified by (a) carries an exception list / declares none, (b) exception list complete against cases the document itself creates, (c) satisfiable given every other rule. Job C — adversarial unit-pairing against v4-only material.'
---

# Contradiction Review v4 — bee Architecture Spine

## Verdict

**NEEDS ANOTHER PASS.** One more, and it should be the last.

This is a genuinely different document from v3. Authoring rule 2 worked: **26 of the 32 prior findings are CLOSED**, and closed properly — not relocated. The function→event table, `measurements.seq`, the `via:` grammar, the `close_reason` failure set, the layer reassignment and the AD-19 exclusivity clause all did exactly what they were asked to do. I re-attacked each closure specifically looking for relocation, since two of v2's five criticals moved rather than resolved, and I found only one repeat offender (below).

But rule 2 was applied to the **eight absolutes the document knew it had**, not to the absolutes it has. v4's claim of 8 qualified absolutes is arithmetically correct — I count exactly eight inline exception lists, and they are the right eight to have noticed. The problem is the denominator. I count **approximately 40 normative absolutes** in the document. Eight carry exception lists. Of those eight, **four have incomplete lists**. The other ~32 carry no list and do not declare they have none, which is a facial violation of the rule stated on line 23.

> **v4's fault class: the second authoring rule was applied as a checklist against the absolutes the previous review named, rather than as a sweep. The absolutes v3 caught are now qualified. The absolutes v3 did not happen to look at are in exactly the state v3's absolutes were in.**

And the single relocation is instructive. v2's N1 (shutdown flush) → v3 relocated it from `Bee.Export.terminate/2` to `Bee.Repo.terminate/2` → v4 has now pinned `trap_exit`, `:shutdown :infinity`, temp-path-and-rename, and the reverse-order invariant, closing every specific defect v3 named — and in doing so has made `Bee.Repo.terminate/2` call a **module whose supervised process the same invariant guarantees is already dead**, on **no legally-assignable connection**, with **no bound on a `:infinity` shutdown**. Three iterations, three different failure modes, same paragraph. That paragraph should be treated as structurally suspect rather than incrementally patched.

**New contradictions: 35** (7 CRITICAL, 12 HIGH, 16 MEDIUM). The raw count is up from 27; the *character* is down. v3's criticals were spread across the document's core; v4's cluster at three seams — the export/shutdown path, migration 000's boundary with 002, and the event-payload key/value contract — all three of which are boundaries **created by v3's fixes**. That is the expected signature of a document converging, not diverging.

Severity key: **CRITICAL** = silently wrong answers in production, or a rule unsatisfiable as written; **HIGH** = incompatible artefacts requiring rework of a landed epic; **MEDIUM** = divergence caught at integration; **LOW** = cosmetic.

---

# JOB A — Closure audit of the 32 prior findings

**Tally: 26 CLOSED · 4 PARTIAL · 2 OPEN.**

## The five v3 criticals

| # | Status | v4 evidence |
| --- | --- | --- |
| **C1** one event or two | **CLOSED** | L136: "including a command carrying a `measure:` (AD-9b), whose measurement appears in that event under `fields.measure`." L171 (AD-9b) states the same resolution from the other side and confines `measurement.recorded` to `Bee.measure/3`. The decision was made in AD-7 as recommended, not in AD-9b. **Resolved, not relocated** — but the chosen resolution creates F6 below, because `fields.measure` has no defined shape and AD-8 pins `fields` keys to storage column names. |
| **C2** ordering authority | **CLOSED** | L165: `measurements(… seq NOT NULL …)`, `UNIQUE(issue_id, seq)`, "**`seq` is the ordering authority; `recorded_at` is descriptive only**". L190: "latest by `seq` per `(issue_id, measure, dims.kind)`". Both halves of the recommended edit landed, including the grouping key. Residue at M10 (`dims.kind` is not mandatory on the default intake path). |
| **C3** migration 000 | **PARTIAL** | Escape A was picked and stated: L223, "000 detects which, and normalises all three to one identical baseline schema, then stamps version 1. **000 is the sole migration permitted per-state branching** … the exemption is stated here and nowhere else." The self-contradiction v3 named is gone. But the *substance* of the divergence — the consumer `projects` columns — was not moved into 000, and migration 002 still executes an adoption that cannot be unconditional. See **F3**. |
| **C4** SQL in Export | **CLOSED** | `Bee.Store.Export` now sits under `Bee.Store` in the layer table (L39) and under `store/` in the seed (L408); AD-4 clause 2 (L114) names it explicitly. The SQL-confinement contradiction is genuinely dead. But relocating Export **into L0** created **F2** — AD-4 clause 1 now has no category for what Export does. The fix resolved C4 and opened a strictly worse defect one clause over. |
| **C5** names per command | **CLOSED** | The function→event table (L322–337) is published, many-to-one is declared intended, AD-7 L136 names it "the sole authority on naming; no name is derived from a facet", and "accepted" is now defined (L135: "passed validation AND produced a non-empty delta"). This is the strongest single fix in v4. Completeness defects at M9 and H10. |

**Probe result — `assign/3` → `issue.updated` vs AD-8's column-name keys: CONSISTENT, not a contradiction.** The table governs the *event name*; AD-8 governs the *payload keys*. `assign/3` writing `issues.assigned_to` produces `issue.updated` with `{"fields": {"assigned_to": "claude"}}`. The name is per-entity by design (declared many-to-one), the key is the column name, and the two never touch. The document is right here and I could not break it.

The real AD-8 breakage is elsewhere, on the path v4 added: `fields.measure` (F6) and id-valued columns (F7).

## The 27 v3 findings

| # | Status | v4 evidence |
| --- | --- | --- |
| X1 trap_exit | **CLOSED** | L281: "**traps exits** (`Process.flag(:trap_exit, true)`; it is the only child that does, and without it `terminate/2` never runs)". |
| X2 torn JSONL / shutdown timeout | **PARTIAL** | Tearing is closed: L246, "**Every export writes to a temp path and atomically renames**". Timeout is closed in the wrong direction: L281 pins `:shutdown` to `:infinity` with no bound on what runs inside it. See **H-cluster / F1**. |
| X3 shutdown ordering | **CLOSED** | L286 replaces the false denial with the actual invariant verbatim as recommended, plus "**Reordering children is a spine amendment.**" All three dependencies are named. |
| X4 backup before version check | **CLOSED** | L225: "**The `user_version` gate is evaluated before anything else. The backup is taken only if at least one step is pending**; a boot with nothing to do performs no I/O." |
| X5 `parent-child` row | **CLOSED** | L205 sets gates? to **no**, predicate "never gates", with the `waits-for` rationale inline. |
| X6 unlayered namespaces | **PARTIAL** | `Bee.Write` is gone; Export and Acyclic are L0; AD-1 is restated as "any distance" (L75) with the sole upward exception named (L76). But the layer table's own absolute — "**Every namespace in the codebase appears in this table**" (L44) — is false: `Bee` (the facade) and `Bee.Application` appear in neither column. See **H5**. |
| X7 AD-4 two clauses | **CLOSED** | L113 scopes clause 1 to "**every read of issue-domain data on behalf of a caller**" and enumerates the control tables; L114 resolves `Bee.Intent.Registry` by delegation. Exactly the recommended sentence. Gap at **H6** (no connection is assigned to those control-table reads). |
| X8 checkpointing | **CLOSED** | L293: PASSIVE-on-timer + TRUNCATE-at-terminate, with the AD-3 consequence stated in both places (L107 and L293). The bidirectional cross-reference is exemplary. Crash-path gap at **H11**. |
| X9 Migrate's connection | **CLOSED** | L84: "**with exactly one exception:** `Bee.Store.Migrate` owns a connection that exists only before `Bee.Repo` starts and is closed before it returns `:ok`". |
| X10 `intent_usage` naming | **CLOSED** | Seed L407: `intents.ex … owns 'intents' + 'intent_usage'`; convention L357 + AD-4 L114 both route the Registry through it. |
| X11 missing tables | **CLOSED** | Migration 003 (L429) creates `intents`, `measures`, `intent_usage`. AD-19 L259 adds the exclusivity clause. The clause's list is incomplete — **F4**. |
| X12 `effort` at boot | **CLOSED** | Moved into migration 003 as seed DML, explicitly permitted by AD-15 L234; re-registration idempotency stated at AD-9 L162. |
| X13 002's retained columns | **CLOSED** | AD-14 L215 enumerates the seven and says "This enumeration is the decision AD-14 requires; migration 002 executes it and decides nothing." Correct division of labour — but see **F3** for the resulting execution problem. |
| X14 `close_reason` | **CLOSED** | Shared Vocabularies L320 gives the failure set and the existing column. Projection gap at **H8**. |
| X15 `SAVEPOINT` | **CLOSED** | L258 names all six statements including the savepoint forms, with the reason inline. |
| X16 `:not_loaded` double duty | **CLOSED** | `:not_loaded` is the sentinel only (L177); the withheld vocabulary (L339) has `:relation_omitted` and `:projected_out` and no `:not_loaded`. |
| X17 `via:` grammar | **CLOSED** | L345 publishes the grammar, default 3, max 10, `:depth_cap` on exceed. Under-specification at **H12** and **M-list**. |
| X18 error atoms | **CLOSED** | L341 carries `:unknown_dep_type`, `:unwritable_dep_type`, `:invalid_dimension_key`, `:unit_mismatch`, `:unknown_measure`; AD-25 L306 adds the closed-*data*-vocabulary sentence v3 asked for. But AD-8's own example uses `invalid_value`, which is not in the vocabulary — **M-list**. |
| X19 rollup shape | **PARTIAL** | The verbatim shape landed with `total: nil` and `partial_total` (L191), and `:missing_measure`'s node-counting exception is now carried inline at AD-11 (L183). Two sub-points unaddressed: `refine` is still vacuous for rollups (M13), and `total: integer` contradicts `value REAL` (**H2**). |
| X20 `fields` keys | **CLOSED** *for `assignee`* | L151 pins keys to column names; the detail-level vocabulary (L343) now says `assigned_to`; `rejected` is an object (L153). `assignee` is gone from the document. Reopened on new ground at **F6/F7**. |
| X21 candidate timing | **CLOSED** | AD-2b L90: "This AD governs *which connection*, not *when*; timing is AD-19's." AD-16 L240 cites both correctly, plus the bounded timeout and `candidates: :timed_out`. |
| X22 `import_jsonl` | **CLOSED** | AD-19 L259 makes it the fourth sanctioned non-command write and states the L3 consequence ("must read `issues.created_at`, not event presence"). Transaction-ownership gap at **H7**. |
| X23 `NOT NULL` | **CLOSED** | Deferred L448 carries the parenthetical exemption for 003's new tables. Exemption incomplete — migration 004 (**M4**). |
| X24 parity determinism | **CLOSED** | AD-26 L312: "**Every ordered corpus spec appends `id` as a final sort key**"; mirrored in the Ordering-authority convention (L360). |
| X25 Mission vs FK deferral | **CLOSED** | Mission L31 enumerates the exceptions exhaustively and both Deferred rows are marked *bee-defers-to-consumer*. But the FK decision collides with a *different* absolute now — AD-15's zero-orphan assertion (**H3**) and the silent-failure convention (**M3**). |
| X26 AD-6 opaque signal | **CLOSED** | "opaque" is deleted; L127 carries the unit-validation clause; AD-12 L190 carries the arithmetic-convention clause. Both recommended sentences landed. |
| X27 seed restating responsibilities | **OPEN** | The seed's comments were stripped to bare AD citations (good), but the seed's absolute — "**No other section restates a responsibility**" (L380) — remains false: AD-17 L246 assigns the flush to `Bee.Repo.terminate/2`, AD-22 L282 assigns the Pool a start-refusal behaviour, AD-2 L84 assigns Migrate connection ownership. All are responsibilities, none is in the seed. |
| v3's AD-21 note (transient vs maintained graph) | **OPEN** | The recommended sentence — "a transient adjacency structure built inside one query and discarded is not a maintained graph" — was not added, and `critical_path.ex` still needs one. |

---

# JOB B — The absolutes sweep

## Method and headline

I extracted every occurrence of `only`, `never`, `no`/`No`, `always`, `every`/`Every`, `sole`/`solely`, `exactly`, `must`, `all`/`All`, `none`, `exhaustive*`, `forbidden`, `unconditional*` — 205 tokens across 75 lines — and reduced them to **~40 distinct normative absolutes** (discarding restatements-by-reference and prose uses).

**v4's claim of 8 qualified absolutes is a correct count of the exception lists present.** Those eight are:

| # | Absolute | Exception list | Complete? |
| --- | --- | --- | --- |
| 1 | Mission presumption (L29) | AD-6 + two Deferred rows, "exhaustively" | ✅ verified — exactly two rows carry the marker |
| 2 | AD-1 downward-only (L75) | AD-2b, "There are no others" | ❌ **F2** — AD-4 clause 1 forces `Bee.Store.Export` (L0) → `Bee.Query.Interpreter` (L1) |
| 3 | AD-2 no own connection (L84) | Migrate, "exactly one" | ❌ **H6** — AD-4's internal control-table reads have no assigned connection |
| 4 | AD-7 one event per command (L135) | empty accepted delta | ❌ **F4** — three `register_*` functions emit none and are not non-command writes |
| 5 | AD-11 withheld counts rows (L183) | `:missing_measure` | ✅ verified against all nine keys |
| 6 | AD-19 non-command writes (L259) | "exhaustively four" | ❌ **F4** — same three |
| 7 | Silent failure forbidden (L364) | AD-20 usage counts, "one enumerated" | ❌ **M3** — sanctioned FK orphaning, Sweeper in-flight loss |
| 8 | Deferred no `NOT NULL` (L448) | 003's new tables | ❌ **M4** — migration 004's PK implies `NOT NULL` on existing columns |

**Four of eight lists are incomplete, and the incompleteness is load-bearing in three of the four.** The remaining ~32 absolutes carry no exception list and do not declare they have none. Most genuinely need none; the ones that do are enumerated below, and they produced most of this review's criticals — the same yield ratio as v3.

---

# CRITICAL findings

## F1 — CRITICAL — `Bee.Repo.terminate/2` flushes through a module whose process AD-22 guarantees is already dead, on no legal connection, with no bound

Four statements, each in one place, jointly unsatisfiable. This is v2-N1 on its third relocation.

1. L246 (AD-17): "**The final flush is performed by `Bee.Repo.terminate/2`**."
2. L283 (AD-22): child **4** is `Bee.Store.Export` — a supervised process.
3. L286 (AD-22): "OTP terminates children in reverse start order. **`Bee.Repo` must be the last stateful child to terminate.** Every child that … needs one [a read connection] (Export) is listed after it and therefore dies first."
4. L281 (AD-22): `Bee.Repo`'s `:shutdown` is `:infinity`.

**(a) The process is dead.** By statement 3, `Bee.Store.Export` has already terminated when `Bee.Repo.terminate/2` runs. If the flush is `GenServer.call(Bee.Store.Export, :flush)` it exits `:noproc`, `Bee.Repo.terminate/2` crashes, and **neither the flush nor AD-23's terminate-time `TRUNCATE` happens** — the exact outcome AD-17's prevents-clause names, produced by AD-22's invariant rather than in spite of it. If instead the flush is a plain module call, then `Bee.Store.Export` is both a supervised process *and* a library called from another process's terminate, and nothing in the document says which. The seed (L408) lists `export.ex` once, under `store/`, with no process/module distinction.

**(b) There is no connection it may use.** AD-2 (L83–84) assigns exactly two connection owners plus one enumerated exception. `Bee.Read.Pool` is child 3 — dead by statement 3. `Bee.Store.Migrate`'s connection is closed before boot completes. That leaves the writer's connection — but **AD-2b (L88) binds only `Bee.Repo`, `Bee.Query.Candidates` and `Bee.Store.Acyclic`.** `Bee.Store.Export` is not in that list, and AD-2's exception list has "exactly one exception", which is not Export. So the mandated terminate-time export must read every issue with no connection it is permitted to hold.

**(c) `:infinity` is unbounded and nothing bounds what runs inside it.** AD-16 bounds candidate computation with a stated timeout. AD-17 bounds nothing. An O(n) full-table dump plus per-issue comment queries over 2,687 issues, to a temp path that may be on a full or unresponsive filesystem, under `:shutdown :infinity`, **hangs the VM's shutdown forever with no operator escape**. v3 correctly demanded `:infinity` "for a permanent worker that must drain"; v4 supplied it without supplying the drain bound that makes `:infinity` safe. Compare AD-16, which got this right on the same class of problem two ADs earlier.

Two implementers: Unit A makes Export a pure module called from the writer's terminate on the writer's connection (violates AD-2/AD-2b, works); Unit B keeps Export a GenServer and calls it (obeys AD-2, crashes terminate, silently loses both the flush and the checkpoint). Unit B's failure is silent and only visible as a stale DevMan mirror plus unbounded WAL growth.

**Tightening.** State that the terminate-time flush is a synchronous function call into `Bee.Store.Export` executing **in the writer's process on the writer's connection**, add `Bee.Store.Export` to AD-2b's binds list, and give the flush a bounded budget with a stated behaviour on expiry (`:infinity` on the child spec, bounded work inside). Separately, decide whether child 4 is the debounce timer only.

## F2 — CRITICAL — AD-4 clause 1 has no category for what `Bee.Store.Export` does, and every available reading breaks a different absolute

- L113 (AD-4 clause 1): "**every read of issue-domain data on behalf of a caller** resolves to a `Bee.Query.Spec` executed by `Bee.Query.Interpreter`. Internal reads of bee's own control tables — `locks`, `intents`, `intent_usage`, `measures`, migration state — are performed by their owning `Bee.Store.*` module and never leave the library."
- L246 (AD-17): `Bee.export/1` is an explicit public call; the JSONL format "is a consumer contract (DevMan, GC-2694)".
- L39: `Bee.Store` (including export) is **L0**. L75–76 (AD-1): upward edges are illegal, sole exception AD-2b, "There are no others; adding one is a spine amendment."

Export reads **every issue** — issue-domain data, on behalf of a caller who called `Bee.export/1`, and the result leaves the library as a contract. Clause 1's two categories are exhaustive by construction ("every read … / internal reads of control tables"), and export fits neither: it is not a control-table read (issues are not in the enumerated list, and the output leaves the library), and it cannot be the caller-facing category without executing through `Bee.Query.Interpreter`.

- **Unit A** routes export through the Interpreter. This is an L0→L1 upward edge that AD-1 does not name, making it a spine amendment. It also collides with AD-24 L300, which says "Export JSONL and candidates **bypass Projection**" — Projection is a stage of the one pipeline AD-4 exists to enforce, so export would use the interpreter partially, a path shape stated nowhere.
- **Unit B** has Export construct its own SQL, which AD-4 **clause 2** explicitly permits (L114 names `Bee.Store.Export`). This directly violates clause 1 on the single path that touches every row in the database.

**The two clauses of AD-4 permit and forbid the same act, for the one module v3's C4 fix moved into the blast radius.** Clause 2 was amended to name Export; clause 1 was amended for control tables; nobody swept clause 1 against the module clause 2 had just admitted. This is authoring rule 2's own failure mode, one line apart.

**Tightening.** Add a third category to clause 1: "**Bulk serialisation of issue-domain data for the JSONL consumer contract is performed by `Bee.Store.Export` (AD-17) and does not resolve to a Spec** — it is the one caller-facing read that bypasses the interpreter, because it projects no fields and applies no filters." Then state the AD-24 consequence (prefixed strings) as following from that, rather than as an exception to Projection.

## F3 — CRITICAL — migration 002's "adopt the seven columns" cannot be unconditional, and 000's "one identical schema" does not say which way it normalises

The C3 escape was chosen but its consequence was not followed through. Five statements:

1. L223 (AD-15): 000 "**normalises all three to one identical baseline schema**, then stamps version 1."
2. L224 (AD-15): "**From version 1 onward every migration is unconditional and produces one schema.** … **`IF NOT EXISTS` is forbidden** — baseline is what makes that safe."
3. L428 (Migration 002): "**Adopt the seven columns AD-14 enumerates**; fold all other consumer `projects` columns into `projects.metadata`."
4. L215 (AD-14): the seven are `description`, `stack`, `domain`, `repo_url`, `canonical_path`, `source`, `last_synced_at`. "migration 002 **executes** it and decides nothing."
5. L228 (AD-15): "Additional tables, columns and indexes are **tolerated**."

gc_daemon's live `projects` has 19 consumer columns; DevMan's has none; fresh has none.

**The direct question the document never answers: does 000 ADD the consumer columns to DevMan and fresh, or DROP them from gc_daemon-live?** Both are consistent with statement 1's wording and they produce opposite databases.

- **If 000 adds them** — 000 must know AD-14's seven-column list (and the other twelve), which statement 4 says is 002's job. 002's adoption clause then becomes dead text, and 002's fold clause operates on columns 000 just created for the sole purpose of folding them away.
- **If 000 drops them** — 000 destroys live consumer data before 002 gets a chance to fold it into `metadata`, and the fold clause has nothing to fold.
- **If 000 does neither** (the reading statement 5 invites, where "identical" silently means "identical in bee-owned objects") — then statement 1's "identical" is false, and **002 is unsatisfiable**: `ALTER TABLE projects ADD COLUMN description` succeeds on DevMan/fresh and fails with a duplicate-column error on gc_daemon-live. Statement 2 forbids the `IF NOT EXISTS` that would paper over it and forbids the branch that would resolve it.

This third reading is the one an implementer will land on, because statement 5 is the only place the document discusses what happens to consumer columns at baseline, and it says "tolerated". **The result is a migration that bricks boot on exactly one of the three target databases — the production one.**

**Tightening.** State the direction explicitly in the 000 row: "000 normalises `projects` by *adding* the seven AD-14 columns where absent and leaving all other consumer columns in place; 002 folds the non-adopted ones into `projects.metadata` and drops them." Then delete 002's "adopt" clause, since 000 now owns adoption, and say so. Whatever is chosen, AD-14's enumeration must be cited by 000, not only by 002.

## F4 — CRITICAL — three public functions emit no event and are not among AD-19's "exhaustively four" non-command writes

- L135 (AD-7): "An ***accepted* command is one that passed validation AND produced a non-empty delta.**" L136: "**One accepted command emits exactly one event.**"
- L259 (AD-19): "**Sanctioned non-command writes, exhaustively four:** intent-usage counting (AD-20), intent registration (AD-5), measure registration (AD-9), and `import_jsonl/3` bulk load (AD-17). Each emits no event. **Adding a fifth is a spine amendment.**"
- L335 (function→event table): "`register_project/3`, `register_agent/3`, `join_project/3` | **none** — not issue-scoped, and `events.issue_id` is `NOT NULL`."

These three functions write rows (to `projects`, `agents`, and a membership table). They are called by consumers with arguments, they validate, they produce a non-empty delta. By AD-7 they are accepted commands and **must emit exactly one event** — which `events.issue_id NOT NULL` makes structurally impossible, as the table itself observes. By AD-19 they must therefore be non-command writes — but the list is closed at four and does not contain them, and adding them is a spine amendment.

**Both absolutes exclude the same three functions. There is no compliant implementation.** This is v3's X11 exactly, reconstituted: v3 asked for the exclusivity clause AD-20 had dropped, v4 added it, and the sweep that should have accompanied it — against the function→event table added in the *same* revision, four sections away — did not happen. The table itself contains the evidence, in the "none" cell.

Note the asymmetry that makes this a real trap rather than a typo: `import_jsonl` gets both a table row *and* a slot in the four, so the author clearly did check the table against AD-19 for one row and not for the row directly above it.

**Tightening.** Either extend AD-19 to "exhaustively seven" naming the three registrations (and restate the L3 consequence: project/agent creation is invisible to the event log, so L3 must read `projects.created_at`), or — better — add a `scope` discriminator to AD-7 and drop `events.issue_id`'s `NOT NULL` to `NULL`-for-non-issue-scoped, which also removes the reason the table gives for the exclusion. The former is one edit; the latter changes AD-7's column contract and migration 003, so the former is probably right.

## F5 — CRITICAL — AD-13's `conditional-blocks` row deadlocks permanently on a successful close

L204, the gate truth table, `issue_id` is ready when…:

| dep_type | gates? | ready when |
| --- | --- | --- |
| `blocks` | yes | `depends_on_id` is `closed` **or** `cancelled` |
| `conditional-blocks` | yes | `depends_on_id` is `cancelled`, or **`closed` with a `close_reason` in the failure set** |

The failure set is `failed`, `abandoned`, `superseded` (L320), and "**Any other value, including `NULL`, is a non-failure close**".

So when a `conditional-blocks` blocker closes **successfully** — the normal, overwhelmingly common outcome, and the one that leaves `close_reason` `NULL` — the predicate is false and **`issue_id` is never ready again**. There is no state transition that can rescue it: the blocker is already terminal, and re-opening it to close it as `failed` is absurd.

`conditional-blocks` is thereby **strictly stronger than `blocks`**, which is the inverse of what the name and the whole vocabulary imply. The evident intent is "this edge gates *only if* the blocker fails" — i.e. satisfied on cancel, satisfied on successful close, and gating only while the blocker is open or has closed as a failure. As written it is satisfied on cancel, satisfied on *failed* close, and gating forever on success.

**This is silent and permanent.** `Bee.ready/1` is in AD-26's parity corpus (L312), but the corpus runs against production data, where zero `conditional-blocks` edges exist today (L208: "correct today only because `insert_dependency` hardcodes `'blocks'`"). The harness will pass. The defect surfaces the first time the vocabulary is actually used, as work items that silently never appear in `ready` — the precise failure mode AD-13's prevents-clause names ("`ready` silently mis-answering once non-`blocks` edges exist").

**Tightening.** The row's predicate should read: "`depends_on_id` is `cancelled`, or `closed` with a `close_reason` **not** in the failure set." And then state what the edge is *for* — it gates while the blocker is open, and on a failure close it gates permanently by design (which is itself a decision worth stating, since it is the mirror deadlock).

## F6 — CRITICAL — `fields.measure` has no defined shape and violates AD-8's own key and value rules

The C1 fix put the measurement inside the command's event:

- L136 (AD-7): "whose measurement appears in that event under **`fields.measure`**." L171 (AD-9b) repeats the location.
- L151 (AD-8): "**`fields` keys are exactly the storage column names** — `assigned_to`, never `assignee`. This is what makes `json_extract` usable by L3."
- L152 (AD-8): "`fields` holds **after** values only."

A measurement is not a column of any row the command wrote. It is a row in `measurements` with six meaningful attributes (`measure`, `value`, `unit`, `dims`, `source`, `seq`). Under `fields.measure`:

- The **key** `measure` is a column name of `measurements`, but `fields`' other keys are columns of `issues`. A single JSON object whose keys are drawn from two tables defeats the one property L151 exists to provide: L3 cannot write `json_extract(payload, '$.fields.X')` and know which table `X` came from, and `measurements.measure` and a future `issues.measure` would collide.
- The **value** cannot be an "after value" of `measurements.measure` (which would be the string `"effort"`, losing the number entirely). It must be a composite. **No shape is given.** Unit A emits `{"measure": {"measure": "effort", "value": 90, "unit": "minutes", "dims": {"kind": "actual"}}}`; Unit B emits `{"measure": "effort", "value": 90}` (flattening, and colliding `value` into `fields`); Unit C emits `{"measure": 90}`. All three are defensible readings of two sentences.

L3's entire measurement history on the **default intake path** (AD-9b's stated purpose, L170: preventing "every AD-12 rollup returning a partial total on day one") is therefore recorded in an undefined shape. Events are kept forever (L139) and are unrecreatable, so this is not repairable later by re-emitting.

**Tightening.** Give the verbatim shape in AD-8, as AD-12 now does for the rollup — e.g. `"measure": {"name": "effort", "value": 90, "unit": "minutes", "dims": {...}, "seq": 41}` — and amend L151 to "`fields` keys are exactly the storage column names of the mutated row, **with one exception: `measure`, whose value is the envelope defined below**." Note that `seq` in the payload is what lets L3 join the event to the `measurements` row without a second query.

## F7 — CRITICAL — AD-8's "after values" and AD-24's "prefixed strings everywhere internal" give id-valued columns two incompatible payload forms

- L151–152 (AD-8): `fields` keys are exactly the storage column names, holding **after values**.
- L300 (AD-24): "**Everything internal — traversal, rollups, event payloads, measurement rows, candidate reasons, export JSONL — uses prefixed strings.** Conversion to integer happens only in `Bee.Query.Projection`, on the way out."

`issues.parent` and `issues.project_id` are integer columns. An `update/3` that reparents an issue writes `parent`. What does the event carry?

- **Unit A** obeys AD-8: `{"fields": {"parent": 5}}` — the after value of the storage column, an integer.
- **Unit B** obeys AD-24: `{"fields": {"parent": "GC-5"}}` — event payloads use prefixed strings, and Projection is not on this path.

Both cite one AD and contradict the other. **This is verbatim the failure AD-24's own prevents-clause names** (L299: "`\"GC-2\"` vs `2` in event payloads breaking every `json_extract` comparison") — reachable not by an implementer's carelessness but by following AD-8 to the letter. And it is silent: both forms parse, both store, and L3's `json_extract(payload, '$.fields.parent') = 'GC-5'` matches half the corpus.

Compounding, AD-8's own example contradicts AD-24 already: L149 shows `"refs": {"comment_id": 91}` — a bare integer, inside a payload AD-24 says uses prefixed strings. Either `refs` is exempt (unstated) or the example is wrong.

**Tightening.** AD-8: "**Id-valued columns (`parent`, `project_id`) carry prefixed strings, per AD-24; they are the one place a `fields` value is not the literal column value.** `refs` values are integers, being satellite row ids with no prefixed form." Then AD-24's "event payloads" clause and AD-8 agree explicitly instead of by luck.

---

# HIGH findings

## H1 — HIGH — AD-12's "the rollup unit is the parent tree" nullifies two of its own three scope selectors

L189 (AD-12): "scope selectors (`:tree`, `:closure`, `:critical_path`) choose the set, one aggregator computes over it. **The rollup unit is the parent tree**; dependencies crossing the boundary appear under `gates:`, never in the totals."

`:closure` means the transitive dependency closure; `:critical_path` means the longest dependency chain. **Both are defined by following dependency edges, and dependency edges routinely leave the parent tree** — that is why `gates:` exists. If cross-boundary dependencies never enter the totals, then `:closure`'s total is the parent-tree total, and `:critical_path`'s total is the parent-tree-restricted path total. `:closure` becomes indistinguishable from `:tree`, and `:critical_path` computes a longest path through a subgraph that is not the critical path.

Two implementers: Unit A honours the boundary and ships three selectors of which two are the same number; Unit B honours the selectors and lets `:closure` sum outside the tree, contradicting L189. Neither is caught by AD-26's corpus, which does not include a rollup.

**Tightening.** Scope the boundary rule to the selector it was written for: "**For `:tree`, the rollup unit is the parent tree**; dependencies crossing the boundary appear under `gates:`. For `:closure` and `:critical_path` the selector *is* the unit, and `gates:` reports only edges leaving the selected set."

## H2 — HIGH — the rollup shape declares `total: integer` while measurements store `value REAL`

- L191 (AD-12), verbatim shape: `%{total: integer | nil, partial_total: integer, …}`.
- L165 (AD-9), column contract: `measurements(… value **REAL** …)`.

Summing REALs yields a float. Unit A rounds to satisfy the declared shape (silently discarding sub-unit effort, and making `partial_total + missing` fail to reconcile); Unit B returns floats and violates a shape the document marks "**verbatim**". The shape is a consumer contract; the storage type is a schema contract; nothing reconciles them.

This also propagates: `Bee.measure/3` accepts arbitrary units (open set), so a measure registered in hours will produce fractional totals as a matter of course.

**Tightening.** Either declare `value` as `INTEGER` in AD-9 (and state that units are chosen to make integers sufficient — which `effort` in *minutes* already implies), or change the rollup shape to `number | nil` and state the rounding rule as none.

## H3 — HIGH — AD-15's zero-orphan assertion contradicts the FK non-restoration Deferred sanctions, and will `ROLLBACK` migration 001 against production

- L230 (AD-15): post-migration verification includes a "**zero-orphan assertion. Mismatch ⇒ `ROLLBACK`.**"
- L447 (Deferred, *bee-defers-to-consumer*): FKs on `issues.project_id`/`assigned_to` are deliberately not restored, because restoring them "turns **today's silent orphaning of project deletion** into `RESTRICT`".

The Deferred entry states as fact that project deletion silently orphans issues **today**, on the live database. AD-15 then asserts zero orphans as a migration gate. If any orphan exists — and the Deferred entry exists precisely because they do — **every migration rolls back**, permanently, with no stated remediation.

AD-15's own tolerance rule does not help: L228 tolerates *additional* objects and *missing FKs*, not violated referential state, and the verification block is separate from the tolerance block.

The document does mandate running 001 against a copy first (L232), so this fails loudly rather than silently — which is why it is HIGH and not CRITICAL. But it blocks the entire migration effort on discovery, and the fix is not obvious under the current text: bee cannot delete the orphans (no hard-delete semantics exist, L450) and cannot adopt them (no project to point at).

**Tightening.** Scope the assertion to what the migration is responsible for: "**zero *newly created* orphans** — orphan counts are computed before and after within the same transaction and must not increase. Pre-existing orphans are recorded in the dry-run report and tolerated, per the FK decision in Deferred."

## H4 — HIGH — AD-3's compile-time-error guarantee is defeated by AD-3's own catch-all row

L106 (AD-3): "The classifier **pattern-matches exhaustively** on `Bee.Query.Spec`, so **adding a field without adding its row is a compile-time error**."

L104, the last row of the same table: "**anything else** | `:fast`".

A catch-all clause makes non-exhaustiveness undetectable by construction — a new spec field falls into `anything else` and is classified `:fast` silently. Separately, Elixir does not raise compile-time errors for non-exhaustive struct matching in the first place; the strongest available mechanism is a `@enforce_keys`/explicit-field match producing a *warning*, and only under some shapes.

So the stated safety property is false twice over, and it is the only thing standing between "someone adds a `rollup_window:` field" and "every query carrying it silently goes to the `:fast` pool", which is the head-of-line blocking AD-3's prevents-clause exists to stop.

**Tightening.** Delete the catch-all row and enumerate the `:fast` fields explicitly, so the classifier can match on the full field set and a new field genuinely fails to compile; or keep the catch-all and replace the guarantee with an enforceable one: "a test asserts that `Bee.Query.Spec.__struct__ |> Map.keys()` equals the classifier's declared key set, so adding a field without adding its row **fails the test suite**."

## H5 — HIGH — the layer table's "every namespace appears in this table" is false for the facade and `Bee.Application`

L44: "**Every namespace in the codebase appears in this table.**"

The table (L37–42) lists `Bee.Store`, `Bee.Read`, `Bee.Repo`, `Bee.Query`, `Bee.Intent`, `Bee.Graph`, `Bee.Stats`. The seed (L384–386) also contains `bee.ex` (namespace `Bee`) and `bee/application.ex` (`Bee.Application`). Neither is in the table.

This is the residue of v3's X6, which was closed for `Bee.Write` and `Bee.Export` and not swept for the two that were always missing. It matters concretely:

- The facade is drawn in the diagram reaching L3, L2, L1 **and L0W** (L56–59). AD-1 permits downward-any-distance, so if the facade is "above L3" this is legal — but that is never said, and if the facade is unlayered, AD-1 is unevaluable for the module that mediates all 19+ public functions.
- `Bee.Application` starts `Bee.Repo` (L0) and `Bee.Stats` is deferred but would be L3. A supervisor referencing every layer is either above L3 or outside the lattice; AD-1 cannot be checked for it either way.

**Tightening.** Add a row: "**L4 Facade** | `Bee`, `Bee.Application` — above L3; may depend on any layer, per AD-1." That also makes the diagram's `API -->` edges legal by the stated rule rather than by exemption.

## H6 — HIGH — AD-4 sanctions internal control-table reads that AD-2 assigns no connection to

- L113 (AD-4): control-table reads "are performed by **their owning `Bee.Store.*` module** and never leave the library."
- L83–84 (AD-2): "all mutations go through the single `Bee.Repo` GenServer… **All external reads go through `Bee.Read`** pooled read-only connections. **No module opens its own connection, with exactly one exception:** `Bee.Store.Migrate`."

AD-2's read clause is scoped to "**external** reads" — a term that appears once and is never defined. Internal control-table reads are, by AD-4's own framing, not external. So AD-2 assigns them no connection, and its no-own-connection absolute forbids them from opening one.

Concretely unresolvable for at least three mandated readers:

- `Bee.Store.Locks.Sweeper` (AD-22 child 5) must `SELECT` expired locks before it can expire them. It is a separate process, so it cannot borrow the writer's connection except by dispatching to it — and AD-2b (L88) does not bind it.
- `Bee.Store.Locks` must read current lock state to return `:locked` (L341), on the caller's process, mid-command.
- `Bee.Store.Intents` must read stored specs to resolve a registered intent — on a **read** path, inside the read's critical path, where AD-20 (L265) forbids touching the writer.

**Tightening.** AD-2 needs one more sentence: "Internal control-table reads (AD-4 clause 1) are served by `Bee.Read` on the reading process's checked-out connection, except reads performed inside a command, which use the writer's connection per AD-2b." Then extend AD-2b's binds list accordingly — it currently names three modules and needs at least five.

## H7 — HIGH — no module may open a transaction for the four sanctioned non-command writes, so a 2,687-issue import runs in autocommit

- L258 (AD-19): "`Bee.Repo` opens exactly one transaction **per accepted command** and commits it." "**`Bee.Store.*` functions never issue `BEGIN`/`COMMIT`/`ROLLBACK`/`SAVEPOINT`/`RELEASE`/`ROLLBACK TO`**."
- L259 (AD-19): the four non-command writes, including "`import_jsonl/3` bulk load".

A non-command write is by definition not a command, so `Bee.Repo`'s transaction rule does not reach it, and the Store prohibition is absolute with no exception list. **There is no module permitted to wrap a non-command write in a transaction.**

For the three registrations this is merely suboptimal (single-row autocommit inserts). For `import_jsonl/3` it is a real defect: 2,687 issues plus comments, labels and dependencies as individual autocommit statements is thousands of WAL frames and fsyncs, against a database where AD-23 already flags WAL growth as a hazard, and with **no atomicity** — a crash mid-import leaves a partially-loaded database that AD-17's `INSERT … ON CONFLICT DO NOTHING` will paper over on retry without ever reporting what was skipped.

**Tightening.** Extend AD-19: "`Bee.Repo` also opens exactly one transaction per sanctioned non-command write (AD-19's four), with the same commit-or-nothing guarantee and no event. `import_jsonl/3` may batch into transactions of bounded size, reporting rows applied per batch."

## H8 — HIGH — AD-10's closed detail-level vocabulary never exposes `metadata`, `close_reason`, `parent`, or `closed_at`

L343 (Detail levels, a closed set — "Adding a member is a spine amendment", L316):

- `:minimal` — id, title
- `:compact` — + status, priority, issue_type, project_id, assigned_to, created_at, updated_at
- `:standard` — + description, labels
- `:full` — + all `include:`-able relations

`:full` adds **relations**, not columns. So no detail level exposes:

- **`issues.metadata`** — which AD-14 (L214) makes "the sanctioned extension point" for consumer JSON, and AD-4 clause 1 requires all caller reads to go through the Spec and Projection. **A consumer can write its own metadata and can never read it back.** That is the single most consequential gap in this list: AD-14's whole design depends on consumers using `metadata` instead of adding columns, and the read path does not return it.
- **`close_reason`** — AD-13's `conditional-blocks` gate is computed from it, and a caller cannot see the value that determines its own readiness.
- **`issues.parent`** — AD-18 (L252) makes it "the sole storage for hierarchy". Hierarchy is presumably reachable via an `include:`-able relation, but `parent-child` is explicitly *not* a writable edge and the relation is never named.
- **`closed_at`** — 27 rows have it NULL (L448), so it is at least a live field.

**Tightening.** Add `metadata` and `close_reason` to `:standard`, name the parent/children relations in the `include:` vocabulary, and state whether `:full` means "all relations" or "all columns and all relations" — the current wording says the former and the level's name implies the latter.

## H9 — HIGH — AD-25's "raise before dispatch" is unsatisfiable for registered-intent specs, and leaves the `order_by` injection guard unowned

L306 (AD-25): "**raise** `ArgumentError`, **in the caller's process before dispatch**, for structural/type errors: … **invalid `order_by` column**, unknown **core** intent atom." And: "`Bee.Query.Spec` carries the `order_by` whitelist — today's `@order_columns` (`store.ex:4`) is **the only thing preventing SQL injection** through interpolated column names and must survive."

L120 (AD-5): **Registered** intents are "a name plus a **stored spec** in the `intents` table, added/removed at runtime with no release". L113 (AD-4): "`ask/2` resolves an intent to a spec then calls the same interpreter."

For `Bee.ask("my_intent", ...)`, the spec is **data read from a table**, and its `order_by` is not known in the caller's process before dispatch — it is known only after `Bee.Store.Intents` reads it, which happens on the read path, inside the interpreter's process. So either:

- the raise happens where AD-25 says it cannot ("before dispatch"), or
- an invalid `order_by` in a stored spec is a data-dependent outcome returning `{:error, …}` — but AD-25 classifies invalid `order_by` as structural, and the error vocabulary (L341) has no atom for it, and adding one is a spine amendment.

**And the security consequence is unowned.** If registered specs are validated only at *read* time, a malformed spec sits in the table indefinitely; if validated at *registration* time, that is a rule stated nowhere, and AD-5 says registered intents express "anything `Bee.query` can and nothing more" without saying who checks. The document names `@order_columns` as the sole injection guard and then routes runtime-supplied specs around the moment it is applied.

**Tightening.** State in AD-5: "a registered spec is validated against `Bee.Query.Spec` **at registration**, and registration returns `{:error, :invalid_spec}` on failure — registration is a data operation, not a programmer error." Then AD-25's raise applies only to caller-constructed specs and core atoms, and the whitelist is enforced once at the boundary.

## H10 — HIGH — "all 19 public functions" is falsified by the document's own enumerations

L416: "`@default_server Bee.Repo` (`bee.ex:6`) is the default for **all 19 public functions**."

Counting only functions the document names with arity or as public entry points: `create/3`, `update/3`, `close/2`, `cancel/2`, `assign/3`, `comment/4`, `block/3`, `unblock/3`, `lock/3`, `unlock/2`, `measure/3`, `register_project/3`, `register_agent/3`, `join_project/3`, `import_jsonl/2`, `export/1`, `query/1`, `ask/2` (18), plus AD-26's parity corpus `get`, `list`, `ready`, `count`, `tree_page`, `agent_load/2`, `who_blocks_whom/1`, `bottlenecks/1` (8 more) = **26 minimum**.

This is not pedantry. AD-7 makes the function→event table "the sole authority on naming" and the table's coverage is only checkable against a known function list. If the eight AD-26 functions are *intents* rather than functions, then `agent_load/2`'s arity notation is wrong and AD-26 is asserting parity on things `Bee.query/1` returns; if they are functions, the table is missing eight rows (all reads, so all mapping to "none" — but the table must say so, since "all reads | none" is a row that only works if the reader knows which functions are reads).

**Tightening.** Publish the public surface as a list, or drop the count. The count is load-bearing for two ADs and is wrong.

## H11 — HIGH — AD-23's TRUNCATE justification and AD-17's flush both assume orderly shutdown; under `:rest_for_one` a `Bee.Repo` crash violates both

L293 (AD-23): "**`TRUNCATE` at writer terminate**, which succeeds because AD-22's shutdown invariant guarantees **the pool is already gone**."

L279 (AD-22): "one **`:rest_for_one`** supervisor", with `Bee.Repo` as child 2 and the Pool as child 3.

`:rest_for_one` means: when child 2 crashes, children 3–5 are terminated **after** it, then all are restarted. `Bee.Repo` traps exits (L281), so its `terminate/2` runs **at the moment of its own crash — while the Pool is still alive**. Therefore, on every writer crash:

1. `TRUNCATE` returns busy (the ten pooled readers are still holding the WAL), so the checkpoint AD-23 relies on for bounded WAL growth silently does not happen — and AD-23's stated reason for why it will succeed is false on this path.
2. AD-17's full-table JSONL export runs **on every crash**, not only on shutdown. Combined with `:rest_for_one`'s restart of the whole tail, a crash loop performs a full O(n) export per iteration — structurally the same disk-thrash hazard as v3's X4 backup loop, which v4 fixed for backups (L225) and did not sweep for exports.
3. The writer is crashing, so its connection may be exactly what is broken — and `terminate/2` is now attempting a full-table read across it.

AD-23's clause is correct for the orderly-shutdown path and stated as if that were the only path. AD-22's shutdown invariant is likewise stated only for "OTP terminates children in reverse start order", which describes supervisor shutdown, not `:rest_for_one` sibling termination.

**Tightening.** Distinguish the paths in AD-22: "`terminate/2` runs on both orderly shutdown and writer crash. On the crash path the pool is still alive: the flush is skipped (the debounce timer will recover it after restart) and `TRUNCATE` degrades to `PASSIVE`. Only the orderly path performs the final flush." That also gives F1's bound a natural home.

## H12 — HIGH — the `via:` grammar does not say which dependency types it traverses, and `:neighbourhood` is undefined against a directed graph

L345: "`via: [direction, depth: n]` where direction is `:blockers | :dependents | :ancestors | :descendants | :neighbourhood`."

L208 (AD-13): "All three enrichment readers … **must filter on `dep_type`** — correct today only because `insert_dependency` hardcodes `'blocks'`."

AD-13 establishes that seven `dep_type` values exist, of which three gate and four do not, and makes filtering on `dep_type` a named correctness requirement. The `via:` grammar names directions and a depth and **says nothing about `dep_type`**. So:

- Does `via: [:blockers]` traverse only **gating** edges (`blocks`, `waits-for`, `conditional-blocks`), or all seven including `related` and `discovered-from`? The name "blockers" implies the former; the grammar constrains neither. Two implementers return different node sets, at every depth, and both report `withheld[:depth_cap]` honestly — v3's X17 failure mode reproduced under the new grammar.
- `:ancestors`/`:descendants` presumably walk `issues.parent` (AD-18's sole hierarchy storage) rather than `dependencies` — never stated, and `parent-child` is a projected `dep_type`, so both readings have textual support.
- **`:neighbourhood` has no definition at all.** In a directed graph it could mean the undirected 1-hop set, the union of blockers and dependents, or the union of all five other directions. It is the only direction with no natural reading, and it is the one most likely to be used by an LLM caller that does not know the graph — which AD-16 (L239) identifies as the primary caller profile.

**Tightening.** Extend the grammar to `via: [direction, depth: n, types: [dep_type]]` with a stated default (gating types only, and `parent` for `:ancestors`/`:descendants`), and define `:neighbourhood` explicitly or delete it.

---

# MEDIUM findings

## M1 — "Only `Bee.Store.*` names a table — no exceptions" is contradicted by AD-4 clause 2

L357 (Consistency Conventions, Naming — modules): "**Only `Bee.Store.*` names a table** — no exceptions."

L114 (AD-4 clause 2): "SQL string construction occurs only in **`Bee.Query.Interpreter`** and `Bee.Store.*`."

Constructing `SELECT … FROM issues JOIN dependencies …` names tables. The Interpreter is the module that does it for every caller-facing read. The convention is presumably about *module naming* (it sits in the "Naming — modules" row), but it is written as an unqualified prohibition with "no exceptions" appended, and v3's X10 was resolved by treating it as literal. An implementer applying it literally cannot write the Interpreter.

**Tightening.** "Only `Bee.Store.*` **modules are named after** a table — no exceptions. (Table *references* in SQL are governed by AD-4 clause 2.)"

## M2 — AD-23's "every connection sets `foreign_keys=ON`" omits the migration connection, which AD-15 requires to set it OFF

L292 (AD-23): "**every connection** sets `foreign_keys=ON`, `busy_timeout=5000`, `synchronous=NORMAL`."

L231 (AD-15): "Table rebuilds require all three pragmas: **`foreign_keys=OFF` before `BEGIN`** … `foreign_keys=ON` restored after."

The migration connection is a connection (AD-2's enumerated exception), and AD-15 mandates it violate AD-23's absolute for the duration of a rebuild. Harmless in practice, textually a clean absolute-without-its-exception — and one of the eight that *did* get a sweep elsewhere in the document.

## M3 — the silent-failure exception list omits two failures the document sanctions by name

L364: "**Silent failure: Forbidden**, with one enumerated exception: AD-20's usage counts may be lost on crash."

Two more exist:

- L447 (Deferred): "**today's silent orphaning** of project deletion" is deliberately preserved. A sanctioned silent failure, named as such, not in the list.
- `Bee.Store.Locks.Sweeper` does not trap exits (L281: `Bee.Repo` "is the only child that does"). A sweep write in flight when the Sweeper is terminated is lost with no record — and its event (`lock.expired`) is the only trace that a lock was released.

## M4 — Deferred's `NOT NULL` absolute exempts migration 003 but not migration 004

L448: "**No migration adds `NOT NULL` to an existing column.** (Migrations 003's new tables declare `NOT NULL` on their own new columns … — that is not this rule's subject.)"

L430 (Migration 004): "`dependencies` PK → `(issue_id, depends_on_id, dep_type)`."

In SQLite, columns in a `PRIMARY KEY` of a non-`WITHOUT ROWID` table are not implicitly `NOT NULL` for the rowid-alias case, but a table **rebuild** to change the PK will declare them, and any correct rebuild of `dependencies` will write `dep_type TEXT NOT NULL` — a `NOT NULL` on an existing column, in a migration, outside the stated exemption.

## M5 — AD-15's FK-restore rationale cites a connection that cannot exist during migration

L231 (AD-15): "`foreign_keys=ON` restored after — **omitting the last leaves the writer's connection unenforced for the process lifetime**."

The writer is `Bee.Repo`, supervisor child **2**; `Bee.Store.Migrate` is child **1** and per AD-2 (L84) its connection "is closed before it returns `:ok`". The writer's connection does not exist while the pragma is being toggled, and the toggle happens on a connection that is about to be discarded. The *rule* is right (restore it); the *reason* names an impossible mechanism, which will lead an implementer to conclude the rule is vestigial and drop it.

## M6 — AD-22 child 3 gates on a "compiled-in target" version the document never defines

L282: `Bee.Read.Pool` "refuses to start if `PRAGMA user_version` is below the **compiled-in target**."

The Migration Plan runs 000–004 and states exactly one stamp: 000 → version 1 (L223). Whether 001–004 stamp 2–5, or the ladder is numbered differently, is never said, so the compiled-in target is unknown and the migration-number→`user_version` mapping does not exist. AD-15's "`PRAGMA user_version = N` the last statement inside" the transaction (L227) uses an unbound `N`.

## M7 — AD-6's "no concept of timers" is contradicted by four timers the document mandates

L126 (AD-6): "bee has **no concept of timers**, resource capacity, availability, or rates."

Bee has: the export debounce (AD-17), the WAL checkpoint timer (AD-23), the lock sweeper (AD-22 child 5), and lock expiry itself — a duration attached to a domain object. v4 added an exception clause to AD-6 for *unit validation* (L127) and did not sweep the absolute it sits under. The intent is clearly "no *work-execution* timers", and the word is now used in both senses in one document.

## M8 — AD-14's "no consumer … no exceptions" is prospective, while the document plans around ongoing consumer DDL

L214 (AD-14): "**No consumer creates, alters or drops objects in bee's database** — no exceptions."

L228 (AD-15) tolerates the consumer columns, `labels` table and `issue_project_backfill_log` that exist *because* consumers did exactly that. L435 (Hard ordering constraint) schedules removal of `project_registry`'s `ALTER TABLE` calls and `SearchIndex.rebuild/0` — "operator-invokable … can revert bee's FTS at any time" — for a future release. Until that release lands, the absolute is false by the document's own account, and F3 turns on which side of it migration 002 runs.

## M9 — three defects in the function→event table

- L336 lists **`import_jsonl/2`**; AD-17 (L246) and AD-19 (L259) both say **`import_jsonl/3`**.
- **`Bee.export/1`** (L246, a public function) has no row, in a table AD-7 calls the sole authority.
- The **Sweeper** row is not a public function, though the column header says "public function" — a small thing, except that it is the mechanism by which an internal actor emits an event, which F4 shows is exactly the boundary the table gets wrong elsewhere.

## M10 — AD-12's `dims.kind` grouping is not guaranteed by AD-9b's default intake path

L190 (AD-12): "latest by `seq` per `(issue_id, measure, **dims.kind**)`. Declared and earned are one measure separated by `dims.kind = "estimate" | "actual"`."

L163 (AD-9): "Dimensions stay schemaless under a grammar… `dims` defaults `'{}'`". L171 (AD-9b): `update/3` accepts a `measure:` option — nothing requires it to carry dims.

So the default intake path can record `effort` with `dims = '{}'`, producing a measurement whose `dims.kind` is NULL. It belongs to neither the estimate nor the actual group. Unit A treats it as a third group (so it never appears in either rollup, and `missing` counts the node while a measurement exists — `total: nil` forever, the exact outcome AD-9b was added to prevent); Unit B defaults it to `"actual"` (silently reclassifying); Unit C rejects the write (an error atom that does not exist).

**Tightening.** Make `kind` mandatory for measures used by AD-12 rollups, or state the default in AD-9b: "`measure:` on a command defaults `dims.kind` to `"actual"`; `Bee.measure/3` requires it explicitly."

## M11 — AD-5's atom/string typing makes "core-then-registry" a type dispatch, not a fallback chain

L120: "Lookup is **core-then-registry**; core names are reserved and can never be shadowed." Core names are atoms (closed set); registered names are strings (open set).

If the types are disjoint, shadowing is impossible by construction and there is no fallback: an atom resolves in core or raises (AD-25, L306), and a string resolves in the registry or returns `:unknown_intent`. "Core-then-registry" describes a chain that cannot occur. Two implementers: Unit A dispatches on type (no chain); Unit B normalises the name and chains, resurrecting the shadowing the AD forbids. Also worth stating: consumers building intent names from external input must use `String.to_existing_atom/1`, or the closed core set becomes an atom-exhaustion surface.

## M12 — candidates must use the interpreter but bypass Projection, an undeclared partial pipeline

L114 (AD-4 clause 2) permits SQL only in `Bee.Query.Interpreter` and `Bee.Store.*`; `Bee.Query.Candidates` is neither, so it must go through the Interpreter. L300 (AD-24) says "Export JSONL and candidates **bypass Projection**". Projection is a stage of the single pipeline AD-4 exists to enforce ("one execution path"). A caller of the pipeline that skips its final stage is a second path shape, and nothing says how it is expressed — a spec flag, a separate entry point, or a post-hoc unwrap.

## M13 — `refine` remains vacuous for rollups (v3 X19 sub-point)

L183 (AD-11): every result carries `refine`, "a keyword list of options that would return more". L191 (AD-12): the rollup shape includes `refine: [...]`. No option cures a missing measurement — the cure is to record one. So a rollup's `refine` is always `[]`, and the one result type where the caller most needs guidance offers none. Either state that (so nobody looks) or let `refine` carry a non-option hint.

## M14 — the Structural Seed's "no other section restates a responsibility" is still false (v3 X27, OPEN)

L380: "The single source for module → responsibility. **No other section restates a responsibility**; ADs are cited for traceability only."

The seed's comments were correctly stripped, but three ADs still assign responsibilities: AD-17 L246 (the flush owner), AD-22 L282 (the Pool's start refusal), AD-2 L84 (Migrate's connection ownership). All are currently consistent, so this is latent — but F1 is precisely a case where the flush owner's responsibility needed editing and lives in two places.

## M15 — AD-21's transient-vs-maintained distinction was not added, and `critical_path.ex` needs it (v3 note, OPEN)

L272 (AD-21): "The check is a recursive CTE against the database — **never a maintained in-memory graph**."

`graph/critical_path.ex` (L412) requires a topological sort and longest-path DP, which requires an in-memory adjacency structure. v3 flagged that AD-21's prohibition is scoped to a *maintained* graph and recommended making that explicit. It was not added, and the seed's clarifying comments were removed in the same revision — so the one place a reader could infer the distinction is gone.

## M16 — AD-16's post-commit candidate computation serialises on the single writer, uncosted

L240 (AD-16): candidates are computed "**after commit** (AD-19) on the writer's connection (AD-2b), under a bounded timeout".

Every `create` and `update` therefore performs an FTS query plus label, project and comment scans **inside the single writer**, blocking all other writes for the duration or the timeout. AD-3's accepted-cost clause (L107) discusses only reader-lane contention. The timeout bounds the damage per command but does not free the writer during it, and the ten pooled read connections sit idle throughout. This is a throughput decision the document makes without recording it as one.

## M17 — AD-8's `rejected` example uses an atom absent from the closed error vocabulary

L148: `"rejected": {"priority": "invalid_value"}`. L153: "`rejected` is an object mapping field name to **a reason atom from the error vocabulary**." L341 (Error atoms, closed set — L316: "Adding a member is a spine amendment"): `:not_found`, `:unknown_intent`, `:unknown_measure`, `:unit_mismatch`, `:unknown_dep_type`, `:unwritable_dep_type`, `:invalid_dimension_key`, `:locked`, `:cycle`, `:parent_cycle`, `:self_parent`, `:schema_unexpected`.

`:invalid_value` is not among them. AD-8's own illustrative example requires a spine amendment to be legal. And the vocabulary has no general-purpose per-field rejection atom, which is what `rejected` structurally needs — every command that partially rejects will want one.

---

# Summary table

| # | Finding | Severity | Sites |
| --- | --- | --- | --- |
| F1 | Terminate-time flush: Export's process is dead by AD-22's own invariant; no legal connection; `:infinity` unbounded | CRITICAL | 246, 281, 283, 286, 88 |
| F2 | AD-4 clause 1 has no category for `Bee.Store.Export`; every reading breaks AD-1 or clause 1 | CRITICAL | 113, 114, 246, 75–76, 300 |
| F3 | Migration 002's unconditional "adopt the seven" is unsatisfiable; 000 never says which way it normalises | CRITICAL | 223, 224, 428, 215, 228 |
| F4 | `register_project/3`, `register_agent/3`, `join_project/3`: not commands (no event), not among AD-19's "exhaustively four" | CRITICAL | 135, 136, 259, 335 |
| F5 | `conditional-blocks` never satisfied by a successful close ⇒ permanent silent deadlock | CRITICAL | 204, 320 |
| F6 | `fields.measure` has no shape and violates AD-8's key and value rules, on AD-9b's default path | CRITICAL | 136, 171, 151, 152 |
| F7 | AD-8 "after values" vs AD-24 "prefixed strings" for `parent`/`project_id`; AD-24's own prevents-clause | CRITICAL | 151, 300, 149 |
| H1 | "Rollup unit is the parent tree" nullifies `:closure` and `:critical_path` | HIGH | 189 |
| H2 | Rollup `total: integer` vs `measurements.value REAL` | HIGH | 191, 165 |
| H3 | AD-15's zero-orphan assertion vs Deferred's sanctioned orphaning ⇒ 001 rolls back on production | HIGH | 230, 447 |
| H4 | AD-3's compile-time-error guarantee defeated by its own catch-all row (and by Elixir) | HIGH | 106, 104 |
| H5 | "Every namespace appears in this table" — `Bee` and `Bee.Application` do not | HIGH | 44, 384–386, 56–59 |
| H6 | AD-4's internal control-table reads have no connection assigned by AD-2 | HIGH | 113, 83–84, 88 |
| H7 | No module may open a transaction for the four non-command writes; import is autocommit-only | HIGH | 258, 259 |
| H8 | Detail levels never expose `metadata` (AD-14's extension point), `close_reason`, `parent`, `closed_at` | HIGH | 343, 214, 204, 252 |
| H9 | AD-25's "raise before dispatch" unsatisfiable for registered specs; `order_by` guard unowned | HIGH | 306, 120, 113 |
| H10 | "All 19 public functions" — the document names ≥26 | HIGH | 416, 322–337, 312 |
| H11 | `:rest_for_one` writer crash: TRUNCATE busy, full export per crash, AD-23's stated reason false | HIGH | 293, 279, 281 |
| H12 | `via:` does not specify `dep_type` traversal; `:neighbourhood` undefined | HIGH | 345, 208 |
| M1 | "Only `Bee.Store.*` names a table — no exceptions" vs AD-4 clause 2 | MEDIUM | 357, 114 |
| M2 | AD-23 "every connection sets `foreign_keys=ON`" vs AD-15's rebuild pragma | MEDIUM | 292, 231 |
| M3 | Silent-failure list omits sanctioned FK orphaning and Sweeper in-flight loss | MEDIUM | 364, 447, 281 |
| M4 | Deferred's `NOT NULL` exemption covers 003 but not 004's PK rebuild | MEDIUM | 448, 430 |
| M5 | AD-15's FK-restore rationale cites the writer's connection, which cannot exist yet | MEDIUM | 231, 84, 279 |
| M6 | "Compiled-in target" version undefined; no migration→`user_version` map | MEDIUM | 282, 223, 227 |
| M7 | AD-6 "no concept of timers" vs four mandated timers | MEDIUM | 126, 246, 293, 284 |
| M8 | AD-14 "no exceptions" is prospective; the plan presumes ongoing consumer DDL | MEDIUM | 214, 228, 435 |
| M9 | Event table: `import_jsonl/2` vs `/3`; `export/1` missing; Sweeper is not a public function | MEDIUM | 336, 246, 333 |
| M10 | `dims.kind` not guaranteed by AD-9b's default path; unclassifiable measurements | MEDIUM | 190, 163, 171 |
| M11 | Atom/string typing makes "core-then-registry" a type dispatch, not a chain | MEDIUM | 120, 306 |
| M12 | Candidates must use the Interpreter but bypass Projection — undeclared partial pipeline | MEDIUM | 114, 300 |
| M13 | `refine` still vacuous for rollups (v3 X19 residue) | MEDIUM | 183, 191 |
| M14 | Seed's "no other section restates a responsibility" still false (v3 X27, OPEN) | MEDIUM | 380, 246, 282, 84 |
| M15 | AD-21's transient-vs-maintained clarification not added; `critical_path.ex` needs it (OPEN) | MEDIUM | 272, 412 |
| M16 | Post-commit candidates serialise on the single writer, uncosted | MEDIUM | 240, 107 |
| M17 | AD-8's `rejected` example uses `invalid_value`, absent from the closed error vocabulary | MEDIUM | 148, 153, 341 |

**New: 35 (7 CRITICAL, 12 HIGH, 16 MEDIUM). Prior findings: 26 CLOSED, 4 PARTIAL (C3, X2, X6, X19), 2 OPEN (X27, the AD-21 note).**

---

# Recommended amendment set (v4)

Ordered by what unblocks the most. Items 1–4 are the ones I would gate the build on.

1. **Rewrite the export/shutdown paragraph as a unit, not a patch.** It has now failed three revisions in three different ways. Decide in one place: is `Bee.Store.Export` a process, a module, or both; which connection the terminate-time flush uses (add it to AD-2b's binds); what bounds it under `:shutdown :infinity`; and what happens on the `:rest_for_one` crash path where the pool is still alive. Closes **F1**, **H11**, and the residue of X2. (AD-17, AD-22, AD-23, AD-2b.)
2. **Add AD-4 clause 1's third category for bulk serialisation**, and state that export's Projection bypass follows from it. Closes **F2** and **M12**. (AD-4, AD-24.)
3. **State migration 000's normalisation direction for consumer `projects` columns**, move adoption into 000, and reduce 002 to the fold. Closes **F3**, and lets **H3**'s orphan assertion be scoped at the same time. (AD-15, AD-14, Migration Plan.)
4. **Fix AD-13's `conditional-blocks` predicate** to "closed with a `close_reason` **not** in the failure set, or cancelled". One word. Closes **F5**.
5. **Extend AD-19's non-command list to seven** (or make `events.issue_id` nullable with a scope discriminator) so `register_project/3`, `register_agent/3`, `join_project/3` have a home; and give the non-command writes a transaction owner. Closes **F4** and **H7**.
6. **Pin the event payload value contract**: the verbatim `fields.measure` envelope, and id-valued columns as prefixed strings. Closes **F6**, **F7**, **M17**. (AD-8.)
7. **Scope AD-12's parent-tree boundary to `:tree`**, and reconcile `total:` with `value REAL`. Closes **H1**, **H2**.
8. **Add `metadata` and `close_reason` to the detail levels** and name the hierarchy relations. Closes **H8** — the one finding a consumer will hit on day one.
9. **Add an L4 Facade row** to the layer table for `Bee` and `Bee.Application`. Closes **H5**.
10. **Assign connections to AD-4's internal control-table reads** in AD-2, extending AD-2b's binds list. Closes **H6**, and unblocks the Sweeper and `Bee.Store.Locks`.
11. **Validate registered specs at registration**, and rescope AD-25's raise. Closes **H9** and the injection surface.
12. **Extend the `via:` grammar with `types:`** and define or delete `:neighbourhood`. Closes **H12**.
13. **Replace AD-3's compile-time-error claim** with an enforceable test-time claim. Closes **H4**.
14. **Sweep the remaining mediums** — they are individually cheap and cluster into four edits: the four incomplete exception lists (M2, M3, M4, M7), the two false counts (H10, M6), the event-table corrections (M9), and the three OPEN/PARTIAL carry-overs (M13, M14, M15).

---

# Cross-cutting observation

v3's diagnosis was that the disease is *"enough interacting rules that satisfying all of them simultaneously is no longer obviously possible"*, and the prescribed instrument was authoring rule 2. v4 adopted the rule and the document is materially better for it: 26 of 32 closed, and the closures are real — I attacked each one specifically for relocation and found one repeat, not five.

But the instrument was **applied as a checklist and not as a sweep**, and the evidence is precise. Every absolute v3 happened to name is now qualified. Every absolute v3 did not name is unqualified. AD-19's exclusivity clause — added in v4, at v3's request — was not swept against the function→event table, added in v4, at v3's request, four sections away, whose own "none" cells contain the counter-example (**F4**). AD-4 clause 2 was amended to admit `Bee.Store.Export`; clause 1, one line above, was amended in the same revision for a different reason; nobody read them together (**F2**). This is not carelessness. It is what happens when a rule about sweeping is executed by working through a prior review's list.

The structural fix is to make the sweep mechanical rather than diligent. Two changes would do it:

> **Authoring rule 2, operationalised.** (a) Every absolute is tagged in the source with the ADs it binds, so the exception list and the binding list are the same artefact and cannot drift. (b) **No revision may add a new enumeration and a new absolute without cross-producting them.** F4, F2, F6 and M9 are all the same defect: a new table and a new closed list, both correct, never multiplied against each other.

I would also observe that the three criticals concentrated in export/shutdown are one problem, not three, and that it has survived three reviews because each pass fixed the specific mechanism the previous pass named. That paragraph does not need another amendment; it needs to be rewritten from its requirements — flush on orderly shutdown, do not flush on crash, bound the work, name the connection — rather than from its current text.

The document is close, and closer than the raw count suggests. Six of the seven criticals are single-sentence fixes; F3 is the only one that requires a decision rather than a clarification. One more pass, sweeping absolutes exhaustively rather than by prior-review list, and this is buildable.
