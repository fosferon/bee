# bee — Programming Constitution

**Version:** 0.3.0 (draft)
**Derived from:** MOBuS Ecosystem Common Constitution v1.0.0 (spirit), adapted for
bee's deliberately different architecture.
**Scope:** All work on the `bee` work-coordination library.
**Changelog:** 0.3.0 — added the 3-7 dimensional-cardinality bound (Miller) to §III.
0.2.0 — added "A grammar is defined by what it refuses" to §III.

---

## Purpose

This document records the **durable values and review standards** for bee — the
things that stay true across features, and that a reviewer should hold every change
against. It is deliberately small.

It is NOT the architecture. The specific, binding technical decisions live in
`_bmad-output/planning-artifacts/architecture/.../ARCHITECTURE-SPINE.md` as numbered
Architecture Decisions (AD-1 … AD-28). **This constitution never restates an AD** —
the spine's own Rule 1 is "every fact stated in exactly one place," and a governance
document that duplicated the spine would break the first principle it is meant to
protect. Where a value has a concrete rule, this document points at the AD; it does
not copy it.

Read this to understand *how we think about bee code*. Read the spine to understand
*what the code must do*.

---

## I. bee is an engine, not an app — and it knows it

bee is a self-contained work-DAG engine with two consumers on **disjoint
interfaces** (a GenServer message protocol and an in-process module API). It has no
UI, no templates, no web layer. Principles from the ecosystem constitution that
assume an application (template separation, LiveView data-prep, bridge peers) **do
not apply** and are intentionally absent.

What bee keeps from the ecosystem: **modularity, resilience, honest boundaries,
documentation, testing discipline.** What it deliberately diverges on is recorded in
§II — and the divergence is a decision, not an oversight.

---

## II. Deliberate divergences from the ecosystem constitution

These are conscious, justified departures. They are listed openly so no reviewer
mistakes them for drift.

- **Raw SQL is the medium, by design.** The ecosystem constitution mandates Ecto and
  forbids raw SQL. bee is the exception: it is a hand-written SQL engine over
  `exqlite`, confined to the storage layer, because the work DAG needs recursive
  CTEs, FTS5, expression indexes, and single-writer serialisation that an ORM would
  obscure. The justification is the entire architecture spine. Raw SQL **outside**
  the storage layer is still forbidden.

- **A single writer, not changesets everywhere.** Correctness comes from serialising
  all writes through one process (see the spine's concurrency ADs), not from
  per-call changeset validation. Validation is shared and explicit (§V), not
  scattered.

- **The message protocol is a first-class versioned contract**, equal to the module
  API — not an implementation detail. A consumer reaching bee by message is as
  supported as one calling a function. (See spine AD-28 and Epic 1.)

---

## III. Consumer sovereignty and honest boundaries

- **Two consumers, disjoint interfaces, both first-class.** A change safe for one
  must be proven safe for the other. Parity is mechanical, not assumed.

- **Validate at the boundary; never trust inbound data.** Structural/type errors
  raise in the caller's own process for good ergonomics; the same validation at the
  server boundary **returns** `{:error, reason}` and **never raises** — because a
  raise there kills the single writer and every queued command behind it.

- **A grammar is defined by what it refuses.** Every admissible member of a closed
  vocabulary — `via:` traversal types, detail/transform presets, the error atoms, any
  DSL enum — must carry a real, distinct meaning. An expressible-but-meaningless
  member (e.g. a `via:` type that names a projected, non-gating relation, so a walk
  through it either states the obvious or conflates two graphs) is **rejected at the
  boundary with a named error**, never silently accommodated. Diluting a sharp tool
  with a meaningless option is not neutral: it costs the trustworthiness of every
  option beside it, because a reader can no longer assume the others mean something.
  Prefer a smaller vocabulary that holds its edges to a larger one that blurs them.

- **A dimension carries three to seven members — no more, and no fewer if it is a
  dimension at all.** The 7±2 bound is Miller's: seven is the ceiling of what a reader
  holds in mind at once, so a *dimensional* closed vocabulary (one that classifies or
  defines an entity along an axis — dependency types, transform tiers, detail presets)
  never exceeds seven. Three is the floor: below it the dimension is too thin to be
  well-defined, and probably should not be modelled as a dimension at all. This governs
  **dimensional** vocabularies, not **enumerative** ones — a list of possible failure
  atoms enumerates outcomes and may legitimately run past seven; it does not define an
  entity. Pairs with the refusal principle above: refusal says each member must mean
  something; the bound says how many meaningful members a dimension may have.

- **A versioned contract classifies every change as additive or breaking.** Only a
  breaking change forces consumer coordination. Silent shape changes to a shared
  contract are the cardinal sin.

- **bee owns its database.** No consumer creates, alters, or drops objects in bee's
  schema. The boundary is the namespace.

---

## IV. Industrial-strength resilience

- **Reliability over features.** A dependable capability beats a flashy brittle one.
  Prefer battle-tested patterns.

- **No silent failure.** Return tagged errors from a *closed* vocabulary, log, and
  fall back — never swallow. Where silence is genuinely permitted, the exceptions are
  **enumerated explicitly** (see the spine); an unlisted silent path is a bug.

- **State honest limits, not false absolutes.** Every durability or safety promise
  names the conditions under which it holds. "We always flush on shutdown" is a lie
  if a brutal kill skips cleanup; "we flush on orderly and trapped exits, and lose at
  most the un-flushed window on a hard kill" is the truth. Bounded honesty over
  comforting absolutes.

- **Data loss is never implicit.** A migration or merge that cannot preserve a row
  **accounts for it** (skip-and-log, or abort with a named atom) — it never
  truncates or coerces silently.

---

## V. Verification is mechanical, not rhetorical

This is bee's sharpest lesson, learned the hard way on this very redesign.

- **Prose review converges on the instances a reviewer names, never the class.**
  Five rounds of careful reading missed what one script caught. Where a property must
  hold across a whole surface (every absolute tagged, every finding dispositioned,
  every API claim backed by the real call graph), **enforce it with a check**, not a
  promise. bee's `scripts/spine/*` checks run in the post-commit hook for exactly
  this reason.

- **"Found" is not "searched."** An enumeration you did not perform is an assumption
  wearing a fact's clothes. When a hazard surfaces incidentally (one grep, one
  crash), the next question is *"what would a complete search find?"* — and if you
  can't answer, completeness is an open question, not a closed one.

- **Recurring hazards become standing checks, not one-time tasks.** If the condition
  that creates a risk outlives the work that addresses it, a completed story is the
  wrong container. Encode it as a hook/check that re-runs.

- **A claim of verification that wasn't performed is worse than no claim.** Do not
  write "cross-checked against X" unless the cross-check ran. State what is verified
  and how; leave the rest openly unverified.

---

## VI. Code organization

- **Dependency direction is downward, with named exceptions only.** Layers call
  strictly into the layer below; the sole upward exceptions are named in the spine
  (AD-1). No implicit back-edges.

- **One responsibility per module, one storage per fact.** Small, focused,
  composable. Before adding, ask what already exists to assemble.

- **No table prefixes.** bee's tables are `issues`, `comments`, `dependencies` — the
  separate database is the namespace.

---

## VII. Data management

- **Schema changes only via versioned migrations**, baselined and run at boot in
  order (see the spine's Migration Plan). No ad-hoc DDL, ever, in any environment.

- **Production database access is read-only** for investigation. Mutations reach
  production only through a reviewed, backed-up, integrity-checked migration.

- **Back up torn-free before mutating.** Never a filesystem copy of a live
  WAL-mode database.

---

## VIII. Documentation & testing discipline

- **Every public module and function carries current docs** — purpose, parameters,
  return values, error conditions — structured for ExDoc. Private-function docs scale
  with complexity.

- **Behaviour parity is proven against a production copy** over a fixed corpus, on
  **both** consumer surfaces, with declared breaking changes in a machine-readable
  exception list.

- **If you can't demonstrate it end-to-end, it isn't done.** Business-critical flows
  have integration coverage; complex logic has focused unit tests.

- **A doc that has drifted from the code is a liability, not an asset.** Correct
  drift at the source and track it, merge only the useful parts with an existing document if fitting, or delete the doc if now irrelevant.

---

## IX. Development workflow

- **Branch per task**, small focused changes, commit messages that explain *why*.
  Never rewrite shared history.

- **The architecture is captured before the code**, as the spine; work decomposes
  into epics and stories that each cite the ADs they implement and the findings they
  resolve. Every non-negotiable finding is claimed by a story or explicitly deferred
  with a reason — enforced by a check, not a promise.

- **When a section fails review twice, rewrite it from its requirements** rather than
  amending it a third time. The one technique that dissolved a cluster of findings
  this session was restating a failing decision from scratch; patching it in place
  never did.

---

## Governance

- **Versioning:** MAJOR = a value reversed or removed; MINOR = a new principle;
  PATCH = clarification. This is a draft at 0.1.0 until ratified.

- **Amendment:** a proposed change with rationale, reviewed, then a version bump.
  A new principle that contradicts an existing one is a conflict to surface, not a
  silent override — the same discipline the spine applies to its ADs.

- **Relationship to the spine:** if this constitution and the spine ever appear to
  conflict, the spine wins on *what the code must do*; this document wins on *how we
  decide and review*. Neither restates the other.

---

**Version:** 0.3.0 (draft) · **Created:** 2026-07-23 · **Updated:** 2026-07-24
