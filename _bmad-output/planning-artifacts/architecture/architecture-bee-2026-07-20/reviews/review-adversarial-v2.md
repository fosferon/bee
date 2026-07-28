---
review: adversarial (round 2)
target: ARCHITECTURE-SPINE.md (bee, 2026-07-20, revised)
prior: reviews/review-adversarial.md
reviewer: adversarial-reviewer
date: '2026-07-20'
method: 'Job A — strict closure audit of H1..H20 against the revised spine. Job B — fresh construction of compliant-but-incompatible unit pairs against material that has never been adversarially reviewed (AD-2b, AD-18..AD-26, Shared Vocabularies, Migration Plan, module map).'
---

# Adversarial Review v2 — bee Architecture Spine

## Verdict

**The revision is a large, genuine improvement and it introduced three new architecture-breaking defects.**

Eight of twenty holes are properly closed. Eleven are partially closed — the AD now names the concept and pins *most* of its shape, leaving a smaller but still load-bearing seam. One (H6, two event emitters) is **not closed and has arguably regressed**: the spine now asserts two different modules are the "sole emitter", in two different sections, and lists both files in the structural seed.

The Shared Vocabularies section is the right instrument and it covers six of the ten shapes I flagged. It **omits the status vocabulary entirely** — which is fatal, because AD-13's gate truth table (the single most safety-critical table in the spine) is written in terms of `closed` and `cancelled`, and its prose contradicts its own table on whether `cancelled` satisfies a `blocks` gate. A closed vocabulary section that pins event names but not statuses has pinned the decoration and left the load-bearing member free.

The three new architecture-breaking defects, all in new material:

1. **AD-22's shutdown order does the exact opposite of what AD-22 says it does.** `:rest_for_one` terminates children in reverse listing order, so `Bee.Export` (child 4) terminates *before* `Bee.Repo` (child 2). AD-22 claims "shutdown is strictly reverse, so export flushes after the writer drains." It does not. The stated guarantee — DevMan's JSONL mirror is not stale — is inverted by the mechanism chosen to provide it.
2. **AD-21 blesses an in-memory cycle graph, which cannot participate in AD-19's transaction.** A `:digraph` mutated during a check that later rolls back retains a phantom edge, permanently and silently corrupting every subsequent cycle check.
3. **Effort has two homes again.** AD-12 says effort is a registered measurement and "metadata is never a source of numbers bee computes on." Migration 002 adds `issues.estimate`. This is H1/H16 reconstituted in the Migration Plan, in violation of AD-18, which the same spine introduced to prevent it.

Severity key unchanged: **CRITICAL** = silently wrong answers in production; **HIGH** = incompatible artefacts requiring rework of a landed epic; **MEDIUM** = divergence caught at integration; **LOW** = cosmetic.

---

# JOB A — Closure Audit

| # | Prior hole | Status | Closed / left open by |
| --- | --- | --- | --- |
| H1 | Parent has two storage locations | **CLOSED** | AD-18 |
| H2 | Dep direction + gate predicates | **PARTIAL** | AD-13 (direction ✓, gates ✗ — status vocab & `close_reason` undefined) |
| H3 | Writer-internal reads | **CLOSED** | AD-2b |
| H4 | Transaction boundary | **PARTIAL** | AD-19 (`SAVEPOINT` not in the prohibition list) |
| H5 | "Exactly one event" granularity | **PARTIAL** | AD-7 + event vocabulary — which *contradict each other* |
| H6 | Two legal event call sites | **OPEN** | AD-7 vs Capability Map vs Structural Seed — three statements, two modules |
| H7 | Payload envelope | **PARTIAL** | AD-8 (envelope ✓; key source, `actor`/`at` home, `refs` vocabulary ✗) |
| H8 | Measure units | **CLOSED** | AD-9 + Registered measures |
| H9 | `dims` grammar | **CLOSED** | AD-9 |
| H10 | `include:`/`detail:` precedence | **PARTIAL** | AD-10 (caller wins ✓; `load:` unmodelled, withheld key for it missing) |
| H11 | `withheld` / `refine` shape | **CLOSED** | AD-11 + Withheld reason keys |
| H12 | Traversal bypasses interpreter | **PARTIAL** | AD-4 (SQL confined ✓; `via:` grammar unspecified) |
| H13 | Classifier totality | **CLOSED** | AD-3 |
| H14 | Two FTS owners | **CLOSED** | AD-15 FTS clause |
| H15 | Intent-usage counting | **PARTIAL** | AD-20 (table ✓; whether it is a command, and its event obligation, ✗) |
| H16 | "Total effort" source | **PARTIAL** | AD-12 (closed in the AD, **reopened by Migration 002**) |
| H17 | Id boundary | **PARTIAL** | AD-24 (parser ✓; Projection's position relative to L2 reduction ✗) |
| H18 | `bee:` registry | **CLOSED** | AD-14 |
| H19 | raise-vs-tuple | **PARTIAL** | AD-25 (line drawn ✓; unknown `dep_type` unclassified, no atom for it) |
| H20 | Boot / shutdown ordering | **PARTIAL** | AD-22 (boot ✓; **shutdown guarantee is inverted** — see N1) |

**Tally: 8 CLOSED / 11 PARTIAL / 1 OPEN.**

## Shared Vocabularies coverage against the ten shapes I flagged

| Shape flagged | Covered? |
| --- | --- |
| Event names | ✅ closed set of 14 — but see H5/N2, the set contradicts AD-7's granularity rule |
| Withheld keys | ✅ closed set of 7 |
| Error atoms | ⚠️ closed set of 10, but incomplete — no atom for an unknown `dep_type`, unregistered dimension key, or invalid measurement unit at intake vs registration |
| Measure units | ✅ four measures, one unit each |
| Dims grammar | ✅ AD-9 |
| Dep direction | ✅ AD-13 |
| Id form | ✅ AD-24 — boundary position still soft (H17/N9) |
| `bee:` keys | ✅ reserved-and-unused |
| `refine` shape | ✅ keyword list, always present — except for rollups, which have no meaningful refine (N8) |
| Payload envelope | ⚠️ envelope given by example, not by grammar |
| **Status vocabulary** | ❌ **absent** — and AD-13 is written in terms of it |
| **`close_reason` vocabulary** | ❌ **absent** — and AD-13's `conditional-blocks` row depends on it |
| **`via:` grammar** | ❌ absent — AD-3 and AD-12 both reference it |

---

## H2 — PARTIAL — direction is pinned, gates are not

AD-13 pins `dependencies(issue_id, depends_on_id, dep_type)` with `depends_on_id` as blocker, ratifies `graph.ex:29`, fixes the PK, and pins one-hop readiness. That closes the inversion hazard cleanly. Three things remain open, and each splits a pair of units:

**(a) The table contradicts its own prose.** The `blocks` row says "`issue_id` is ready when `depends_on_id` is `closed`." The paragraph directly beneath says "A `cancelled` blocker **satisfies** a `blocks` gate." Unit A implements the table: a cancelled blocker is not closed, so it gates forever. Unit B implements the prose. Both cite AD-13. Since `cancelled` is not in any vocabulary, Unit A can also reasonably hold that `cancelled` *is* a value of `status` alongside `closed`, or that it is a `close_reason` on a `closed` row — three readings, three different ready-sets.

**(b) `close_reason` exists nowhere else in the spine.** The `conditional-blocks` row reads "closed with a failure `close_reason`". No column, no migration (001–004 do not add it), no vocabulary of failure reasons. Unit A adds `close_reason TEXT` in migration 002 and defines failure as `close_reason IN ('failed','abandoned')`. Unit B stores it in `metadata` — forbidden for numbers by AD-12 but not for strings — and defines failure as anything non-null. `conditional-blocks` therefore gates differently on the same data.

**(c) No status enum.** `issue.status_changed` is a sanctioned event name whose payload carries `fields.status`; AD-8 makes payloads SQL-transparent so L3 can aggregate on it; nothing constrains the value set.

**Tightening.** Add to Shared Vocabularies: **Statuses** — the closed set, with exactly one terminal-success and one terminal-failure member — and **Close reasons** — the closed set, with which members count as failure for `conditional-blocks`. Then rewrite the `blocks` row to say "`depends_on_id` is in a terminal status (`closed` **or** `cancelled`)" and delete the contradicting sentence. Add `close_reason` to migration 002 explicitly.

## H4 — PARTIAL — `SAVEPOINT` is not in the prohibition

AD-19 forbids `Bee.Store.*` from issuing `BEGIN`/`COMMIT`/`ROLLBACK`. It does not mention `SAVEPOINT`/`RELEASE`/`ROLLBACK TO`. Unit A (`Bee.Store.Labels.sync/2`) wraps its label diff in `SAVEPOINT labels … RELEASE`, correctly observing it issues none of the three forbidden statements and gaining per-step recovery. Unit B (`Bee.Repo`) rolls the whole command back on a later failure and finds the labels partially applied where the savepoint was released — a partial command commit, which is exactly the failure AD-19 was written to prevent, achieved without violating a word of it. The prior review's tightening named a single `checkpoint/1` owner for this; the revision dropped it.

**Tightening.** Extend AD-19's prohibition to `SAVEPOINT`, `RELEASE`, `ROLLBACK TO`. Reinstate the grep test: no transaction-control keyword outside `repo.ex`.

## H5 — PARTIAL — the event vocabulary contradicts the granularity rule (see N2 below)

## H6 — **OPEN** — the two-emitter hole has regressed (see N3 below)

## H7 — PARTIAL — envelope by example, not by grammar

AD-8 pins the top level (`fields`/`rejected`/`refs`), after-values-only, and the truncation sentinel. Three sub-shapes are still example-only:

- **`fields` keys.** The example uses `status`. Nothing says keys are *exactly the column names, snake_case, no aliases*. Unit A emits `assigned_to`; Unit B emits `assignee` (the Detail-levels vocabulary in this same spine calls it "assignee"). `json_extract(payload,'$.fields.assigned_to')` sees half the data.
- **`rejected` shape.** `["priority"]` — a bare array, so the *reason* for rejection is lost. But the Return-shapes convention says commands return a report naming applied and rejected fields, and AD-25 owns a closed reason-atom list. Unit A emits `["priority"]`; Unit B emits `{"priority": "invalid_value"}` to preserve the report content. Array vs object at the same JSON path: every L3 query on rejections breaks on one of them.
- **`refs` vocabulary.** `refs.comment_id` is the only example. Dependency events need a ref; AD-24 says ids are prefixed strings; is it `refs.dep = {"issue_id":"GC-1","depends_on_id":"GC-2","dep_type":"blocks"}` or `refs.depends_on_id = "GC-2"`? Unspecified.
- **`actor` and `at`.** Prior review asked for these to be pinned as columns. The revision does not say. Unit A puts `actor` in `fields`, Unit B in a column.

## H10 — PARTIAL — caller wins, but the withheld key for it does not exist

AD-10 now says plainly "the caller's `detail:`/`include:` governs the output", which closes the precedence question. Two residues:

- The `load:` vs `include:` split was not adopted, so **the intent's internal materialisation is not a spec field**. AD-3's classifier "pattern-matches exhaustively on `Bee.Query.Spec`", so every field must have a lane row. If an intent widens materialisation without a field, the classifier cannot see it and a `:compact` caller can trigger an unbounded compute-lane load classified `:fast`.
- When an intent loads a relation and Projection strips it, which withheld key? The vocabulary offers `:not_loaded` — which is *false*, it was loaded. The prior tightening named `:detail_level`; the revision dropped it and did not substitute. Unit A reports `:not_loaded` (wrong but available); Unit B reports nothing (nothing fits) — and AD-11's whole purpose is defeated silently.
- `:not_loaded` is doing double duty as a **withheld reason key** and as the **sentinel value** AD-10 mandates for an unloaded relation. Same atom, two meanings, one of which appears inside a result field and the other inside the withheld map.

## H12 — PARTIAL — `via:` has no grammar

AD-4's confinement of SQL to three modules is a clean close, and L2-as-spec-builder is now explicit. But the prior tightening specified `via:` as "edge types, direction, and max depth"; the revision references `via:` in AD-3 and AD-12 and never defines it. Unit A builds `via: [types: [:blocks], dir: :up, depth: 5]`; Unit B builds `via: %{edge: "blocks", direction: :ancestors, max_depth: nil}`. Both satisfy AD-3's row ("`via:` present ⇒ `:compute`") and the exhaustive struct match, because the field exists in both. The Interpreter can compile one. Additionally `:depth_cap` is a sanctioned withheld key, which asserts a cap exists — with no stated default, so two traversals of the same graph return different node sets and both report `:depth_cap` honestly.

## H15 — PARTIAL / H16 — PARTIAL / H17 — PARTIAL / H19 — PARTIAL / H20 — PARTIAL

Each expanded as a fresh finding below: N4 (H15), N5 (H16), N9 (H17), N10 (H19), N1 (H20).

---

# JOB B — Fresh attack on the new material

## N1 — CRITICAL — AD-22's shutdown order inverts the guarantee AD-22 exists to provide

**The AD.** AD-22 lists `:rest_for_one` children in order: (1) `Bee.Store.Migrate`, (2) `Bee.Repo`, (3) `Bee.Read.Pool`, (4) `Bee.Export`, (5) `Bee.Store.Locks.Sweeper`. It then states: "Shutdown is strictly reverse, so export flushes after the writer drains." AD-17 makes the same claim: "a flush on terminate **after** the writer has drained (AD-22)."

**The mechanism.** An OTP supervisor terminates children in **reverse of the start order**. Reverse of that list is: Sweeper, **Export**, Pool, **Repo**. `Bee.Export` runs its `terminate/2` flush while `Bee.Repo` is still alive and still holding unprocessed messages in its mailbox. Any command that lands between Export's flush and Repo's own termination is committed to SQLite and **never mirrored to JSONL**.

**The two units.**
- **Unit A — `Bee.Application`.** Writes the child list exactly as AD-22 dictates. Fully compliant. Ships the stale-mirror bug.
- **Unit B — `Bee.Export`.** Reads AD-17's guarantee as binding on its own behaviour and implements `terminate/2` as *"synchronously call `Bee.Repo` to drain, then flush"*. Fully compliant with AD-17. Deadlocks or times out whenever the writer is mid-shutdown, and under a supervisor-initiated shutdown with a bounded timeout it is killed brutally with the flush half-written — a **torn JSONL file**, which is worse than a stale one, because AD-17 declares the format a consumer contract and `import_jsonl/3`'s only idempotency mechanism (a blanket `rescue`, `export.ex:106`) is scheduled for removal.

**Why nobody catches it.** Both units test in isolation. The failure surfaces only on a clean daemon restart under load, and manifests as DevMan reading a mirror missing the last few mutations — indistinguishable from debounce lag.

**Tightening.** Either (a) list `Bee.Export` **before** `Bee.Repo` (children: Migrate, Export, Repo, Pool, Sweeper) so reverse-order shutdown terminates Repo first and Export last — but then Export must tolerate a not-yet-started writer at boot; or (b) preferably, **make the flush the writer's responsibility**: `Bee.Repo.terminate/2` performs the final synchronous export handoff, and `Bee.Export` holds no terminate-time obligation at all. State explicitly in AD-22 that OTP terminates in reverse *start* order and name which child terminates first, with the reasoning shown — the current phrasing is a mechanism claim, and it is wrong.

Secondary, same AD: `Bee.Store.Migrate` is child 1 of a `:rest_for_one` supervisor and a "transient task". A transient child that exits `:normal` is not restarted — correct. But `:rest_for_one` means **if `Bee.Repo` crashes, children 3–5 restart and child 1 does not**, so migrations do not re-run. That is intended. It also means if the *supervisor* restarts (parent crash), migrations re-run against an already-migrated DB — safe under `user_version` gating, but AD-15's "mandatory pre-migration backup via `VACUUM INTO`" then fires on **every supervisor restart**, writing a full database copy on a crash loop. Unit A backs up before the `user_version` check (AD-15 lists backup as "mandatory pre-migration"); Unit B backs up only when the version gate says work is pending. Unit A fills the disk during a crash loop. **Pin the order: version check first, backup only if steps are pending.**

## N2 — CRITICAL — the event-name vocabulary contradicts AD-7's one-event-per-command rule

**The two ADs.** AD-7: "**One accepted command emits exactly one event**, regardless of how many fields it touched." Shared Vocabularies (event names): `issue.updated`, `issue.status_changed`, `issue.assigned`, `issue.reparented`, `issue.labelled`, `issue.unlabelled`, `dep.added`, … — a **per-facet** name set.

**The command.** `Bee.update("GC-1", status: :closed, assigned_to: "claude", parent: "GC-9", labels: ["a"])`. One accepted command. One event, per AD-7. **Which name?**

- **Unit A — `Bee.Repo` update handler.** Emits `issue.updated` with all four facets in `fields`. Reasoning: one command, one event, and `issue.updated` is the general name; the specific names are for commands that *only* do that thing (`Bee.close/2`, `Bee.assign/3`). Compliant.
- **Unit B — `Bee.Repo` update handler (different epic, dep/label writes).** Emits the **most specific applicable** name, `issue.status_changed`, because a status transition is the signal L3 exists to consume and burying it inside a generic `issue.updated` makes transition analysis require scanning every `issue.updated` payload. Also exactly one event. Also compliant.

**The incompatibility.** It is precisely H5, unfixed: `SELECT count(*) FROM events WHERE event_type='issue.status_changed'` counts an implementation-dependent subset of status transitions. AD-7's fix (command granularity) is correct; the vocabulary the revision added **re-introduces field granularity through the naming dimension**. Worse, the vocabulary makes Unit B's reading the more natural one — why enumerate `issue.labelled` and `issue.unlabelled` as separate names at all, if a command that changes labels emits `issue.updated`?

Sub-cases with no answer: does `Bee.create/2` with labels and a parent emit `issue.created` only, or `issue.created` + `issue.labelled` + `issue.reparented` (three events, violating AD-7) — or `issue.created` with the labels in `fields` (then `issue.labelled` is only ever emitted by a label-only command, and label churn is not countable)? Does a no-op update ("accepted" but changed nothing) emit? AD-7 says "one **accepted** command"; "accepted" is undefined.

**Tightening.** Choose one and state it. The safe choice: **the event name is a function of the command, not of the fields.** Publish the mapping as a table — public function → event name — in Shared Vocabularies, e.g. `Bee.update/2 → issue.updated`, `Bee.close/2 → issue.status_changed`, `Bee.assign/3 → issue.assigned`, `Bee.label/3 → issue.labelled`. Then a composite `update` that changes status emits `issue.updated` and L3 finds the transition in `fields.status`, always, with no dependence on which API the caller happened to use. Add: **a command whose accepted delta is empty emits no event.**

## N3 — CRITICAL — two modules are each declared the "sole emitter"

**Three statements in the revised spine:**
- AD-7: "**`Bee.Store.Events` is the only emitter**, called only by `Bee.Repo`."
- Capability → Architecture Map: "Event capture | **`Bee.Write.Events`** | AD-7, AD-8, AD-19".
- Structural Seed: `write/events.ex  # sole emitter (AD-7)` **and** `store/events.ex` — both files listed.

**The two units.**
- **Unit A — Epic "event log".** Implements `Bee.Store.Events.emit/2` per AD-7's literal text, called from `Bee.Repo`. Leaves `write/events.ex` unimplemented as dead scaffolding.
- **Unit B — Epic "write path".** Implements `Bee.Write.Events.emit/2` per the capability map and the seed's own comment, and treats `Bee.Store.Events` as the read surface (which is what the prior review's tightening actually proposed). Also called from `Bee.Repo`.

**The incompatibility.** This is H6 verbatim, and the revision made it *worse* by adding a third assertion rather than removing one. A command touching both epics emits twice; the "fix" of deleting one call site silently drops events for the commands routed through the other. AD-7's own prevention clause — "(b) two emitters double-writing" — is defeated by the spine's own module map.

Additionally: AD-19 binds `Bee.Store.*` as "pure DML, never issue BEGIN". If the emitter is `Bee.Write.Events`, it is not in `Bee.Store.*` and AD-19 does not bind it — so nothing forbids it opening a transaction. If the emitter is `Bee.Store.Events`, AD-4's SQL confinement covers it (`Bee.Store.*` is a listed SQL site) but `Bee.Write.Events` is **not** one of AD-4's three SQL modules — so under the capability map's reading, **the sole emitter is forbidden from writing SQL**. The two readings are not merely divergent; one of them is internally impossible.

**Tightening.** Delete `write/events.ex` from the structural seed. Correct the capability map row to `Bee.Store.Events`. Restate AD-7 as: "`Bee.Store.Events.emit/2` is the only function that inserts into `events`; it is called only from `Bee.Repo` command handlers; `Bee.Store.Events` also provides the read surface and contains no other write."

## N4 — HIGH — AD-20's `intent_usage` write is not a command, and AD-19 does not describe it

**The probe.** AD-20: intent usage is "updated by an **asynchronous coalesced write dispatched to `Bee.Repo`**." AD-19: "`Bee.Repo` opens exactly one transaction **per accepted command** and commits it." AD-7: "one accepted **command** emits exactly one event" and "**`events.issue_id` is `NOT NULL`**."

**Is a usage write a command?**
- **Unit A — `Bee.Intent.Registry`.** Yes: it is dispatched to `Bee.Repo`, so it goes through the command path, gets its own transaction per AD-19 — and per AD-7 must emit exactly one event. There is no event name for it in the closed vocabulary, and `events.issue_id` is `NOT NULL` with no issue in sight. Unit A resolves this by adding `intent.invoked` to the vocabulary and `issue_id = 0` — reintroducing **exactly the event-log pollution AD-20 exists to prevent**, while formally obeying AD-7 and AD-19.
- **Unit B — `Bee.Query` telemetry path.** No: usage is not a mutation of domain state, so it is a privileged non-command write inside `Bee.Repo` (`handle_cast({:usage_flush, counts}, …)`) that opens its own transaction, emits nothing, and is invisible to AD-19. Now `Bee.Repo` has **two write paths**, one of which no AD governs — and AD-19's "exactly one transaction per accepted command" is silent about whether a non-command write may run between a command's DML and its post-commit side effects.

**Further undefined, and each splits units:** the coalescing window (10ms? 1s? on-terminate only?); the increment semantics (`count = count + 1` per call vs `count = count + N` per flush — under Unit A's per-call reading the "coalesced" adjective is meaningless and the writer takes one transaction per read, which inverts AD-2's entire performance argument); whether `last_used_at` is the flush time or the read time; and whether a usage write can be lost on shutdown (AD-20 says yes, acceptable — but AD-22's shutdown order says nothing about draining the coalescer, so the loss window is unbounded).

**Tightening.** State it explicitly in AD-20: "**an `intent_usage` write is not a command.** It is a `handle_cast` on `Bee.Repo` that opens its own transaction, emits no event, is never interleaved with an open command transaction, and flushes on a fixed N-second timer and on writer terminate. AD-19's one-transaction-per-command rule is scoped to commands; this is the only sanctioned non-command write, and adding another is a spine amendment." Pin the window and the `ON CONFLICT DO UPDATE SET count = count + excluded.count` form.

## N5 — CRITICAL — AD-21 blesses an in-memory cycle graph that cannot be transactional

**The AD.** AD-21: cycle checks run "**inside the command transaction** via AD-2b"; and "**whether the check is a recursive CTE or a maintained in-memory graph is an implementation choice**; that the guarantee survives is not."

**The two units.**
- **Unit A — `Bee.Graph.Acyclic` (CTE).** Issues `WITH RECURSIVE` through `Bee.Query.Interpreter` with the writer's connection injected, inside the transaction, per AD-2b. Sees the in-flight edge. If the transaction rolls back, the edge vanishes from the DB and from every future check. Correct.
- **Unit B — `Bee.Graph.Acyclic` (maintained `:digraph`).** Keeps the ETS-backed `:digraph.new([:acyclic])` that AD-21 explicitly identifies as today's mechanism. To check whether a new edge creates a cycle, it must **add the edge to the digraph** — that is how `:digraph` with `[:acyclic]` reports a cycle: `add_edge/3` returns `{:error, {:bad_edge, path}}`. Explicitly sanctioned by AD-21.

**The incompatibility.** Unit B's digraph is **process state, not transaction state**. AD-19 mandates one transaction per command that may fail *after* the cycle check — an FK violation on `depends_on_id`, a `NOT NULL` on the event, a `busy_timeout` expiry (AD-23 sets 5000ms, so this is reachable), a crash. On rollback, SQLite discards the edge; the digraph keeps it. From that moment, `Bee.block/3` rejects a legitimate future edge as `{:error, :cycle}` — or, on the reverse case (an edge deleted in a rolled-forward path but never removed from the graph), **accepts a real cycle**. AD-21 names cycle acceptance "the single most dangerous silent regression available here" and then licenses the implementation that produces it.

Compounding: AD-22 restarts `Bee.Repo` under `:rest_for_one` without restarting `Bee.Store.Migrate`. If the digraph is rebuilt in `Bee.Repo.init/1` a restart heals it; if it lives in a separate ETS table or its own process, a `Bee.Repo` restart leaves the divergence in place forever. AD-22 does not list `Bee.Graph.Acyclic` as a child, so its lifecycle is undefined — a third unit makes it a supervised sibling and it survives every writer restart, corrupt.

**Tightening.** Remove the implementation freedom. AD-21 should read: "**the check is a recursive CTE executed through `Bee.Query.Interpreter` on the writer's connection inside the command transaction (AD-2b).** No in-memory graph is maintained, because process state cannot roll back with the transaction and a divergence between the two is undetectable. The `:digraph` at `graph.ex:6` is removed only after the CTE check and its rejection test land." Measured density is ~13% over 2,687 issues; the CTE is not a performance concern.

## N6 — HIGH — Migration 002 is two migrations wearing one number

**The rules.** AD-15: "**One transaction per migration**, and `PRAGMA user_version = N` is the **last statement inside** that transaction"; "`PRAGMA foreign_keys=OFF` **must precede `BEGIN`** for any table rebuild (it is a silent no-op inside a transaction)"; "`IF NOT EXISTS` is forbidden"; "individual statements are strict and unconditional".

**The migration.** 002 does four things: add `issues.metadata`; add `projects.metadata`; add `issues.estimate`; **adopt the useful consumer `projects` columns as first-class bee columns and fold the rest into `projects.metadata`.** The fourth is a table rebuild — folding columns *away* means dropping them, and SQLite cannot drop a column that is indexed or referenced; against a live database with 19 consumer-injected columns of unknown index status, the safe form is create-new/copy/drop/rename.

**The two units.**
- **Unit A — "migration 002".** Honours "one transaction per migration" literally: one `BEGIN`, all four steps, `user_version = 2`, `COMMIT`. Because the rebuild is inside the transaction, its `PRAGMA foreign_keys=OFF` is the silent no-op AD-15 itself warns about, and the copy-and-rename trips FK enforcement (which AD-23 has just turned **ON** for every connection — it is currently `0` in production, so this failure mode is *new*).
- **Unit B — "migration 002".** Honours the FK rule literally: `PRAGMA foreign_keys=OFF` outside, then splits into 002 (additive columns, one transaction, `user_version = 2`) and 003 (the `projects` rebuild, one transaction, `user_version = 3`) — because a rebuild and an `ADD COLUMN` cannot share a transaction under both rules simultaneously. This renumbers everything downstream: the Migration Plan's 003 and 004 shift, and the "Hard ordering constraint" that ties gc_daemon's de-injection to "migration 001/002" now points at the wrong number.

**Both are forced by AD-15; the two rules are jointly unsatisfiable for 002 as written.**

Secondary, same row: 002 says gc_daemon "keeps reading the same names and stops `ALTER`ing." But AD-15 tolerates "additional columns on bee tables". So if the de-injection release slips — and the spine's own "Hard ordering constraint" flags this as the risk — gc_daemon re-`ALTER`s a column that 002 just folded into `metadata`, bee boots fine (tolerated), and the same datum now lives in a column *and* in `metadata`, with bee reading one and gc_daemon writing the other. Silent, and structurally identical to H1.

**Tightening.** Split 002 into **002 (additive: `issues.metadata`, `projects.metadata`, `issues.estimate` — see N7, `close_reason`) and 003 (`projects` rebuild)**, renumber 003→004 and 004→005, and state per migration whether it requires a table rebuild and therefore an out-of-transaction `PRAGMA foreign_keys=OFF`. Add a column to the Migration Plan table: "rebuild? Y/N". Add to AD-15: "a migration that requires a table rebuild contains **only** that rebuild."

## N7 — CRITICAL — effort has two homes again: AD-12 vs Migration 002

**The two statements.**
- AD-12: "**Effort is a registered measurement (`measure: "effort"`), latest value per issue — `metadata` is never a source of numbers bee computes on.**" Shared Vocabularies registers `effort` with unit **minutes**.
- Migration Plan 002: "Add `issues.metadata`, `projects.metadata`, **`issues.estimate`**".

`issues.estimate` is governed by no AD. Nothing says what it is for, what unit it carries, or who reads it.

**The two units.**
- **Unit A — `Bee.Graph.Rollup`.** Sums the latest `effort` measurement per node, contributing `0` and incrementing `withheld[:missing_measure]` for nodes without one. Exactly AD-12.
- **Unit B — write path / `Bee.Store.Issues`.** Accepts `Bee.update("GC-1", estimate: 90)` writing `issues.estimate`, because migration 002 added the column and columns exist to be written. Unit B is not violating AD-12 — it never touches `metadata`, and AD-12 only forbids `metadata` as a number source. It never claims `estimate` is effort.

**The incompatibility.** Every consumer that sets an estimate uses the column, because it is the obvious affordance and it is in the schema; every rollup reads measurements; rollups over the real tree return `0` with `withheld[:missing_measure]` equal to the node count, while the data sits in a column three feet away. AD-12's specific nightmare — "a 69-node tree where 60 nodes lack estimates rolling up to a confident, tiny, wrong number" — is realised in full by the spine's own migration plan. This is AD-18 ("one storage location per relationship") violated by the document that introduced AD-18, one section later.

Compounding: `issues.estimate` has no unit. `effort` is registered as **minutes**. A consumer writing `estimate: 2` means two *points* or two *hours*; AD-9's registry protects `measure` names and does not reach columns.

**Tightening.** **Delete `issues.estimate` from migration 002.** If a column is genuinely wanted for query performance, it must be declared in AD-12 as a *derived cache of the latest `effort` measurement, written only by the measurement intake path, never by a public API*, with its unit stated as minutes — and even then it contradicts AD-12's "no materialisation, no cache". The clean answer is to remove it.

## N8 — HIGH — a rollup's result shape is not the query envelope, and `refine` has no meaning for it

**The probe.** AD-3 classifies `rollup:` as a spec field ⇒ `:compute` lane. AD-4 says every read resolves to a `Spec` executed by the Interpreter. So a rollup **is** a query, and the Return-shapes convention plus AD-11 say every query result is "a map with `withheld` and `refine`", both always present.

**The two units.**
- **Unit A — `Bee.Graph.Rollup`.** Returns `%{total: 1440, unit: :minutes, nodes: 69, withheld: %{missing_measure: 60}, refine: []}`. Compliant with the envelope. But `refine: []` violates AD-11's *purpose*: `refine` is "a keyword list of options that would return more", and **no option cures a missing measurement** — the cure is to go record one. An always-present-but-always-empty `refine` trains consumers to ignore it.
- **Unit B — `Bee.Graph.Rollup`.** Reads AD-12's "a rollup with any missing effort is **never reported as a bare number**" as a shape mandate and returns `{:partial, %{total: 1440, missing: 60}}` — a third return shape, neither `{:ok, …}` nor the query map — reasoning that a caller that pattern-matches `%{total: t}` will use `t` as if it were the answer, which is exactly what AD-12 forbids.

**The incompatibility.** Both defensible. Unit A's satisfies the conventions and defeats AD-12's intent (the total *is* reported as a number, next to a footnote). Unit B's satisfies AD-12's intent and breaks the universal result contract, so no generic consumer, telemetry handler, or projection can handle it. And AD-12's `withheld[:missing_measure]` is a **count of nodes**, while every other withheld key counts *rows withheld from the result* — a telemetry handler summing `withheld` values across queries is now summing two different units.

Also unresolved: AD-12 says external gates are "reported separately as external gates, never merged into totals" — is that a third top-level key on the rollup result? Under what name? And is it in the closed withheld vocabulary (it is not — `:scope` is the nearest and means something else)?

**Tightening.** State the rollup result shape verbatim in AD-12, including a `unit:` key sourced from the measure registry, an explicit `external_gates:` key, and — the important part — **`total: nil` when any node is missing effort**, with the partial sum under a separate key (`partial_total:`). That makes AD-12's prohibition structural rather than advisory: a caller cannot accidentally use the number, because there is no number. Add a `:missing_measure` note to AD-11 saying its value counts nodes, not rows.

## N9 — HIGH — Projection's position in the pipeline is unpinned, and rollup member ids can escape integerised

**The two rules.** AD-24: "**everything internal** — traversal, rollups, event payloads, measurement rows, candidate reasons, export JSONL — uses prefixed strings. Conversion to integer happens in exactly one place: `Bee.Query.Projection`, on the way out." AD-10: "Id integerisation is *projection, not enrichment*: it happens at **every** detail level including `:minimal`."

**Where does Projection sit?** AD-1 forbids upward edges, so L2 (`Bee.Graph.Rollup`) calls down into L1 and receives whatever L1 returns.

- **Unit A — `Bee.Query.Interpreter`.** Projection is the last stage of the interpreter, unconditionally (AD-10: "every detail level"). So L1 hands `Bee.Graph.Rollup` rows whose ids are **integers**. The rollup reduces over them, and its `member_ids` are integers — violating AD-24's "rollups use prefixed strings", through no fault of the rollup, which never converted anything.
- **Unit B — `Bee.Query.Interpreter`.** Projection is a separate stage the *facade* invokes, so internal callers (L2, `Bee.Write.Candidates`) get unprojected prefixed-string rows and only public exits integerise. Satisfies AD-24. But then **Projection has two call sites** (the facade for L1 results, the facade again for L2 results) and AD-10's "every detail level" has no meaning inside L2, where detail was never requested.

**The escape.** Under Unit A, a rollup returning `member_ids` goes to the facade. The facade does not re-project (already projected). Those integers are correct. But `Bee.Graph.CriticalPath` consuming the same rollup needs prefixed strings to build a follow-up `via:` spec, so it re-parses integers back through `Bee.Store.Id` — and **integer → prefixed string is not a total inverse** unless every issue in the database shares one prefix. bee ids are prefixed (`GC-2691`); nothing in the spine says the prefix is global. If a second project ever gets its own prefix, the round-trip is ambiguous and silently produces ids for the wrong project. AD-24 pins the parser and does not pin its *invertibility*.

Under Unit B, `Bee.Write.Candidates` — declared to use prefixed strings — is fine, but `Bee.Export` is called from outside the query path entirely (`Bee.export/1`, and the debounced flush), so nothing routes it through Projection at all; AD-24 declares export uses prefixed strings, which is consistent, but the *rule* ("conversion in exactly one place") is then vacuously true for a path that never converts.

**Tightening.** State the pipeline explicitly: `Interpreter → rows (prefixed strings, unprojected)` → consumed by L2/L3/candidates as-is → **`Bee.Query.Projection` is invoked exactly once, by `Bee.ex` (the facade), on whatever is about to leave the library**, whether it came from L1, L2 or L3. Then add: "**integerisation is one-way and lossy; no internal code path ever converts back.** If a prefix is not globally unique, integerisation is a spine amendment."

## N10 — HIGH — AD-26's parity harness cannot distinguish an intended break from a regression

**The rules.** AD-26: "asserts **identical results** for `get`, `list`, `ready`, `count`, `tree_page` across a fixed spec corpus. Documented behaviour changes are declared as parity exceptions with a reason."

**The problem.** The spine declares breaking changes that touch **every item in the corpus**:
- AD-11: every result now carries `withheld` and `refine`. Old `get`/`list`/`ready`/`count`/`tree_page` carry neither.
- AD-10: relations are `:not_loaded` sentinels, never `[]`/`nil`/absent keys — so old and new `get` differ on every unrequested relation.
- AD-24 + AD-10: id integerisation at every detail level, including `:minimal`.
- Return shapes convention: commands return `{:ok, report}`, "never a naked value" — and names `agent_load/2`, `who_blocks_whom/1`, `bottlenecks/1` as the declared breaks, **none of which are in AD-26's corpus**. So the three functions the spine explicitly says are breaking are the three the harness does not test.

**The two units.**
- **Unit A — parity harness.** Compares the whole return value. Every single corpus item fails on day one. To get a green harness, Unit A adds a blanket parity exception: "envelope added to all results." The harness now asserts nothing about the corpus, because the exception covers the entire diff.
- **Unit B — parity harness.** Normalises before comparing: strips `withheld`/`refine`, coerces `:not_loaded` to `[]`, coerces ids to a common form. Green immediately. But the normaliser now **hides the exact regressions the harness exists to catch** — a projection that drops `assignee` at `:compact`, an id integerised from the wrong prefix, a `withheld` that under-reports. Unit B's harness passes a build where `list` silently truncates, because truncation shows up in `withheld`, which the normaliser strips.

**The incompatibility.** Both harnesses are green. Neither proves anything. And because AD-26 binds "the whole migration effort", whichever lands first becomes the sole evidence that the refactor is safe.

**Tightening.** AD-26 must (a) **enumerate the parity exceptions in the spine**, one line each, tied to the AD that causes them — an exception not listed here is a regression; (b) state that comparison is on the **unenveloped domain value**, and that `withheld`/`refine` are asserted by a **separate, positive** assertion set (for corpus specs known to withhold, the harness asserts the expected key *and count*, not just presence); (c) extend the corpus to the three declared-breaking functions with *before/after shape* assertions rather than identity; (d) forbid normalisation of anything not on the exception list — the normaliser is the attack surface, so it must be a whitelist, not a transformation.

## N11 — MEDIUM — AD-2b and AD-19 disagree about when candidates are computed

AD-16: candidates are "computed via AD-2b" — i.e. on the writer's connection, inside the command, so they observe uncommitted state. AD-19: "Side effects (export debounce, telemetry, **candidate computation**) fire **after** commit, never inside."

- **Unit A — `Bee.Write.Candidates`.** Runs inside the transaction (AD-16 + AD-2b). Candidates reflect the issue just created — which is what a *create returning candidates* needs. Cost: an FTS query plus label and project scans hold the single write lock, on the hottest path in the system.
- **Unit B — `Bee.Repo`.** Runs after commit on the writer's connection (AD-19), which is legal under AD-2b (still the writer's connection, still not `Bee.Read`). Cost: the writer is blocked on FTS with the pool idle — the head-of-line blocking AD-3 exists to eliminate, relocated onto the writer. And if the caller's reply is sent before candidates are ready, the return shape changes; if after, the writer is serialised on analytics.

Both are compliant with the ADs they cite, and the ADs cite each other. **Tightening:** AD-16 and AD-19 must agree in one place. Recommended: candidates are computed **after commit, on the writer's connection, and returned in the command reply** — and AD-19 gains a note that this is a deliberate writer-latency cost, bounded by a query timeout, with a stated fallback (`candidates: :not_computed`, plus `withheld[:not_loaded]`) when the timeout fires, so a slow FTS never blocks a create.

## N12 — MEDIUM — AD-25's error-atom list is incomplete for the write-rejections the spine mandates

AD-13 mandates "unknown types are rejected at write". AD-9 mandates "an unregistered measure or a unit mismatch is rejected at write" (covered: `:unknown_measure`, `:unit_mismatch`) and "keys `^[a-z][a-z0-9_]*$`" — with no stated rejection atom. AD-18 gives `:unwritable_dep_type` for `parent-child` specifically. So:

- **Unit A — `Bee.Store.Deps`.** `dep_type: "blocked-by"` is an invalid value for a closed vocabulary field ⇒ **raises `ArgumentError`** per AD-25 ("invalid spec field", closed set, typo is a programmer error) — the same reasoning AD-25 uses for unknown core intent atoms.
- **Unit B — `Bee.Store.Deps`.** Returns `{:error, :unwritable_dep_type}`, reusing the only available atom — which AD-18 defined to mean something else entirely (a *known* type that is projected, not written). A consumer now cannot distinguish "you typoed the type" from "parent-child lives in a column".
- Invalid dimension key: Unit A raises; Unit B returns `{:error, :invalid_dimension_key}`, an atom not in the closed list, so it is by definition a spine violation — arrived at by trying to obey AD-9.

**Tightening.** Add `:unknown_dep_type` and `:invalid_dimension_key` to the error-atom vocabulary, and add a sentence to AD-25: "a value rejected against a closed *data* vocabulary returns a tuple; only a malformed *structure* raises."

---

## Summary of new findings

| # | New hole | Severity | AD(s) |
| --- | --- | --- | --- |
| N1 | AD-22's `:rest_for_one` shutdown order inverts its own guarantee; backup-on-every-restart | CRITICAL | AD-22, AD-17, AD-15 |
| N2 | Event-name vocabulary re-introduces field granularity that AD-7 forbids | CRITICAL | AD-7 + Shared Vocabularies |
| N3 | Two modules each declared "sole emitter"; one of the readings is internally impossible | CRITICAL | AD-7, AD-4, AD-19, Capability Map, Seed |
| N5 | AD-21 licenses an in-memory cycle graph that cannot roll back with the transaction | CRITICAL | AD-21, AD-19, AD-2b, AD-22 |
| N7 | `issues.estimate` (migration 002) gives effort a second home, violating AD-18 | CRITICAL | AD-12, AD-18, Migration Plan |
| N4 | `intent_usage` write: command or not? AD-7's NOT NULL makes the command reading impossible | HIGH | AD-20, AD-19, AD-7 |
| N6 | Migration 002 is two migrations; AD-15's txn rule and FK rule are jointly unsatisfiable for it | HIGH | AD-15, Migration Plan |
| N8 | Rollup result shape vs the universal query envelope; `refine` meaningless for rollups | HIGH | AD-12, AD-11, AD-3, AD-4 |
| N9 | Projection's pipeline position unpinned; integerisation is lossy and re-parsed internally | HIGH | AD-24, AD-10, AD-1 |
| N10 | Parity harness cannot separate intended break from regression; corpus omits the declared breaks | HIGH | AD-26 |
| N11 | Candidates: AD-16 says in-transaction, AD-19 says post-commit | MEDIUM | AD-16, AD-19, AD-2b |
| N12 | Error-atom vocabulary incomplete for mandated write rejections | MEDIUM | AD-25, AD-13, AD-9 |

## Recommended amendment set (v2)

1. **AD-22 rewritten** — correct the shutdown mechanism; move the terminate flush onto `Bee.Repo`; version-check before backup (N1).
2. **AD-7 + event vocabulary** — event name is a function of the command, published as a function→name table; empty delta emits nothing (N2, H5).
3. **AD-7 + Capability Map + Seed reconciled** — `Bee.Store.Events` is the sole emitter; delete `write/events.ex` (N3, H6).
4. **AD-21 tightened** — cycle check is a recursive CTE inside the transaction; no in-memory graph (N5).
5. **Migration 002 amended** — delete `issues.estimate`; add `close_reason`; split the `projects` rebuild into its own migration and renumber (N6, N7, H2).
6. **AD-20 amended** — an `intent_usage` write is explicitly not a command; pin the window and the upsert form (N4, H15).
7. **AD-12 amended** — verbatim rollup result shape with `total: nil` on incompleteness, `unit:`, `external_gates:` (N8).
8. **AD-24 amended** — pin Projection's single invocation point at the facade; declare integerisation one-way (N9, H17).
9. **AD-26 amended** — enumerate parity exceptions in the spine; compare unenveloped values; whitelist normalisation; extend the corpus (N10).
10. **AD-16/AD-19 reconciled** — candidates post-commit on the writer connection, with a timeout fallback (N11).
11. **AD-19 amended** — `SAVEPOINT`/`RELEASE`/`ROLLBACK TO` added to the prohibition; grep test reinstated (H4).
12. **Shared Vocabularies extended** — **Statuses**, **Close reasons**, **`via:` grammar**, `:unknown_dep_type`, `:invalid_dimension_key`; a withheld key for loaded-but-not-projected; disambiguate `:not_loaded`'s double duty (H2, H10, H12, N12).
13. **AD-8 amended** — `fields` keys are exactly column names; `rejected` is an object keyed by column with a reason atom; `refs` vocabulary; `actor`/`at` are columns (H7).
14. **AD-13 corrected** — the `blocks` row and the `cancelled` sentence contradict; pick one (H2).

## Cross-cutting observation

The v1 fault was *ADs delegating wire format*. The v2 fault is different and, in one way, more dangerous: **the same fact is now stated in more than one place, and the statements disagree.** N3 (two sole emitters), N7 (two effort homes), N11 (candidates in vs after the transaction), and H2's `blocks` row vs its own paragraph are all the same shape — a spine long enough to repeat itself, without a rule that each fact has exactly one home.

That rule is already written down. It is AD-18. Applied to the document instead of the schema — **one storage location per fact** — it resolves four of the five criticals mechanically: the Capability Map and Structural Seed should *reference* ADs, never restate them; the Migration Plan should never introduce a column no AD governs; and no AD should describe a behaviour another AD already owns.
