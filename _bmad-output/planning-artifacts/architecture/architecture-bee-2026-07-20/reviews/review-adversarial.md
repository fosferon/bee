---
review: adversarial
target: ARCHITECTURE-SPINE.md (bee, 2026-07-20)
reviewer: adversarial-reviewer
date: '2026-07-20'
method: 'Construct pairs of one-level-down units that each obey every AD to the letter yet build incompatibly. Every pair is a hole.'
---

# Adversarial Review — bee Architecture Spine

## Verdict

**The spine is strong on layering and weak on shared shapes.** Every AD is defensible in isolation; the failures are all *between* ADs. I constructed 20 concrete unit pairs where two agents, both fully compliant, produce artefacts that cannot coexist. Three of them (H1 parent duality, H2 direction/gating semantics, H3 writer-internal reads) are architecture-breaking rather than convention-breaking: they produce silently wrong answers, not merge conflicts.

The generative fault is that the spine governs **who may act** thoroughly and **what shape the acted-upon data takes** barely at all. AD-1/2/3/4 are airtight ownership rules. AD-7/8/9/11/13 name a concept and leave its wire format to the implementer. An architecture spine that hands two agents the same table with no shape contract has not constrained them.

Severity key: **CRITICAL** = silently wrong answers in production; **HIGH** = incompatible artefacts requiring rework of a landed epic; **MEDIUM** = divergence caught at integration; **LOW** = cosmetic drift.

| # | Hole | Severity | AD(s) |
| --- | --- | --- | --- |
| H1 | Parent relationship has two legal storage locations | CRITICAL | AD-12, AD-13 |
| H2 | `dep_type` edge direction and gate predicates undefined | CRITICAL | AD-13 |
| H3 | Writer-internal reads: connection and snapshot undefined | CRITICAL | AD-2, AD-4 |
| H4 | Transaction boundary defined nowhere | CRITICAL | AD-7, AD-2 |
| H5 | "Exactly one event" — mutation granularity undefined | HIGH | AD-7 |
| H6 | Event emission has two legal call sites | HIGH | AD-7 |
| H7 | Event payload envelope shape undefined | HIGH | AD-8 |
| H8 | Measurement units unconstrained; bee sums incompatible measures | CRITICAL | AD-9 |
| H9 | `dims` key naming/casing/null-form unconstrained | HIGH | AD-9 |
| H10 | `include:`/`detail:` — caller vs core intent, no precedence rule | HIGH | AD-10 |
| H11 | `withheld` reason keys and `refine` shape uninvented | HIGH | AD-11 |
| H12 | Graph traversal may legitimately bypass the Interpreter | HIGH | AD-4, AD-1 |
| H13 | Classifier is not a total function; borderline specs split | HIGH | AD-3 |
| H14 | Two owners of the FTS index content and its sync mechanism | HIGH | AD-14, AD-15, AD-16 |
| H15 | Intent-usage counting contradicts AD-7 and AD-2 | HIGH | AD-5, AD-7, AD-2 |
| H16 | "Total effort" has no defined source field | HIGH | AD-12, AD-9 |
| H17 | Id representation boundary and parse-function owner ambiguous | MEDIUM | Conventions |
| H18 | `bee:` metadata namespace has no registry | MEDIUM | AD-14 |
| H19 | raise-vs-tuple line undrawn | MEDIUM | Conventions |
| H20 | Boot ordering: pool vs migrations vs export flush | MEDIUM | AD-15, AD-17 |

---

## H1 — CRITICAL — The parent relationship has two legal storage locations

**Unit A — Epic "Graph rollups" / Story `Bee.Graph.Rollup` scope `:tree`.**
AD-12 says "the rollup unit is the parent tree." The ER diagram in the spine shows `ISSUES ||--o{ ISSUES : parent` — a self-referencing column. Unit A implements the `:tree` scope selector as a recursive CTE over `issues.parent_id`. Fully AD-12 compliant, AD-1 compliant, AD-2 compliant.

**Unit B — Epic "Dependency vocabulary" / Story `Bee.Store.Deps` write path.**
AD-13 says "the vocabulary is exactly `blocks`, `parent-child`, `conditional-blocks`, `waits-for` … and `related`, `discovered-from`, `replies-to`. Unknown types are rejected at write." Unit B therefore implements `parent-child` as a first-class writable row in `dependencies`, and `Bee.Graph.Ready` reads children by selecting `dep_type = 'parent-child'` — required, because AD-13's `waits-for` rule literally says it "gates on all of a node's children", and the only children Unit B can see are edge rows.

**Both obey every AD.** Neither AD forbids the other's storage.

**The incompatibility.** After both land, an issue created through the write path that sets `parent_id` is invisible to `Ready`; an issue whose parent was expressed as a `parent-child` edge is invisible to `Rollup`. The failure is silent: rollups return plausible-but-short totals, and `waits-for` nodes report ready when children are outstanding. Neither unit's tests fail, because each seeded its own fixture through its own path. Worse, the production DB already has 1349 issues with a parent (per `.memlog.md`), all in a column, so Unit B's `Ready` is dead on arrival against real data — exactly the class of bug already documented in the memlog (`labels` vs `issue_labels`).

**Tightening — new AD-18 (Single storage per relationship).**
> A relationship is stored in exactly one place. `issues.parent_id` is the sole storage for parentage. `parent-child` is **removed from the writable `dep_type` vocabulary**; if traversal wants a uniform edge view, `Bee.Graph.Traverse` may *project* virtual `parent-child` edges from `parent_id` at read time, and writing one is rejected with `{:error, :parent_is_a_column}`. Any future relationship that is both a column and an edge type must be resolved before its story is written, not during it.

---

## H2 — CRITICAL — Edge direction and gate predicates are undefined; two units will invert them

AD-13 names seven types and says "readiness is computed from edge type, never assumed." It never says which end of the edge gates.

**Unit A — Story `Bee.Graph.Ready`.** Reads `dependencies(from_id, to_id, dep_type)` and interprets `A blocks B` as "row from=A, to=B means A gates B." So `ready?(B)` selects rows `WHERE to_id = B`.

**Unit B — Story "write path: `Bee.block/2`".** Implements `Bee.block(issue, on: other)` — "issue is blocked by other" — and, reading the same table with no stated convention, writes `from_id = issue, to_id = other` because the subject of the API call is naturally the `from`. Fully AD-13 compliant (type is in the vocabulary, unknown types rejected).

**The incompatibility.** Every edge is stored backwards relative to how it is read. `ready` inverts across the whole graph. This will not be caught by unit tests on either side — each is internally consistent — and only surfaces as "why does bee say this is ready when it's obviously blocked", which is precisely the class of complaint the spine exists to prevent.

Layered on top, the *gate predicate* is equally undefined even with direction fixed. Consider node X with four inbound edges: a `blocks` from an issue in status `cancelled`; a `conditional-blocks` from an issue that completed successfully; a `waits-for` where X has no children at all; and a `related`.

- Unit A: `ready ⟺ no inbound blocking-class edge whose source is not in a terminal status`. `cancelled` is terminal → satisfied. `conditional-blocks` from a success → AD-13 says it "gates on failure", so satisfied. `waits-for` with no children → vacuously satisfied. **Ready.**
- Unit B: treats `cancelled` as "never completed, therefore permanently unsatisfied" (defensible — the work did not happen); treats `waits-for` with zero children as *not* satisfiable because the semantics are "wait for children to exist and complete"; treats `conditional-blocks` as satisfied only once the condition is *evaluated*, and there is no condition field, so it gates. **Not ready.**

Both read AD-13 literally. Both are defensible. They disagree on every non-trivial node.

Also unspecified: is readiness one-hop or transitive? Unit A checks only direct gates; Unit B recurses (a blocker that is itself blocked is not "really" clear). Different answers, both compliant.

**Tightening — AD-13 replaced with a truth table.**
> Edges are stored `(from_id, to_id, dep_type)` where **`from_id` gates `to_id`** — read as "*from* must be satisfied before *to* is ready". All public write APIs normalise to this orientation, and the normalisation lives in one function, `Bee.Store.Deps.normalise/3`.
>
> | dep_type | class | gate satisfied when source is… | notes |
> | --- | --- | --- | --- |
> | `blocks` | blocking | `done` | `cancelled` **does not** satisfy; use unblock |
> | `conditional-blocks` | blocking | `done` **or** `cancelled` | gates only on failure-to-complete |
> | `waits-for` | blocking | all of *target's* children in `done`/`cancelled`; **zero children ⇒ satisfied** | children read from `issues.parent_id` (see H1) |
> | `related`, `discovered-from`, `replies-to` | non-blocking | always | never gate, never appear in `why_blocked` |
>
> Readiness is the **conjunction over direct inbound blocking edges only — one hop, never transitive.** Self-edges and cycles are rejected at write. A node with zero inbound blocking edges is ready if its own status permits. Adding a `dep_type` requires adding a row to this table in the spine.

---

## H3 — CRITICAL — Writer-internal reads have no defined connection or snapshot

AD-2: "all reads go through `Bee.Read` pooled read-only connections. No module opens its own connection." AD-4: "there is no second way to read." AD-16 requires the write path to compute candidates "from FTS, labels, project and comment references" — i.e. the writer must read. Cycle checking (AD-2's own justification) must read. Nothing in the spine says how.

**Unit A — Story `Bee.Write.Candidates`.** Reads on the writer's own RW connection, inside the mutation transaction. Justification: AD-2 says no module opens *its own* connection — it isn't; it's using `Bee.Write`'s. This sees uncommitted state, which is what a cycle check needs.

**Unit B — Story "create returns candidates".** Calls `Bee.query/1` from inside the writer's `handle_call`. Justification: AD-4 says there is no second way to read, and AD-1 permits nothing about writers bypassing the query layer, so going through the Interpreter is the *more* compliant choice.

**The incompatibility.**
1. **Deadlock/starvation.** Unit B's writer blocks on a `Bee.Read` pool checkout while holding the only write connection. Under a compute-lane burst (AD-3 sizes `:compute` at 1–2) the single writer stalls behind analytics — the exact head-of-line blocking AD-3 exists to prevent, reintroduced on the write side.
2. **Different answers.** WAL gives readers an MVCC snapshot taken at checkout. Unit B's cycle check reads a snapshot that **excludes the edge currently being inserted**, so a two-edge cycle inserted in one command passes validation. Unit A's does not. This is a correctness divergence, not a performance one.
3. Whichever lands second inherits a codebase where the other convention is already load-bearing.

**Tightening — AD-2 gains a clause; AD-4 gains an explicit carve-out.**
> **AD-2b.** Reads performed *by the writer, for the purpose of validating or enriching the command in flight* execute on the writer's own connection, inside the command transaction, so they observe uncommitted state. The writer **must never** call `Bee.Read` or `Bee.query/1`; doing so is a defect. `Bee.Query.Interpreter.run/2` accepts an injected connection precisely so the writer can reuse the one execution path without touching the pool — this satisfies AD-4 rather than excepting it. Every SQL statement the writer issues still originates in the Interpreter or `Bee.Store.*`; the writer authors none.

---

## H4 — CRITICAL — The transaction boundary is defined nowhere

AD-7: events emit "inside the writer, in the same transaction as the mutation." No AD says who opens that transaction. SQLite does not support nested `BEGIN`.

**Unit A — Story "comments".** `Bee.Store.Comments.insert/2` wraps its insert + event in `BEGIN … COMMIT`, reading AD-7 as a per-operation obligation. Compliant.

**Unit B — Story "update issue".** `Bee.Write.Server.handle_call({:update, …})` opens one transaction around the whole command: update fields, update labels (which calls `Bee.Store.Labels`), insert event, compute candidates. Compliant, and arguably more correct — AD-7's "exactly one event per mutation" implies command-level atomicity.

**The incompatibility.** The moment a command handler that opens a transaction calls a Store function that also opens one, SQLite raises `cannot start a transaction within a transaction`. This is a hard runtime error, so it *will* be caught — but only after both epics have landed and only in the integration path that crosses them, and the fix is a rewrite of whichever side loses. Worse is the partial case: Unit A's Store function commits mid-command, so a later failure in the same command leaves the comment persisted and the event missing — violating AD-7 without any code violating AD-7.

Related and unaddressed: is the AD-16 candidate computation inside the transaction (holding the write lock while running FTS) or after commit? Is the AD-17 export debounce notification fired pre- or post-commit? Two units will differ, and a pre-commit export notification on a rolled-back transaction writes a JSONL file describing state that never existed.

**Tightening — new AD-19 (One transaction per command).**
> Exactly one database transaction per accepted command, opened and committed **only** by `Bee.Write.Server`. `Bee.Store.*` functions are pure DML: they never contain `BEGIN`, `COMMIT`, `ROLLBACK`, or `SAVEPOINT`, and are only callable from within an open command transaction. Multi-step commands use `SAVEPOINT` via `Bee.Write.Server.checkpoint/1`, never a nested `BEGIN`. Side effects that are not database writes — candidate computation, export debounce notification, telemetry — execute **after commit**, never inside the transaction. A test asserts no `BEGIN` string exists outside `write/server.ex`.

---

## H5 — HIGH — "Every mutation emits exactly one event": two implementers will disagree on what one mutation is

**Unit A — Story "update issue".** `Bee.update("GC-1", status: :done, priority: 2, title: "…", assigned_to: "claude", labels: ["a","b"])` emits **one** `issue.updated` event whose payload names five field changes plus a label delta. Reading: one API call = one mutation = one event.

**Unit B — Story "labels and assignment".** Emits `issue.updated` for the scalar fields, plus `label.added`/`label.removed` per label, plus `issue.assigned` — because labels live in a satellite table and each row insert is *a* mutation, and because AD-7 binds "all of L3", which needs label churn as a distinguishable signal. Reading: one row change = one mutation = one event.

**Both obey AD-7 to the letter.** The AD does not define its own unit.

**The incompatibility.** Every L3 metric that counts events — churn, cadence, flapping, time-to-first-touch, rework — reads a different number depending on which epic wrote the mutation being measured. This is not a merge conflict; it is a permanently poisoned dataset, and AD-7's whole justification is that events are the asset L3 exists to consume. It is also unrecoverable: you cannot retroactively re-derive the intended granularity from a mixed log.

Adjacent, same root: does `create` with labels and a parent emit one event or four? Does `close` emit `issue.updated` **and** `issue.closed`, or one of them? Does a no-op update (new value equals old) emit? Unit A skips it; Unit B emits, because "the caller mutated." Does a *rejected* field (see the "Update results" convention: mutations report which fields were applied and which rejected) appear in the event? Unit A includes rejections; Unit B logs only what was applied.

**Tightening — AD-7 gains a definition and a vocabulary.**
> **One mutation = one accepted public write API call.** Exactly one event per command, emitted once by the command handler after all DML in that transaction, carrying the *complete* delta including satellite tables (labels, deps, assignment) in its payload. Satellite tables never emit their own events. A command that applies zero changes emits **no** event. Rejected fields are recorded in the payload under `rejected`, never as a separate event.
>
> Event names are a closed, spine-owned vocabulary in `Bee.Write.Events`, formatted `<entity>.<past-tense-verb>`: `issue.created`, `issue.updated`, `issue.closed`, `issue.reopened`, `issue.cancelled`, `comment.added`, `dependency.added`, `dependency.removed`, `lock.claimed`, `lock.released`, `measurement.recorded`. A close emits `issue.closed` **only** (never also `issue.updated`). Adding a name is a spine amendment.

---

## H6 — HIGH — Event emission has two legal call sites

The structural seed lists **both** `bee/write/events.ex` ("event emission (same txn as mutation)") **and** `bee/store/events.ex`. AD-7 binds "`Bee.Write`, `Bee.Store.Events`". The capability map says event capture lives in `Bee.Write.Events`. Three statements, two modules, no ownership rule.

**Unit A — Story "comments".** Emits from `Bee.Store.Comments`, calling `Bee.Store.Events.insert/1` — it's the module doing the insert, it has the ids, and `Bee.Store.Events` is named in AD-7's binds.

**Unit B — Story "dependency writes".** Emits from the `Bee.Write.Server` command handler via `Bee.Write.Events.emit/2` — per the capability map.

**The incompatibility.** A command that touches both paths emits twice or, once someone "fixes" the duplicate by deleting the Store-level call, not at all for commands that only go through Store. Combined with H5, the event log becomes unusable as an analytics substrate. This also silently breaks AD-1's spirit: `Bee.Store.Events` being callable from sibling `Bee.Store.*` modules makes L0 self-entangled.

**Tightening — AD-7 gains a single call site.**
> `Bee.Write.Events.emit/2` is the **only** function that writes to `events`, and it is called **only** from `Bee.Write.Server` command handlers. `Bee.Store.Events` is the read/query surface for the events table (used by L1/L3) and contains no insert. `Bee.Store.*` mutation modules never reference events. Enforced by a test.

---

## H7 — HIGH — The event payload envelope has no defined shape

AD-8 constrains payloads to JSON, size, and "text fields store the after value only." It does not define the envelope, key casing, or the before/after representation for non-text fields.

**Unit A — Story "status transitions".** Payload: `{"from": "open", "to": "done", "actor": "claude"}` — status is not a text field, so before/after is retained, and it's the shape L3 wants for transition analysis.

**Unit B — Story "field updates".** Reads AD-8's "store the after value only" as universal, not text-specific: `{"status": "done", "priority": 2, "title_hash": "…"}`.

Both compliant. AD-8's sentence is genuinely ambiguous about whether "text fields" is a restriction or an example.

**The incompatibility.** AD-8's stated *purpose* is that payloads stay "transparent to SQL, so `json_extract` aggregation works." Every L3 query must now be written twice: `json_extract(payload,'$.to')` and `json_extract(payload,'$.status')`. The expression indexes AD-9 sanctions can only cover one. And L3 is deferred, so nobody finds out until the data is a year old.

Further undefined: casing (`assigned_to` vs `assignedTo`); whether keys mirror column names exactly; the truncation sentinel shape (Unit A: `{"title": {"hash":…,"len":…,"preview":…}}`; Unit B: `{"title_hash":…, "title_len":…}` — different `json_extract` paths, and Unit B's makes "was this truncated?" unanswerable); whether `actor` lives in the payload or a column.

**Tightening — AD-8 gains a canonical envelope.**
> Every payload is an object with a fixed top level:
> ```json
> {"fields": {"<column_name>": {"before": <v|null>, "after": <v>}},
>  "rejected": {"<column_name>": "<reason_atom>"},
>  "refs": {"comment_id": 12, "dep": {"from": "GC-1", "to": "GC-2", "type": "blocks"}}}
> ```
> Keys under `fields` are **exactly the column names**, snake_case, no aliases. `before` is present for all typed columns; for text columns above the size cap, both `before` and `after` are replaced by `{"truncated": true, "hash": "<sha256>", "len": <int>, "preview": "<first 120 chars>"}` and `before` may be omitted entirely per AD-8. `actor` and `at` are **columns on `events`**, never payload keys. Absent sections are omitted, never `null`.

---

## H8 — CRITICAL — Measurement units are unconstrained; bee will sum incompatible measures

AD-9: "bee partitions on dimension values and performs arithmetic on measures; it never branches on what a dimension value *means*." Bee is explicitly licensed to do arithmetic on measures and explicitly forbidden from understanding them.

**Unit A — Story "measurement intake on close".** Records `measure: "duration", value: 3600` — seconds, because ISO/SQL-adjacent code defaults to seconds.

**Unit B — Story "measurement intake on update" (a different epic, agent-timing signal).** Records `measure: "duration", value: 3600000` — milliseconds, because `System.monotonic_time(:millisecond)` is what the caller had.

**Both obey AD-9 perfectly.** AD-9 forbids bee from having an opinion — so it has none, and sums them.

**The incompatibility.** `SUM(value) WHERE measure = 'duration'` produces a number that is meaningless by a factor of 1000, with no error, no warning, and no way to disentangle after the fact. Because AD-9 explicitly makes bee agnostic, *no amount of downstream care fixes this* — the agnosticism is the vulnerability. This is the sharpest instance of the general problem: AD-9 gives bee arithmetic authority over values whose comparability it refuses to police.

**Tightening — AD-9 gains a measure registry.**
> `measure` names are registered, not free text. A `measures` table holds `(name, unit, aggregation)` where `unit` is a closed enum (`:seconds`, `:count`, `:bytes`, `:points`, `:ratio`) and `aggregation` is `:sum | :mean | :max | :last`. Intake with an unregistered `measure` is **rejected at write** (`{:error, :unknown_measure}`) — registration is a cheap runtime call, exactly like AD-5's registered intents, so this costs nothing and closes the hole. Bee still never interprets what a measure *means*; it only refuses to add seconds to milliseconds. Aggregation across differing units is rejected, not coerced. Canonical names carry no unit suffix; the registry is the single source of truth.

---

## H9 — HIGH — `dims` key naming, casing, and empty-form are unconstrained

AD-9 keeps dimensions "schemaless" and sanctions expression indexes on `json_extract(dims,'$.k')`.

**Unit A — Story "intake piggybacks on update".** Writes `{"issue_type": "bug", "agent": "claude", "project": "GC"}`.

**Unit B — Story "retroactive `measure/2`".** Writes `{"issueType": "Bug", "Agent": "Claude", "project_id": "GC"}` — camelCase because it mirrors a JSON API payload it received, capitalised values because it passed them through verbatim (AD-9 says bee never interprets values, so it doesn't normalise them either).

**Both compliant.** Nothing in AD-9 constrains keys.

**The incompatibility.** `GROUP BY json_extract(dims,'$.agent')` sees half the data. The expression index built by whichever epic landed first is useless to the other. `"bug"` and `"Bug"` are different partitions of the same population. And since AD-9 is precisely the AD that makes bee "simultaneously agnostic and useful", a fragmented dimension space makes it agnostic and useless.

Also undefined: is absent-dims stored as `NULL`, `'{}'`, or `''`? Three units, three answers; `json_extract` on `NULL` returns `NULL` and silently drops the row from every `GROUP BY`. Is key order canonicalised? If dims are ever hashed or compared for equality, insertion order breaks it.

**Tightening — AD-9 gains a dims grammar.**
> Dimension keys match `^[a-z][a-z0-9_]{0,39}$`; violations are **rejected at write** (`{:error, {:invalid_dimension_key, key}}`). Values are coerced to strings and stored verbatim — bee still never interprets them — but keys are bee's namespace and bee owns them. Dims serialise with keys sorted, so the JSON text is canonical and hashable. Absent dims store `'{}'`, never `NULL`; the column is `NOT NULL DEFAULT '{}'`. A `dimensions` table records seen keys with a first-seen timestamp and count, so the vocabulary is discoverable without a migration — this is what makes the constraint cheap.

---

## H10 — HIGH — `include:`/`detail:` — no precedence rule between caller and core intent

AD-10: detail defaults `:compact`; relations "never loaded unless requested via `include:`". AD-5: core intents "may run arbitrary Elixir" and exist for ranking and aggregation — which needs data the caller did not request.

**Unit A — Story "core intent `:ready_work`".** Ranking needs labels and dependency counts. Caller says `detail: :compact`. Unit A overrides to `:full` internally *and returns* `:full` rows, reasoning that the intent knows what its answer requires. Compliant: it "requested via `include:`", just on the caller's behalf.

**Unit B — Story `Bee.Query.Projection`.** Treats caller options as authoritative and final, per AD-10's plain reading — the whole AD exists to stop "indiscriminate output consumers then had to trim themselves." So it clamps the spec's detail down to the caller's `:compact` before execution, starving any intent that needed more.

**The incompatibility.** Whichever lands first defines the semantics. If Unit A's, AD-10's entire purpose is defeated — intents quietly return `:full` and the N+1-avoidance win is kept but the payload-size win is lost. If Unit B's, every core intent that ranks is broken, and AD-5's justification (intents encode knowledge a consumer can't reproduce) evaporates because the intent can't reach the data. Neither agent will discover this; each tests its own layer.

Sub-case with no answer at all: caller asks `include: [:comments]`, intent needs `[:labels]`. Union, caller-only, or intent-only? Three defensible readings. And if the intent loaded labels but the projection strips them, does that count as withheld (H11), and under which reason?

**Tightening — AD-10 separates loading from projection.**
> A spec carries two independent things: `load:` (what the execution must materialise to compute the answer — set by the intent, invisible to the caller) and `detail:`/`include:` (what the result exposes — set by the caller, authoritative). Execution loads `union(load, include)`. **Projection emits exactly what the caller asked for; the caller always wins on output.** Data loaded for computation and not projected is recorded in `withheld` under `:detail_level` with a `refine` hint naming the option that would expose it. An intent may never widen the caller's output; a caller may never narrow the intent's computation.

---

## H11 — HIGH — `withheld` reason keys and `refine` shape will be invented independently

AD-11 gives four example reasons in prose ("truncation, rank cutoff, scope, limit") and names a `refine` hint. No schema.

**Unit A — Story "list queries".** `withheld: %{limit: 340}`, `refine: [limit: 500]`.

**Unit B — Story "core intent `:ready_work`".** `withheld: %{"rank_cutoff" => 12, "truncation" => 3}`, `refine: "pass rank_cutoff: 50 to see more"`.

Atom vs string keys. `limit` vs `truncation` for the same phenomenon (Unit A calls a hit limit `limit`; Unit B calls it `truncation` because rows were truncated). A keyword list the caller can splat back vs. a human sentence. Both fully AD-11 compliant — the AD only forbids *silence*.

**The incompatibility.** The "Query results" convention says results are always a map with `withheld`; the telemetry convention says `[:bee, :query, :stop]` carries "withheld counts". A telemetry handler cannot aggregate a map whose keys are sometimes atoms, sometimes strings, and whose vocabulary is open. Consumers pattern-matching `%{withheld: %{limit: n}}` silently miss Unit B's results — and *silently missing an incompleteness signal* is exactly the failure AD-11 was written to prevent. The AD defeats itself by being unspecified.

Also: is `withheld` present-and-empty (`%{}`) or absent when nothing was withheld? Unit A omits it (smaller payload); Unit B always includes it. Consumers that check `Map.has_key?` break.

**Tightening — AD-11 gains a closed vocabulary.**
> `withheld` is **always present** and is a map with **atom** keys drawn from a closed set, containing only non-zero entries (`%{}` when nothing was withheld):
>
> | reason | means |
> | --- | --- |
> | `:limit` | rows matched but were cut by `limit:` |
> | `:rank_cutoff` | rows scored below a ranking threshold |
> | `:scope` | rows outside the requested project/tree/closure |
> | `:detail_level` | fields computed or loaded but not projected (see H10) |
> | `:not_included` | relations exist but were not requested via `include:` |
> | `:payload_truncated` | a returned text field was truncated per AD-8's cap |
>
> `refine` is a **keyword list of concrete option overrides** the caller can splat back into the identical call — e.g. `[limit: 500, include: [:labels]]` — never prose. Adding a reason key is a spine amendment.

---

## H12 — HIGH — Graph traversal can legitimately bypass the Interpreter

AD-4: "every read resolves to a `Bee.Query.Spec` and is executed by `Bee.Query.Interpreter`. There is no second way to read." The dependency graph shows `L2 → L1` (Graph depends on Query), and `L1 → L0R`. So L2 has no legal path to a connection except through L1. But nothing says a `Spec` can *express* a recursive CTE.

**Unit A — Story `Bee.Graph.Traverse`.** Concludes the Spec cannot express `WITH RECURSIVE`, so it writes the CTE in `graph/traverse.ex` and executes it… via `Bee.Read.checkout/2`, which is an L2→L0 call. AD-1 says "a module may depend only on its own layer or one below" — L2's layer-below is L1, so this is an AD-1 violation, but the agent will not see it that way: the mermaid diagram omits an L2→L0R edge, and the prose emphasises "no upward edges", so a *downward* skip reads as permitted. **Compliant by the letter of AD-1's stated rule ("its own layer or one below") only if you count L0 as "below"; the agent will rationalise it.**

**Unit B — Story `Bee.Graph.CriticalPath`.** Extends `Bee.Query.Spec` with a `via:` clause (AD-3 already references `via:` as an existing spec field!) and teaches the Interpreter to emit recursive CTEs. Fully AD-4 compliant.

**The incompatibility.** Two SQL-emitting sites for the same traversal, with different cycle handling, different depth defaults, different `parent-child` handling (see H1), and — critically — Unit A's path never passes through AD-11's withheld accounting or AD-3's classifier, so traversals bypass both the lane assignment and the incompleteness reporting. The spine's two most load-bearing guarantees are silently exempted for the layer most likely to need them.

Note AD-3 already presumes `via:` is a spec field. AD-4 should say so explicitly, because AD-3 mentioning it in passing is not a mandate.

**Tightening — AD-4 gains a grep-able rule.**
> `Bee.Query.Spec` **must** be able to express traversal: `via:` declares edge types, direction, and max depth, and the Interpreter compiles it to a recursive CTE. L2 modules are **spec builders and result reducers**. They hold no connection, call no pool, and contain no SQL. **No SQL string may appear outside `Bee.Query.Interpreter` and `Bee.Store.Migrate` (DDL) and `Bee.Store.*` (single-row DML on the writer's connection).** A test greps for `SELECT|INSERT|UPDATE|DELETE|WITH ` outside those modules and fails the build.

---

## H13 — HIGH — The classifier is not a total function; borderline specs split

AD-3: "A spec carrying traversal (`via:`), a rollup scope, or a statistics selector is `:compute`; everything else is `:fast`." A closed list of three triggers plus a catch-all sounds total. It is not, because the spec grows.

**Unit A — Story "FTS search".** Adds `search:` to the spec. Full-text search over 2686 rows plus a rank sort is heavier than a point read, so Unit A classifies `search:` as `:compute`. AD-3 compliant: it added a trigger, and the AD's *purpose* (protect point reads) argues for it.

**Unit B — Story "shallow neighbourhood read".** Adds a `via: [depth: 1]` fast path — a one-hop join is not traversal in any meaningful sense, so it stays `:fast`. AD-3 compliant: it did not violate the letter, it refined it, and the AD's purpose (protect point reads) argues that a one-hop join is a point read.

**The incompatibility.** After both, `%Spec{search: "foo", via: [depth: 1]}` has two applicable rules with opposite outcomes and no precedence. More corrosive: Unit A introduced *cost-based* classification ("this is heavy") into a rule the spine defined as *shape-based* ("this carries `via:`"). Once cost reasoning is legal, every future spec field is argued case by case, and AD-3's guarantee — "callers never select a lane and cannot get it wrong" — becomes "callers can't get it wrong but bee might."

Your prompt's example — a filtered list over 10k rows — falls out the same way: Unit A adds a row-estimate check and routes it `:compute`; Unit B leaves it `:fast` because the spec shape has no traversal. Both defensible, and the one that routes by row estimate has made classification non-deterministic across databases.

**Tightening — AD-3 gains totality and a precedence rule.**
> Classification is a **total function of spec shape only** — never row estimates, never runtime cost, never data volume — expressed as a single table in `Bee.Query.Classifier`:
>
> | spec field present | lane |
> | --- | --- |
> | `via:` (any depth) | `:compute` |
> | `rollup:` | `:compute` |
> | `stats:` | `:compute` |
> | `search:` | `:fast` |
> | anything else | `:fast` |
>
> **Any `:compute` trigger wins over any `:fast` trigger** (union semantics — a spec is `:compute` if any field says so). Adding a field to `Bee.Query.Spec` **requires** adding its row to this table; the classifier pattern-matches exhaustively on the struct so an undeclared field is a compile-time error. Changing a field's lane is a spine amendment.

---

## H14 — HIGH — Two owners of the FTS index content and its sync mechanism

AD-14 forbids *consumers* from touching bee's DDL. AD-15 gives migration 001 the job of rebuilding FTS. Neither says what FTS indexes, nor how it stays in sync, nor who may add a second index.

**Unit A — Story "migration 001, FTS ownership".** Rebuilds `issues_fts` over `title, description` with the default tokenizer and three triggers (`ai/ad/au`) mirroring what it dropped.

**Unit B — Story `Bee.Write.Candidates` (AD-16).** AD-16 requires candidates "computed from FTS, labels, project and **comment references**." Comments are not in Unit A's index. Unit B is inside bee, so AD-14 does not restrain it, and AD-15 lets it add migration 003 creating `comments_fts` with its own triggers — plus, needing consistent scoring, a `porter unicode61` tokenizer that differs from Unit A's default.

**The incompatibility.** Two FTS tables with two tokenizers, so a candidate's FTS score is not comparable to a search result's rank — and AD-16 requires candidates to carry "a confidence", which is now computed on an incomparable scale. Six triggers instead of three, each firing on every write, on the path AD-17 already worries about.

Sharper sub-hole: **is FTS maintained by triggers or by the application?** Unit A uses triggers (mirrors what it dropped). A third unit — "issue update path" — sees that the writer already has the row in hand and writes the FTS row explicitly, which is faster and avoids trigger opacity. Both compliant. Result: **duplicate FTS rows for every update**, which corrupts ranking and inflates the index, and is very hard to notice because search still returns the right documents, just weighted wrong.

**Tightening — AD-15 gains an FTS clause.**
> Bee has **one** FTS table, `issues_fts`, defined in `Bee.Store.Migrate`: columns `title, description`, tokenizer `unicode61 remove_diacritics 2`, contentless-delete external-content over `issues`. It is maintained **exclusively by triggers** — no application code ever writes to an FTS table; a write to `issues_fts` from `Bee.Write` or `Bee.Store.Issues` is a defect. Indexing additional content (comments) is a spine amendment specifying the table, columns, and tokenizer, and the tokenizer must match `issues_fts` so scores remain comparable. Only `Bee.Store.Migrate` creates, alters, or drops any database object — this restriction binds bee's own modules, not just consumers.

---

## H15 — HIGH — Intent-usage counting contradicts AD-7 and is physically impossible under AD-2

The memlog's AD-5 rationale is load-bearing: "Every `ask/2` call is an event; intent name is a dimension. Usage counts make registration reversible… which is precisely what makes speculative registration safe." Pruning-by-evidence is the argument that keeps the open catalogue from rotting. But:

- AD-7 says `events` is a record of **mutations** ("Every mutation emits exactly one event"). A read is not a mutation.
- The ER diagram shows `ISSUES ||--o{ EVENTS` — events hang off an issue. An `ask` has no issue.
- AD-2 says all reads go through **read-only** connections. A read path physically cannot write its own usage record.

**Unit A — Story "intent registry".** Writes usage rows into `events` with `issue_id = NULL` and `event_type = "intent.invoked"`. Compliant with AD-5's rationale; quietly breaks AD-7's semantics and makes `events.issue_id` nullable, which every L3 query must now defend against.

**Unit B — Story "telemetry".** Concludes reads must not write, and satisfies AD-5's evidence requirement by attaching intent name to the `[:bee, :query, :stop]` telemetry event — leaving usage counting to whoever attaches a handler, i.e. nobody, i.e. the pruning loop never happens and the catalogue rots exactly as AD-5 feared.

**The incompatibility.** Either the event log is polluted with non-mutations (poisoning every L3 aggregate that assumes one row = one state change) or AD-5's safety argument is unimplemented. There is no third option in the current spine, and the two units cannot both be right.

**Tightening — new AD-20 (Read telemetry is not the event log).**
> `events` records **mutations only**; `events.issue_id` is `NOT NULL`. Intent usage is counted in a dedicated `intent_usage(name, kind, count, last_used_at)` table, updated by an **asynchronous, coalesced write dispatched to `Bee.Write`** after the read completes — never on the read connection, never in the read's critical path, never blocking the caller. Losing usage counts on crash is acceptable; polluting the event log is not.

---

## H16 — HIGH — "Total effort" has no defined source field

AD-12: "total effort is the base additive primitive over a node set." bee has no effort column today (`lib/bee/store.ex` issues table).

**Unit A — Story `Bee.Graph.Rollup`.** Reads effort from `metadata['bee:estimate']` — AD-14 sanctions `metadata` with a `bee:` prefix, so this is the sanctioned extension point.

**Unit B — Story "measurements".** Records effort as a measurement with `measure: "effort"` — AD-9 makes measures "numeric and calibratable", which is exactly what effort is, and AD-9 is the AD that binds `Bee.Stats`.

**Both compliant, and Unit B is right**, but nothing in the spine says so.

**The incompatibility.** Rollups over a tree where half the issues got their effort through each path return a total that is neither. And a second divergence sits underneath: **what does a node with no effort contribute?** Unit A treats missing as `0` and returns a number; Unit B propagates `nil` and returns `{:error, :incomplete}`; a third reading returns the partial sum and reports the gap in `withheld` under `:scope`. All three are consistent with AD-11 (which forbids silent truncation but says nothing about missing inputs). Unit A's answer is the dangerous one: a tree of 69 issues where 60 lack estimates rolls up to a confident, tiny, wrong number.

**Tightening — AD-12 names its source and its gap semantics.**
> Effort is a **measurement**, `measure: "effort"` (registered per H8's registry), latest value per issue. `metadata` is never a source of numbers bee computes on. Nodes lacking an effort measurement contribute `0` to the total **and increment `withheld[:missing_measure]` by one**, so every rollup states how much of its own tree it could not see. A rollup where more than zero nodes are missing effort is never reported as a bare number.

---

## H17 — MEDIUM — Id representation boundary and parse-function owner are ambiguous

The convention says "One parse function in `Bee.Store` — never reimplemented." But `lib/bee/id.ex` already exists (47 LOC) and the structural seed does not list it — so is it deleted, moved, or is `Bee.Store` a facade over it? Unit A uses `Bee.Id.parse/1`; Unit B adds `Bee.Store.parse_id/1`. Two parse functions, which is precisely what the convention forbids, arrived at by two agents both trying to obey it.

Deeper: "Internal/storage: prefixed string. Public API… returns integers." Where is the boundary? Unit A (`Bee.Graph.Traverse`) returns prefixed strings from a CTE — internal. Unit B (`Bee.Query.Projection`) converts to integers — public. When L2 hands a result to the facade unprojected (a rollup returning member ids, say), which form escapes? And `withheld`/`refine`/candidate reasons/event payloads all contain ids — in which form? Unit A's event payload has `"GC-2"`; Unit B's has `2`; `json_extract` comparisons across them fail.

**Tightening.** Name the module (`Bee.Store.Id`, `lib/bee/id.ex` deleted or reduced to a delegate) and state the boundary explicitly: **conversion to integer happens in exactly one place, `Bee.Query.Projection`, on the way out.** Everything internal — traversal, rollups, event payloads, export JSONL, candidate reasons — uses prefixed strings. Anything that leaves bee without passing through Projection (export, candidates) must state its form in the spine; DevMan's JSONL contract (AD-17) pins it, so say which it is.

---

## H18 — MEDIUM — The `bee:` metadata namespace has no registry

AD-14 reserves `bee:` and `_` prefixes but nobody owns what goes in them. Unit A writes `bee:estimate`; Unit B writes `bee:effort_estimate`; a third reads `bee:estimate` and finds nothing. The reservation prevents consumer collision and creates internal collision.

**Tightening.** State that `bee:` is **reserved and unused**: bee reads and writes nothing under it. If bee needs a field, it is a column or a measurement, decided in the spine. The reservation exists solely so a future bee feature has room, and claiming a key is a spine amendment. (This also removes H16's Unit A entirely.)

---

## H19 — MEDIUM — The raise-vs-tuple line is undrawn

"`{:ok, result}` / `{:error, reason}` with atom reasons. Argument validation raises `ArgumentError` in the **caller's** process, before any dispatch." Unit A raises on an unknown intent name (it's an argument, validated before dispatch). Unit B returns `{:error, :unknown_intent}` — because registered intents are runtime data, so an unknown one is a data-dependent outcome, not a programmer error. Both readings are correct for *different* intent classes and the spine does not separate them. Consumers writing `case Bee.ask(...)` crash on Unit A's path.

**Tightening.** Draw the line explicitly: **structural/type errors raise** (wrong arity, non-map opts, malformed id, invalid spec field, unknown *core* intent atom — a closed set, so a typo is a programmer error and must fail loudly per AD-5). **Data-dependent outcomes return tuples** (`:not_found`, `:unknown_intent` for registered strings, `:locked`, `:cycle`, `:unknown_measure`). Publish the closed atom-reason list in the spine alongside AD-11's withheld vocabulary.

---

## H20 — MEDIUM — Boot ordering and shutdown ordering are unspecified

AD-15 runs migrations "inside the writer at boot, before anything serves." AD-17 flushes export "on terminate." Neither pins supervision order.

**Startup:** Unit A (`Bee.Read.Pool`) opens read-only connections in `init/1`. Unit B (`Bee.Write.Server`) runs migrations in `init/1`. In a `:one_for_one` supervisor with the pool listed first, the pool opens connections against a pre-migration schema — and read-only connections against a missing table either fail to boot or cache a stale schema, depending on exqlite behaviour. Both units are compliant; the supervisor's child order, an unreviewed detail in a third story, decides correctness.

**Shutdown:** if `Bee.Export` terminates before `Bee.Write.Server`, the final flush precedes the last commits and the JSONL mirror — a *load-bearing* contract for DevMan — is silently one mutation stale. Nobody notices until a DevMan session reads it.

**Tightening.** Pin both in the spine: children start `Bee.Store.Migrate` (a transient task that must return `:ok`) → `Bee.Write.Server` → `Bee.Read.Pool` → `Bee.Export`; shutdown is strictly reverse (`:rest_for_one`), so `Bee.Export` flushes *after* the writer has drained and committed. Add: **`Bee.Read.Pool` refuses to start if `PRAGMA user_version` is below the compiled-in target** — AD-15's fail-loudly rule applied to readers, not just the migration runner.

---

## Cross-cutting observation

Fourteen of these twenty holes are the same failure repeated: **an AD names a concept and delegates its wire format.** `events` payload (H7), `dims` keys (H9), measure units (H8), `withheld` keys (H11), `refine` shape (H11), dep direction (H2), id form (H17), `bee:` keys (H18), event names (H5), error atoms (H19).

The spine already contains the template for fixing all of them — AD-13's closed `dep_type` vocabulary is exactly the right move, applied once. The tightening is mechanical: **every shared shape gets a closed vocabulary or a grammar, in the spine, with "adding a member is a spine amendment" attached.** Roughly two pages of tables. Without them, the ADs constrain who writes and not what is written, and two compliant agents will produce a database that is internally inconsistent in ways no test on either side can see.

## Recommended amendment set

1. **AD-13 replaced** with the direction + gate truth table (H2).
2. **AD-18 new** — one storage per relationship; `parent-child` unwritable (H1).
3. **AD-19 new** — one transaction per command, owned by `Bee.Write.Server`; post-commit side effects (H4).
4. **AD-20 new** — read telemetry is not the event log; `intent_usage` table (H15).
5. **AD-2 + AD-4 amended** — writer-internal reads on the writer connection via an injected-connection Interpreter (H3, H12); no SQL outside three named modules.
6. **AD-7 amended** — mutation = one accepted command; one emitter; closed event-name vocabulary (H5, H6).
7. **AD-8 amended** — canonical payload envelope with `fields`/`rejected`/`refs` and a truncation sentinel (H7).
8. **AD-9 amended** — measure registry with units; dims key grammar; `'{}'` not `NULL`; sorted keys (H8, H9).
9. **AD-10 amended** — `load:` vs `detail:`/`include:`; caller wins on output (H10).
10. **AD-11 amended** — closed withheld vocabulary; `refine` is a keyword list; always present (H11).
11. **AD-3 amended** — total, shape-only classification table; `:compute` wins; exhaustive match (H13).
12. **AD-15 amended** — one FTS table, trigger-only maintenance, fixed tokenizer; DDL only in `Migrate` (H14).
13. **AD-12 amended** — effort is a registered measurement; missing effort reported in `withheld` (H16).
14. **Conventions amended** — `Bee.Store.Id` named and `lib/bee/id.ex` resolved; conversion only in Projection; raise-vs-tuple line drawn; supervision and shutdown order pinned (H17, H19, H20). `bee:` reserved-and-unused (H18).
