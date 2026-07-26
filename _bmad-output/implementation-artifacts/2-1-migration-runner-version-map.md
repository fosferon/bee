---
baseline_commit: e3750a8
---

# Story 2.1: Migration runner with an explicit version map

Status: review

## Story

As a bee maintainer,
I want a boot-time migration runner driven by an explicit migration-to-version map,
So that schema upgrades are deterministic, resumable, and reject a newer schema.

## Acceptance Criteria

1. Pending migrations run in ascending order, each inside its own transaction, with
   `PRAGMA user_version` written last.
2. `target_version/0` and the migration-to-version map are explicit.
3. A database already at target runs no migrations; a database ahead of target fails
   with `:version_ahead`.
4. A failed migration rolls back only its transaction, reports
   `{:migration_failed, name, reason}`, and a later boot resumes at that migration.
5. The runner is validated on the isolated production-copy fixture without mutating it.

## Tasks / Subtasks

- [x] Add `Bee.Store.Migrate` with explicit migration-plan validation, version map,
  target version, and transactional runner.
- [x] Run the migration gate before `Bee.Repo` opens its writer connection.
- [x] Add tests for ordered execution, no-op target, failed migration rollback,
  resume, version-ahead refusal, and invalid plans.
- [x] Validate the default no-op runner against the production-copy fixture and prove
  its SHA-256 is unchanged.
- [x] Run scoped formatting and the full Bee test suite.

## Dev Notes

- The default migration plan is empty until Stories 2.3–2.5 add migrations 000–004.
  This makes the new boot hook a no-op for the deployed schema while exercising the
  same control path.
- `Bee.Store.Migrate` owns a short-lived connection and closes it before
  `Bee.Repo` opens its writer connection.
- The live database was backed up with `VACUUM INTO` before implementation. All
  development and validation used the isolated production-copy fixture.

## Dev Agent Record

### Completion Notes List

- Added transactional migration execution with a strict sequential version plan.
- Added boot-time gating before writer ownership.
- Validated seven migration tests and the full 75-test suite.
- Ran the no-op default runner against the isolated production-copy fixture and
  verified its SHA-256 remained unchanged.

### File List

- `lib/bee/store/migrate.ex` (new)
- `lib/bee/repo.ex` (modified)
- `test/migrate_test.exs` (new)

## Change Log

- 2026-07-26: Implemented and validated the Epic 2 migration runner foundation.
