---
review: contradiction sweep (round 5, final verification)
target: ARCHITECTURE-SPINE.md (bee, 2026-07-20, v5)
prior: reviews/review-final-v4.md
reviewer: contradiction-hunter
date: '2026-07-20'
method: 'Job A — closure audit of F1–F7, H1–H12, M1–M17 against v5 text, discriminating resolved from relocated. Job B — mechanical extraction of every absolute-bearing token in v5 by the method declared on line 23, reduced to distinct normative absolutes, each checked for [abs] tag, exception list, and list completeness. Job C — full cross-product of v5''s eleven closed lists against its seven tables (77 cells). Job D — adversarial unit-pairing against v5-only material.'
---

# Contradiction Review v5 — bee Architecture Spine

## Verdict

**NEEDS ANOTHER PASS.**

Two things happened in v5, and they point opposite directions.

**The good.** The `[abs]` tagging worked as an instrument. Where a tag exists, the absolute has an exception list, and the lists are mostly right. **26 of the 36 prior findings are CLOSED**, and the biggest one — the export/shutdown paragraph that had failed three consecutive revisions — is genuinely, structurally fixed. Rewriting AD-17 from its requirements rather than amending its text was the correct move and it worked: `Bee.Store.Export` as a pure module with no process removes the supervision slot, the shutdown ordering, the connection question and the dead-process call in a single stroke. F1, F2, F5, F6, F7, H1, H2, H3, H7, H8, H12 are dead and did not move. That is the strongest single revision in this document's history.

**The bad.** Authoring rule 2 was applied *for the third consecutive time as a checklist against the prior review's list*. The `[abs]` marker made the checklist mechanical — but a mechanical checklist over the wrong denominator is still the wrong denominator. v5 carries **35 tags** (36 occurrences, one of which is the rule statement on line 23). v4's sweep named ~40 absolutes at a coarse reduction. The 35 tags land almost exactly on the ~40 v4 enumerated. Applying **v5's own declared extraction method** (line 23's trigger words) to **v5's own text** yields **112 distinct normative absolutes**. So **77 are untagged**, which is a facial violation of the rule stated on line 23, at a *higher* absolute count than v4 had.

> **v5's fault class: the tag was treated as a label to be applied to known absolutes, not as a predicate to be evaluated over the document. Every absolute v4 named is tagged. Almost no absolute v4 did not name is tagged. The instrument changed; the denominator did not.**

And authoring rule 3 — the cross-product rule v5 added specifically to catch F4's class — **fails its own first test**. Line 337 states: *"Cross-checked against AD-19's seven non-command writes per authoring rule 3."* That cross-check is false on the table it annotates: three of AD-19's seven have no row, two of those three are public API functions the document never names anywhere, one non-command write (intent *removal*) is missing from AD-19's closed seven entirely, and the `import_jsonl/2` vs `/3` arity mismatch v4 reported as M9 is still there, on the row directly beneath the claim. The rule was written down and then not executed on the one artefact that cites it.

**New findings: 29** (4 CRITICAL, 11 HIGH, 14 MEDIUM). Down from 35, and the character continues to improve: v4's criticals clustered at three seams; v5's cluster at **one** — the boundary between a closed list and the table that is supposed to enumerate the same thing. That is authoring rule 3's exact subject matter.

**Six findings RELOCATED rather than resolved** (F3, H4, H5, H9, H11, M6, and F2 into a sibling module). This remains the document's characteristic failure mode and it is the reason for the verdict. In every case the *specific mechanism the prior review named* was fixed and the *class* was not swept.

Severity key: **CRITICAL** = silently wrong answers in production, or a rule unsatisfiable as written; **HIGH** = incompatible artefacts requiring rework of a landed epic; **MEDIUM** = divergence caught at integration.

---

# JOB A — Closure audit of the 36 prior findings

**Tally: 22 CLOSED · 9 PARTIAL · 5 OPEN.**
**Relocated rather than resolved: 6** (F3, H4, H5, H9, H11, M6) — plus F2, which closed for the named module and reopened for its sibling (tracked as new finding G2).

## The seven v4 criticals

| # | Status | v5 evidence |
| --- | --- | --- |
| **F1** terminate flush | **CLOSED** | AD-17 rewritten (L248–260). L255: "`Bee.Store.Export` is a pure module with no process. It exposes `flush(conn, path, opts)` and holds no state." L256: "`Bee.Repo` owns the debounce timer and calls `flush/3` on its own connection (AD-2b)". L258: bounded by a work budget with stated expiry behaviour. AD-2b's binds list (L88) now names `Bee.Store.Export`; its rule (L90) explicitly covers "after commit (candidates, **export flush**)". AD-22 L300: "There is no Export child." **All three of F1's sub-defects — dead process, no legal connection, unbounded `:infinity` — are gone, and gone because the design changed, not because the sentence changed.** This is the model for how the rest of the document should be repaired. |
| **F2** no AD-4 category for Export | **CLOSED for Export, REOPENED for its siblings** | L113 adds category 3 verbatim as recommended, and L315 correctly restates AD-24's Projection bypass as *following from* category 3 rather than as an exception to it. Export is now fully categorised. **But clause 1's absolute is "[abs] every read falls into exactly one of three categories, and there are no others" (L110), and the sweep against every *other* reader in the document did not happen.** `Bee.Query.Candidates`, `Bee.Store.Acyclic` and `Bee.Graph.*` all perform reads that fit none of the three. See **G2**. |
| **F3** migration 000 direction | **PARTIAL — RELOCATED** | The direction is now stated (L229: "Its normalisation direction is **additive**: it *creates* AD-14's seven columns where absent and leaves every other pre-existing column in place. It never drops.") and 002 is reduced to the fold (L438: "Adoption happened in 000."). The question v4 asked is answered. **But the answer contradicts the sentence immediately preceding it in the same bullet** — "Migration 000 normalises all three to one identical schema" — and makes migration 002's DROP conditional, violating L230's unconditional absolute. See **G1**. The defect moved from "which direction?" to "the chosen direction breaks the invariant it was chosen to establish." |
| **F4** three `register_*` functions | **CLOSED** | AD-19 L273: "[abs] Sanctioned non-command writes, **exhaustively seven**", naming all three registrations with the `events.issue_id NOT NULL` rationale inline, plus the L3 consequence at L274. Function→event table L350 gives them a row. The specific three are homed. **Cross-product residue at G3** — the *other* three of the seven are not in the table, and an eighth exists. |
| **F5** `conditional-blocks` deadlock | **CLOSED** | L210: "`depends_on_id` is `cancelled`, or `closed` with a `close_reason` **not** in the failure set." The mirror decision is stated inline ("A failure close gates permanently — that is the edge's purpose"). Exactly the recommended edit plus the recommended rationale. Clean. |
| **F6** `fields.measure` shape | **CLOSED** | L149–151 gives the verbatim envelope including `seq`; L155 tags the key exception ("[abs] `fields` keys are exactly the storage column names of the mutated row, with exactly one exception: `measure`"). Both halves landed. Minor note: the envelope's inner key is `"name"` while the storage column is `measure`; the exception covers the whole envelope so this is legal, but an implementer scanning for column-name fidelity will pause. |
| **F7** id-valued columns | **CLOSED** | L156: "[abs] `fields` values are the after-values of those columns, with exactly one class of exception: id-valued columns (`parent`, `project_id`, `assigned_to`) carry **prefixed strings** per AD-24". L157 exempts `refs`. AD-24 L315 mirrors it with "Exception, exhaustively one: `refs`". The example at L149 now shows `"parent": "GC-5"` and `"refs": {"comment_id": 91}` — both consistent. **Resolved, not relocated.** Residue: the *prefix grammar* for `project_id`/`assigned_to` is undefined — see **G12**. |

## The twelve v4 highs

| # | Status | v5 evidence |
| --- | --- | --- |
| **H1** rollup boundary | **CLOSED** | L195: "**The parent-tree boundary applies to `:tree` only**; the other two are defined by their own edges." `:closure` and `:critical_path` are redefined as gating-closure and gating-chain. Exactly the recommended scoping. |
| **H2** `total: integer` vs `REAL` | **CLOSED** | L197: `%{total: float \| nil, partial_total: float, …}` — "`float` because `measurements.value` is `REAL`". The reconciliation is stated in the shape itself. |
| **H3** orphan assertion | **CLOSED** | L236 scopes the orphan check "**to FK relationships bee enforces** — `issues.parent`, `dependencies.*`, `comments.issue_id`, `issue_labels.issue_id`. It excludes `issues.project_id`/`assigned_to` … asserting on them would `ROLLBACK` against production." A different resolution than the recommended before/after delta, and a better one — it scopes by responsibility rather than by arithmetic. |
| **H4** classifier guarantee | **PARTIAL — RELOCATED** | L103 correctly retracts the false compile-time claim and states why ("A compile-time guarantee is not achievable — the catch-all row matches any unknown field"). But the replacement — "A test asserts every `Bee.Query.Spec` field appears in this table" — **is tautological against a table containing a catch-all row.** The recommended enforceable form (compare the struct key set against the classifier's *declared* key set) was not used. See **G14**. |
| **H5** layer table completeness | **PARTIAL — RELOCATED** | A **Facade** row was added (L37) carrying `Bee` and `Bee.Application`, so L43's namespace-coverage absolute is now true. **But the row is unnumbered.** v4's recommendation was "**L4 Facade** … above L3". AD-1's rule is "a module may depend on any layer **below its own**" — a module in an unnumbered row has no "own layer", so AD-1 remains unevaluable for the two modules that mediate the entire public surface and the entire supervision tree. See **G15**. |
| **H6** control-table connections | **PARTIAL** | L84 adds the rule: "**Control-table reads** — `locks`, `intents`, `intent_usage`, `measures` — run on whichever connection their caller already holds; they are ordinary function calls, not connection owners." This resolves `Bee.Store.Locks` (in-command, writer's connection) and `Bee.Store.Intents` (on a read, the reader's checked-out connection) cleanly. **It does not resolve `Bee.Store.Locks.Sweeper`, which is a separate process whose caller holds no connection.** See **G13**. |
| **H7** transactions for non-command writes | **CLOSED** | L273: "**Each still runs in a `Bee.Repo`-owned transaction** — non-command means no event, not no transaction; `import_jsonl/3` uses one transaction for the whole load, not one per row." Both halves. The chosen shape (one transaction for the whole load rather than bounded batches) is a decision, legitimately taken; its cost is uncosted (G23's class). |
| **H8** detail levels | **CLOSED** | L357: `:compact` gains `parent`; `:standard` gains `close_reason`, `closed_at`, `metadata`; `:full` names the six `include:`-able relations including `children`. All four missing fields are homed and the hierarchy relations are named. **Cross-product residue at G4**, against AD-10's own tagged absolute. |
| **H9** registered-spec validation | **PARTIAL — RELOCATED** | AD-5 L120 now says "validated by `Bee.Query.Spec` **at registration time** and rejected with `:invalid_spec`; resolution never validates", and AD-25 L321 mirrors it. The *timing* question is answered. **But moving validation to registration puts it inside AD-25's raise clause**, which mandates `ArgumentError` for "invalid spec field" in caller-supplied arguments — and a registration argument is caller-supplied. Same input, two mandated outcomes. And "resolution never validates" is now a release-boundary injection surface. See **G7**. |
| **H10** "all 19 public functions" | **CLOSED by deletion** | L426 now reads "is every public function's default" — the false count is gone. Substantively PARTIAL: the document still publishes no public surface, so the function→event table's completeness remains uncheckable, which is precisely how **G3** survived. |
| **H11** `:rest_for_one` crash path | **OPEN — RELOCATED** | AD-17 L259 adds a "Crash path" bullet and AD-23 L308 adds "On the crash path neither runs; the next boot's PASSIVE timer recovers." **But both sentences define "crash path" as brutal kill only** ("`terminate/2` does not run on a brutal kill"). H11's scenario was a *trapped* crash: `Bee.Repo` traps exits (L296), so on an ordinary abnormal exit `terminate/2` **does** run — with the Pool still alive, because `:rest_for_one` terminates siblings *after* the crashing child. Every claim H11 attacked is still on the page and still false for that path. See **G5**. This is the clearest relocation in the revision: the term was narrowed until the sentences became true of the case they now describe. |
| **H12** `via:` grammar | **CLOSED** | L359 adds `types: [dep_type]` with "**`types:` defaults to the gating types**", states that `:ancestors`/`:descendants` follow `issues.parent` "not edges", and deletes `:neighbourhood`. All three sub-points. |

## The seventeen v4 mediums

| # | Status | v5 evidence |
| --- | --- | --- |
| **M1** "only Store names a table" | **CLOSED** | L369 appends the reconciling gloss: "consistent with AD-4 clause 2, which permits `Bee.Query.Interpreter` to *construct SQL* over tables named by `Bee.Store`, not to name them." |
| **M2** `foreign_keys=ON` exception | **CLOSED** | L307: "with exactly one exception: the migration connection may set `foreign_keys=OFF` for the duration of a table rebuild (AD-15)". AD-15 L237 carries the reciprocal reference. Bidirectional. |
| **M3** silent-failure list | **PARTIAL** | L376 goes from one exception to "exhaustively three", adding AD-23's crash-path checkpoint and the sanctioned FK orphaning. **The Sweeper in-flight loss v4 named is not among them** — the Sweeper still does not trap exits (L296: `Bee.Repo` is "the only child that does"), so a sweep write in flight at Sweeper termination is lost with no record, and `lock.expired` is the only trace a lock was released. See **G27**. |
| **M4** `NOT NULL` and migration 004 | **CLOSED** | L458: "migrations 003 **and 004** declare it only on new tables and new keys", and L440 adds "The new PK implies `NOT NULL` on `dep_type`, which is already `NOT NULL DEFAULT 'blocks'`." Both the exemption and the fact that closes it. |
| **M5** FK-restore rationale | **CLOSED** | The impossible "writer's connection for the process lifetime" reason is deleted. L237 now reads "The migration connection is exempt from AD-23's always-on rule for exactly this window, and restores it before closing." The rule survives with a true reason. |
| **M6** compiled-in target version | **PARTIAL — RELOCATED** | L297 names an owner: "below `Bee.Store.Migrate.target_version/0`". **The values are still undefined.** The document states exactly one stamp (000 → 1, L229/L436); 001–004 stamp nothing stated; AD-15 L233's "`PRAGMA user_version = N`" has `N` unbound. `target_version/0` is now a named function returning an undefined number, which is where the missing fact went rather than where it was supplied. See **G17**. |
| **M7** AD-6 and timers | **CLOSED** | L127: "[abs] This constrains bee's *domain model*, not its *runtime*. Internal timers (export debounce, lock expiry, WAL checkpoint, usage-count coalescing) are implementation mechanics." All four named. Classification of *lock expiry* is contestable — see **G28** — but the contradiction v4 reported is resolved. |
| **M8** AD-14 prospective | **CLOSED** | L220: "(The current violations are pre-existing and removed by the Hard ordering constraint; this rule is prospective and says so.)" |
| **M9** event-table defects | **OPEN** | (a) L350 still says **`import_jsonl/2`**; AD-17 L260 and AD-19 L273 both say **`/3`**. Unchanged from v4. (b) `Bee.export/1` has no row — now defensibly covered by "all reads \| none" given AD-4 category 3, so this half is effectively closed. (c) The Sweeper is still listed under a column headed "public function". **This is the finding on the very line that claims a cross-check was performed (L337).** Rolled into **G3**. |
| **M10** `dims.kind` default | **PARTIAL — RELOCATED** | L176: "**The intake path sets `dims.kind` to `\"actual\"` when the caller omits it**, so AD-12's grouping key is always populated." The `update/3`/close path is fixed. **`Bee.measure/3` — named in the same sentence as the standalone out-of-band and retroactive path — is given no default**, and v4's recommendation explicitly covered it. The unclassifiable measurement M10 describes is now reachable only via the retroactive path, which is exactly where estimates get backfilled. See **G8**. |
| **M11** core-then-registry | **CLOSED** | L120: "Lookup dispatches on type — atom to core, string to registry — so a core name and a registered name can never collide." The false chain language is gone. (The `String.to_existing_atom/1` atom-exhaustion note was not added; noted, not counted.) |
| **M12** candidates partial pipeline | **OPEN — escalated** | Unchanged, and the addition of AD-4 category 3 for Export made it worse by establishing that uncategorised readers *are* a real problem and then not sweeping for others. Escalated to CRITICAL as **G2**. |
| **M13** `refine` vacuous for rollups | **OPEN** | L188 defines `refine` as "options that would return more"; L197 keeps `refine: [...]` in the rollup shape. No option cures a missing measurement. Unchanged. See **G21**. |
| **M14** seed restates responsibilities | **OPEN — worse** | L392's absolute is unchanged and v5 **added** responsibility assignments elsewhere: L255 (`Bee.Store.Export` exposes `flush/3`, holds no state), L256 (`Bee.Repo` owns the debounce timer), L321 (`Bee.Query.Spec` owns the `order_by` whitelist), on top of v4's L297 and L83. The seed's own line 418 comment ("pure module, no process") is itself a responsibility restated from AD-17. See **G20**. |
| **M15** transient vs maintained graph | **CLOSED** | L287: "**A graph built and discarded entirely within one read is permitted** — `Bee.Graph.CriticalPath` does exactly that, and it is not a cache." Verbatim what was asked for, with the module named. |
| **M16** candidates serialise on the writer | **CLOSED** | L246: "**Accepted cost:** this runs on the single writer, so candidate computation serialises with subsequent commands; the timeout is what bounds the queue." The decision is now recorded as one. |
| **M17** `rejected` example atom | **PARTIAL** | L152 replaces `invalid_value` with `invalid_dimension_key`, which *is* in the vocabulary — but the resulting example, `"rejected": {"priority": "invalid_dimension_key"}`, says the `priority` field was rejected for an invalid dimension key. Dimensions belong to measurements. The normative example now teaches a wrong mapping, and M17's second half — the vocabulary has no general per-field rejection atom — is untouched. See **G19**. |

---

# JOB B — The exhaustive sweep

## Method

I extracted every occurrence of the tokens v5's own line 23 declares as the trigger set, plus the tokens v4 used: `only`, `never`, `no`/`No`, `none`, `always`, `every`/`Every`, `all`/`All`, `sole`/`solely`, `exactly`, `exhaustive*`, `forbidden`, `unconditional*`, `must`, `mandatory`, `any`. I then discarded prose uses, restatements-by-reference (a sentence whose only content is "see AD-N"), and schema facts that carry no normative force beyond the DDL, and reduced the remainder to distinct normative absolutes — claims that a reader could independently violate.

## Headline

| | Count |
| --- | --- |
| `[abs]` occurrences in v5 | **36** |
| minus the rule statement on L23 | **35 tagged absolutes** |
| distinct normative absolutes by the above method | **112** |
| **untagged normative absolutes** | **77** |
| tagged / untagged split | **31% / 69%** |

**The gap is real, and it is larger than v4's, not smaller.** v4 reported ~40 normative absolutes at a coarse reduction and eight exception lists. v5 tagged 35 — which reads as near-complete coverage of a 40-item denominator, and would be, if 40 were the denominator. It is not. The 35 tags map, near one-to-one, onto the ~40 absolutes **v4's review enumerated**. The absolutes v4 did not enumerate are in exactly the state v4's un-enumerated absolutes were in, which was exactly the state v3's were in.

The reduction did not differ. The denominator did.

## The eleven tagged absolutes with materially incomplete or false lists

Of the 35 tags, 24 carry lists that survive scrutiny. Eleven do not:

| # | Line | Tagged absolute | Defect |
| --- | --- | --- | --- |
| 1 | L43 | "Every namespace in the codebase appears in this table; there are no others" | True as to coverage; the Facade row carries no layer level, so AD-1 cannot be evaluated for its members (**G15**) |
| 2 | L110 | "every read falls into exactly one of three categories, and there are no others" | Candidates, Acyclic and Graph reads fit none (**G2**) — CRITICAL |
| 3 | L114 | "SQL string construction occurs only in `Bee.Query.Interpreter` and `Bee.Store.*`; no other module, with no exceptions" | AD-13 L214 mandates `graph.ex:19` filter on `dep_type`, and `Bee.Graph` is neither (**G2**) |
| 4 | L137 | "One accepted command emits exactly one event … Exceptions, exhaustively: the seven" | The Sweeper expiring N locks cannot emit one event with one `issue_id` (**G13**) |
| 5 | L182 | "A relation not loaded carries `:not_loaded` — never `[]`, `nil`, or an absent key; no exceptions" | Unsatisfiable at `:minimal`/`:compact`/`:standard` against the detail-level closed list (**G4**) — CRITICAL |
| 6 | L188 | "Every withheld value counts rows, with exactly one exception: `:missing_measure`" | `:relation_omitted` counts rows that were never loaded (**G6**) |
| 7 | L230 | "From version 1 onward every migration is unconditional and produces one schema; no exceptions" | Migration 002's drop is necessarily conditional (**G1**) — CRITICAL |
| 8 | L273 | "Sanctioned non-command writes, exhaustively seven … Adding an eighth is a spine amendment" | Intent *removal* (AD-5 L120) is an unlisted eighth; the `effort` seed registration cannot satisfy the "Repo-owned transaction" clause (**G3**, **G10**) — CRITICAL |
| 9 | L315 | "Everything internal uses prefixed strings … Exception, exhaustively one: `refs`" | No prefix grammar is defined for `project_id`/`assigned_to` (**G12**) |
| 10 | L376 | "Silent failure: Forbidden, with exceptions exhaustively three" | Sweeper in-flight loss is a fourth (**G27**) |
| 11 | L392 | "No other section restates a responsibility" | False at five sites, three of them added in v5 (**G20**) |

## The 77 untagged normative absolutes

Every one below is a normative claim carrying a trigger token, with **no `[abs]` marker, no inline exception list, and no declaration that it has none.** They are grouped by whether the missing qualification is load-bearing.

### Group A — untagged AND known-false or unsatisfiable (7)

These produce findings in this review.

| Line | Absolute | Why it fails |
| --- | --- | --- |
| L229 | "Migration 000 normalises all three to **one identical schema**" | Contradicted by the next sentence in the same bullet (**G1**) |
| L229 | "It **never** drops" | Correct in itself; jointly with the above, fatal (**G1**) |
| L308 | "`TRUNCATE` at writer terminate, which **succeeds because the pool is already gone**" | False on the trapped-crash path (**G5**) |
| L308 | "**On the crash path neither runs**" | False — on a trapped crash `terminate/2` runs (**G5**) |
| L138 | "Names come from the function→event table, the **sole** naming authority" | Three of AD-19's seven have no row (**G3**) |
| L337 | "**Cross-checked against** AD-19's seven non-command writes per authoring rule 3" | The cross-check demonstrably was not performed (**G3**) |
| L176 | "so AD-12's grouping key is **always** populated" | False via `Bee.measure/3` (**G8**) |

### Group B — untagged AND materially under-qualified (14)

| Line | Absolute | Missing qualification |
| --- | --- | --- |
| L84 | "**Every** other database access borrows a connection from `Bee.Repo` … or `Bee.Read`" | The Sweeper borrows from neither (**G13**) |
| L90 | "The writer **never** calls `Bee.query/1` and **never** checks out from `Bee.Read`" | No exception declared; correct, but the twin absolute at L84 has a hole |
| L103 | "A test asserts **every** `Bee.Query.Spec` field appears in this table" | Tautological against the catch-all row (**G14**) |
| L120 | "resolution **never** validates" | Release-boundary injection surface (**G7**) |
| L120 | "expressing anything `Bee.query` can and **nothing more**" | No mechanism stated for enforcing the upper bound at registration |
| L214 | "Readiness is **one-hop**" | Untagged; interacts with `via:` default depth 3 without either citing the other |
| L221 | "Bee adopts **exactly these seven**" | A closed list with no `[abs]`, load-bearing for G1 and G11 |
| L234 | "Additional tables, columns and indexes are **tolerated**" | This is the sentence that makes L229's "identical" false (**G1**) |
| L297 | "refuses to start if `PRAGMA user_version` is below `target_version/0`" | The value is undefined (**G17**) |
| L301 | "`Bee.Repo` **must** be the last stateful child to terminate" | True on the orderly path only (**G5**) |
| L321 | "**raise** … in the caller's process **before dispatch**" | Collides with AD-5's registration-time validation (**G7**) |
| L321 | "`@order_columns` is **the only thing** preventing SQL injection … and **must survive**" | Not applied at resolution (**G7**) |
| L426 | "is **every** public function's default" | Unverifiable — no public surface is published (**G3**) |
| L432 | "Governing rules are in AD-15 and are **not restated**" | L436 restates two of them (**G18**) |

### Group C — untagged, and correct as far as I can determine (56)

Listed for completeness of the sweep. Each carries a trigger token and no marker; each survived cross-checking against the rest of the document. **They are still facial violations of line 23** and each should either be tagged with "no exceptions" or reworded.

L21 (rule 1: every fact in exactly one place) · L25 (rule 3: no revision adds a closed list and a table without multiplying them) · L74 (may depend on any layer below; same-layer legal) · L96 (classification never uses row estimates, never data volume) · L112 (control-table reads never leave the library) · L113 (export projects no fields, applies no filters, emits every row) · L120 (a core name and a registered name can never collide) · L126 (no domain concept of capacity/availability/rates/working time) · L126 (captures its own events unconditionally) · L134 (nothing reconstructs state from events) · L147 (payloads never `:erlang.term_to_binary`) · L157 (`refs` have no prefixed form) · L159 (`actor`/timestamps never in the payload) · L167 (registration binds exactly one unit) · L167 (re-registering with the same unit is an idempotent no-op) · L168 (`dims` never `NULL`) · L168 (keys serialized sorted) · L169 (`->>` is forbidden) · L170 (`seq` is the ordering authority; `recorded_at` descriptive only) · L188 (silent truncation is forbidden) · L195 (crossing dependencies never in totals) · L196 (latest by `seq`) · L196 (no `estimate` column) · L197 (`total` is `nil` whenever `missing > 0`) · L197 (`partial_total` always carries the sum) · L198 (no materialisation, no cache) · L204 (unrecognised type ⇒ `:unknown_dep_type`) · L209 (all children closed/cancelled; zero children ⇒ satisfied) · L211 (`parent-child` never gates; never written) · L212 (`related`/`discovered-from`/`replies-to` never gate) · L231 (gate evaluated before anything else) · L231 (backup only if at least one step is pending) · L232 (never a filesystem copy) · L233 (one transaction per migration; `user_version` the last statement) · L236 (every assertion computed at runtime, never hardcoded) · L237 (table rebuilds require three pragmas) · L238 (001 must be verified against a copy first) · L250 (never produce a torn file; never hang shutdown) · L255 (pure module, no process, no state, no supervision slot, no connection) · L257 (never a partial file) · L259 (never corrupt) · L260 (`rescue` removed only after the upsert lands) · L274 (L3 must read `created_at`, never event presence) · L280 (`events` records mutations only) · L280 (never on the read connection, never in the read's critical path) · L286 (every `block/3` and every `parent` update checked in-transaction) · L288 (cycle-rejection test mandatory before digraph removal) · L295 (Migrate must return `:ok`) · L296 (`Bee.Repo` is the only child that traps exits) · L300 (there is no Export child) · L309 (WAL cannot work over a network filesystem) · L315 (`Bee.Store.Id` is the sole parser) · L315 (conversion to integer only in Projection) · L327 (every ordered corpus spec appends `id`) · L327 (existing tests migrated, not deleted) · L331 (closed sets; adding a member is a spine amendment) · L335 (any other `close_reason`, including `NULL`, is a non-failure close) · L351 ("all reads" → none) · L359 (default depth 3, maximum 10) · L359 (`types:` defaults to the gating types) · L361 (AD-13's table is the sole definition) · L371 (fixed 6-digit precision, `Z` suffix) · L373 (NULLs last in both directions; must not be normalised to 0) · L375 (a per-row query inside a result loop is a defect) · L377 (every `ask`/`query` emits telemetry) · L440 (zero inbound FKs, triggers, duplicates, orphans) · L460 (no hard-delete semantics exist).

> **Note on L331.** "Closed sets. Adding a member is a spine amendment" is a *governing* absolute over six enumerations (status, `close_reason` failure set, withheld keys, error atoms, detail levels, `via:` directions). It is untagged, and it is the absolute that makes G3, G4 and G19 spine amendments rather than edits. If one untagged absolute deserves a tag, it is this one.

---

# JOB C — Cross-product audit (authoring rule 3's own test)

Eleven closed lists × seven tables = **77 cells**. Reporting only the cells that have no home or contradict. Fifteen do.

| Cell | Result |
| --- | --- |
| **7 non-command writes × function→event table** | **FAILS — CRITICAL (G3).** Three of the seven (intent registration, measure registration, intent-usage counting) have no row. Two are public API. `import_jsonl/2` vs `/3`. Intent *removal* is an unlisted eighth. |
| **7 non-command writes × migration plan** | **FAILS — HIGH (G10).** Migration 003 seeds `effort` as measure registration (L240, L363, L439). That is one of the seven, and L273 requires each to run "in a `Bee.Repo`-owned transaction" — but `Bee.Repo` is supervisor child 2 and does not exist while child 1 runs migrations. |
| **7 non-command writes × structural seed** | **FAILS — HIGH (G9).** `join_project/3` writes a project-membership table. No migration creates one (003 creates `events`, `measurements`, `intents`, `measures`, `intent_usage`), and no seed module owns one. |
| **3 read categories × structural seed** | **FAILS — CRITICAL (G2).** `candidates.ex`, `acyclic.ex`, `graph/traverse.ex`, `graph/ready.ex`, `graph/critical_path.ex`, `graph/rollup.ex`, `graph/allocation.ex` all read issue-domain data. None is caller-facing, none is a control table, none is bulk serialisation. |
| **3 read categories × layer table** | **FAILS (G2).** Clause 2 confines SQL to `Bee.Query.Interpreter` and `Bee.Store.*`. `Bee.Graph` is L2 and is neither, yet AD-13 L214 mandates that `graph.ex:19` "filter on `dep_type`" — a SQL predicate. |
| **detail levels × AD-10's `:not_loaded` absolute** | **FAILS — CRITICAL (G4).** `:minimal` is "(id, title)"; L182 forbids an absent key for any unloaded relation. The two cannot both hold for the six `include:`-able relations. |
| **withheld keys × detail levels** | **FAILS — HIGH (G6).** `:relation_omitted` must "count rows" (L188) for a relation that was, by definition, not loaded. |
| **7 adopted columns × migration plan** | **FAILS — CRITICAL (G1).** 002 must drop the non-adopted consumer columns; they exist only on gc_daemon-live; L230 forbids conditional migrations from version 1 onward. |
| **7 adopted columns × migration plan (types)** | **FAILS — HIGH (G11).** 000 creates the seven "where absent" and leaves pre-existing ones in place, so their *types* are whatever each consumer chose. "One identical schema" is not type-identical even for the adopted seven. |
| **error atoms × function→event table** | **FAILS — MEDIUM (G19).** No atom can legitimately reject a `priority` field, which is what AD-8's own `rejected` example does. |
| **error atoms × migration plan** | **FAILS — MEDIUM (G26).** Backup failure, `PRAGMA integrity_check` failure, row-count parity mismatch, FTS parity mismatch and `foreign_key_check` failure all abort or `ROLLBACK` (L232, L236, L237) with no atom in the closed vocabulary. |
| **dep types × `via:` directions** | **FAILS — MEDIUM (G25).** `types:` accepts any `dep_type`; `parent-child` is a `dep_type`; `:ancestors`/`:descendants` are declared to follow `issues.parent` "not edges". `via: [:blockers, types: ["parent-child"]]` is expressible and undefined. |
| **`via:` directions × classifier table** | **PASSES.** `via:` → `:compute`. Consistent. |
| **status set × gate truth table** | **PASSES.** Only `closed`/`cancelled` appear; both are in the status set. |
| **`close_reason` failure set × gate truth table** | **PASSES.** Consumed by `conditional-blocks` only, with the `NULL` case explicit at L335. |
| **`close_reason` failure set × detail levels** | **PASSES.** `close_reason` is in `:standard` — a gap H8 closed and this cell confirms. |
| **measures seed × stack / migration plan** | **PASSES** for the seed value (`effort`, minutes, migration 003, matching L363); fails only via the transaction-ownership cell above. |
| **classifier table × structural seed** | **FAILS — MEDIUM (G24).** The table routes `stats:` to `:compute`; L3 is deferred (L423, L451). L103's test requires `stats:` to exist as a `Bee.Query.Spec` field, so v1 must ship a spec field for an unimplemented layer. |
| **layer table × structural seed** | **PASSES** on namespace coverage. `graph/allocation.ex` (L422) is unreferenced by any AD and its name is the domain AD-6 forbids — **MEDIUM (G22)**. |
| **stack × everything** | **PASSES.** `nimble_pool` serves AD-3's pools; `db_connection` is correctly marked unused; FTS5/WAL match AD-15/AD-23. No contradictions. |
| **migration plan × gate truth table** | **PASSES.** 004's PK `(issue_id, depends_on_id, dep_type)` correctly permits the same pair under multiple types, which AD-13's seven-type vocabulary requires. |

**Verdict on authoring rule 3:** the rule is correct and would have caught F4's class. It was written into the document and then executed on exactly one pair (AD-19 × function→event), and even that one is annotated as done (L337) while being demonstrably not done. Fifteen of 77 cells fail, four at CRITICAL.

---

# JOB D — Fresh attack on v5-only material

## The pure-module export — the design holds

I attacked this hardest, since it is v5's signature change and its predecessor failed three times. **It survives.** `flush(conn, path, opts)` on the writer's own connection, called from the writer's process, is legal under AD-2b L90 (which names "export flush" explicitly), needs no supervision slot, cannot deadlock on a pool checkout, and cannot call a dead process. The multi-statement read (issues, then comments, then labels) is not wrapped in a transaction — AD-19 L272 forbids `Bee.Store.*` from issuing `BEGIN` — but because the writer is single-threaded and is the only writer, no interleaving write can tear the read. **The design is correct for a reason the document does not state**, which is worth stating.

The residual attack is throughput, not correctness (**G23**): the *terminate-time* flush is bounded (L258); the *debounce* flush is not. A 2,687-issue dump on the single writer blocks every command for its duration, on a timer, in steady state. AD-16 costed the same class of problem for candidates at L246 and v5 did not sweep the cost clause against the flush it added in the same revision.

## Compliant-but-incompatible unit pairs

| Pair | Unit A | Unit B | Both compliant? |
| --- | --- | --- | --- |
| **`:minimal` result shape** | `%{id:, title:}` — honours the detail-level list | `%{id:, title:, comments: :not_loaded, blocked_by: :not_loaded, blocks: :not_loaded, children: :not_loaded, lock: :not_loaded, measurements: :not_loaded}` — honours L182 | Yes. **G4** |
| **`Bee.Query.Candidates`' read** | Goes through `Bee.Query.Interpreter` (obeys clause 2) — but is not a caller-facing read, so it is category-less under clause 1, and bypasses Projection per L315, a partial pipeline shape stated nowhere | Constructs its own SQL (violates clause 2 outright) | Yes for A, and A is what an implementer picks. **G2** |
| **Migration 002 against DevMan** | Emits `ALTER TABLE projects DROP COLUMN <non-adopted>` unconditionally per L230 → **errors, no such column** | Branches on `PRAGMA table_info` → **violates L230** | Yes. **G1** |
| **`Bee.register_intent/2` with a bad `order_by`** | `raise ArgumentError` per AD-25 L321 ("invalid spec field", caller-supplied) | `{:error, :invalid_spec}` per AD-5 L120 | Yes. **G7** |
| **`Bee.measure/3` with `dims: %{}`** | Stores `dims = '{}'`; the row groups under neither `estimate` nor `actual`, so AD-12 counts the node as `missing` while a measurement exists → `total: nil` forever | Defaults `kind` to `"actual"` by analogy with L176 → silently reclassifies a backfilled estimate as earned effort | Yes. **G8** |
| **Sweeper expiring 4 locks** | One command, one event — impossible, `events.issue_id` is a single `NOT NULL` column | Four commands, four events, four transactions — not stated anywhere, and the Sweeper is not a public function so AD-19's per-command transaction rule does not obviously reach it | Neither is clearly compliant. **G13** |
| **The AD-3 classifier test** | `assert Enum.all?(Map.keys(%Spec{}), &classify_field/1)` — passes for every field, including new ones, because the catch-all returns `:fast` | `assert MapSet.new(Map.keys(%Spec{})) == MapSet.union(@compute_fields, @fast_fields)` — fails when a field is added | Yes for A, which is the literal reading of L103. **G14** |
| **`Bee.Store.Id` on `assigned_to`** | `"AGENT-7"` — invents a prefix, since L315 mandates prefixed strings internally | `7` — no prefix grammar exists for agents, so the raw integer is the only defined form, violating L315 | Yes. **G12** |
| **`Bee.Repo` crashes with the Pool alive** | Runs the terminate flush and `TRUNCATE` per L258/L308 → TRUNCATE returns busy, full O(n) export per crash-loop iteration | Skips both, treating any crash as L259's "crash path" → contradicts L259, which scopes that to brutal kill only | Yes. **G5** |

## The additive-only migration 000 — the type attack

L229 commits 000 to "creates AD-14's seven columns where absent and leaves every other pre-existing column in place." Consider `last_synced_at`:

- On gc_daemon-live it already exists, with whatever affinity `project_registry`'s `ALTER TABLE` gave it — plausibly `INTEGER` (epoch) or `TEXT`.
- On DevMan and fresh, 000 creates it, at whatever affinity 000 declares.

000 "never drops", so it cannot normalise the type. The result is that **`projects.last_synced_at` has a different declared type on the production database than on every other database**, and every later migration, every `ORDER BY`, and the Timestamps convention at L371 (which mandates fixed-width ISO8601 for lexical comparability) apply to a column whose storage class is not guaranteed. The same argument applies to `source`, `stack` and `domain` if the consumer declared them with a non-`TEXT` affinity. **G11.**

This is what "one identical schema" (L229) was supposed to buy and what "never drops" (L229) makes unpurchasable. The two sentences are three words apart.

## AD-6's domain-vs-runtime split

L127 classifies "lock expiry" as an internal timer, i.e. runtime mechanics. But `lock/3` (function→event table L347) is a public function that takes a lock, and the Deferred/vocabulary text nowhere says the expiry duration is fixed and internal. If a *caller supplies* the TTL, then bee holds a domain concept of how long a unit of work may be held — which is working time attached to a domain object, precisely what L126 says bee holds no domain concept of. Either state that lock TTL is a bee-internal constant (making L127's classification true) or acknowledge it as a second Mission exception. **G28** — MEDIUM, but it is the sole exception clause under a tagged absolute, so it is load-bearing.

---

# New findings

## CRITICAL

### G1 — CRITICAL — migration 000's "one identical schema" is falsified by its own additive rule, and migration 002's drop is necessarily conditional

Four statements, one bullet apart:

1. L229: "**Migration 000 normalises all three to one identical schema** and stamps version 1."
2. L229, next sentence: "Its normalisation direction is **additive**: it *creates* AD-14's seven columns where absent and **leaves every other pre-existing column in place. It never drops.**"
3. L230: "**[abs] From version 1 onward every migration is unconditional and produces one schema; no exceptions.** … `IF NOT EXISTS` is **forbidden** — baseline is what makes that safe."
4. L438 (migration 002): "Fold non-adopted consumer `projects` columns into `projects.metadata` and **drop them**."

gc_daemon-live's `projects` carries 19 consumer columns; DevMan's and fresh's carry none. Statement 2 leaves the twelve non-adopted ones in place. **Therefore at `user_version = 1` the three databases do not have one identical schema** — statement 1 is false by statement 2. Statement 3 then makes migration 002 unsatisfiable: `ALTER TABLE projects DROP COLUMN <name>` succeeds on gc_daemon-live and errors on DevMan and fresh, and both escapes are forbidden — `IF NOT EXISTS` explicitly, and a per-state branch by "unconditional … no exceptions" with 000 named as "the sole migration permitted per-state branching" (L229).

L234's "Additional tables, columns and indexes are **tolerated**" is the sentence that invites the reading where "identical" quietly means "identical in bee-owned objects." Under that reading statement 1 is honest and **002 is the migration that bricks boot on the production database** — F3's exact predicted outcome, now reachable by a shorter path than in v4.

**This is F3 relocated.** v4 asked "which direction does 000 normalise?"; v5 answered "additive"; the answer is correct in isolation and destroys the invariant that answer was chosen to establish.

**Tightening.** Two coherent options, and the document must pick one:

- **(a)** Make 000 own the whole normalisation: "000 creates the seven where absent **and folds the non-adopted consumer columns into `projects.metadata` and drops them**, so version 1 is genuinely identical." 002 then only adds `issues.metadata`. This preserves L230 intact.
- **(b)** Keep 000 additive and rewrite L229's first sentence to "000 normalises all three to one identical **bee-owned** schema; consumer columns are tolerated per the schema-tolerance rule and are folded by 002", and add an exception to L230: "**with exactly one exception:** migration 002's fold-and-drop of non-adopted consumer `projects` columns is conditional on their presence, because 000 is additive and does not remove them."

(a) is cleaner — it makes 000 the only conditional migration in fact as well as in claim. (b) is smaller but adds a second conditional migration to a document that just declared there is exactly one.

### G2 — CRITICAL — AD-4 clause 1's three categories have no home for `Bee.Query.Candidates`, `Bee.Store.Acyclic`, or `Bee.Graph.*` — F2 reproduced one module over

L110: "**[abs] every read falls into exactly one of three categories, and there are no others.**" The three are (1) caller-facing issue-domain reads resolving to a Spec via the Interpreter, (2) internal control-table reads (`locks`, `intents`, `intent_usage`, `measures`, migration state), (3) bulk serialisation by `Bee.Store.Export`.

Now enumerate the readers the document mandates:

- **`Bee.Query.Candidates`** (AD-16 L246) reads "FTS + labels + project + comment references" after every create and update. Issue-domain data. Not caller-facing — the caller asked to create an issue, not to read. Not a control table. Not bulk serialisation. **No category.** And clause 2 (L114) confines SQL to `Bee.Query.Interpreter` and `Bee.Store.*` — Candidates is neither, so it must route through the Interpreter, which is category 1's mechanism for a read that is not category 1; and L315 says candidates "do not pass through Projection", so it would be a partial traversal of the one pipeline AD-4 exists to make singular.
- **`Bee.Store.Acyclic`** (AD-21 L287) runs a recursive CTE over `dependencies` and `issues.parent` inside every command transaction. Issue-domain data. Not a control table (neither table is in clause 1's enumerated list). Not caller-facing. Not bulk serialisation. **No category.** It is at least `Bee.Store.*`, so clause 2 permits its SQL — but clause 1 still has no slot for it.
- **`Bee.Graph.Traverse` / `Ready` / `Rollup` / `CriticalPath`** (AD-13 binds all of them) read `dependencies` and `issues`. AD-13 L214 states as a requirement that "**All three enrichment readers (`store.ex:452`, `:466`, `graph.ex:19`) must filter on `dep_type`**" — a SQL predicate, mandated in a module (`Bee.Graph`, L2) that clause 2 forbids from constructing SQL, with no exception.

**This is F2's fault class, reproduced for the modules sitting immediately beside the one F2 named.** AD-2b's binds list (L88) enumerates `Bee.Query.Candidates` and `Bee.Store.Acyclic` on the same line as `Bee.Store.Export`. The third category was added for Export; the sweep across the other two names *on that same line* did not happen. Authoring rule 3's failure mode, one line apart, for the second consecutive revision.

**Tightening.** Clause 1 needs a fourth category, and it should be defined by *who the read serves* rather than by module name, so it does not need extending again:

> **4. Library-internal issue-domain reads** — performed by a bee module in service of a command or a traversal, not on behalf of a caller's query: cycle checks (`Bee.Store.Acyclic`, AD-21), candidate computation (`Bee.Query.Candidates`, AD-16), and graph traversal (`Bee.Graph.*`, AD-13). These construct SQL under clause 2 or route through `Bee.Query.Interpreter`, and do not pass through `Bee.Query.Projection`.

Clause 2 must then be extended to admit `Bee.Graph.*`, or AD-13 L214's `dep_type` filtering requirement must be reassigned to `Bee.Store.Deps`. The latter is more consistent with AD-4's intent.

### G3 — CRITICAL — the function→event table fails the cross-check its own caption claims to have passed, and AD-19's "exhaustively seven" is eight

L337, verbatim: "**Cross-checked against AD-19's seven non-command writes per authoring rule 3.**"

AD-19's seven (L273): intent-usage counting, intent registration, measure registration, `import_jsonl/3`, `register_project/3`, `register_agent/3`, `join_project/3`.

The table's non-command row (L350): "`register_project/3`, `register_agent/3`, `join_project/3`, `import_jsonl/2` | none".

Four defects:

**(a) Three of the seven have no row.** Intent registration and measure registration are missing. These are not internal mechanics — AD-5 L120 says registered intents are "added/removed **at runtime** with no release" and AD-9 L167 says "Measures **register at runtime**". Both are public API. **The document never names either function, anywhere.** So the table AD-7 calls "the sole naming authority" (L138) omits two public functions, and no reader can detect the omission because no public surface is published (H10's residue). Intent-usage counting is genuinely internal and correctly absent — but the table should say so, since it found room for the Sweeper.

**(b) Intent removal is an unlisted eighth.** AD-5 L120: registered intents are "added/**removed** at runtime". Removal deletes a row from `intents`. It is not issue-scoped, so it cannot emit an event (`events.issue_id NOT NULL`, L139), so by AD-7 L137 it must be one of the seven non-command writes. It is not. L273: "**Adding an eighth is a spine amendment.**" **AD-5 mandates a write that AD-19 forbids without an amendment.** This is F4 verbatim, on a function AD-5 named in the same clause v5 revised.

**(c) `import_jsonl/2` vs `/3`.** L350 says `/2`; AD-17 L260 and AD-19 L273 both say `/3`. Reported as M9 in v4. Unchanged, on the row directly beneath the cross-check claim.

**(d) The Sweeper is listed under a column headed "public function."** M9's third point, unchanged. It matters more now than in v4, because the Sweeper is the only internal actor emitting an event and G13 shows its event cardinality is undefined.

**Tightening.** (i) Name the two registration functions in the table and in a published public-surface list. (ii) Extend AD-19 to eight and name intent removal, or state in AD-5 that removal is a form of "intent registration" for AD-19's purposes — one sentence either way. (iii) Fix `/2` → `/3`. (iv) Rename the column "entry point" and mark the Sweeper as internal. (v) **Delete the "Cross-checked" caption until it is true** — a false provenance claim is worse than no claim, because it stops the next reviewer from checking.

### G4 — CRITICAL — `:minimal` and `:compact` cannot satisfy AD-10's no-absent-key absolute

L182 (AD-10): "**[abs] A relation not loaded carries `:not_loaded` — never `[]`, `nil`, or an absent key; no exceptions.**"

L357 (Detail levels, a closed set governed by L331): "`:minimal` (id, title) · `:compact` (+ status, priority, issue_type, project_id, assigned_to, parent, created_at, updated_at) · `:standard` (+ description, close_reason, closed_at, metadata, labels) · `:full` (+ all `include:`-able relations: `comments`, `blocked_by`, `blocks`, `children`, `lock`, `measurements`)."

At `:minimal` no relation is loaded. L182 forbids an absent key for any of the six. So a `:minimal` result must be:

```elixir
%{id: 2, title: "…", comments: :not_loaded, blocked_by: :not_loaded,
  blocks: :not_loaded, children: :not_loaded, lock: :not_loaded,
  measurements: :not_loaded}
```

— eight keys, six of them sentinels, for the level whose entire purpose is to be minimal. The same argument applies to `:compact` (the default, L182) and `:standard`. Only `:full` is consistent.

Two implementers, both compliant, incompatible on every single result: Unit A returns the columns the level names and omits relation keys (violates L182, honours L357); Unit B returns six sentinels at every level (honours L182, makes L357's level names false and inflates the default response for every agent read in the system).

**And it is not detectable by AD-26's parity harness**, because AD-26 L327 asserts parity "on the **payload within the envelope**" against the *old* implementation, which has no `:not_loaded` concept at all — so both units diff identically against the baseline.

This is a clean authoring-rule-3 cell: AD-10's absolute was tagged in v5, and the detail-level closed list was *edited* in v5 (H8's fix added four fields and named the six relations), and the two were not multiplied.

**Tightening.** Scope L182 to relations the level admits: "**A relation the requested `detail:` level includes, but which was not loaded, carries `:not_loaded`** — never `[]`, `nil`, or an absent key. Relations above the requested level are absent, which is what the level means; a caller wanting the distinction requests `:full`." Then state that `:full` without `include:` yields six `:not_loaded` values, which is the case the sentinel was invented for.

## HIGH

### G5 — HIGH — H11 is unclosed: "crash path" was narrowed to brutal kill, and a trapped `Bee.Repo` crash still runs `terminate/2` with the Pool alive

L259 (AD-17): "**Crash path:** `terminate/2` does **not** run on a **brutal kill**."
L308 (AD-23): "**On the crash path neither runs**; the next boot's PASSIVE timer recovers."
L296 (AD-22): `Bee.Repo` "**traps exits** (the only child that does; without it `terminate/2` never runs)".
L294 (AD-22): "one **`:rest_for_one`** supervisor", `Bee.Repo` child 2, `Bee.Read.Pool` child 3.

A trapping GenServer runs `terminate/2` on **any** abnormal exit, not only on supervisor-ordered shutdown. Under `:rest_for_one`, when child 2 exits abnormally the supervisor terminates children 3–4 **after** it. So on an ordinary `Bee.Repo` crash — a bad match in `handle_call`, an exqlite error, a `raise` from a Store function — `terminate/2` runs **while `Bee.Read.Pool` and its up-to-ten connections are alive**. Consequently:

1. L308's stated reason for TRUNCATE succeeding — "the pool is already gone (AD-22)" — is false, and TRUNCATE returns busy, so the checkpoint AD-23 relies on for bounded WAL growth silently does not happen on the one path where the WAL is most likely to be large.
2. AD-17's terminate-time flush runs on **every** writer crash. `:rest_for_one` restarts the tail, so a crash loop performs one O(n) export per iteration — structurally identical to the backup-loop hazard v4's X4 fixed at L231, and against the same disk.
3. The writer is crashing, so its connection may be exactly what is broken, and `terminate/2` is attempting a full-table read across it.

v5's response was to add sentences about brutal kill. Brutal kill is the case where `terminate/2` provably does *not* run, i.e. the case that was never the problem. **The failure mode H11 named — trapped crash, pool alive — is not addressed anywhere in v5.** This is the review's clearest relocation: the term was narrowed until the surrounding sentences became true of the narrowed case.

**Tightening.** AD-22 needs the three-path distinction stated once:

> **`terminate/2` runs on two of three exit paths.** *(i) Orderly shutdown* — children terminate in reverse order, the pool is gone, the final flush runs and `TRUNCATE` succeeds. *(ii) Trapped crash under `:rest_for_one`* — `terminate/2` runs with the pool still alive: **the flush is skipped** (the debounce timer recovers it after restart) and `TRUNCATE` degrades to `PASSIVE`. *(iii) Brutal kill* — `terminate/2` does not run; the next boot's PASSIVE timer recovers, and the JSONL is at most one debounce interval stale.

Then AD-23 L308 cites (i) for its "pool is already gone" reason instead of asserting it universally, and AD-17 L258's bound applies to (i) only. This also removes the crash-loop export.

### G6 — HIGH — `withheld[:relation_omitted]` cannot count rows it did not load

L188 (AD-11): "**[abs] Every withheld value counts rows, with exactly one exception:** `:missing_measure` counts nodes."
L353: withheld keys include `:relation_omitted`.
L182 (AD-10): "Relations load only via `include:`."

`:relation_omitted` reports that a relation was not loaded. Its value must be a row count. **The rows were never fetched, so the count is unknown without performing the read the key exists to report as skipped** — which is an N+1 across the result set, precisely what AD-10's prevents-clause forbids ("N+1 enrichment (~4 queries per row)").

Contrast `:projected_out` (L182), which is computable: the core intent *did* load the relation and Projection dropped it, so the count is in hand. That asymmetry is the tell — one key names a completed read, the other names a read that never happened, and one tagged absolute governs both.

Two implementers: Unit A emits `%{relation_omitted: 3}` counting *relations* omitted (violating L188's row rule, matching `:missing_measure`'s node precedent); Unit B runs a `COUNT(*)` per omitted relation per result set to honour L188 (correct by the letter, an N+1 by the row). Unit A's number and Unit B's number differ by orders of magnitude and both are labelled the same key.

**Tightening.** Extend L188's exception clause: "**with exactly two exceptions:** `:missing_measure` counts nodes, and `:relation_omitted` counts **relations**, because the rows were never fetched." One word each side.

### G7 — HIGH — validating registered specs at registration puts AD-5 and AD-25 in direct conflict, and "resolution never validates" is a release-boundary injection surface

**(a) Two mandated outcomes for one input.**

L120 (AD-5): "A registered spec is **validated by `Bee.Query.Spec` at registration time** and **rejected with `:invalid_spec`**."
L321 (AD-25): "**raise** `ArgumentError`, in the caller's process before dispatch, for structural/type errors in *caller-supplied code-level arguments*: … **invalid spec field, invalid `order_by` column** …"

A registration call supplies a spec as a caller-supplied code-level argument. If it carries an invalid `order_by` column, AD-25 mandates `raise` and AD-5 mandates `{:error, :invalid_spec}`. AD-25 tries to disambiguate with "anything derived from stored data (`:invalid_spec` on a registered intent, validated at registration per AD-5, never at resolution)" — but at *registration* the spec is not yet stored data; it is an argument. The disambiguator describes the wrong moment.

This is exactly the consumer-facing hazard AD-25's prevents-clause names: "consumers writing `case Bee.ask(...)` and crashing because the other implementer chose to raise."

**(b) The injection guard is not applied where the spec is used.**

L321: "`@order_columns` … is **the only thing preventing SQL injection** through interpolated column names and **must survive**, applying to registered specs **at registration** and to caller specs before dispatch."
L120: "**resolution never validates.**"

Registered intents are stored per-database and persist across releases (Deferred L455, "Per-database by design"). A spec validated against release *N*'s `@order_columns` is resolved unvalidated under release *N+1*. If the whitelist ever narrows — a column renamed by a migration, a column dropped by 002's fold — the stored spec feeds a now-unwhitelisted string straight into interpolation, on a path the document has declared never validates. The document names one guard, declares it must survive, and then routes the one class of spec that outlives the guard's evaluation around it.

**Tightening.** (i) AD-25: "Registration is a data operation. `Bee.register_intent/2` **returns** `{:error, :invalid_spec}`; it does not raise. AD-25's raise clause applies to specs passed to `query/1` and to core intent atoms." (ii) AD-5: "resolution **re-checks `order_by` against the whitelist** and returns `{:error, :invalid_spec}` on failure — a stored spec may outlive the whitelist that admitted it. No other validation occurs at resolution." That keeps the cheap-resolution intent while closing the surface.

### G8 — HIGH — `Bee.measure/3` has no `dims.kind` default, so L176's "always populated" is false on the retroactive path

L176 (AD-9b): "**The intake path sets `dims.kind` to `\"actual\"` when the caller omits it**, so AD-12's grouping key is **always** populated. `Bee.measure/3` is a standalone command for out-of-band and retroactive recording."

The default is attached to "the intake path" — `update/3` and the close path, per the same sentence's opening. `Bee.measure/3` is introduced in the *next* clause as a separate thing. AD-9 L168 says "`dims` defaults `'{}'`". So `Bee.measure(id, %{measure: "effort", value: 90}, [])` stores `dims = '{}'`, and AD-12 L196 groups "latest by `seq` per `(issue_id, measure, **dims.kind**)`" over a row whose `dims.kind` is absent.

**And `Bee.measure/3` is the estimate path.** AD-12 L196: "Declared and earned are one measure separated by `dims.kind = \"estimate\" | \"actual\"`." Estimates are declared up front and backfilled — "out-of-band and retroactive", L176's own words for `measure/3`. So the function most likely to carry `kind: "estimate"` is the one with no default and no requirement.

Unit A treats the unclassified row as a third group: it appears in neither rollup, `missing` counts the node while a measurement exists, and `total` is `nil` forever — the precise outcome AD-9b's prevents-clause was written to stop. Unit B defaults it to `"actual"` by analogy with the intake path, silently reclassifying a backfilled estimate as earned effort, which corrupts every AD-12 rollup with a number that looks right.

v4's recommended tightening named both halves: "`measure:` on a command defaults `dims.kind` to `\"actual\"`; **`Bee.measure/3` requires it explicitly.**" v5 wrote the first clause and dropped the second.

**Tightening.** Append to L176: "`Bee.measure/3` **requires `dims.kind` explicitly** and returns `{:error, :invalid_dimension_key}` if absent — the default exists to protect the incidental path, not the deliberate one."

### G9 — HIGH — `join_project/3` writes a table no migration creates and no seed module owns

AD-19 L273 sanctions `join_project/3` as a non-command write of "project/agent records". Its parenthetical says these "are not issue-scoped and so cannot satisfy `events.issue_id NOT NULL`."

- **Migration Plan.** 003 (L439) creates `events`, `measurements`, `intents`, `measures`, `intent_usage`. 000, 001, 002 and 004 create no table. **No migration creates a project-membership table.**
- **Structural Seed** (L419). `store/` contains `issues.ex deps.ex comments.ex labels.ex locks.ex agents.ex projects.ex`. `agents.ex` and `projects.ex` own the `agents` and `projects` rows respectively. **No module owns a membership relation.**
- **Consistency Conventions** L369: "[abs] Only `Bee.Store.*` names a table; no exceptions" — so the table, if it exists, must be named by a `Bee.Store.*` module that the seed does not list, contradicting L392's "single source for module → responsibility".

Either `join_project/3` writes a column on `agents` (in which case it is `register_agent/3` under another name and does not need its own slot in the seven), or it writes a join table that must appear in a migration and in the seed. The document commits to the third possibility — a distinct write — without providing either.

**Tightening.** Decide, and reflect it in both artefacts. If it is a join table, migration 003 gains `agent_projects(agent_id, project_id, role, joined_at)` with FKs `ON DELETE RESTRICT` per L439's convention, and the seed gains the module. If it is a column, drop `join_project/3` from AD-19's seven and say why.

### G10 — HIGH — the `effort` seed registration is a sanctioned non-command write that cannot run in a `Bee.Repo`-owned transaction

L273 (AD-19): "measure registration (AD-9)" is one of the seven. "**Each still runs in a `Bee.Repo`-owned transaction.**"
L240 (AD-15): "**Seed DML (AD-9's `effort` registration) is permitted inside a migration.**"
L439 (migration 003): "seed `effort` (minutes)."
L295–296 (AD-22): `Bee.Store.Migrate` is child **1**; `Bee.Repo` is child **2**.

Migrations run before `Bee.Repo` exists. The seed registration therefore runs inside `Bee.Store.Migrate`'s own transaction (AD-15 L233: "One transaction per migration"), on Migrate's own connection (AD-2 L83). It **cannot** run in a `Bee.Repo`-owned transaction, because there is no `Bee.Repo`.

L273's "Each still runs in a `Bee.Repo`-owned transaction" is a tagged absolute's clause with no exception, and the document's own migration plan violates it in the one instance it names.

Unit A obeys L273 and defers the `effort` seed to first boot after migration — reintroducing the boot-time registration that v3's X12 removed. Unit B obeys L240 and seeds in the migration, violating L273.

**Tightening.** Append to L273: "— **except measure registration performed as migration seed DML (AD-15), which runs in the migration's own transaction**, since `Bee.Repo` does not yet exist." This is the same exception AD-2 already grants Migrate for connections; it just needs granting for transactions too.

### G11 — HIGH — 000's additive-only rule leaves the adopted columns' *types* unnormalised, so "one identical schema" is not type-identical

L229: "**one identical schema**" / "creates AD-14's seven columns **where absent** and leaves every other pre-existing column in place. **It never drops.**"
L221 (AD-14): the seven are `description`, `stack`, `domain`, `repo_url`, `canonical_path`, `source`, `last_synced_at`.

On gc_daemon-live these columns already exist, created by `project_registry`'s `ALTER TABLE` calls (L445), with whatever affinity that consumer chose. On DevMan and fresh, 000 creates them with whatever affinity 000 declares. **000 cannot reconcile a mismatch, because reconciling requires a rebuild, and 000 never drops.**

The concrete hazard is `last_synced_at`: an epoch `INTEGER` on live and an ISO8601 `TEXT` everywhere else is a live possibility, and the Timestamps convention (L371) mandates fixed-width ISO8601 specifically so lexical comparison works. A column that is `INTEGER` on production and `TEXT` elsewhere makes every `ORDER BY last_synced_at` return a different order on the production database than in test — silently, and only on production.

The same argument covers `source` and `stack` if declared with a non-`TEXT` affinity, and covers any `NOT NULL` or `DEFAULT` the consumer attached.

**Tightening.** Either (a) 000 rebuilds `projects` — which contradicts "never drops" and is the honest cost of "one identical schema"; or (b) state the weaker true claim and its consequence: "000 guarantees the seven columns **exist**; it does not normalise their declared types, which are whatever each database already had. **A dry-run reports any type divergence in the adopted seven and refuses to proceed if one is found**, since AD-15's post-migration parity cannot detect it." (b) is cheap and turns a silent production-only divergence into a loud pre-flight failure, which is the whole point of the dry-run mode L235 already mandates.

### G12 — HIGH — AD-24 mandates prefixed strings for `project_id` and `assigned_to` without defining a prefix grammar for either

L315 (AD-24): "`Bee.Store.Id` is the **sole** parser. **[abs] Everything internal uses prefixed strings** … **Exception, exhaustively one:** `refs`."
L156 (AD-8): id-valued columns are "`parent`, `project_id`, `assigned_to`" and "carry **prefixed strings** per AD-24."
L457 (Deferred): "restoring FKs on `issues.project_id`/**`assigned_to`**" — confirming both are integer FKs, not free text.

The document shows exactly one prefixed form anywhere: `"GC-5"` (L149), an *issue* id. There are three id spaces — issues, projects, agents — and one parser, and the grammar for two of them is nowhere.

This is live on three paths that all bypass Projection and therefore emit the prefixed form to the outside: event payloads (AD-8, kept forever and unrecreatable per L141), export JSONL (a consumer contract, L260), and candidate reasons (returned from every create and update, L246).

Unit A invents `"PROJ-3"` / `"AGENT-7"`. Unit B, finding no grammar, emits raw integers for projects and agents while prefixing issues — a mixed payload that satisfies AD-8's example and violates L315. **Both forms end up in an append-only, never-compacted, unrecreatable event log**, and L3's `json_extract(payload, '$.fields.project_id')` matches half the corpus — verbatim the failure AD-24's prevents-clause names (L314).

**Tightening.** State the grammar in AD-24: "`Bee.Store.Id` parses and emits `<PREFIX>-<integer>` for three spaces: issues (`GC-`), projects (`PRJ-`), agents (`AGT-`) — or, if projects and agents have no prefix convention, **`fields` carries them as raw integers and AD-24's exception list is two, not one**." Either is fine; the silence is not.

### G13 — HIGH — the Sweeper holds no connection, and its event cardinality is undefined

**(a) No connection.** L84: "Control-table reads — `locks`, … — run on **whichever connection their caller already holds**; they are ordinary function calls, not connection owners."

`Bee.Store.Locks.Sweeper` (AD-22 child 4) is a **separate process**. It has no caller and holds no connection. L82's "[abs] At most one read-write connection exists at any instant, with no exception" and L83's "[abs] Modules that open their own connection, exhaustively one: `Bee.Store.Migrate`" forbid it from opening one. L301 says "The Sweeper **dispatches writes** to it [`Bee.Repo`]" — writes only; the sweep must first `SELECT` expired locks. Three options, none sanctioned: check out from `Bee.Read` (`locks` is a control table, and L84 does not route it there), open its own (forbidden), or dispatch the whole sweep to `Bee.Repo` (not stated, and AD-2b L88's binds list names `Bee.Store.Locks` but not the Sweeper).

H6's fix resolved the two in-process readers and left the one out-of-process reader in exactly the state H6 described.

**(b) Undefined event cardinality.** The function→event table (L348) maps "Sweeper (AD-22 child 4)" to `lock.expired`. A sweep finds N expired locks across N different issues. L137: "**[abs] One accepted command emits exactly one event.**" L140: `events.issue_id` is a single `NOT NULL` column. **One event cannot represent N locks on N issues.** So a sweep must be N commands — which is stated nowhere, which AD-19 L272 then makes N transactions, and which raises whether the Sweeper's writes are "accepted commands" at all given L136 defines acceptance as "passed validation AND produced a non-empty delta" for a caller-supplied input the Sweeper does not have.

**Tightening.** One sentence in AD-22 covers both: "The Sweeper holds no connection. It dispatches a `expire_locks` operation to `Bee.Repo`, which performs the read and the writes on its own connection (AD-2b) and **emits one `lock.expired` event per expired lock, each its own transaction**; the Sweeper itself performs no database access." Then add `Bee.Store.Locks.Sweeper` to AD-2b's binds and note the N-events case as an explicit non-exception to L137 (N commands, N events).

### G14 — HIGH — AD-3's replacement test claim is tautological against AD-3's own catch-all row

L103: "**A test asserts every `Bee.Query.Spec` field appears in this table**; a field added without a row fails that test. (A compile-time guarantee is not achievable — the catch-all row matches any unknown field.)"

The table (L98–101) is two rows: `via:`/`rollup:`/`stats:` → `:compute`; "`search:` **or anything else**" → `:fast`.

The parenthetical is right and is exactly why the assertion above it cannot hold: **with a catch-all row, every conceivable field "appears in this table" by definition.** A test written literally against L103 — "for each field of `%Spec{}`, assert the classifier returns a lane" — passes for a newly added `rollup_window:` field, returns `:fast`, and the head-of-line blocking AD-3's prevents-clause exists to stop happens silently. The document diagnosed the disease and prescribed a placebo.

v4's recommended form was enforceable and specific: assert `MapSet.new(Map.keys(%Bee.Query.Spec{}))` equals the union of the classifier's **explicitly declared** `@compute_fields` and `@fast_fields`. v5 kept the shape of the recommendation and dropped the mechanism.

Unit A writes the tautology and ships. Unit B writes the set comparison. Only B fails when a field is added, and nothing in L103 tells A it is wrong.

**Tightening.** Replace L103's first clause: "**A test asserts that the set of `Bee.Query.Spec` struct keys equals the union of the classifier's declared `@compute_fields` and `@fast_fields`**; the catch-all row exists for robustness at runtime, not as a classification decision, and a field absent from both declared sets fails the suite."

### G15 — HIGH — the Facade row carries no layer level, so AD-1 remains unevaluable for `Bee` and `Bee.Application`

L37: "| **Facade** | `Bee`, `Bee.Application` |" — added in v5, closing H5's namespace-coverage half.
L74 (AD-1): "a module may depend on **any layer below its own**, at any distance."

Every other row is numbered (`L0 Substrate`, `L1 Query`, `L2 Graph`, `L3 Intelligence`). The Facade row is not, and its position — printed *above* L0 in a table that otherwise ascends — reads ambiguously. AD-1's rule is stated relative to "its own" layer. A module in an unnumbered row has no own layer, so **AD-1 is not evaluable for the two modules that mediate the entire public surface and the entire supervision tree** — which is verbatim the consequence H5 stated and which v5 did not address.

Concretely: the diagram (L55–58) draws `API` → L3, L2, L1 **and L0W**. Those four edges are legal under AD-1 if and only if the Facade is above L3. Nothing says it is. And `Bee.Application` starts `Bee.Repo` (L0), `Bee.Read.Pool` (L0) and `Bee.Store.Migrate` (L0) while `Bee.Stats` (L3) is deferred — a supervisor referencing both ends of the lattice, whose legality cannot be checked.

**Tightening.** One character: "| **L4 Facade** | `Bee`, `Bee.Application` — above L3; may depend on any layer, per AD-1. |" This also makes the diagram's four `API -->` edges legal by the stated rule instead of by exemption, which is what AD-1's "Sole upward exception" tag at L75 implicitly assumes when it claims there is only one.

## MEDIUM

### G16 — `import_jsonl/2` vs `/3`, and the Sweeper under a "public function" heading

M9 unchanged. L350 says `/2`; L260 and L273 say `/3`. The Sweeper row (L348) sits under a column headed "public function". Both are one-word fixes; both are on the table whose caption claims a cross-check (G3).

### G17 — `target_version/0` is named but the migration → `user_version` map does not exist

L297: the Pool "refuses to start if `PRAGMA user_version` is below `Bee.Store.Migrate.target_version/0`."
L229/L436: 000 stamps version 1. **No other stamp is stated.** L233: "`PRAGMA user_version = N` the last statement inside it" — `N` unbound for 001–004.

An implementer cannot determine whether `target_version/0` returns 4 or 5, and the Migration Plan table (L434–441) has no version column. M6's missing fact moved from "the compiled-in target" to "`target_version/0`" without becoming known — the same relocation shape as F3 and H11, at lower stakes.

**Tightening.** Add a version column to the Migration Plan table: 000→1, 001→2, 002→3, 003→4, 004→5, and state `target_version/0 == 5`.

### G18 — the Migration Plan's "not restated" claim is false, violating authoring rule 1

L432: "Governing rules are in AD-15 and are **not restated**."
L436 restates two of them verbatim: "**Baseline, additive only**" (AD-15 L229) and "**The sole migration permitted per-state branching**" (AD-15 L229, tagged `[abs]` there).
L440 restates AD-15's `NOT NULL` reasoning.

This is authoring rule 1's subject ("Every fact is stated in exactly ONE place"), self-declared and self-violated four lines apart. It matters because G1 turns on which of the two statements of 000's behaviour a reader trusts, and there are now two.

### G19 — AD-8's `rejected` example teaches a wrong mapping, and the vocabulary still has no per-field rejection atom

L152: `"rejected": {"priority": "invalid_dimension_key"}`.
L158: "`rejected` maps field name to an atom from the error vocabulary."
L355: the closed vocabulary.

`:invalid_dimension_key` (AD-9 L168) is raised when a *measurement dimension key* violates `^[a-z][a-z0-9_]*$`. Applying it to a rejected `priority` field is semantically wrong, and it is the document's only normative example of `rejected`. M17's atom-vocabulary defect was fixed by substituting an in-vocabulary atom rather than by adding the atom the structure needs.

Scanning the vocabulary for an atom that could legitimately reject `priority`: `:not_found`, `:unknown_intent`, `:invalid_spec`, `:unknown_measure`, `:unit_mismatch`, `:unknown_dep_type`, `:unwritable_dep_type`, `:invalid_dimension_key`, `:locked`, `:cycle`, `:parent_cycle`, `:self_parent`, `:schema_unexpected`. **None applies.** So `rejected` — a field on every command report (L374) — is structurally unusable for its most obvious case, and the set is closed by L331.

**Tightening.** Add `:invalid_value` to the error atoms (a spine amendment, correctly declared as one) and restore AD-8's example to `{"priority": "invalid_value"}`.

### G20 — the seed's "no other section restates a responsibility" is more false in v5 than in v4

L392: "**[abs] No other section restates a responsibility; ADs are cited for traceability only.**"

v4 identified three violations (AD-17's flush owner, AD-22's Pool refusal, AD-2's Migrate connection ownership). v5 added three more: L255 (`Bee.Store.Export` "exposes `flush(conn, path, opts)` and holds no state"), L256 (`Bee.Repo` "owns the debounce timer"), L321 (`Bee.Query.Spec` "owns the `order_by` whitelist"). The seed's own comment at L418 — "`export.ex # AD-17 — pure module, no process`" — is itself a responsibility restated from AD-17 inside the artefact that forbids restating responsibilities.

The rule as written is unachievable: an AD that cannot say who does the thing cannot state a rule. **Tightening:** rewrite L392 to what is actually wanted — "The single source for **module → file → AD mapping**. Where an AD assigns a responsibility, the seed cites the AD and does not paraphrase it."

### G21 — `refine` remains vacuous for rollups (M13, third revision)

L188 defines `refine` as "a keyword list of **options** that would return more, `[]` when none would." L197 keeps `refine: [...]` in the rollup shape. No query option cures a missing measurement — the cure is to record one. So a rollup's `refine` is invariably `[]` on the one result type where the caller most needs to know what to do next, and the caller learns nothing from a key that is present precisely to be informative.

**Tightening.** One sentence in AD-12: "For rollups, `refine` is `[]` by construction — no option produces a total when measurements are missing; the `missing` count and `withheld[:missing_measure]` are the actionable output."

### G22 — `graph/allocation.ex` is unexplained and its name is the domain AD-6 forbids

L422 (seed): "`traverse.ex ready.ex critical_path.ex rollup.ex **allocation.ex**`". Every other seed entry is either cited to an AD or is a self-evident store module. `allocation.ex` appears exactly once in the document, with no AD citation and no responsibility.

L126 (AD-6): "bee holds **no domain concept** of resource **capacity, availability**, cost rates, or working time."

"Allocation" is the standard name for assigning work to resources under capacity constraints. Either the module does something else and needs a name that says so, or it does what its name says and contradicts an `[ADOPTED]` AD. It is also the only seed file with no home in any layer's responsibility set.

### G23 — the debounce flush is unbounded and serialises with every command

L258 (AD-17): "**The terminate-time flush is bounded** by a work budget."
L256: "`Bee.Repo` owns the debounce timer and calls `flush/3` on its own connection … **after a quiet interval**."

Only the terminate flush is bounded. The debounce flush is a full O(n) serialisation of 2,687 issues plus satellites, executed **inside the single writer**, on a timer, in steady state. Every command arriving during it queues. AD-16 recorded exactly this cost for candidate computation at L246 ("**Accepted cost:** this runs on the single writer…") in the same revision that rewrote AD-17, and the cost clause was not swept across.

Mitigating: a "quiet interval" means by definition no commands were arriving. But the interval elapsing does not guarantee none arrives during the flush, and a steady drip of commands at just under the debounce period produces a flush-per-drip.

**Tightening.** Give the debounce flush the same treatment as candidates: state the accepted cost, and either bound it with the same work budget or note that a flush in progress is cancelled and rescheduled when a command arrives.

### G24 — the classifier table requires a `Bee.Query.Spec` field for a deferred layer

L99 routes `stats:` to `:compute`. L423 (seed) and L451 (Deferred) both mark L3 / `Bee.Stats` as deferred — "Requires accumulated event history. Building now would train on data that does not exist."

L103's test requires every `Bee.Query.Spec` field to appear in the classifier table; the converse is not stated, but the table naming `stats:` implies the field exists. So v1 ships a spec field routing to a lane serving a layer that does not exist. Harmless if deliberate; it should say so, since the alternative reading is that L3 is not deferred.

### G25 — `via: types: ["parent-child"]` is expressible and undefined

L359: "`via: [direction, depth: n, **types: [dep_type]**]`. Directions: `:blockers`, `:dependents`, `:ancestors`, `:descendants` (the last two follow `issues.parent`, **not edges**)."
L211 (AD-13): `parent-child` is a `dep_type`, "**Projected from `issues.parent`, never written**".

`types:` accepts any `dep_type`, and `parent-child` is one. `via: [:blockers, types: ["parent-child"]]` is grammatically valid and semantically undefined — it asks to traverse blocker edges of a type that is not an edge, and it duplicates `:ancestors`, which the grammar says explicitly does not use edges.

**Tightening.** "`types:` accepts the six writable dep types; `parent-child` is rejected with `:unwritable_dep_type`, since hierarchy is reached via `:ancestors`/`:descendants`."

### G26 — the migration abort paths have no error atoms

L232: "**Abort** if the backup or its `PRAGMA integrity_check` fails."
L236: row-count parity, FTS parity and orphan check — "Mismatch ⇒ **`ROLLBACK`**."
L237: "`PRAGMA foreign_key_check` before `COMMIT`."
L295 (AD-22): Migrate "**must return `:ok` or the tree fails to start**."

Migrate returns something other than `:ok` on five distinct failures, and the closed error vocabulary (L355) contains one migration atom: `:schema_unexpected`, which L229 assigns specifically to an unrecognised `user_version = 0` database. An operator staring at a daemon that will not boot gets no discrimination between "the backup disk is full", "your database is corrupt" and "row counts diverged." The set is closed by L331, so adding them is a spine amendment and should be taken deliberately.

### G27 — the silent-failure list omits the Sweeper's in-flight loss (M3, unclosed half)

L376 now names three exceptions. The fourth: `Bee.Store.Locks.Sweeper` does not trap exits (L296 makes `Bee.Repo` "the only child that does"), so a sweep write dispatched but not yet committed when the Sweeper is terminated is lost with no record. Its event (`lock.expired`, L348) is the only trace that a lock was released, and AD-7 L141 keeps events forever precisely because they are "the one unrecreatable asset."

Low practical impact — the next sweep re-expires the lock — but it is a sanctioned silent failure under an absolute that says there are exactly three.

### G28 — AD-6's classification of lock expiry as "runtime mechanics" is contestable and load-bearing

L127: "**[abs] This constrains bee's *domain model*, not its *runtime*.** Internal timers (export debounce, **lock expiry**, WAL checkpoint, usage-count coalescing) are implementation mechanics."
L126: "bee holds **no domain concept** of … **working time**."

Export debounce, WAL checkpoint and usage-count coalescing are unambiguously internal — no caller can observe or set them. **Lock expiry is different**: `lock/3` is a public function (L347), and if its TTL is caller-supplied then bee holds and enforces a caller-meaningful duration over a domain object, which is working time in the domain model. The exception clause is the sole qualifier on a tagged Mission-level absolute, so a contestable member weakens it.

**Tightening.** State that the lock TTL is a bee-internal constant, not a caller parameter — or, if it is a parameter, move it out of L127's list and record it as a third Mission exception alongside AD-6 and the two Deferred rows (which would require amending L31's "exhaustively two").

### G29 — AD-9b's `"actual"` default silently misclassifies an omitted-kind estimate

L176: "The intake path sets `dims.kind` to `\"actual\"` when the caller omits it."

The default is safe against `NULL` (which is what M10 asked for) and unsafe against misclassification. A caller doing `update(id, [measure: %{measure: "effort", value: 480}])` intending to *declare* an estimate gets it recorded as *earned* effort. AD-12 L196 then sums it into the actual total, and AD-12's `total` is a confident number that is wrong — which is the second half of AD-12's own prevents-clause ("rolling up to a confident, tiny, wrong number", inverted).

Silent, and undetectable after the fact because the event log records the defaulted value, not the omission.

**Tightening.** Either require `kind` explicitly on the intake path too (and reject with `:invalid_dimension_key`), or note the hazard inline: "the default is `\"actual\"` because the intake path fires on a state transition, which is when effort is *earned*; callers declaring estimates must pass `kind` explicitly."

---

# Summary table

| # | Finding | Severity | Sites |
| --- | --- | --- | --- |
| G1 | 000's "one identical schema" is falsified by its own additive rule; 002's drop is necessarily conditional | CRITICAL | 229, 230, 234, 438 |
| G2 | AD-4's three categories have no home for Candidates, Acyclic or Graph reads — F2 one module over | CRITICAL | 110, 114, 214, 246, 287, 315 |
| G3 | The function→event table fails the cross-check its caption claims; AD-19's seven is eight | CRITICAL | 337, 350, 273, 138, 120 |
| G4 | `:minimal`/`:compact`/`:standard` cannot satisfy AD-10's no-absent-key absolute | CRITICAL | 182, 357 |
| G5 | H11 unclosed: "crash path" narrowed to brutal kill; a trapped crash runs `terminate/2` with the Pool alive | HIGH | 259, 308, 296, 294, 301 |
| G6 | `withheld[:relation_omitted]` cannot count rows it did not load | HIGH | 188, 353, 182 |
| G7 | AD-5 registration validation vs AD-25 raise; "resolution never validates" is an injection surface | HIGH | 120, 321, 455 |
| G8 | `Bee.measure/3` has no `dims.kind` default; L176's "always populated" is false on the retroactive path | HIGH | 176, 168, 196 |
| G9 | `join_project/3` writes a table no migration creates and no seed module owns | HIGH | 273, 439, 419, 369 |
| G10 | The `effort` seed registration cannot run in a `Bee.Repo`-owned transaction | HIGH | 273, 240, 439, 295 |
| G11 | 000's additive rule leaves the adopted columns' types unnormalised across the three baselines | HIGH | 229, 221, 371 |
| G12 | No prefix grammar for `project_id`/`assigned_to` under AD-24's prefixed-strings absolute | HIGH | 315, 156, 457, 149 |
| G13 | The Sweeper holds no connection; its event cardinality is undefined | HIGH | 84, 301, 137, 140, 348 |
| G14 | AD-3's replacement test claim is tautological against its own catch-all row | HIGH | 103, 98–101 |
| G15 | The Facade row carries no layer level; AD-1 unevaluable for `Bee`/`Bee.Application` | HIGH | 37, 74, 55–58 |
| G16 | `import_jsonl/2` vs `/3`; Sweeper under a "public function" heading (M9 unclosed) | MEDIUM | 350, 260, 273, 348 |
| G17 | `target_version/0` named; migration→`user_version` map absent (M6 relocated) | MEDIUM | 297, 229, 233 |
| G18 | Migration Plan's "not restated" is false — authoring rule 1 self-violation | MEDIUM | 432, 436, 440 |
| G19 | AD-8's `rejected` example teaches a wrong mapping; no per-field rejection atom | MEDIUM | 152, 158, 355 |
| G20 | Seed's "no other section restates a responsibility" is more false in v5 than v4 | MEDIUM | 392, 255, 256, 321, 418 |
| G21 | `refine` still vacuous for rollups (M13, third revision) | MEDIUM | 188, 197 |
| G22 | `graph/allocation.ex` unexplained; its name is the domain AD-6 forbids | MEDIUM | 422, 126 |
| G23 | The debounce flush is unbounded and serialises with every command | MEDIUM | 256, 258, 246 |
| G24 | Classifier requires a `stats:` Spec field for a deferred layer | MEDIUM | 99, 103, 451 |
| G25 | `via: types: ["parent-child"]` is expressible and undefined | MEDIUM | 359, 211 |
| G26 | Migration abort paths have no error atoms | MEDIUM | 232, 236, 237, 295, 355 |
| G27 | Silent-failure list omits Sweeper in-flight loss (M3 unclosed half) | MEDIUM | 376, 296, 348 |
| G28 | AD-6's "lock expiry is runtime mechanics" is contestable and load-bearing | MEDIUM | 127, 126, 347 |
| G29 | AD-9b's `"actual"` default silently misclassifies an omitted-kind estimate | MEDIUM | 176, 196 |

**New: 29 (4 CRITICAL, 11 HIGH, 14 MEDIUM). Prior findings: 22 CLOSED, 9 PARTIAL, 5 OPEN. Relocated rather than resolved: 6.**

---

# Recommended amendment set (v5)

Items 1–4 gate the build.

1. **Resolve migration 000/002.** Pick option (a) — 000 owns the entire `projects` normalisation including the fold-and-drop — and make version 1 genuinely identical. Add the type-divergence pre-flight check. Closes **G1**, **G11**, and removes the second conditional migration the document just declared impossible. (AD-15, AD-14, Migration Plan.)
2. **Add AD-4 clause 1's fourth category** for library-internal issue-domain reads (cycle checks, candidates, graph traversal), and reassign AD-13's `dep_type` filtering to `Bee.Store.Deps` so clause 2 need not admit `Bee.Graph`. Closes **G2** and the long-running M12. (AD-4, AD-13, AD-16, AD-21.)
3. **Repair the function→event table and AD-19's seven together, and delete the false cross-check caption.** Name the two registration functions, home intent removal (eighth, or fold into "intent registration"), fix `/2`→`/3`, mark the Sweeper internal, and publish the public surface as a list so the table's completeness becomes checkable at all. Closes **G3**, **G16**, and the substantive half of H10. (AD-19, AD-5, Shared Vocabularies.)
4. **Scope AD-10's `:not_loaded` absolute to relations the requested level admits.** One sentence. Closes **G4** — the finding a consumer hits on the first `Bee.get/2`.
5. **State the three exit paths in AD-22** (orderly / trapped crash / brutal kill) and make AD-17's flush and AD-23's `TRUNCATE` cite the path they hold on. Closes **G5**, and gives **G23**'s debounce bound a home. (AD-22, AD-17, AD-23.)
6. **Settle registration semantics:** registration returns, never raises; resolution re-checks `order_by` only. Closes **G7**. (AD-5, AD-25.)
7. **Require `dims.kind` on `Bee.measure/3`**, and note why the intake default is `"actual"`. Closes **G8**, **G29**. (AD-9b.)
8. **Give the Sweeper an explicit contract** — no connection, dispatches an operation to `Bee.Repo`, one event per expired lock. Closes **G13**, **G27**, and the H6 residue. (AD-22, AD-2b.)
9. **Define the id prefix grammar for all three id spaces, or declare two exceptions instead of one.** Closes **G12**. (AD-24.)
10. **Home `join_project/3`'s table** in migration 003 and the seed, or delete the function. Closes **G9**. (AD-19, Migration Plan, Structural Seed.)
11. **Exempt migration seed DML from AD-19's Repo-owned-transaction clause.** One clause. Closes **G10**.
12. **Replace AD-3's test claim with the set-comparison form**, and number the Facade row `L4`. Closes **G14**, **G15**. Two edits, both mechanical.
13. **Sweep the remaining mediums** — they cluster into four edits: the exception-list completions (G6, G27, G28), the vocabulary additions (G19, G26), the restatement/provenance corrections (G18, G20, G21, G24, G25), and the one unexplained module (G22).

---

# THE STRUCTURAL RECOMMENDATION

Read this before making any of the above edits.

**The tag is not the sweep.** v5 did what v4 asked — it made the absolutes mechanically checkable — and then checked the 35 it had already found. The `[abs]` marker is a *label*, and a label applied by hand reproduces exactly the coverage of the hand that applied it. That is why the tagged/untagged split is 35/77 and why six findings relocated rather than resolved: the same mind that wrote the absolute wrote its exception list, and it enumerated the exceptions it had in mind.

The fix is to invert the operation. **Do not tag the absolutes you know about. Grep for the trigger tokens, and for every hit either tag it or reword it so it is not an absolute.** Line 23 already names the token set. The operation is:

```
grep -nEi '\b(only|never|no|none|always|every|all|sole|exactly|exhaustive[a-z]*|forbidden|unconditional[a-z]*|must|mandatory)\b' ARCHITECTURE-SPINE.md
```

Every line it returns is either `[abs]`-tagged, or rewritten without the token, or the sweep is not done. That is a five-minute mechanical pass and it is the difference between 35 and 112. **A reviewer can run it. Run it first.**

**Authoring rule 3 needs the same treatment.** It is the right rule and it caught nothing, because it was executed as a claim (L337's "Cross-checked against…") rather than as a matrix. Eleven closed lists × seven tables is 77 cells; four of this review's criticals live in them, and every one is findable in an afternoon by writing the grid out and filling it in. **Write the grid into the document as an appendix.** A filled grid is checkable by the next reader; a sentence claiming the grid was filled is not — and this revision demonstrates the difference, since L337's claim is false about the very table it annotates.

**On the trajectory.** The raw counts are 35 → 29 new findings and 7 → 4 criticals, but the more meaningful number is the character of what remains. AD-17's rewrite proves the method that works: when a paragraph fails twice, do not amend it a third time — restate its requirements and rebuild it, and the amendments that would have been needed stop being needed. **AD-4 clause 1 is now that paragraph.** It has been extended twice for two specific modules (control tables in v4, Export in v5) and both times the extension was module-shaped rather than principle-shaped, and both times the next reader found a module the extension did not reach. G2 is the third instance. Rewrite it from the question "what kinds of read exist and who serves each?" rather than from "which module needs admitting this time," and it will stop generating findings — exactly as AD-17 did.

Three of the four criticals (G1, G3, G4) are single-decision fixes; G2 is a single-paragraph rewrite of the kind v5 has already shown it can execute well. **One more pass, with the grep and the grid run mechanically rather than by recall, and this is buildable.** The document is closer than 29 findings suggests — but the specific discipline it still lacks is the one it has now written down twice and executed zero times.
