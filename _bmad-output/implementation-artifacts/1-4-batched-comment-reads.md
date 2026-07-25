---
baseline_commit: 03893a6
---

# Story 1.4: Read comments back, batched, in the relation shape

Status: review

## Story

As an agent coordinating through Bee,
I want comments read through both the module API and the GenServer protocol,
so that agents can read the comments they write without causing per-issue comment queries.

## Acceptance Criteria

1. `include: [:comments]` returns comments through the module API and the equivalent GenServer message API.
2. A read without the comments include returns `comments: :not_loaded`, never `[]`.
3. A result set of N issues with comments requested loads comments in one batched query, not one query per issue.
4. Enriched issue maps merge comments alongside existing labels, dependencies, and locks.

## Tasks / Subtasks

- [x] Task 1: Add red tests for comment relation behavior (AC: 1-4)
  - [x] Cover requested and omitted comments through module and message `get` calls.
  - [x] Cover grouped, ordered comment loading through `list` and `tree_page`.
  - [x] Preserve existing two-argument `Bee.get(id, server)` and `{:get, id}` compatibility.
- [x] Task 2: Add opt-in, batched comment loading (AC: 1-4)
  - [x] Preserve the literal `{:get, id}` request and add `{:get, id, opts}` as an additive protocol request.
  - [x] Add an isolated, parameterized Store batch loader, with `created_at, id` ordering and an empty list for requested issues with no comments.
  - [x] Thread `include: [:comments]` through `get`, `list`, and `tree_page`; all omitted paths use `:not_loaded`.
  - [x] Do not make comments default-loaded, alter the schema, or make `ready/2` honor options.
- [x] Task 3: Update the versioned contract and validate (AC: 1-4)
  - [x] Document the additive `{:get, id, opts}` form and comments relation behavior.
  - [x] Run formatter, spine checks, and the full test suite using only isolated temporary SQLite files.

## Dev Notes

### Safety boundary

Never use a live Bee database, invoke migrations, start the application, or access `gc_daemon`. All tests must reuse `test/bee_test.exs` setup, which creates a unique SQLite file under `System.tmp_dir!()` with `jsonl_path: nil`.

### Implementation decisions

- The existing `Bee.get(id, server)` call must remain valid. Add `Bee.get(id, opts, server)` while guarding the options form so a server name is not mistaken for options.
- Preserve `{:get, id}`. `{:get, id, opts}` is an additive message-protocol request and must use the same boundary validation behavior as Story 1.1.
- `include: [:comments]` is supported for `get`, `list`, and `tree_page`. `ready/2` keeps its existing option-discarding behavior and returns `comments: :not_loaded`.
- The current default loading of labels, dependency directions, and locks remains unchanged. This story only makes comments explicit and opt-in.
- Use one parameterized `IN` query for the result collection, ordered by `issue_id ASC, created_at ASC, id ASC`; use raw prefixed ids to group before public numeric-id projection.
- An omitted comments relation is `:not_loaded`. A requested relation with no comments is `[]`.
- Do not introduce an index or any schema change.

### Target files

- `lib/bee.ex`
- `lib/bee/repo.ex`
- `lib/bee/store.ex`
- `test/bee_test.exs`
- `docs/contracts/bee-repo-message-protocol.md`

### References

- [Source: `_bmad-output/planning-artifacts/epics.md` - Story 1.4]
- [Source: `lib/bee.ex` - module API]
- [Source: `lib/bee/repo.ex` - message handlers]
- [Source: `lib/bee/store.ex` - comments and enrichment]
- [Source: `test/bee_test.exs` - isolated SQLite setup]

## Dev Agent Record

### Agent Model Used

GPT-5.6 Terra

### Debug Log References

- Confirmed the test suite uses unique temporary SQLite files with JSONL disabled.

### Completion Notes List

- Added opt-in `include: [:comments]` support for `get`, `list`, and `tree_page` across both module and message APIs.
- Added direct `Bee.get_comments/2` and `{:get_comments, id}` reads for agents that need one issue's comment stream.
- Added `get_comments_for_issues/2`, a single parameterized grouped query preserving `created_at, id` comment order.
- Omitted comments now consistently return `:not_loaded`; requested empty relations return `[]`.
- Confirmed the protocol addition is additive and validated all checks with 46 passing tests. No live Bee database, migration, application server, or gc_daemon process was accessed.

### File List

- `_bmad-output/implementation-artifacts/1-4-batched-comment-reads.md` (new)
- `_bmad-output/planning-artifacts/architecture/architecture-bee-2026-07-20/ARCHITECTURE-SPINE.md` (modified)
- `lib/bee.ex` (modified)
- `lib/bee/repo.ex` (modified)
- `lib/bee/store.ex` (modified)
- `test/bee_test.exs` (modified)
- `docs/contracts/bee-repo-message-protocol.md` (modified)

## Change Log

- 2026-07-25: Added batched, opt-in comments relation reads and completed Story 1.4.
