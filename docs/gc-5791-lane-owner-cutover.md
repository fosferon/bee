# GC-5791 staged Bee owner cutover

This increment is opt-in (`lane_write_fence: true` on Bee.Repo/Bee.Supervisor).
It does not activate Grand Central's Workbench edge or supply a G2 gateway.
Bee's existing default remains compatible while the consuming daemon prepares
and reviews its deliberate dependency update and cutover.

The owner classifies every legacy mutation in its mailbox using its writer
connection. Reads remain reads; unsupported future mutations deny. Target sets
include both dependency endpoints, old/new parents, project/agent/measure
references, every imported issue/comment/dependency reference plus its stored old parent and incident graph endpoints, and an immutable
snapshot of expired-lock targets. Any linked target prohibits legacy mutation.
An absent payload lane field is never a neutral classification. Owner restart
retains the durable links. A diagnostic classification is not an admission permit.

Imports are read and validated once in both fence modes. Nondeleting SQL upsert retains owner event history and propagates every write failure. The qualified decoded snapshot is applied
inside one owner transaction; a later invalid write rolls back every earlier
change. Graph rebuild/export scheduling follow successful commit. Prepared
import/sweeper messages are private to the owner wrapper, never callable by
sending those messages directly to the public GenServer protocol.

The separate internal mutate_lane_issue port accepts a closed set of comment,
update, assign and unlock commands. An admission callback supplies the original
principal/lane decision and is checked after BEGIN IMMEDIATE. The Bee-local
command key binds principal, lane, issue, action and exact body. The issue write,
owned event and durable receipt commit together. Exact retry reuses the receipt;
changed request conflicts; another caller/lane cannot receive it. A receipt read
checks the current issue sequence/link and reports matching versus stale. Missing
receipt is not a G2 absence certificate or a safe-abandon proof. An issue shared
by multiple lanes denies until a gateway can prove admission for every lane.

The port carries no bearer token. It does not authenticate an external payload,
allocate Workbench lane-wide sequence, issue a DispatchPermit, authorize fan-out,
or persist a Workbench submission/outbox/abandonment decision. Those remain G2.
No HTTP/MCP route, worker or schedule is activated by this dependency increment.

Acceptance fixtures cover neutral legacy behavior, linked mutation denial,
complete graph/parent/import targets, import rollback, restart classification,
deny-by-default owner-message inventory, caller/key mismatch, exact-key concurrency,
receipt restart/reconciliation, shared-lane denial, current admission inside the
owner transaction, and issue/event/receipt rollback on injected SQLite failure.
The default-mode existing suite must also pass to prove staged compatibility.

Final bounded evidence (2026-10-04): full Bee suite 250 tests, zero failures
(one existing performance exclusion), seed recorded in
/private/tmp/gc-5791-bee-owner-final-suite.log. Three independent review layers
resolved all confirmed defects; default and fenced import rollback, collateral
targets and private messages also passed external independent probes.

## Owner-only registry and bulk extension

The consumer audit found additional raw writer bypasses. The staged extension
adds closed `upsert_project_registry` and `backfill_projects` owner messages.
Project upserts carry twelve canonical fields and the original fourteen-column
row snapshot (nil for a new project); the owner compares that exact snapshot
inside BEGIN IMMEDIATE before writing, preserving created identity and refusing
stale overwrites. There is no SQL, connection loan, or executable builder port.
Project target qualification includes every issue referring to that project.
Backfill qualifies every issue and its existing parent, then commits all actual
issue changes, audit log rows and owned events in one transaction. Already-filled
rows contribute zero to the returned update count. Both messages requalify under
the write transaction; unknown messages still fail closed when fenced.

Legacy Store.update_issue now propagates column and label write errors to its
existing Repo transaction, so failed updates cannot emit successful receipts or
cause gc_work done to report closure. Five permanent fixtures cover snapshot
conflicts, project fence rejection, all-target bulk rejection, audit rollback,
and column/label failure rollback. Standalone suite: 255 tests, zero failures,
one existing performance exclusion; seed 430745. These changes remain local,
unpublished, and require independent extension review and consumer verification.

Consumer compatibility check: bulk backfill preserves the original issue updated_at,
as required by the existing wire fixture. The new owned event and audit log carry
the backfill time; unrelated issue timestamps are not rewritten.
Independent edge review found malformed IDs could reach a SQL bind in fenced
project writes, or raise in default-mode backfills. The project classifier now
checks binary/nonempty bounds before binding; bulk ID validation handles parser
errors and wrong prefixes. Both modes have permanent malformed-input fixtures.
A concurrent initial-project CAS fixture proves exactly one winner. Full suite
with these additional fixtures: 257/0, seed338554; final guard recheck after the
project classifier fix: 23/0, seed110697. Final extension review remains required.
