---
baseline_commit: 81a9497
---

# Story 1.5: Behaviour-parity harness over both surfaces

Status: review

## Story

As a bee maintainer,
I want a parity harness that replays a fixed corpus against both the module API and
the message protocol and asserts identical behaviour, wired to run on every epic
release,
So that no later epic can silently change what a consumer receives on either surface.

## Acceptance Criteria

1. The harness replays a fixed corpus against both the module API (`Bee.*`) and the
   GenServer message protocol (`{verb, args}`), asserting identical behaviour on
   **both** surfaces. [NFR6, G30]
2. Declared breaking changes are present in a machine-readable exception list and the
   harness passes because the difference is declared, not because it went unnoticed.
3. `id` is appended to every ordered spec for deterministic pagination.
4. The harness re-runs via the post-commit hook on every commit that touches `.ex`
   files; it is a standing check, not a one-time Epic 1 deliverable. [premortem L1]

## Tasks / Subtasks

- [x] Task 1: Build the parity harness test file
  - [x] Fixed corpus: three issues with labels, priority, hierarchy, comments, a dependency edge, and a lock.
  - [x] Read parity: get, get with include comments, get missing, get_comments, get_comments empty.
  - [x] List/count/tree_page/ready parity with valid opts.
  - [x] Write parity: create and comment return identical results via both surfaces.
- [x] Task 2: Machine-readable exception list
  - [x] `docs/contracts/parity-exceptions.json` declares `validation_error_surface`.
  - [x] Harness reads and asserts the exception list is well-formed and declares the known difference.
  - [x] Tests assert module API raises ArgumentError while message boundary returns tagged error.
  - [x] Tests assert the writer process survives the message-boundary validation error.
- [x] Task 3: Deterministic pagination
  - [x] Ordered specs include `id` in the sort key.
  - [x] Tests assert two consecutive calls produce identical ordering.
- [x] Task 4: Standing check wiring
  - [x] Post-commit hook runs `mix test test/parity_harness_test.exs` when `.ex` files change.
- [x] Task 5: Validate without touching live data
  - [x] All tests use unique temporary SQLite files with `jsonl_path: nil`.
  - [x] Formatter, spine checks, and full suite pass.

## Dev Notes

### Safety boundary

Never use a live Bee database, invoke migrations, start the application, or access
`gc_daemon`. All tests use unique SQLite files under `System.tmp_dir!()` with
`jsonl_path: nil`.

### Design decisions

- The module API and the message protocol are nearly isomorphic for valid inputs:
  `Bee.get/2` calls `GenServer.call(server, {:get, id})` internally. Parity for
  writes is therefore trivially identical (both route through the same
  `handle_call`). The harness focuses on reads, where the module API adds
  caller-process validation on top.
- The single declared exception (`validation_error_surface`) is intentional per
  AD-25 / Story 1.1: structural/type errors raise in the caller's process (module
  API) but return `{:error, reason}` at the server boundary (message protocol), so
  a bad option arriving by message never raises inside `handle_call` and kills the
  single writer.
- `id` is appended to ordered specs because SQLite row ordering is not guaranteed
  beyond the sort key; without `id` as a tiebreaker, two issues with the same
  `priority` could appear in different orders across calls, making parity
  assertions flaky.
- The exception list is a JSON file (not a module attribute) so it is
  machine-readable by other tools and can be extended without touching test code.

### Target files

- `test/parity_harness_test.exs` (new)
- `docs/contracts/parity-exceptions.json` (new)
- `.git/hooks/post-commit` (modified — standing check wiring)

### References

- [Source: `_bmad-output/planning-artifacts/epics.md` - Story 1.5]
- [Source: `lib/bee.ex` - module API]
- [Source: `lib/bee/repo.ex` - message handlers]
- [Source: `docs/contracts/bee-repo-message-protocol.md` - versioned contract]

## Dev Agent Record

### Agent Model Used

GLM-5.2 (Droid Core)

### Completion Notes List

- 21 parity tests covering get, get_comments, list, count, tree_page, ready, write, declared exceptions, and deterministic pagination.
- `docs/contracts/parity-exceptions.json` declares the single intentional difference (validation error surface).
- Post-commit hook runs the harness on every commit touching `.ex` files.
- No live Bee database, migration, application server, or gc_daemon process was accessed.

### File List

- `test/parity_harness_test.exs` (new)
- `docs/contracts/parity-exceptions.json` (new)

## Change Log

- 2026-07-25: Built parity harness, exception list, and standing-check wiring for Story 1.5.
