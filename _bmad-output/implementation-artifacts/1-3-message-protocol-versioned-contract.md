---
baseline_commit: 40dc8fe
---

# Story 1.3: Message protocol as a versioned contract

Status: review

## Story

As a consumer maintainer (`gc_daemon`),
I want the Bee GenServer message protocol declared a first-class versioned contract with an explicit compatibility policy,
so that I coordinate an upgrade only when a change actually breaks a consumer reply pattern.

## Acceptance Criteria

1. `Bee.Repo`'s public GenServer requests and their success and error replies are documented as a supported contract, peer to the `Bee.*` module API, not an implementation detail.
2. The contract classifies changes as additive (new optional field, no current consumer pattern breaks) or breaking (an existing request, field, or reply shape changes). Only breaking changes increment the contract major version and require consumer coordination.
3. The initial contract explicitly records the Story 1.2 breaking-change set: `gc_daemon` sites at `work_handler.ex:272`, `:294`, `:326`, `:331`, `:345`, `:356-359`, and `:1144` ignore a Bee reply and require an error path before a new error shape is relied upon.
4. The architecture spine makes `Bee` and `Bee.Application` L4 Facade modules, adds a protocol-contract AD, and changes the Structural Seed to map modules to files and ADs without restating AD-owned responsibilities.

## Tasks / Subtasks

- [x] Task 1: Create the canonical message-protocol contract (AC: 1, 2, 3)
  - [x] Preserve the current literal wire grammar, including bare list-returning requests. Do not introduce a `{verb, args}` envelope.
  - [x] Set independent initial contract version `1.0.0`; do not couple it to package version `0.1.0`.
  - [x] Document every public `Bee.*` operation's matching request and current success/error reply.
  - [x] Exclude `:conn` as explicitly retired and classify `:prefix` as implementation-private until a later story decides otherwise.
  - [x] Record the seven `gc_daemon` adaptation targets individually, with their current unsafe success report and the required `{:error, reason}` propagation.
- [x] Task 2: Amend the architecture spine (AC: 1, 2, 4)
  - [x] Make the Facade `L4` in the Design Paradigm table.
  - [x] Add the next numbered AD, owning protocol support, document ownership, and the additive/breaking policy while referencing AD-25 for validation behavior.
  - [x] Correct the Structural Seed's ownership statement and remove the `export.ex` responsibility paraphrase.
  - [x] Update the Constitution's protocol-AD pointer without duplicating the contract table.
- [x] Task 3: Validate documentation and database safety (AC: 1-4)
  - [x] Verify every documented request against `Bee` and `Bee.Repo`.
  - [x] Run the existing spine checks if present, then `mix test`.
  - [x] Resolve the pre-existing `mix format --check-formatted` failures before marking the story complete. Do not start `Bee.Repo` with a non-temporary path, invoke migrations, access `gc_daemon`, or access any live Bee database. The ExUnit setup uses unique files under `System.tmp_dir!()` with `jsonl_path: nil`.

## Dev Notes

### Safety boundary

This story is documentation and architecture only. It must not alter runtime code, SQLite schema, migrations, data paths, or process configuration. Never run an application server or inspect/write a live `bee.db`. Test setup at `test/bee_test.exs:5-26` creates a uniquely named SQLite file under `System.tmp_dir!()`, starts a uniquely named `Bee.Repo`, passes `jsonl_path: nil`, and removes only that temporary file.

### Current protocol baseline

`lib/bee.ex` exposes 20 public operations. `lib/bee/repo.ex` defines matching `handle_call/3` clauses, plus the private `:conn` and `:prefix` requests. Freeze the existing literal request grammar, including `:who_blocks_whom` and `:bottlenecks`; the `{verb, args}` wording in the epic is descriptive, not a request to alter the wire format.

Current read shapes:

- `{:get, id}` returns `{:ok, issue} | {:error, :not_found}`.
- `{:list, opts}`, `{:count, opts}`, and `{:tree_page, opts}` return their `{:ok, value}` result or the Story 1.1 boundary validation error.
- `{:ready, opts}` returns `{:ok, issues}`.
- `:who_blocks_whom` and `:bottlenecks` intentionally return raw lists.

The command surface intentionally has mixed existing success envelopes (`:ok` and `{:ok, value}`); this story documents, rather than normalizes, those shapes. Do not promise error shapes the current implementation cannot return. The contract must distinguish actual current errors from future error vocabulary extensions.

### Story 1.2 intelligence

The primary consumer has 34 operational raw calls, plus two preview-only `{:get, id}` calls. Seven operational sites discard the reply and falsely report success: `work_handler.ex:272` (done update), `:294` (comment), `:326` (block), `:331` (unblock), `:345` (release), `:356-359` (cancel update), and `:1144` (project registration). They are breaking-change coordination targets, not changes to make in this repository during Story 1.3.

Thirteen sites use an intentional fallback (`_ -> ...`), fourteen propagate non-success replies, and two plan requests consume raw lists. The contract must describe those facts without collapsing fallback handling and ignored replies into one category.

### Architecture guardrails

- Add `AD-28` after AD-27. It must name the contract document as the sole owner of request grammar, reply shapes, current version, and breaking-change ledger.
- Keep AD-25 authoritative for module-API raising versus boundary tuple errors. AD-28 references it, it must not duplicate it.
- Make the Design Paradigm row `L4 Facade`, so AD-1's downward-dependency rule is decidable for `Bee` and `Bee.Application`.
- Replace the Structural Seed claim with module → file → AD mapping. Seed entries cite ADs but do not paraphrase AD-owned responsibilities.
- The Constitution can point to AD-28, but must not copy the wire table.

### Project Structure Notes

- New canonical contract: `docs/contracts/bee-repo-message-protocol.md`.
- Architecture changes: `_bmad-output/planning-artifacts/architecture/architecture-bee-2026-07-20/ARCHITECTURE-SPINE.md`.
- Constitutional cross-reference only: `docs/CONSTITUTION.md`.
- No new dependencies, code modules, schema objects, migrations, or consumer-repository edits.

### References

- [Source: `_bmad-output/planning-artifacts/epics.md` - Story 1.3]
- [Source: `_bmad-output/planning-artifacts/architecture/architecture-bee-2026-07-20/ARCHITECTURE-SPINE.md` - AD-1, AD-25, AD-26, AD-27, Structural Seed]
- [Source: `lib/bee.ex` - public module API]
- [Source: `lib/bee/repo.ex` - current `handle_call/3` protocol]
- [Source: `test/bee_test.exs` - isolated temporary SQLite setup]
- [Source: Bee work item `GC-3412` - Story 1.2 reply-shape corpus]

## Dev Agent Record

### Agent Model Used

GPT-5.6 Terra

### Debug Log References

- Confirmed test isolation before development: every test server uses a unique SQLite path under `System.tmp_dir!()` and `jsonl_path: nil`.

### Completion Notes List

- Published protocol contract version 1.0.0, preserving all current literal message forms and documenting replies for the 20 public `Bee.*` operations.
- Recorded the seven gc_daemon ignored-error adaptations as the initial breaking-change ledger.
- Added AD-28, assigned `Bee` and `Bee.Application` to L4, and corrected Structural Seed ownership wording.
- Validated all spine checks and `mix test` (40 tests, 0 failures). Tests used only unique temporary SQLite files and JSONL was disabled; no live Bee database, migration, application server, or gc_daemon process was accessed.
- Applied the user-approved formatter to existing Elixir source, then verified `mix format --check-formatted`.

### File List

- `_bmad-output/implementation-artifacts/1-3-message-protocol-versioned-contract.md` (new)
- `docs/contracts/bee-repo-message-protocol.md` (new)
- `_bmad-output/planning-artifacts/architecture/architecture-bee-2026-07-20/ARCHITECTURE-SPINE.md` (modified)
- `docs/CONSTITUTION.md` (modified)
- `lib/bee.ex` (formatted)
- `lib/bee/agents.ex` (formatted)
- `lib/bee/export.ex` (formatted)
- `lib/bee/store.ex` (formatted)
- `test/bee_test.exs` (formatted)

## Change Log

- 2026-07-25: Defined Bee.Repo's versioned message-protocol contract and completed Story 1.3.
