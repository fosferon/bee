---
stepsCompleted: ["step-01-validate-prerequisites", "step-02-design-epics", "step-03-create-stories", "step-04-final-validation"]
inputDocuments:
  - _bmad-output/planning-artifacts/architecture/architecture-bee-2026-07-20/ARCHITECTURE-SPINE.md
  - _bmad-output/planning-artifacts/architecture/architecture-bee-2026-07-20/.memlog.md
  - _bmad-output/planning-artifacts/architecture/architecture-bee-2026-07-20/reviews/review-final-v5.md
  - docs/plans/2026-07-20-bee-supercharger-design-brief.md
  - scripts/spine/findings.json
---

# bee - Epic Breakdown

## Overview

This document decomposes the bee library redesign (GC-2691) into epics and stories.

**No PRD exists.** bee went brainstorm → architecture directly, and a reconstructed PRD would back-derive user-facing requirements from decisions already settled — inventing scope rather than recording it. Per operator decision, the functional requirements below are **derived from the architecture spine's 28 ADs and its Migration Plan**, the non-functional requirements from the spine's *measured* constraints, and a third category — MUST-RESOLVE — carries the 26 open architecture findings the operator has declared non-negotiable.

Every requirement traces to reviewed, machine-checked material. Nothing here is invented.

**Enforcement.** `scripts/spine/check_findings.py` runs on every commit and fails unless every MR item carries `fixed`, `story:<key>`, or `deferred:<reason>` — and a story key pointing at a nonexistent story also fails. The coverage map below is therefore not documentation; it is the input to a gate.

## Requirements Inventory

### Functional Requirements

Derived from the architecture spine. Each cites the ADs that govern it.

```
FR1:  Expose a composable query core (`Bee.query/1`) taking a validated Bee.Query.Spec,
      executed by a single interpreter. [AD-4 cl.1 cat.1, AD-25]
FR2:  Expose named intents (`Bee.ask/2`) in two classes: CORE (compiled, atoms, may run
      arbitrary Elixir) and REGISTERED (runtime data, strings, stored specs, no release
      needed). Both resolve to a Spec and run through the same interpreter. [AD-5, AD-4]
FR3:  Count intent usage in `intent_usage`, written asynchronously off the read path, so
      the registered catalogue can be pruned by evidence. [AD-20, AD-5]
FR4:  Support per-attribute output shaping as two orthogonal knobs — role (retrieve|filter
      |group|scan) and a tiered transform (:pushdown|:local|:external) — with the four
      named presets (:minimal|:compact|:standard|:full) and :custom as assignments over it.
      Opt-in relation loading via `include:`, batched per result set. A field below the
      selected shape is an absent key; a relation not loaded is `:not_loaded`, never `[]`.
      [AD-10 amended, AD-TRANSFORM new — see Spine Amendments]
FR5:  Return `withheld` and `refine` on every read, keyed from the closed withheld
      vocabulary. Silent truncation forbidden. [AD-11]
FR6:  Record one event per accepted command in an append-only log, emitted solely by
      Bee.Store.Events inside the command transaction, named from the function→event
      table. Retained forever. [AD-7, AD-8, AD-19]
FR7:  Accept measurements as measure (runtime-registered, unit-bound) × dimensions
      (schemaless, grammared), rejecting unknown measures and unit mismatches. [AD-9]
FR8:  Accept a `measure:` option on update/close recorded in the same transaction, plus a
      standalone `Bee.measure/3` for retroactive recording. [AD-9b]
FR9:  Compute rollups over a node set via one aggregator with pluggable scope selectors
      (:tree|:closure|:critical_path), reporting `total: nil` whenever any node lacks an
      effort measurement. [AD-12]
FR10: Support a closed, compiled vocabulary of 3-7 dependency types (Miller bound:
      three floor, seven ceiling) with their gate truth table (one row per defined
      type), and compute one-hop readiness from edge type. [AD-13 amended]
FR11: Prevent dependency and parent cycles via a recursive CTE inside the command
      transaction. [AD-21]
FR12: Support graph traversal expressed as spec fields (`via:` with direction, depth,
      types), never as its own SQL. [AD-4 cl.1, via: grammar]
FR13: Return advisory candidate edges on create/update, computed after commit on the
      writer's connection under a bounded timeout. Never mandatory. [AD-16]
FR14: Run versioned migrations at boot: 000 baseline (the sole per-state branching
      migration), then 001–004 unconditional. [AD-15, Migration Plan]
FR15: Provide `metadata` JSON on issues and projects as the sanctioned consumer
      extension point, with `bee:` reserved and unused. [AD-14]
FR16: Export JSONL debounced (never per write), temp-write plus atomic rename, final
      flush by the writer; import idempotent via upsert. [AD-17]
FR17: Read comments back through the public API and the message protocol — currently
      write-only, blocking live agents. [GC-2693]
FR18: Serve reads from a pooled reader with two lanes classified by spec shape alone,
      and all writes from a single writer. [AD-2, AD-2b, AD-3]
FR19: Supervise the tree :rest_for_one with pinned boot order and a stated shutdown
      invariant. [AD-22]
FR20: Convert ids to integers in exactly one place; everything internal uses prefixed
      strings. [AD-24]
FR21: Raise on structural/type errors before dispatch; return tuples from the closed
      error vocabulary for data-dependent outcomes. [AD-25]
FR22: Honour the GenServer message protocol as a versioned contract alongside the
      module API. NO AD COVERS THIS TODAY — see MR26. [gap]
```

### NonFunctional Requirements

Every NFR below is anchored to a measurement taken against the live database or the
real call graph. None is aspirational.

```
NFR1: Heavy analytics must never stall routine agent reads. Two lanes; :fast sized
      schedulers_online() capped 8, :compute sized 2. [AD-3]
NFR2: No N+1 enrichment. Current code fires ~4 queries per row on every list
      (2,687 issues × 4 ≈ 10,748 queries for an unfiltered list). [AD-10]
NFR3: Migrations run against a live 16MB production database and MUST NOT brick boot.
      Additional tables/columns/indexes are tolerated. [AD-15]
NFR4: Pre-migration backup via VACUUM INTO, never a filesystem copy — the WAL is
      uncheckpointed (measured 4.0MB) and cp yields a torn database. [AD-15]
NFR5: Migration 001 must be verified against a copy of the live production database
      before running against it. [AD-15, snapshot fixture]
NFR6: Behaviour parity proven against a production copy over a fixed spec corpus, with
      declared breaking changes in a machine-readable exception list and `id` appended
      to every ordered spec for deterministic pagination. [AD-26]
NFR7: WAL mandatory; foreign_keys/busy_timeout/synchronous set on every connection;
      checkpointing PASSIVE-on-timer (TRUNCATE cannot succeed against 10 persistent
      readers). WAL cannot work over a network filesystem. [AD-23]
NFR8: Rollups computed on demand — largest measured subtree is 69 nodes, so
      materialisation is unjustified. [AD-12]
NFR9: Event log retained forever, no compaction (~20k rows / ~7MB for all history to
      date); it is the only unrecreatable asset. [AD-7]
NFR10: Silent failure forbidden, with exactly three enumerated exceptions. [Conventions]
NFR11: No consumer may create, alter or drop objects in bee's database. [AD-14]
NFR12: Dimension queries must hit their expression indexes — SQLite matches expression
      indexes on exact text only, so the interpreter emits one canonical form. [AD-9]
```

### Additional Requirements

From the architecture and the measured consumer coupling.

```
- Stack: bump exqlite ~> 0.34 → ~> 0.39; add nimble_pool ~> 1.1. db_connection 2.9.0 is
  already present transitively and is deliberately unused.
- No starter template. This is a brownfield refactor of an existing 1,971-LOC library
  with 24 existing tests that are migrated, not deleted. [AD-26]
- TWO CONSUMERS WITH DISJOINT INTERFACES (measured via elixir-context, not assumed):
  gc_daemon = 34 raw GenServer.call sites, 0 module calls;
  DevMan    = 10 Bee.* module calls, all in lib/dev_man/bee/cli.ex, 0 messages.
  A change safe for one can silently break the other. [GC-2694, MR26]
- HARD RELEASE ORDERING: gc_daemon's SearchIndex (incl. operator-invokable rebuild/0),
  project_registry's ALTER TABLE calls, and engagement.ex:1296,1336 must be removed in
  the SAME release as migrations 001/002 — engagement.ex joins the `labels` table that
  001 drops.
- DevMan is pinned two commits behind master (a6ed78c) and predates tree_page; its
  migration is a6ed78c → v2, not v1 → v2. [GC-2694]
- The ghost `labels` table holds 219 label assignments on 69 issues, absent from
  issue_labels, 67 of which have no issue_labels rows at all. Merge before drop.
- Spine self-checks (check_absolutes, check_api_coverage, check_findings) run in the
  post-commit hook and must stay green.
- The elixir-context index for bee is maintained by the same hook and is the source of
  truth for API-surface claims.
```

### UX Design Requirements

None. bee is a library with no user interface.

### MUST-RESOLVE (open architecture findings)

Non-negotiable per operator instruction. Source: `scripts/spine/findings.json`,
enforced by `scripts/spine/check_findings.py`. **26 open** (12 HIGH, 14 MEDIUM);
G1–G4 (CRITICAL) are already fixed in the spine.

```
HIGH
MR5  (G5)  AD-22 must state all three exit paths (orderly / trapped crash / brutal kill);
           AD-17's flush and AD-23's TRUNCATE must each cite the path they hold on.
MR6  (G6)  withheld[:relation_omitted] cannot count rows it did not load.
MR7  (G7)  Registration-time validation vs AD-25's raise; order_by injection surface.
MR8  (G8)  Bee.measure/3 has no dims.kind default; AD-9b's "always populated" is false.
MR9  (G9)  join_project/3 writes project_agents, which no migration creates.
MR10 (G10) The effort seed registration cannot run in a Repo-owned transaction.
MR11 (G11) Migration 000 leaves adopted column TYPES unnormalised across baselines.
MR12 (G12) No prefix grammar for project_id/assigned_to under AD-24.
MR13 (G13) The Sweeper holds no connection; its event cardinality is undefined.
MR14 (G14) AD-3's test claim is tautological against its own catch-all row.
MR15 (G15) The Facade row has no layer level; AD-1 unevaluable for Bee/Bee.Application.
MR26 (G30) NO AD COVERS THE GENSERVER MESSAGE PROTOCOL — the primary consumer's only
           interface. An implementer can satisfy every AD and break gc_daemon in 34
           places, and AD-26's parity corpus would pass.

MEDIUM
MR16 (G16) Sweeper listed under a "public function" heading though it is internal.
MR17 (G17) target_version/0 named; migration → user_version map absent.
MR18 (G18) Migration Plan's "rules not restated" is false (authoring rule 1).
MR19 (G19) AD-8's rejected example teaches a wrong mapping; no per-field atom.
MR20 (G20) Seed's "no other section restates a responsibility" is false.
MR21 (G21) refine remains vacuous for rollups (unclosed across three revisions).
MR22 (G22) graph/allocation.ex unexplained; its name is the domain AD-6 forbids.
MR23 (G23) The debounce flush is unbounded and serialises with every command.
MR24 (G24) Classifier requires a stats: Spec field for a deferred layer.
MR25 (G25) via: types: ["parent-child"] is expressible and undefined.
MR27 (G26) Migration abort paths have no error atoms.
MR28 (G27) Silent-failure list omits Sweeper in-flight write loss.
MR29 (G28) AD-6's "lock expiry is runtime mechanics" is contestable and load-bearing.
MR30 (G29) AD-9b's "actual" default silently misclassifies an omitted-kind estimate.
```

### FR Coverage Map

Every FR maps to exactly one epic. No FR is unclaimed; no FR is claimed twice.

```
FR1:  Epic 4 - composable query core (Bee.query/1)
FR2:  Epic 4 - named intents (Bee.ask/2), CORE + REGISTERED
FR3:  Epic 4 - intent_usage counting off the read path
FR4:  Epic 4 - per-attribute (role x tiered-transform) shaping; 4 levels + :custom as presets
FR5:  Epic 4 - withheld/refine on every read, no silent truncation
FR6:  Epic 6 - one event per accepted command, append-only log
FR7:  Epic 6 - measurements as measure x dimensions
FR8:  Epic 6 - measure: option on update/close + Bee.measure/3
FR9:  Epic 6 - rollups via one aggregator, total: nil on missing effort
FR10: Epic 5 - closed 3-7 dependency types (Miller bound) + gate truth table + readiness
FR11: Epic 5 - cycle prevention via recursive CTE in-transaction
FR12: Epic 5 - graph traversal as spec fields (via:)
FR13: Epic 5 - advisory candidate edges on create/update
FR14: Epic 2 - versioned migrations at boot (000 baseline, 001-004)
FR15: Epic 6 - metadata JSON extension point on issues + projects
FR16: Epic 3 - JSONL export debounced, temp-write + atomic rename
FR17: Epic 1 - comments readable via module API AND message protocol
FR18: Epic 3 - pooled reader (two lanes) + single writer
FR19: Epic 3 - :rest_for_one supervision, pinned boot, shutdown invariant
FR20: Epic 2 - id->integer conversion in exactly one place
FR21: Epic 1 - raise on structural errors, return tuples for data-dependent
FR22: Epic 1 - GenServer message protocol as a versioned contract
```

### NFR Coverage Map

```
NFR1:  Epic 3 - two lanes, heavy analytics never stall routine reads
NFR2:  Epic 4 - no N+1 enrichment (batched relation loading)
NFR3:  Epic 2 - migrations must not brick boot on the live 16MB DB
NFR4:  Epic 2 - pre-migration backup via VACUUM INTO, never cp
NFR5:  Epic 2 - migration 001 verified against a production copy first
NFR6:  Epic 1 - behaviour parity over BOTH message protocol and module API
NFR7:  Epic 3 - WAL + per-connection PRAGMAs + PASSIVE checkpoint on timer
NFR8:  Epic 6 - rollups on demand (largest measured subtree 69 nodes)
NFR9:  Epic 6 - event log retained forever, no compaction
NFR10: Epic 3 - silent failure forbidden, three enumerated exceptions
NFR11: Epic 2 - no consumer may create/alter/drop objects in bee's DB
NFR12: Epic 4 - dimension queries must hit expression indexes (canonical form)
```

### MUST-RESOLVE Coverage Map

All 27 open findings (G5-G31) claimed exactly once. `check_findings.py` gate
turns green once the story files exist.

```
Epic 1: G7, G15, G19, G20, G30, G31
Epic 2: G9, G10, G11, G12, G17, G18, G26
Epic 3: G5, G13, G14, G16, G23, G27, G28
Epic 4: G6, G24
Epic 5: G22, G25
Epic 6: G8, G21, G29
```

## Epic List

Six epics, organised by **consumer capability** — what gc_daemon, DevMan, and the
agents behind them can do that they could not before — not by the L0-L3 layer
stack. Each epic stands alone and enables those after it without requiring them.

Sequencing note: Epic 1 ships first as the *contract* epic (not the deprioritised
GC-2693 hotfix); the versioned message-protocol contract it settles is a
precondition every later epic's return shapes depend on. Epic 2 (migration)
precedes Epic 3 (topology) so the backup/integrity apparatus lands before anything
touches the WAL. Epics 4-6 build on 1-3.

Every enhancement below traces to a recorded elicitation pass (assumption audit,
pre-mortem, second-order) and is marked [audit] / [premortem] / [2nd-order].

### Epic 1: Agents can see their own conversation

An agent that writes a comment can read it back — through both the module API and
the GenServer message protocol. Malformed input (a bad `order_by`) returns an error
from the closed vocabulary instead of raising inside `handle_call` and killing the
writer with every queued command behind it. The message protocol becomes a
first-class **versioned contract**, and behaviour parity is proven over both
consumer surfaces. This is the only epic that ships with no schema change and no
process-topology change.

**FRs covered:** FR17, FR21, FR22
**NFRs:** NFR6 (parity harness over BOTH surfaces)
**Resolves:** G7, G15, G19, G20, G30, G31

Design spine: one shared validator called in two places — caller-process for
embedders (raises `ArgumentError`, good ergonomics), server boundary defensively
(returns `{:error, reason}`, never raises). Lets gc_daemon delete its copied
`@order_columns` whitelist (`work_handler.ex:608`).

Enhancements folded in:
- [audit] A reply-shape reconnaissance story: trace how each of gc_daemon's 34
  `GenServer.call` sites handles the *reply* before the reply shape changes —
  otherwise the fix relocates the writer-kill bug to the caller. The parity corpus
  captures outputs, not just inputs.
- [premortem/2nd-order] The versioned contract classifies every change as
  **additive** (new optional field, no consumer break) or **breaking** (shape
  change); only breaking changes bump the major version and force consumer
  coordination. Without this, "versioned contract" becomes five forced gc_daemon
  migrations across the redesign.
- [premortem] The parity corpus runs on **every** epic release, not just Epic 1's —
  once gc_daemon deletes its whitelist, bee's validator is the sole defence.
- [2nd-order] Comments ship in FR4's relation shape (`include:`, `:not_loaded` when
  absent) with a **batched** loader from day one — the unblocked agent pair puts
  live comment-read load on it months before Epic 4's general N+1 fix.

### Epic 2: Safe landing on the live database

bee boots on the real 16MB production database with the new schema, provably
behaving as it did before. Consumers observe nothing — that invisibility is the
deliverable. Carries the safety apparatus (backup, integrity check, abort atoms)
and the hard cross-repo release ordering.

**FRs covered:** FR14, FR20
**NFRs:** NFR3, NFR4, NFR5, NFR11
**Resolves:** G9, G10, G11, G12, G17, G18, G26

Hard release ordering: gc_daemon's SearchIndex (incl. operator-invokable
`rebuild/0`), `project_registry`'s ALTER TABLE calls, and `engagement.ex:1296,1336`
must be removed in the **same release** as migrations 001/002 — 001 drops the
`labels` table that `engagement.ex` joins.

Enhancements folded in:
- [audit] A cross-repo coupling-discovery step, delivered as a **post-commit-hook
  script** (not a one-shot story) alongside the spine self-checks: every migration
  re-greps both consumer repos for the schema objects it touches, confirming
  `engagement.ex` is the only coupling rather than merely the first one found.
- [premortem] Migration 000's per-state branching gains an explicit
  **unknown-baseline → named abort** arm: an unrecognised fourth database state
  fails loud with an atom rather than silently branching into a wrong assumption
  (strengthens G11 type-divergence and G26 abort atoms).

### Epic 3: Heavy analytics stop stalling routine reads

A rollup over a large subtree no longer blocks an agent's `ready` call. Reads are
served from a pooled reader with two shape-classified lanes; all writes from a
single writer. Shutdown is defined on all three exit paths (orderly / trapped crash
/ brutal kill), so the JSONL flush and the WAL checkpoint each cite the path they
hold on.

**FRs covered:** FR16, FR18, FR19
**NFRs:** NFR1, NFR7, NFR10
**Resolves:** G5, G13, G14, G16, G23, G27, G28

### Epic 4: Ask for exactly what you need

The headline capability. `Bee.query/1` for composable specs, `Bee.ask/2` for named
intents (CORE compiled + REGISTERED runtime). Output is shaped by **two orthogonal
per-attribute knobs** — the *role* an attribute plays (retrieve / filter / group /
scan) and a *tiered transform* on its retrieved value (`:pushdown` in SQL / `:local`
in Elixir / `:external` via a consumer-registered hook). The four levels
(`:minimal/:compact/:standard/:full`) plus `:custom` are presets over this, not the
primitive. Nothing is silently truncated — every read returns `withheld` and `refine`
naming the transform applied per attribute and how to ask for more. Kills the N+1:
today an unfiltered list fires ~4 queries per row (~10,748 for 2,687 issues).

Mechanism, not policy: bee ships the `:pushdown` and `:local` tiers and the
`:external` registration hook, but **no LLM or external transform inside bee** — a
summary-via-LLM transform is a consumer registration (parallel to REGISTERED intents
and measures), keeping bee agnostic per AD-6.

**FRs covered:** FR1, FR2, FR3, FR4, FR5
**NFRs:** NFR2, NFR12
**Resolves:** G6, G24

Model change folded in (operator steer, 2026-07-24):
- [transform-model] Per-attribute (role × tiered-transform) is the output primitive;
  the four detail levels + `:custom` are presets. Requires a spine Update — see the
  **Spine Amendments Required** section at the end of this document.

### Epic 5: The DAG answers questions about itself

Seven dependency types with a real gate truth table, cycle prevention via recursive
CTE, traversal expressed as spec fields (`via:` with direction/depth/type), and
advisory candidate edges on write — the mechanism meant to prompt LLM consumers to
declare dependencies they currently skip.

**FRs covered:** FR10, FR11, FR12, FR13
**Resolves:** G22, G25

### Epic 6: bee accumulates evidence about the work

Every accepted command writes one event to the append-only log. Effort and duration
arrive as measure (runtime-registered, unit-bound) x dimensions (schemaless).
Rollups over a tree, closure, or critical path report `total: nil` honestly whenever
any node lacks a measurement, rather than a confident wrong number. This is the
substrate the deferred L3 intelligence layer will later consume.

**FRs covered:** FR6, FR7, FR8, FR9, FR15
**NFRs:** NFR8, NFR9
**Resolves:** G8, G21, G29

Enhancement folded in:
- [premortem] L3 deferral is stated as an **exit criterion**, not a margin note:
  Epic 6 ships the measurement substrate and nothing that reads it for
  optimisation. Deferral as an acceptance line, so scope cannot creep through the
  door once the event history exists.

---

## Epic 1: Agents can see their own conversation — Stories

Story order is constrained: 1.1 → 1.2 → 1.3 is a hard chain (validate, then
observe the live contract, then version it). 1.4, 1.5, 1.6 may follow in any order
once 1.3 lands. No story depends on a later one.

### Story 1.1: Shared validator with a closed error vocabulary

As a bee maintainer,
I want one option-and-argument validator invoked at both the module API and the
GenServer boundary, raising in the caller's process but returning a tagged error at
the server boundary,
So that malformed input can never again raise inside `handle_call` and take the
single writer down with every queued command behind it.

**Acceptance Criteria:**

**Given** a caller uses the in-process module API (e.g. `Bee.list/2`) with a
structurally invalid option (unknown key, wrong type),
**When** the validator runs,
**Then** it **raises** `ArgumentError` in the caller's own process — structural/type
errors raise before dispatch [FR21, AD-25],
**And** the writer process is never involved.

**Given** the same invalid option arrives as a GenServer message
(`{:list, opts}`) at the server boundary,
**When** the validator runs defensively before dispatch,
**Then** it **returns** `{:error, reason}` where `reason` is a member of the closed
error vocabulary — data-dependent outcomes return a tuple, never raise at the boundary
[FR21, AD-25],
**And** the writer process does not crash and continues serving the queue.

**Given** a data-dependent invalid `order_by` value (a real column name that is not
orderable, or an injection attempt),
**When** it arrives by either surface,
**Then** it is rejected by the same validation logic (no second, divergent
whitelist), resolving the `order_by` injection surface [G7].

**Given** AD-8's payload envelope rejects a specific field,
**When** the rejection is produced,
**Then** the error carries a per-field rejection atom from the vocabulary, and the
documented example maps to the atom the code actually returns [G19].

**Given** an intent or spec is registered at runtime,
**When** registration validates it,
**Then** registration returns a result and never raises; resolution re-checks only
`order_by` [G7].

### Story 1.2: Reply-shape reconnaissance across the 34 message sites

As a bee maintainer,
I want a read-only trace of how each of gc_daemon's 34 `GenServer.call(@bee, …)`
sites consumes the reply — success shape and error shape alike,
So that I change the reply contract only after I know which sites would break on a
new shape, rather than relocating the writer-kill bug to the caller.

**Acceptance Criteria:**

**Given** the elixir-context index of the gc_daemon repo,
**When** the reconnaissance runs,
**Then** every `GenServer.call` site targeting bee is enumerated with the pattern it
matches on the reply (e.g. `{:ok, x}`, bare list, `{:error, _}`, unmatched),
**And** the enumeration is complete, not a sample — an unreachable or unparseable
site is reported explicitly, never silently omitted [audit L2].

**Given** the enumeration,
**When** a site matches success shapes only and has no clause for `{:error, _}`,
**Then** it is flagged as a site that would crash on the new error reply, feeding
Story 1.3's breaking-change classification.

**Given** this is a read-only investigation,
**When** it completes,
**Then** it changes no code in either repo and produces the corpus input consumed by
Story 1.5 [G30, NFR6].

### Story 1.3: Message protocol as a versioned contract

As a consumer maintainer (gc_daemon),
I want the GenServer message protocol declared a first-class versioned contract
with an explicit additive-vs-breaking policy,
So that I coordinate a bee upgrade only when a change actually breaks my 34 sites,
not on every release.

**Acceptance Criteria:**

**Given** the message protocol,
**When** it is documented as a contract,
**Then** it is a peer of the module API — not an implementation detail — and both
the request shapes `{verb, args}` and the reply shapes (success and error) are
specified [FR22, G30].

**Given** a change to the protocol,
**When** it is classified,
**Then** it is either **additive** (a new optional field; no existing consumer
pattern breaks) or **breaking** (a shape change to an existing field or reply),
**And** only a breaking change bumps the major contract version and requires
consumer coordination [premortem/2nd-order].

**Given** Story 1.2 flagged sites that would break on the new error reply,
**When** the initial version is cut,
**Then** those sites' required change is listed in the contract's breaking-change
set, and the version reflects it.

**Given** the architecture spine's layer model,
**When** the Facade row (`Bee`, `Bee.Application`) is evaluated for AD-1,
**Then** it carries an explicit layer level L4 so AD-1 is decidable for it [G15],
**And** the Structural Seed no longer restates a responsibility owned elsewhere
[G20].

### Story 1.4: Read comments back, batched, in the relation shape

As an agent coordinating through bee,
I want to read comments back through both the module API and the message protocol,
So that two agents talking through `comment` are no longer writing into a void.

**Acceptance Criteria:**

**Given** `Bee.Store.get_comments/2` exists but is unwired,
**When** a read requests comments via `include: [:comments]`,
**Then** comments are returned through the module API and through the message
protocol alike [FR17].

**Given** a read that does not request comments,
**When** it returns,
**Then** the comments relation is `:not_loaded`, never `[]` — matching the FR4
relation contract this pre-dates [2nd-order].

**Given** a result set of N issues each with comments requested,
**When** comments are loaded,
**Then** loading is batched (not one query per issue), so the first live user — the
unblocked agent pair — does not hit an N+1 that Epic 4's fix has not yet landed
[2nd-order, NFR2 anticipation].

**Given** the enriched issue map,
**When** relations are merged,
**Then** `enrich_issue/2` includes comments alongside labels, dependencies and
locks when requested.

### Story 1.5: Behaviour-parity harness over both surfaces

As a bee maintainer,
I want a parity harness that replays a fixed corpus against both the module API and
the message protocol and asserts identical behaviour, wired to run on every epic
release,
So that no later epic can silently change what a consumer receives on either
surface.

**Acceptance Criteria:**

**Given** the corpus from Story 1.2 plus the module-API spec corpus,
**When** the harness runs against a production copy,
**Then** it asserts parity on **both** surfaces — the message protocol and the
module API — not the module API alone [NFR6, G30].

**Given** a declared breaking change,
**When** the harness runs,
**Then** the change is present in a machine-readable exception list and the harness
passes because the difference is declared, not because it went unnoticed.

**Given** ordered specs,
**When** the corpus runs,
**Then** `id` is appended to every ordered spec for deterministic pagination.

**Given** any later epic (2 through 6),
**When** it is released,
**Then** the harness re-runs via the post-commit hook — it is a standing check, not
a one-time Epic 1 deliverable [premortem L1].

### Story 1.6: Correct gc_daemon's bee-work-dag.md drift

As an engineer onboarding to the bee/gc_daemon boundary,
I want gc_daemon's `docs/subsystems/bee-work-dag.md` to match bee's real schema and
behaviour,
So that the onboarding document does not hand me a wrong model of the system.

**Acceptance Criteria:**

**Given** the corrected document (already applied at source this session),
**When** it is verified against the live `bee.db` schema,
**Then** table names (`comments` not `issue_comments`; `dependencies` not `blocks`),
the `parent` column, the `issue_labels` junction, the lock columns
(`locked_by`/`locked_at`), and the real status set (`open`/`in_progress`/
`closed`/`cancelled`) all match [G31].

**Given** the document's behavioural claims,
**When** they are checked,
**Then** the JSONL trail is described as a full-file rewrite (not append) that is
off for gc_daemon, `show(id)` is flagged as not returning comments, and
`Bee.Lock.sweep_expired/1` is documented as present on a 60s timer, not a future
extension [G31].

**Given** the finding ledger,
**When** `check_findings.py` runs,
**Then** G31's `story:gc-daemon-doc-drift` disposition resolves to this existing
story rather than a ghost [gate honesty].

---

## Epic 2: Safe landing on the live database — Stories

Ownership decision (per AD-15): Epic 2 owns all five migration files (000–004) as
one baselined, sequential set that brings the schema to its target `user_version`
at boot. Epics 5 and 6 build *behaviour* on tables that already exist; they do not
author migrations. Story order: 2.1 (runner) and 2.2 (safety) precede any
migration; 2.3 → 2.4 → 2.5 run in migration-number order; 2.6 and 2.7 are
independent once the schema lands. NFR3 (must-not-brick-boot) is asserted across
2.1 and 2.3 rather than owning a story.

### Story 2.1: Migration runner with an explicit version map

As a bee maintainer,
I want a boot-time migration runner driven by an explicit migration→`user_version`
map with a named `target_version/0`,
So that the schema advances deterministically from whatever version a database is
at, and boot never silently runs the wrong set.

**Acceptance Criteria:**

**Given** a database at some `PRAGMA user_version`,
**When** the runner starts at boot,
**Then** it runs the versioned migrations (000 baseline, then 001–004 unconditional)
between the current version and `target_version/0`, in ascending order, each wrapped
per AD-19's one-transaction rule [FR14, AD-15].

**Given** `target_version/0` is named in the spine,
**When** the runner is built,
**Then** a complete migration→`user_version` map exists (no absent mapping) [G17].

**Given** the Migration Plan section of the spine claimed "rules not restated,"
**When** the plan is reconciled,
**Then** the authoring-rule-1 self-violation is corrected [G18].

**Given** a database already at `target_version`,
**When** the runner starts,
**Then** it applies nothing and boot proceeds — additional tables/columns/indexes
beyond the expected set are tolerated, not fatal [NFR3].

**Given** a database whose `user_version` is **greater than** `target_version/0` —
written by a newer bee than the running code (e.g. after a release rollback),
**When** the runner starts,
**Then** it refuses to boot with a named `:version_ahead` atom rather than applying
nothing and running old code blindly against a newer schema [FMEA: downgrade hole].

**Given** a multi-migration run where migration N fails after N−1 committed (each
migration is its own transaction per AD-19),
**When** the failure is reported,
**Then** it returns `:migration_failed` naming migration N, the database is left
cleanly at the post-(N−1) `user_version` with the pre-run backup retained, and the
next boot resumes from N [FMEA: mid-sequence].

### Story 2.2: Pre-migration safety apparatus

As an operator migrating a live 16MB production database,
I want a torn-free backup and an integrity gate before any migration mutates the
file, with named abort atoms on every failure path,
So that a failed migration is always recoverable and never leaves a half-written
database.

**Acceptance Criteria:**

**Given** an uncheckpointed WAL (measured ~4.0MB),
**When** the pre-migration backup runs,
**Then** it uses `VACUUM INTO`, never a filesystem `cp`, so the backup is not torn
[NFR4].

**Given** the backup completed,
**When** the integrity gate runs `integrity_check`,
**Then** a failure aborts the migration before any schema change, returning a named
atom (`:backup_failed`, `:integrity_check_failed`, `:verification_mismatch`) rather
than a bare crash [G26].

**Given** the backup target has insufficient space for a full second copy (`VACUUM
INTO` roughly doubles the file size — ~16MB today and growing),
**When** the backup is attempted,
**Then** the out-of-space failure surfaces as `:backup_failed`, checked before the
backup is trusted, not as an unnamed exqlite error [edge sweep].

**Given** a migration abort for any of those reasons,
**When** it is reported,
**Then** each abort path carries its own error atom from the vocabulary, and the
original database file is untouched.

### Story 2.3: Migration 000 — baseline normalisation with unknown-state refusal

As a bee maintainer,
I want migration 000 to normalise the three known baselines and explicitly refuse
any database it does not recognise,
So that the sole per-state branching migration cannot silently mis-branch on an
unforeseen fourth database state.

**Acceptance Criteria:**

**Given** a fresh database at `user_version` 0 with no tables (a new install),
**When** migration 000 evaluates it,
**Then** it takes an explicit empty-database arm that creates the target schema
directly — a greenfield database is NOT an unknown baseline and must never hit the
refusal path [edge sweep: fresh-install].

**Given** a database matching one of the three known baselines (production, the dev
mix-daemon snapshot, DevMan at a6ed78c),
**When** migration 000 runs,
**Then** it creates `projects.metadata`, folds and drops the superseded columns, and
adopts the seven columns — bringing all three to one identical schema.

**Given** the adopted columns may have divergent column *types* across baselines,
**When** migration 000 runs its pre-flight,
**Then** a type-divergence check normalises the adopted column types, so the three
baselines converge on types as well as presence [G11].

**Given** adopted-column data that cannot be coerced to the normalised type without
loss (e.g. a text column holding non-integer values),
**When** the type-divergence check runs,
**Then** it aborts with a named atom rather than silently truncating or coercing —
data loss is never implicit [FMEA: irreconcilable divergence].

**Given** a *populated* database of unrecognised shape (tables present, matching no
known baseline),
**When** migration 000 evaluates it,
**Then** it aborts with a named `:unknown_baseline` atom rather than branching into
a wrong assumption — distinct from the empty-database arm above [premortem].

**Given** migration 000 completes,
**When** boot continues,
**Then** the database is at the post-000 `user_version` and the subsequent unconditional
migrations can run [NFR3].

### Story 2.4: Migration 001 — FTS rebuild and ghost-labels merge, prod-copy verified

As a bee maintainer,
I want migration 001 to rebuild FTS and merge the orphaned `labels` table into
`issue_labels`, verified against a copy of the live database before it runs against
it,
So that no label data is lost and the drop is coordinated with the consumer that
still reads the old table.

**Acceptance Criteria:**

**Given** the ghost `labels` table (219 assignments on 69 issues, 67 with no
`issue_labels` rows),
**When** migration 001 runs,
**Then** it merges every mergeable assignment into `issue_labels` before dropping
`labels`, and accounts for every row that is not mergeable — "no data lost" means
merged-or-accounted, not merged-blindly [edge sweep].

**Given** a `labels` row whose `issue_id` points at a deleted/absent issue,
**When** the merge runs,
**Then** that orphaned row is skipped rather than merged (which would violate the FK
or create a new orphan), and the skip count is logged, not silent [edge sweep].

**Given** a `labels` row whose `(issue_id, label)` already exists in `issue_labels`,
**When** the merge runs,
**Then** it dedupes (`INSERT OR IGNORE` semantics) rather than double-inserting
[edge sweep].

**Given** the FTS rebuild step,
**When** it fails,
**Then** it aborts with its own named atom, distinguishable from a labels-merge
failure, so the failing step is unambiguous [FMEA: FTS rebuild].

**Given** migration 001 changes the schema FTS and labels depend on,
**When** it is prepared,
**Then** it is verified against a copy of the live production database before being
run against production [NFR5].

**Given** `engagement.ex:1296,1336` joins the `labels` table that 001 drops, and
gc_daemon's SearchIndex (incl. operator-invokable `rebuild/0`) and
`project_registry`'s ALTER TABLE calls read the pre-001 shape,
**When** 001 ships,
**Then** those gc_daemon removals ship in the **same release** — the hard release
ordering is documented as a release gate, not left to chance [release ordering].

### Story 2.5: Migrations 002–004, seed-DML exemption, and project_agents

As a bee maintainer,
I want the additive schema (issue metadata, the event/measurement/intent tables,
and the dependency-type primary key) created as unconditional migrations, with the
effort-measure seed and the `project_agents` table given a home,
So that Epics 5 and 6 build on tables that already exist and are correctly seeded.

**Acceptance Criteria:**

**Given** migration 002,
**When** it runs,
**Then** it adds `issues.metadata` (unconditionally), the sanctioned extension point
with `bee:` reserved and unused.

**Given** migration 003,
**When** it runs,
**Then** it creates `events`, `measurements`, `intents`, `measures`, and
`intent_usage`.

**Given** the effort-measure seed registration must populate `measures` but runs
inside migration 003 — before the `Bee.Repo` writer process exists,
**When** the seed DML executes,
**Then** AD-19 grants an explicit seed-DML exemption for migration-time writes, so
the seed does not require the writer [G10].

**Given** migration 003 re-runs (a retried boot after a later migration failed),
**When** the effort-measure seed executes again,
**Then** it is idempotent — `INSERT OR IGNORE` / upsert on measure name — and does
not double-insert into `measures` [edge sweep].

**Given** `join_project/3` writes a `project_agents` table,
**When** the migrations run,
**Then** migration 003 (or its sibling) creates `project_agents`, so no code writes
a table no migration created [G9].

**Given** migration 004,
**When** it runs,
**Then** it changes the `dependencies` primary key to `(issue_id, depends_on_id,
dep_type)`.

### Story 2.6: Single-point id conversion with a prefix grammar

As a bee maintainer,
I want prefixed-string ids converted to integers in exactly one place, governed by
an explicit prefix grammar covering all three id spaces,
So that AD-24's prefixed-strings invariant holds and `project_id`/`assigned_to` are
not an unhandled exception to it.

**Acceptance Criteria:**

**Given** an inbound prefixed id (e.g. `GC-805`),
**When** it crosses into storage,
**Then** it is converted to its integer form in exactly one conversion site;
everything internal uses prefixed strings [FR20].

**Given** three id spaces (issue ids, `project_id`, `assigned_to`),
**When** the prefix grammar is defined,
**Then** each has a stated prefix rule, closing the gap where `project_id`/
`assigned_to` had no grammar under AD-24 [G12].

**Given** an id that does not match the grammar,
**When** conversion runs,
**Then** it is rejected via the closed error vocabulary (structural error → raise in
caller / return at boundary, per Story 1.1).

**Given** the boundary inputs a lazy caller actually produces — `"GC-"` (prefix,
no number), an already-integer id, `nil`, and an empty string,
**When** conversion runs,
**Then** each is handled explicitly: `"GC-"` and empty/`nil` are rejected with a
named atom, and an already-integer input is accepted idempotently rather than
double-converted [edge sweep].

### Story 2.7: Coupling-sweep hook and the no-consumer-DDL guard

As a bee maintainer,
I want a standing hook script that greps both consumer repos for every schema object
a migration touches, plus an enforced rule that no consumer may alter bee's database,
So that a cross-repo coupling like `engagement.ex`↔`labels` is caught before a
migration ships — every time, not just once.

**Acceptance Criteria:**

**Given** a migration touching a set of tables/columns,
**When** the sweep runs in the post-commit hook,
**Then** it greps both gc_daemon and DevMan for references to those objects and
reports every hit, confirming the known coupling set is complete rather than
merely first-found [audit L2].

**Given** the sweep finds a consumer reference to an object a migration drops or
alters, and that reference is NOT in the known-and-scheduled-for-removal set,
**When** the hook runs,
**Then** it **fails the commit** — a standing check that only reports is decorative;
an unremoved coupling must block, not warn [FMEA: sweep must fail, premortem death #3].

**Given** the sweep is a standing check,
**When** any later migration is authored,
**Then** the sweep re-runs automatically — it is a hook script beside the spine
self-checks, not a one-time story [premortem L1].

**Given** AD-14's rule that bee owns its database,
**When** a consumer is audited,
**Then** no consumer creates, alters, or drops objects in bee's database; existing
violations (gc_daemon SearchIndex DDL, `project_registry` ALTER TABLE) are the ones
removed in Story 2.4's release [NFR11].

---

## Epic 3: Heavy analytics stop stalling routine reads — Stories

Story order: 3.1 (pool + writer) and 3.2 (connections) precede 3.3 (the tree that
supervises them and defines shutdown over them). 3.4, 3.5, 3.6 attach once the tree
exists. G5 (the three exit paths) is anchored in 3.3 and cross-referenced by 3.2
(which path the checkpoint holds on) and 3.4 (which path the flush holds on) —
written as explicit references, not restated in three places.

### Story 3.1: Single writer with a two-lane pooled reader

As an agent issuing a routine read,
I want reads served from a pooled reader whose lanes are chosen by the shape of the
query, with all writes funnelled through one writer,
So that a heavy analytics query cannot stall my `ready` call, and writes stay
serialised for correctness.

**Acceptance Criteria:**

**Given** an inbound read spec,
**When** it is classified,
**Then** it is routed to `:fast` or `:compute` by the **shape of the spec alone** —
no runtime timing, no consumer hint [FR18].

**Given** an attribute in the spec carries a transform tier above `:pushdown` (a
`:local` or `:external` transform, per Epic 4's transform-model),
**When** the spec is classified,
**Then** **tier is part of the spec shape** the Classifier reads: any tier above
`:pushdown` cannot ride `:fast` (`:local` → `:compute`; an `:external` transform over
a large set is pushed out of the synchronous read). This keeps classification a total
function of spec shape — tier is spec shape, not runtime timing [FR18, cross-ref
Epic 4].

**Given** the two lanes,
**When** the pool is sized,
**Then** `:fast` is sized `schedulers_online()` capped at 8 and `:compute` is sized 2
[NFR1].

**Given** all write commands,
**When** they are dispatched,
**Then** they are serialised through the single writer, never the reader pool.

**Given** the lane classifier,
**When** its correctness is tested,
**Then** the test is a **set comparison** — every Spec field is mapped to exactly one
lane, and the set of classified fields equals the set of Spec fields — not a
tautological check against a catch-all row [G14].

**Given** a spec whose shape matches no classified field,
**When** it is classified,
**Then** it is handled by an explicit default with a stated lane, and that default is
itself part of the set-comparison test (no silent catch-all).

**Given** a lane is saturated (e.g. a third `:compute` query behind the two
connections) and pool checkout waits,
**When** the checkout timeout fires,
**Then** the caller receives a **tagged error** (or a documented bounded wait), never
a silent hang or a crash — NFR10's no-silent-failure rule applies at the pool
boundary too [audit A4].

### Story 3.2: Per-connection PRAGMAs and timer-driven checkpoint

As a bee operator,
I want WAL mode and the safety PRAGMAs set on every connection, with checkpointing on
a timer that can actually make progress against persistent readers,
So that the database stays durable and the WAL does not grow without bound.

**Acceptance Criteria:**

**Given** any connection (writer or reader) is opened,
**When** it initialises,
**Then** WAL mode is on and `foreign_keys`, `busy_timeout`, and `synchronous` are set
on that connection — none is assumed global [NFR7].

**Given** ~10 persistent reader connections that a `TRUNCATE` checkpoint cannot
complete against,
**When** checkpointing runs,
**Then** it uses PASSIVE on a timer rather than TRUNCATE, so it makes incremental
progress instead of failing [NFR7].

**Given** bee runs on a network filesystem,
**When** WAL is evaluated,
**Then** it is documented as unsupported there — WAL cannot work over a network
filesystem [NFR7].

**Given** the TRUNCATE checkpoint that the spine's checkpoint AD reserves for
shutdown,
**When** its guarantee is stated,
**Then** it cites the exit path it holds on (orderly / trapped), per Story 3.3's
exit-path model [G5 cross-ref].

**Given** reverse-order termination kills `Read.Pool` (child 3) before `Repo`
(child 2),
**When** the shutdown TRUNCATE checkpoint runs,
**Then** it succeeds precisely because no persistent readers remain to block it —
this ordering is why AD-23 can reserve TRUNCATE for shutdown, and is stated so it is
not silently broken by moving the checkpoint earlier [chaos S3/Gc].

**Given** a single reader connection fails mid-query,
**When** the pool handles it,
**Then** the failure is **isolated** — the pool replaces that one connection — and is
NOT escalated to a `Read.Pool`-process crash; only a Pool-process crash triggers the
`:rest_for_one` cascade, so one bad query never becomes a pool-wide read outage
[chaos S2/Gb].

### Story 3.3: Supervision tree with a stated shutdown invariant

As a bee maintainer,
I want the supervision tree pinned to a known boot order with `:rest_for_one`
semantics and an explicitly stated shutdown invariant covering all three exit paths,
So that the system starts deterministically and every cleanup step declares exactly
when it is guaranteed to run.

**Acceptance Criteria:**

**Given** the child processes in AD-22 order (`Migrate` → `Repo` → `Read.Pool` →
`Sweeper`),
**When** the tree boots,
**Then** boot order is pinned and the strategy is `:rest_for_one`, so a failure
restarts the failing child and everything started after it, in order [FR19].

**Given** a process can stop in three fundamentally different ways,
**When** the shutdown invariant is stated,
**Then** it names all three exit paths explicitly: **orderly** (supervisor asks to
stop; `terminate/2` runs cleanup), **trapped crash** (an exit signal is caught;
`terminate/2` still runs, on a degraded surrounding state), and **brutal kill**
(hard kill or shutdown-timeout expiry; `terminate/2` does NOT run) [G5].

**Given** each piece of on-shutdown cleanup (the JSONL flush, the WAL checkpoint),
**When** its guarantee is documented,
**Then** it cites which of the three paths it is guaranteed on and what is lost on the
path where it is not — a bounded, honest promise, not "always" [G5].

**Given** `Bee.Repo` traps exits (the only child that does) and so runs `terminate/2`
on an ordinary crash,
**When** the durability promise is stated,
**Then** it distinguishes a **Repo crash** (exception or exit signal → `terminate/2`
runs → the flush IS guaranteed via the trapped-crash path) from a **brutal kill**,
so the promise is sharper than "brutal kill loses the window" [cascade F2].

**Given** a brutal kill,
**When** it is documented, it is split into two sub-cases:
**Then** (a) `Repo` alone is killed out-of-band while the VM lives — `terminate/2` is
skipped so the window is lost, but the supervisor restarts the tree and the app keeps
serving; and (b) the whole VM is killed — the window is lost and the app stops. In
both, worst-case loss is exactly the un-flushed debounce window plus the
un-checkpointed WAL delta, recoverable on next boot, and nothing more [cascade F2].

**Given** `Bee.Repo` is child 2 and `:rest_for_one` restarts every child after it,
**When** `Repo` crashes mid-life (not app shutdown),
**Then** `Read.Pool` and `Sweeper` restart too — **all in-flight reads are dropped
and are retryable**, and the Sweeper's in-flight dispatch is lost (per G27). This
writer-restart cascade is documented as known and accepted (writer crashes are rare,
reads retry), not left as a surprise [cascade F1].

### Story 3.4: Debounced JSONL export

As a consumer using the JSONL trail,
I want the export debounced and written atomically, with an idempotent import,
So that a full-table rewrite never runs on every command and a re-import never
duplicates rows.

**Acceptance Criteria:**

**Given** a stream of write commands,
**When** the export runs,
**Then** it is debounced — never once per command — so the flush does not serialise
with every write on the single writer [G23, FR16].

**Given** an export flush,
**When** it writes,
**Then** it writes to a temp file and atomically renames, so a reader never sees a
half-written trail [FR16].

**Given** the debounce buffer at shutdown,
**When** the final flush runs,
**Then** it is performed by the writer and cites the exit path it holds on (orderly /
trapped), per Story 3.3 — on a brutal kill the un-flushed window is the documented
loss [FR16, G5 cross-ref].

**Given** a re-import of a JSONL trail,
**When** it runs,
**Then** it is idempotent via upsert — re-importing the same trail changes nothing
[FR16].

**Given** the flush duration,
**When** it is bounded,
**Then** it is explicitly bounded rather than unbounded, so a large export cannot
stall the writer indefinitely [G23].

**Given** the internal flush bound can fire mid-flush during an orderly or trapped
shutdown,
**When** it does,
**Then** `terminate/2` running guarantees the flush is **attempted atomically within
the bound**, not that it completes — a bound-out means the atomic rename does not
occur, the prior trail stays intact (no corruption), and the window is lost but
recoverable by re-export since JSONL is derived [chaos S1/Ga].

**Given** `Bee.Repo` carries `:shutdown :infinity`, so the supervisor never times it
out and the AD-17 flush bound is the ONLY guard against a hung shutdown,
**When** the flush bound is implemented,
**Then** it is a **hard** bound that fires regardless of scheduler pressure — not a
soft `receive … after` a busy scheduler can starve — because there is no supervisor
backstop behind it [audit A2].

### Story 3.5: Lock-sweeper contract

As a bee maintainer,
I want the expired-lock sweeper to have an explicit, correct contract — no connection
of its own, dispatching through the writer, one event per expired lock,
So that lock expiry is handled without a rogue connection and without losing an
in-flight write on shutdown.

**Acceptance Criteria:**

**Given** the sweeper on its 60s timer,
**When** it reclaims expired locks,
**Then** it holds **no connection of its own** — it dispatches a lock-expiry
operation to `Bee.Repo` (the writer), which performs the write [G13].

**Given** a batch of expired locks,
**When** they are reclaimed,
**Then** the event cardinality is defined as **one event per expired lock**, not one
per sweep [G13].

**Given** a writer-restart cascade re-runs the sweeper, which re-dispatches expiry
for still-expired locks,
**When** re-dispatch happens,
**Then** it cannot double-count because each lock's release and its event emission
are **one transaction** (AD-19) — a released lock no longer matches the
"expired AND held" query, so a second dispatch is a no-op, not a second event
[cascade F3].

**Given** the event table's "public function" heading,
**When** the sweeper is placed,
**Then** it is listed as an **internal** operation, not under public functions — it is
not consumer-callable [G16].

**Given** the silent-failure exception list,
**When** the sweeper's in-flight write can be lost on a brutal-kill shutdown,
**Then** that loss is added to the enumerated silent-failure exceptions rather than
omitted [G27].

**Given** an orderly shutdown where the sweeper's timer fired just before it was told
to terminate,
**When** the sequence is examined,
**Then** the last dispatch is still processed because a **local** message send enqueues
synchronously and the supervisor sends `Repo`'s shutdown only after the Sweeper is
confirmed dead — so the cast is already in `Repo`'s mailbox before shutdown begins.
This guarantee is **single-node only** (it is NOT per-sender FIFO, which does not
order two different senders); cross-node dispatch is out of scope until the
federation path defines its own ordering. So G27's loss is **strictly** the
brutal-kill / crash case on a single node [chaos S4, audit A7].

**Given** the spine's claim that "lock expiry is runtime mechanics" and not
work-execution modelling,
**When** that claim is re-examined against AD-6,
**Then** it is either defended with a stated reason or reclassified — it is
load-bearing and must not rest on an unexamined assertion [G28].

### Story 3.6: Silent-failure invariant

As a consumer of bee,
I want silence on failure forbidden except for a short, enumerated list of
exceptions,
So that a failure never disappears without a trace I can act on.

**Acceptance Criteria:**

**Given** any operation that can fail,
**When** it fails,
**Then** it returns a tagged error from the closed vocabulary, logs, or falls back —
it never swallows the failure silently [NFR10].

**Given** the enumerated exceptions to the no-silent-failure rule,
**When** they are listed,
**Then** they are **exactly three**, each named with its reason, and the sweeper
in-flight-write case from Story 3.5 is reconciled against this list [NFR10, G27].

**Given** a new code path that would fail silently,
**When** it is reviewed,
**Then** it is rejected unless it is added to the enumerated exception list with a
stated reason — the list is closed, not a convention.

---

## Epic 4: Ask for exactly what you need — Stories

Story order: 4.1 (`query/1` + interpreter) is the foundation; 4.2 (`ask/2` resolves
to a Spec and calls the same interpreter), 4.3/4.4 (detail levels and withheld —
tightly coupled, they cross-reference), 4.5 (usage counting), and 4.6 (canonical
form) all build on it. No story depends on a later one.

### Story 4.1: Composable query core

As a consumer,
I want a single `Bee.query/1` that takes a validated query specification and runs it
through one interpreter,
So that every caller-facing read is expressed the same way and executed by one code
path, not a proliferation of bespoke query functions.

**Acceptance Criteria:**

**Given** a caller builds a `Bee.Query.Spec`,
**When** `Bee.query/1` runs it,
**Then** the spec is validated (per Story 1.1's shared validator) and executed by the
single `Bee.Query.Interpreter` — the only module that turns a Spec into SQL for
caller-facing reads [FR1, AD-4 cl.1 cat.1].

**Given** a structurally invalid spec (unknown field, wrong type),
**When** it is validated,
**Then** it raises in the caller's process / returns at the boundary per the closed
error vocabulary — never a silent empty result [FR1, AD-25].

**Given** any ordered spec,
**When** it is executed,
**Then** `id` is appended to the sort key for deterministic pagination (matching the
parity harness's requirement in Story 1.5).

**Given** two callers expressing the same read,
**When** they build the same Spec,
**Then** they get the same SQL — there is no second query surface that drifts from the
interpreter [FR1].

### Story 4.2: Named intents in two classes

As a consumer,
I want `Bee.ask/2` to resolve a named intent — either a compiled CORE intent or a
runtime-registered one — to a Spec and run it through the same interpreter,
So that common questions have stable names without freezing the catalogue at
design-time or letting it rot.

**Acceptance Criteria:**

**Given** a CORE intent named by an atom,
**When** it is asked,
**Then** it is compiled code (may run arbitrary Elixir), resolves to a Spec, and runs
through `Bee.Query.Interpreter` — the same interpreter as `query/1` [FR2, AD-5].

**Given** a REGISTERED intent named by a string,
**When** it is asked,
**Then** it is a stored spec in the `intents` table, added or removed at runtime with
no release, expressing anything `Bee.query` can and nothing more [FR2, AD-5].

**Given** a registered spec at registration time,
**When** it is registered,
**Then** it is validated by `Bee.Query.Spec` and rejected with `:invalid_spec` if
malformed — registration validates and never raises; resolution never re-validates
(per Story 1.1 / G7) [FR2, AD-5].

**Given** a CORE atom name and a REGISTERED string name,
**When** either is looked up,
**Then** dispatch is by type — atom to core, string to registry — so the two name
spaces can never collide [AD-5].

### Story 4.3: Per-attribute output shaping with presets

As an agent constructing a targeted output format,
I want to shape each attribute independently — the role it plays and the granularity
of its returned value — with named presets for the common cases,
So that I can pull a lean list, a full record, or a precisely mixed shape (this field
summarised, that one full, that one just present) without the engine hauling data it
will only discard.

**Acceptance Criteria:**

**Given** two orthogonal per-attribute knobs — **role** (`retrieve` | `filter` |
`group` | `scan`, i.e. which clause the attribute lands in) and **granularity/
transform** on its retrieved value,
**When** a read is built,
**Then** each attribute is shaped independently; one attribute can be filtered at full
value while another is retrieved at a prefix [FR4, transform-model].

**Given** the granularity of a retrieved attribute is a **tiered transform**,
**When** it is declared,
**Then** it is one of `:pushdown` (computed in SQL — full, char-prefix, presence,
relation-count), `:local` (Elixir, post-fetch — trim, format, redact), or `:external`
(a consumer-registered hook; see Story 4.7). bee ships `:pushdown` and `:local` only
[FR4, transform-model].

**Given** the four named presets (`:minimal`, `:compact`, `:standard`, `:full`) and
`:custom`,
**When** a read specifies one,
**Then** each is an **assignment** over the per-attribute knobs — `:minimal` =
presence/id everywhere, `:full` = full everywhere, `:custom` = a caller-supplied
attribute→transform map, first-class not a fallback [FR4, transform-model].

**Given** an attribute below the selected shape,
**When** the result is built,
**Then** it is an **absent key** (not null, not empty) — the shape selects which
fields are present [FR4, AD-10 amended].

**Given** a relation requested via `include:`,
**When** the read runs,
**Then** it is loaded **batched per result set** — one query for all issues' comments,
not one per issue; a relation not requested is `:not_loaded`, never `[]` [FR4, NFR2,
AD-10 amended].

**Given** an unfiltered list that today fires ~4 queries per row (~10,748 for 2,687
issues),
**When** it runs under the new loader,
**Then** query count is bounded by the number of requested relations, not row count
[NFR2].

**Given** a `:pushdown` granularity such as a char-prefix,
**When** the interpreter emits SQL,
**Then** the prefix is computed in the query (e.g. `substr`) so the full value is
never read and hauled only to be trimmed — the weight is not pulled [transform-model,
efficiency; interpreter mechanics in Story 4.6].

### Story 4.4: withheld and refine on every read

As an agent that received a partial result,
I want every read to tell me what it withheld and how to ask again,
So that I never mistake a truncated or level-limited result for the whole truth.

**Acceptance Criteria:**

**Given** any read,
**When** it returns,
**Then** it carries `withheld` (what was not returned, keyed from the closed withheld
vocabulary) and `refine` (how to ask for it) — silent truncation is forbidden
[FR5, AD-11].

**Given** a relation was omitted because it was not `include:`d,
**When** `withheld` reports it,
**Then** it reports **that** the relation was omitted, not a **count** of rows it did
not load — a count for un-fetched data is unobtainable by construction and must not be
fabricated [G6].

**Given** a shape dropped fields (a preset or `:custom` assignment),
**When** `withheld` reports it,
**Then** it names the omission category and `refine` states the shape or `include:`
that would return them [FR5, AD-11].

**Given** an attribute was returned through a transform (a `:pushdown` prefix, a
`:local` trim, or an `:external` summary),
**When** the read returns,
**Then** `withheld`/`refine` name **the transform applied and its tier per attribute** —
so a caller knows it received a 200-char prefix or an LLM summary, not the source
value, and `refine` gives the `granularity: full` spec that would return it
[FR5, transform-model, AD-11 amended].

**Given** a result limited by a page size,
**When** it returns,
**Then** `withheld` signals there is more and `refine` gives the next-page spec —
never a truncated list presented as complete [FR5].

### Story 4.5: Usage counting off the read path

As a catalogue maintainer,
I want intent usage counted asynchronously, off the read path,
So that the registered catalogue can be pruned by evidence without slowing any read.

**Acceptance Criteria:**

**Given** an intent is asked,
**When** its usage is recorded,
**Then** the count is written to `intent_usage` **asynchronously**, off the read path —
a read never blocks on a usage write [FR3, AD-20].

**Given** usage counts accumulate,
**When** the catalogue is pruned,
**Then** REGISTERED intents can be removed by evidence of disuse [FR3, AD-5].

**Given** the usage write fails,
**When** it does,
**Then** it fails per the silent-failure rule (logged / tagged), and the read it
accompanied is unaffected — usage telemetry is not the event log [AD-20].

### Story 4.6: Canonical-form interpreter and Spec field coherence

As a bee maintainer,
I want the interpreter to emit one canonical SQL form for any query that must hit an
expression index, and the Spec's field set to stay coherent with what the Classifier
expects,
So that dimension queries actually use their indexes and the Classifier never routes
on a field that does not exist.

**Acceptance Criteria:**

**Given** SQLite matches expression indexes on exact text only,
**When** the interpreter emits a query that must hit one,
**Then** it emits **one canonical form** — the same text every time — so the
expression index is used, not bypassed [NFR12, AD-9].

**Given** a `:pushdown` transform on an attribute (char-prefix, presence,
relation-count),
**When** the interpreter emits SQL,
**Then** the transform is computed in the query (e.g. `substr`, an `EXISTS`, a
`COUNT`) so the full value is never materialised — and it too is emitted in one
canonical form, so a pushed-down transform still hits its index [transform-model,
NFR12].

**Given** an attribute carries a `:local` or `:external` transform (tier above
`:pushdown`),
**When** the read is classified,
**Then** tier is an input to the Classifier (Story 3.1): anything above `:pushdown`
cannot ride `:fast` — `:local` routes `:compute`, and an `:external` transform over a
large set is pushed out of the synchronous read (materialised/async), never blocking
the fast lane [transform-model, cross-ref Story 3.1].

**Given** dimension queries land in Epic 6 (measurements),
**When** they are executed,
**Then** they go through this interpreter's canonical-form path — the discipline lives
here in the interpreter; Epic 6 exercises it [NFR12 cross-ref Epic 6].

**Given** the Classifier (Story 3.1) routes a `stats:` Spec field to `:compute`, but
`stats:` is an L3 field and L3 is deferred,
**When** the Spec field set is defined,
**Then** the incoherence is resolved: `stats:` is either reserved as a defined-but-
inert field or removed from the Classifier's table until L3 lands — the Classifier
never references a field the Spec does not define [G24].

**Given** the set-comparison test from Story 3.1,
**When** it runs against the resolved Spec field set,
**Then** it passes because every Classifier-referenced field exists in the Spec [G24].

### Story 4.7: External transform hook (mechanism, not policy)

As a consumer that wants an attribute transformed by something bee must not own
(an LLM summary, a translation, an enrichment),
I want to register that transform and have bee invoke it per attribute through a
bounded, failure-isolated hook,
So that bee stays agnostic — it ships the slot, never the LLM — while I get the
targeted output I asked for.

**Acceptance Criteria:**

**Given** bee must not couple to an external service (AD-6),
**When** an `:external` transform is provided,
**Then** it is **registered by the consumer** (parallel to REGISTERED intents and
consumer measures) and invoked through a hook — bee ships no LLM or external transform
of its own, and never knows the transform is an LLM [transform-model, AD-6,
AD-TRANSFORM new].

**Given** an `:external` transform is applied in a read,
**When** it runs,
**Then** it is tier-classified so it never rides `:fast`, and an LLM-per-row over a
large set is materialised/async rather than run synchronously in the read
[transform-model, cross-ref Story 3.1/4.6].

**Given** an `:external` transform fails or exceeds its bound,
**When** the read completes,
**Then** it **degrades to the untransformed value plus a `withheld` note** naming the
failed transform — it never crashes or hangs the read (silent-failure discipline from
Epic 3 applied to the hook) [transform-model, NFR10].

**Given** the registration surface for external transforms,
**When** a transform is registered,
**Then** it is validated at registration (never raises; returns a tagged error on a
bad registration, per Story 1.1 / G7) and is removable at runtime with no release
[transform-model, AD-TRANSFORM new].

---

## Epic 5: The DAG answers questions about itself — Stories

Story order: 5.1 (dependency types + gate) is foundational — readiness and traversal
both lean on the edge-type semantics. 5.2 (acyclicity) and 5.4 (candidates) are
edge-writing concerns; 5.3 (traversal) is edge-reading; 5.5 is independent cleanup.
No story depends on a later one.

### Story 5.1: A bounded vocabulary of dependency types with a gate truth table

As a consumer asking what can start,
I want a closed, compiled vocabulary of 3-7 dependency types, each carrying explicit
gating semantics in one truth table, and one-hop readiness computed from edge type,
So that "what's ready" is a precise consequence of the edges, and the type dimension
is sharp — neither too thin to define nor too broad to grasp.

**Acceptance Criteria:**

**Given** the dependency-type vocabulary,
**When** it is defined,
**Then** it holds **at least three and at most seven** members (Miller bound: below
three the dimension is too thin to be well-defined; above seven it exceeds
graspability and dilutes) [FR10, AD-13 amended, constitution §III].

**Given** gate semantics drive readiness and are correctness-critical,
**When** the vocabulary is implemented,
**Then** it is **closed and compiled** — like CORE intents and the error atoms, not
runtime-registrable like REGISTERED intents or measures. A consumer cannot add a
dependency type at runtime [FR10, transform contrast].

**Given** each defined type,
**When** its semantics are stated,
**Then** it has exactly one row in one gate truth table saying whether and how it
gates readiness — the table has **one row per defined type (3-7 rows), not a mandated
seven** [FR10, AD-13 amended].

**Given** the temptation to reach seven with speculative types,
**When** the vocabulary is designed,
**Then** only genuinely-needed types are defined — inventing speculative members to
fill the quota is forbidden, because it dilutes the dimension (constitution §III)
[FR10].

**Given** an issue with incoming dependency edges,
**When** readiness is computed,
**Then** it is a one-hop function of the incoming edge types against the gate table —
an issue is ready iff no incoming edge of a gating type is unsatisfied [FR10, AD-13].

**Given** two distinct concepts the word "ready" blurs,
**When** they are defined,
**Then** they are kept separate: the **`ready` query** ("what can I start") returns
**`open` + unblocked** issues — `in_progress` is **excluded** because it is already
claimed and started, matching gc_daemon's actual `ready` semantics; the
**blocked/unblocked property** ("is this work blocked?") is computable for **any**
non-terminal issue, `open` or `in_progress`. A `closed`/`cancelled` issue is N/A to
both [FR10, first-principles].

**Given** an issue with **zero incoming gating edges**,
**When** its readiness is computed,
**Then** it is unblocked — the base case, stated explicitly [FR10, boundary B6].

**Given** the same ordered pair carries more than one gating type (e.g. `A blocks B`
and `A requires B`, both storable under migration 004's `(issue_id, depends_on_id,
dep_type)` PK),
**When** B's readiness is computed,
**Then** it is the **union** — B is blocked if **any** incoming gating edge is
unsatisfied; redundant edges are harmless and the union rule is stated, not emergent
[FR10, boundary B5].

**Given** the gate table,
**When** it is tested,
**Then** every defined type appears in exactly one row, and a type added without a row
fails the test (same set-comparison discipline as the Classifier in Story 3.1) [FR10].

**Given** the Miller bound must be held, not merely documented,
**When** the gate-table test runs,
**Then** it **asserts `3 <= row count <= 7`** and fails outside that range — an eighth
type or a drop below three breaks the build, so the bound is enforced [FR10,
constitution §III, inversion I2].

**Given** a non-gating dependency type,
**When** readiness is computed,
**Then** it is projected/reported but does not gate — its non-gating status is stated
in the table, not inferred [FR10, AD-13].

**Given** a gating edge whose blocker is in some state,
**When** readiness asks whether the edge is *satisfied*,
**Then** the predicate is explicit: a gating edge is **satisfied iff the blocker is
`closed`**; a **`cancelled` blocker also satisfies** (the block is moot — the work
will not happen); `open` and `in_progress` do **not** satisfy. Readiness is never
ambiguous about what clears a blocker [FR10, inversion I3].

**Given** the spine's AD-13 defines **all seven typed edges** with distinct gate
semantics (`blocks`, `waits-for`, `conditional-blocks` gate; `parent-child`,
`related`, `discovered-from`, `replies-to` do not), each earning its place by a
real, distinct meaning,
**When** the implementation is built,
**Then** it supports **all seven** — the readiness engine implements each gating
type's rule from the truth table, and the write path accepts a `dep_type` argument
instead of hardcoding `blocks` (today `insert_dependency` hardcodes it, which is why
only `blocks` appears in data). `parent-child` remains derived from `issues.parent`,
not written (`:unwritable_dep_type`). This is implementation catching up to an
adopted spec — **not an open decision** [FR10, AD-13].

### Story 5.2: Cycle prevention via recursive CTE, in-transaction

As a bee maintainer,
I want dependency and parent cycles prevented by a recursive CTE inside the command
transaction that would create them,
So that the DAG can never acquire a cycle, even under concurrent edge writes.

**Acceptance Criteria:**

**Given** a command that would add a dependency edge,
**When** it runs,
**Then** an acyclicity check (recursive CTE) runs **inside the same transaction**, on
the writer's connection, seeing the in-flight edge — and the command is rejected with
a named error if it would create a cycle [FR11, AD-21, AD-2b].

**Given** a command that would set an issue's `parent`,
**When** it runs,
**Then** the same in-transaction check prevents a parent-hierarchy cycle [FR11].

**Given** two concurrent edge-adding commands that are individually acyclic but
jointly cyclic,
**When** they run,
**Then** serialisation through the single writer plus the in-transaction check means
the second sees the first's committed edge and is rejected — no cycle slips through a
race [FR11, cross-ref Epic 3 single-writer].

**Given** a command that would add a self-dependency (an issue depends on itself,
A→A),
**When** it runs,
**Then** it is rejected with a named error — a self-edge is a trivial cycle (the issue
could never start), and the direct case is checked explicitly, not left to the CTE
alone [FR11, inversion I1].

**Given** the acyclicity CTE,
**When** it is written,
**Then** it is **unbounded** (or bounded strictly past the longest possible path) — a
depth-limited cycle check is forbidden, because a cycle deeper than the limit would
slip through [FR11, inversion I1].

**Given** a loop that crosses both graphs (A depends-on B, B parent-of A),
**When** its safety is assessed,
**Then** it is harmless **because no traversal mixes the two graphs**: `via:` walks
only dependency types (Story 5.3) and `tree` walks only `parent`, so a dep+parent loop
is a cycle in neither walked graph. Introducing a mixed walk that would make such a
loop reachable is a spine amendment, not a casual feature [FR11, inversion I1,
cross-ref Story 5.3].

### Story 5.3: Graph traversal as spec fields, with a grammar that holds its edges

As a consumer walking the DAG,
I want traversal expressed as `via:` spec fields — direction, depth, and a closed set
of dependency types — executed by the one interpreter,
So that traversal is as composable as any other query and the type filter stays
sharp.

**Acceptance Criteria:**

**Given** a traversal,
**When** it is expressed,
**Then** it is `via:` spec fields (direction, depth, `types:`) resolved to a
`Bee.Query.Spec` and executed by `Bee.Query.Interpreter` — traversal emits no SQL of
its own [FR12, AD-4 cl.1].

**Given** the `via: types:` filter,
**When** its vocabulary is defined,
**Then** it is **closed to exactly the defined gating dependency types** (the 3-7
vocabulary from Story 5.1) — each of which has a real traversal meaning [FR12, G25,
constitution §III "a grammar is defined by what it refuses"].

**Given** a `via: types:` value outside that set — `parent-child` (a projected,
non-gating relation), a typo, or any future non-gating relation,
**When** it is validated,
**Then** it is **rejected with a named error** (`:invalid_via_type`), never silently
walked-as-nothing and never muddily accommodated — the sharpness is enforced at the
boundary, not merely documented [G25, constitution §III].

**Given** hierarchy IS traversable, but through a **direction**, not a type,
**When** a caller wants to walk parent-child,
**Then** the spine's `via:` grammar already provides it as the `:ancestors` /
`:descendants` **directions** (which follow `issues.parent`, per AD-3/AD-4), alongside
`tree`. `parent-child` is excluded from the `types:` *filter* precisely because
hierarchy is a **direction**, not a gating edge type — putting it in `types:` would be
the meaningless member the sharp-grammar rule rejects [G25, reconciled with spine
via: grammar].

**Given** the `via: types:` field,
**When** it is omitted versus an empty list,
**Then** **omitted defaults to the gating types** (`blocks`, `waits-for`,
`conditional-blocks`) — matching the spine's `via:` grammar, since traversal usually
follows what gates — and **`types: []` is rejected** with a named error: "follow none
of the types" is a meaningless request, the degenerate case the sharp-grammar
principle excludes [FR12, constitution §III, boundary B1, reconciled with spine].

**Given** the `via:` direction field,
**When** a traversal is expressed,
**Then** direction is **required** (or has one explicitly-documented default) — upstream
("what blocks me") and downstream ("what I block") are opposite walks, and an ambiguous
direction silently returns the wrong half of the graph [FR12, boundary B2].

**Given** `via: depth: 0`,
**When** it runs,
**Then** it returns the **start node only** (zero hops = itself) — a defined base case,
not an accidental empty or error [FR12, boundary B3].

**Given** a traversal from a root id that does not exist,
**When** it runs,
**Then** it returns a **named error**, never a silent empty result conflated with "no
edges"; a `closed`/`cancelled` root traverses its edges normally (terminal status
stops readiness, not traversal) [FR12, boundary B7].

**Given** a `via: types:` list with more than one dependency type (e.g.
`[blocks, requires]`),
**When** it is walked,
**Then** it is **coherent** — following multiple edge kinds **within the one
dependency graph** is meaningful, unlike mixing in `parent` (a second graph). This is
why a multi-type dependency filter is allowed while the dep+parent mix is rejected
[FR12, first-principles, cross-ref G25].

**Given** an unbounded-depth traversal,
**When** it runs,
**Then** it terminates safely **because Story 5.2 guarantees the dependency graph is
acyclic** — a finite reachable set, so no depth cap is needed for correctness (mirror
of 5.2's cross-graph brace) [FR12, first-principles, cross-ref Story 5.2].

### Story 5.4: Advisory candidate edges on write

As an LLM consumer that tends to skip declaring dependencies,
I want bee to propose candidate edges after I create or update an issue,
So that I am prompted to declare a dependency I would otherwise have left implicit —
without ever being forced to.

**Acceptance Criteria:**

**Given** a create or update command,
**When** it commits,
**Then** candidate edges are computed **after commit, on the writer's connection,
under a bounded timeout**, and returned as advisory suggestions [FR13, AD-16, AD-2b].

**Given** candidate edges are advisory,
**When** they are returned,
**Then** they are **never mandatory** — the command has already committed; candidates
are a suggestion the consumer may act on or ignore, never a gate [FR13, AD-16].

**Given** the candidate computation exceeds its bounded timeout,
**When** it does,
**Then** it returns no candidates rather than delaying the command's reply — the nudge
is best-effort and never on the critical path [FR13, AD-16].

**Given** the intent is to prompt dependency declaration,
**When** candidates are surfaced,
**Then** they are shaped so a consumer can turn a suggestion into a declared edge in
one follow-up command — the nudge is actionable, not just informational.

### Story 5.5: Resolve graph/allocation.ex

As a bee maintainer,
I want `graph/allocation.ex` investigated and resolved — removed if dead, relocated
and renamed if it is legitimate graph math, escalated if it truly models allocation,
So that no module's name asserts a work-execution domain bee forbids itself.

**Acceptance Criteria:**

**Given** `graph/allocation.ex` exists with a name in the agent-load/allocation domain
that AD-6 forbids bee to model,
**When** it is investigated,
**Then** its actual behaviour is determined via the elixir-context call graph (callers
and calls), not assumed [G22, constitution §V].

**Given** the investigation finds it is dead code,
**When** it is resolved,
**Then** it is removed.

**Given** the investigation finds it is legitimate graph computation wearing a
work-execution name,
**When** it is resolved,
**Then** it is renamed and relocated so its name states what it does, with no
allocation-domain vocabulary [G22, AD-6].

**Given** the investigation finds it genuinely models allocation (capacity, load,
assignment optimisation),
**When** it is resolved,
**Then** it is an AD-6 violation and is escalated — removed from bee or moved to a
consumer — because bee must not own that domain [G22, AD-6].

**Given** allocation-domain creep is a recurring hazard, not a one-time fix,
**When** the resolution lands,
**Then** a standing lint (beside the spine self-checks) flags AD-6-forbidden domain
vocabulary — `capacity`, `allocation`, `availability`, `cost rate`, `working time` —
appearing in bee's source, so the exclusion is held over time, not re-litigated
[G22, AD-6, constitution §V "recurring hazards become standing checks", inversion I5].

---

## Epic 6: bee accumulates evidence about the work — Stories

Story order: 6.1 (events) is foundational — measurements and rollups emit events.
6.2 → 6.3 → 6.4 is the measure chain (define → record → aggregate). 6.5 is
independent; 6.6 is the epic's closing boundary. No story depends on a later one.

### Story 6.1: One event per accepted command

As a future consumer of bee's history (including L3),
I want exactly one event per accepted command in an append-only log emitted by a
single module and retained forever,
So that the event log is a trustworthy, unrecreatable record — never double-written,
never compacted.

**Acceptance Criteria:**

**Given** an accepted command (passed validation AND produced a non-empty delta),
**When** it commits,
**Then** exactly **one** event is written, inside the command transaction, by
`Bee.Store.Events` — the **sole** module that inserts into `events` [FR6, AD-7, AD-19].

**Given** a command that produced an empty delta,
**When** it completes,
**Then** it emits **no** event and returns `{:ok, report}` with an empty `applied`
list — an event means a real state change [FR6, AD-7].

**Given** the empty-delta check and event emission both run inside the transaction,
**When** they are ordered,
**Then** empty-delta detection **precedes** (gates) emission — a no-op command can never
write a phantom event [FR6, inversion I2].

**Given** the event insert is inside the command transaction,
**When** either the state change or the event insert fails,
**Then** the whole transaction rolls back — state-without-event and event-without-state
are both impossible; they commit atomically or not at all [FR6, AD-19, inversion I2].

**Given** the seven non-command writes enumerated in AD-19 (including the lock
sweeper),
**When** they run,
**Then** they emit **no** event — the one-event-per-command rule's only exceptions,
stated, not implicit [FR6, AD-7, AD-19].

**Given** an event needs a name,
**When** it is written,
**Then** the name comes from the function→event table — the sole naming authority — and
`events.issue_id` is `NOT NULL`, which is why non-issue-scoped writes cannot be
commands [FR6, AD-7, AD-8].

**Given** the event log is the only unrecreatable asset and L3's only input,
**When** retention is considered,
**Then** it is kept **forever** — no compaction, no aging, no deletion (~20k rows /
~7MB for all history to date). Adding a compactor is a spine amendment [NFR9, AD-7].

**Given** retention-forever is a recurring hazard (a future "cleanup" could delete),
**When** it is enforced,
**Then** a standing lint asserts **no `DELETE FROM events`** anywhere in bee's source —
retention held by a check, not just documented (same pattern as the coupling sweep and
allocation lint) [NFR9, constitution §V, inversion I5].

**Given** bee has **no command idempotency key**,
**When** a consumer retries a command after a lost reply (writer committed, reply lost),
**Then** bee receives it as a **new** command → a duplicate command + event (correct
from bee's side: two commands received). Exactly-once is a **consumer concern /
deferred feature**, stated here rather than silently assumed [FR6, inversion I1].

### Story 6.2: Measurements as measure x dimensions

As a consumer calibrating bee with effort/duration signal,
I want to record a measurement as a runtime-registered, unit-bound measure against
schemaless dimensions,
So that bee collects the evidence it needs without owning a fixed measurement schema.

**Acceptance Criteria:**

**Given** a measure,
**When** it is registered,
**Then** it is runtime-registered and **unit-bound** — a measurement in the wrong unit
is rejected with a named error (arithmetic hygiene, not domain modelling, per AD-6)
[FR7, AD-9].

**Given** a measurement against an unregistered measure,
**When** it is recorded,
**Then** it is rejected with a named error — unknown measures are not silently accepted
[FR7, AD-9].

**Given** effort and duration are non-negative by nature while bee stays agnostic about
a measure's semantics,
**When** a measure is registered,
**Then** it may declare a **validity domain** (e.g. non-negative) alongside its unit,
and a value outside the domain is rejected with a named error — "unit-bound" becomes
"unit-and-domain-bound," so a negative effort cannot silently corrupt a rollup [FR7,
AD-9, boundary B2].

**Given** dimensions,
**When** they are attached to a measurement,
**Then** they are **schemaless but grammared** — open in what they can express, but
emitted in the one canonical form so dimension queries hit their expression indexes
(NFR12, Story 4.6) [FR7, AD-9, NFR12].

**Given** a dimension value supplied on a **write**,
**When** the measurement is stored,
**Then** the value is **canonicalised (or rejected with a named error) on write** — a
non-canonical value stored verbatim would silently miss the expression index on later
reads; canonicalisation at write time closes that silent gap [FR7, NFR12, inversion I4].

### Story 6.3: Recording paths — measure: and Bee.measure/3

As a consumer recording effort,
I want to attach a measurement when I update or close an issue, and to record one
retroactively, with the estimate/actual distinction always explicit,
So that no measurement is silently misclassified and every one is fully populated.

**Acceptance Criteria:**

**Given** an update or close command,
**When** it carries a `measure:` option,
**Then** the measurement is recorded in the **same transaction** as the command, and
the command still emits exactly one event (per Story 6.1) [FR8, AD-9b].

**Given** a retroactive recording,
**When** `Bee.measure/3` is called,
**Then** it records a measurement outside a command — its own write, per AD-19's
enumerated non-command writes [FR8, AD-9b].

**Given** the `kind` distinction (estimate vs actual) is a **binary flag, not a
dimension** (two members, below the 3-floor — a boolean, exempt from the 3-7 rule like
enumerative sets),
**When** a measurement is recorded on either path,
**Then** `kind` is **required and explicit** — omitting it is a **named error**, never a
silent default to `actual`. This resolves both G8 (always populated, because required)
and G29 (no misclassification, because no silent default) [FR8, G8, G29, constitution
§III].

### Story 6.4: Rollups — one aggregator, scope selectors, honest total

As a consumer asking for the total effort under a node,
I want rollups computed on demand by one aggregator over a selected scope, reporting
an honest nil when the data is incomplete,
So that I get the real number or a truthful "unknown," never a confident wrong total.

**Acceptance Criteria:**

**Given** a rollup over a node set,
**When** it is computed,
**Then** it uses **one aggregator** with a pluggable scope selector — `:tree`,
`:closure`, or `:critical_path` (a closed dimensional vocabulary of exactly three, at
the Miller floor) [FR9, AD-12].

**Given** each scope selector picks a node set,
**When** the set is defined,
**Then** each selector **precisely defines what it follows and includes**: `:tree`
follows `parent` (hierarchy descendants); `:closure` follows the **gating dependency
edges only** (not non-gating relations, which would roll up unrelated work). An
imprecise node set is a wrong total, not a nil [FR9, AD-12, inversion I3b].

**Given** a cancelled node may hold real effort spent before cancellation,
**When** a selector defines contribution,
**Then** it **states which meaning it computes** — "effort spent" (a cancelled node's
recorded effort **counts**, the work happened) vs "effort to complete" (it does
**not**, the work is moot) — so cancelled effort is never silently dropped or silently
included [FR9, AD-12, boundary B9].

**Given** a DAG where a node is reachable by more than one path,
**When** the rollup aggregates,
**Then** each node is counted **exactly once** (node-set union), never summed per-path —
a diamond-shaped graph must not double-count, which would be the confident wrong number
this story exists to prevent [FR9, AD-12, inversion I3c].

**Given** `:critical_path` must select the longest-effort path,
**When** any node on the candidate paths lacks an effort measurement,
**Then** the path **cannot be determined** and the result is `nil` — never a path
guessed from incomplete effort [FR9, AD-12, inversion I3d].

**Given** a node measured at exactly `0` versus a node with no measurement,
**When** completeness is assessed,
**Then** they are **distinct**: `0` is a **complete** measurement (genuinely trivial
effort); only an **absent** measurement triggers `total: nil`. Conflating them would
either nil-out a complete rollup or break the nil-honesty by treating missing as zero
[FR9, AD-12, boundary B1].

**Given** any node in the scope lacks an effort measurement,
**When** the rollup is computed,
**Then** `total:` is **nil** — never a partial sum presented as complete [FR9, AD-12].

**Given** a node carries **more than one** measurement of the same `(measure, kind)`
(worked across sessions, or re-recorded to correct),
**When** the rollup reduces it,
**Then** per-node effort is the **latest** measurement (a read-time reduction over the
append-only measurement history); the rollup then sums each node's latest **once**
(per I3c). Re-recording **corrects**; **accrual across sessions is the consumer's job**
(record the running total) — so the total is deterministic regardless of how many times
a value was recorded [FR9, AD-12, boundary B7].

**Given** a rollup requested over a node id that does not exist,
**When** it runs,
**Then** it returns a **named error**, not `nil` — `nil` means "incomplete data," which
is a different failure from "no such node"; the two are never conflated [FR9, AD-12,
boundary B4].

**Given** rollups are computed **on demand** (largest measured subtree is 69 nodes),
**When** the aggregator runs,
**Then** nothing is materialised — on-demand computation is justified at this scale
[NFR8, AD-12].

**Given** `refine` was vacuous for a `total: nil` rollup (no query option cures a
missing measurement),
**When** a rollup returns `total: nil`,
**Then** `refine` names **which nodes lack an effort measurement** — the only real
remedy is to record the missing data (a data act, not a query option), so `refine`
points at the gap rather than offering a useless knob [FR9, G21, honest-limit pattern].

### Story 6.5: Metadata JSON extension point

As a consumer needing to attach my own data to bee's entities,
I want a sanctioned metadata JSON field on issues and projects,
So that I can extend without altering bee's schema.

**Acceptance Criteria:**

**Given** an issue or a project,
**When** a consumer attaches data,
**Then** it goes in the `metadata` JSON field — the sanctioned extension point — and no
consumer alters bee's schema to add fields (per NFR11) [FR15, AD-14].

**Given** the `bee:` key prefix in metadata,
**When** the field is defined,
**Then** `bee:` is **reserved and unused** — held for bee's own future use so a
consumer key can never collide with one bee later introduces [FR15, AD-14].

### Story 6.6: L3-deferral exit criterion

As the operator guarding scope,
I want Epic 6 to ship the measurement substrate and nothing that reads it for
optimisation,
So that the deferred L3 intelligence layer cannot creep in through the door the event
history opens.

**Acceptance Criteria:**

**Given** Epic 6 ships events, measurements, and rollups,
**When** its boundary is drawn,
**Then** it delivers the **measurement substrate only** — nothing that *reads* the
accumulated history for optimisation, prediction, or critical-path *intelligence*
(the `:critical_path` scope selector computes a rollup over a given path; it does not
*choose* the path) [FR6-9, L3 deferral].

**Given** enough event history will eventually exist to tempt an L3 build,
**When** that temptation arises,
**Then** L3 is a **separate future epic**, not scope creep into this one — deferral is
an **exit criterion** of Epic 6, enforced at review, not a margin note [premortem
death #4].

---

## Spine Amendments — LANDED 2026-07-24

**Status: applied.** The `bmad-architecture` Update pass ran 2026-07-24 and landed all
four amendments in the spine (AD IDs stable; AD-27 added as the new decision). The
reviewer gate passed: lint_spine 0 findings, check_absolutes 0 unreviewed, api_coverage
clean, findings clean. The list below is retained as the record of what changed.

**Reconciliations discovered during the Update** (epics.md corrected to match the spine,
which is the authority on what the code must do):
- **Story 5.1** — the spine's AD-13 already DEFINES seven typed edges with gate
  semantics; only `blocks` is used in data. The open decision is which *defined* types
  to start writing, not which to invent. (Story 5.1 corrected.)
- **Story 5.3** — hierarchy IS traversable via `via:` `:ancestors`/`:descendants`
  DIRECTIONS (not `tree` alone); `parent-child` is excluded from `types:` because
  hierarchy is a direction, not a gating type. (Story 5.3 corrected.)
- **Story 5.3** — `via: types:` omitted defaults to the GATING types (not "all
  defined"), matching the spine grammar. (Story 5.3 corrected.)

The original amendment list (now applied):

- **AD-10 — amend.** From "four detail levels (`:minimal/:compact/:standard/:full`),
  a field below the level is an absent key" to: output is shaped by two orthogonal
  per-attribute knobs — **role** (retrieve/filter/group/scan) and a **tiered
  transform** (`:pushdown`/`:local`/`:external`) on the retrieved value. The four
  levels plus `:custom` are **presets** (named assignments) over this primitive, not
  the primitive itself. The absent-key and `:not_loaded` rules carry over unchanged.

- **AD-11 — amend.** `withheld`/`refine` must additionally report, per attribute, the
  **transform applied and its tier**, so a caller knows it received a prefix or a
  summary rather than the source value, and how to obtain `granularity: full`.

- **AD-TRANSFORM — new decision.** A per-attribute transform hook as a first-class
  extension point, sibling to AD-5 (intents), AD-9 (measures), AD-14 (metadata).
  Binds: the interpreter, the classifier, the registration surface. Rule: bee owns
  the **mechanism** (a tiered transform slot + a consumer registration hook), never
  the **policy** — it ships `:pushdown` and `:local` transforms and never performs an
  external one. An `:external` transform is consumer-registered, tier-classified so it
  never rides `:fast`, and failure-isolated (degrade to untransformed value + a
  `withheld` note, never crash or hang). Prevents: bee absorbing text-understanding or
  coupling to a live external service (guards AD-6).

- **AD-3 — note.** The Classifier already keys on spec shape; **tier is spec shape**,
  so admitting tier as a classification input is consistent with AD-3, not an
  exception to it. No amendment, but the set-comparison test (G14) must include the
  tier dimension.

- **AD-13 — amend.** "Seven dependency types" is a **bound, not a fixed enumeration**:
  a closed, compiled vocabulary of **3-7** types (Miller: three floor, seven ceiling),
  each with distinct gate semantics, one gate-table row per defined type. Inventing
  speculative types to reach seven is forbidden (dilution). Open: production has one
  type (`blocks`) today; meeting the floor is an operator design decision (Story 5.1).

Scope held: Epic 4 implements `:pushdown` + `:local` + the `:external` registration
hook. No LLM or external transform ships inside bee; the summary-via-LLM transform is
a consumer registration or an L3-era capability.

Cross-cutting principle (from the operator, 2026-07-24): the **3-7 Miller bound**
governs *dimensional* closed vocabularies (dependency types, transform tiers, detail
presets) — not *enumerative* sets like the error-atom vocabulary, which may exceed
seven. Recorded in constitution §III alongside "a grammar is defined by what it
refuses."
