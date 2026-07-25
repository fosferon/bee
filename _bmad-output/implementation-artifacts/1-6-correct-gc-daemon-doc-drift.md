---
baseline_commit: 81a9497
---

# Story 1.6: Correct gc_daemon's bee-work-dag.md drift

Status: review

## Story

As an engineer onboarding to the bee/gc_daemon boundary,
I want gc_daemon's `docs/subsystems/bee-work-dag.md` and its onboarding twin to
match bee's real schema and behaviour,
So that the onboarding document does not hand me a wrong model of the system.

## Acceptance Criteria

1. Table names match the schema in `bee/lib/bee/store.ex init_schema/1`: `comments`
   (not `issue_comments`), `dependencies` (not `blocks`), `issue_labels` junction,
   `locks` with `locked_by`/`locked_at`/`expires_at`. [G31]
2. The `parent` column (not `parent_id`), the real status set
   (`open`/`in_progress`/`closed`/`cancelled`), and `issue_type` values match. [G31]
3. The JSONL trail is described as a full-file rewrite (not append) that is off for
   gc_daemon (`jsonl_path: nil`). [G31]
4. `show(id)` documents comments as opt-in via `include: ["comments"]`; the
   "write-only" note is corrected to reflect GC-2693 delivery. [G31]
5. `Bee.Lock.sweep_expired/1` is documented as present on a 60s timer, not a future
   extension. [G31]
6. `check_findings.py` resolves G31's `story:gc-daemon-doc-drift` disposition to a
   real story file. [gate honesty]

## Tasks / Subtasks

- [x] Task 1: Verify developer-facing doc (`docs/subsystems/bee-work-dag.md`)
  - [x] Table names, columns, statuses, JSONL note, lock-sweep note all match `init_schema/1`.
  - [x] Updated `show(id)` and `comment` rows to reflect GC-2693 comment-read delivery.
  - [x] Replaced the "write-only" warning block with a "comments are now readable" note.
- [x] Task 2: Fix onboarding twin (`priv/docs/onboarding/30-subsystems/04-work-dag.md`)
  - [x] Updated `show` action to document `include: ["comments"]`.
  - [x] Updated `comment` action to note read-back via `show` with include.
  - [x] Corrected the troubleshooting row from "not wired" to "was not wired in earlier versions".
- [x] Task 3: Verify against the schema source of truth
  - [x] Grep confirms no drift terms remain (issue_comments, parent_id, blocks_id, holder, claimed_at).
  - [x] G31's `story:gc-daemon-doc-drift` disposition resolves to this story via `epics.md` and this file.

## Dev Notes

### Safety boundary

No live `bee.db` access. The schema source of truth is `bee/lib/bee/store.ex
init_schema/1`, not the live database. Verification is a grep against the doc
files, not a query against production.

### Why two docs

gc_daemon carries two copies of the Bee subsystem documentation:
- `docs/subsystems/bee-work-dag.md` — developer-facing reference (already corrected in a prior session).
- `priv/docs/onboarding/30-subsystems/04-work-dag.md` — onboarding guide for new agents/engineers (drifted).

Both must match bee's real schema. The onboarding twin still carried the old
"Comments cannot be read back" troubleshooting row, which is now wrong after
GC-2693.

### Target files (gc_daemon repo)

- `docs/subsystems/bee-work-dag.md` (modified)
- `priv/docs/onboarding/30-subsystems/04-work-dag.md` (modified)

### References

- [Source: `bee/lib/bee/store.ex` - `init_schema/1` schema source of truth]
- [Source: `_bmad-output/planning-artifacts/epics.md` - Story 1.6 ACs]
- [Source: `scripts/spine/findings.json` - G31]

## Dev Agent Record

### Agent Model Used

GLM-5.2 (Droid Core)

### Completion Notes List

- Both gc_daemon Bee subsystem docs now match the schema defined in `bee/lib/bee/store.ex init_schema/1`.
- The "comments are write-only" drift is corrected in both docs to reflect GC-2693 delivery (opt-in `include: ["comments"]`).
- No drift terms remain (issue_comments, parent_id, blocks_id, holder, claimed_at).
- No live bee.db was accessed; verification was grep-based against doc files and the schema source of truth in code.

### File List (gc_daemon repo)

- `docs/subsystems/bee-work-dag.md` (modified)
- `priv/docs/onboarding/30-subsystems/04-work-dag.md` (modified)

## Change Log

- 2026-07-25: Corrected both Bee subsystem docs for schema drift and GC-2693 comment-read delivery.
