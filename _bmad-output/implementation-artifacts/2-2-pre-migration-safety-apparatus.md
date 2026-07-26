---
baseline_commit: 0e165b1
---

# Story 2.2: Pre-migration safety apparatus

Status: review

## Story

As an operator migrating a live Bee database,
I want a torn-free backup and integrity gate before any pending migration mutates it,
So that every failure is recoverable and leaves the source database unchanged.

## Acceptance Criteria

1. A migration run with pending work creates a fresh, timestamped `VACUUM INTO`
   backup before the first migration.
2. A completed backup must pass `PRAGMA integrity_check`, `foreign_key_check`, and
   source-version parity before migrations proceed.
3. No backup is taken when the database is already at target version.
4. Backup creation failures return `:backup_failed`; integrity and verification
   failures return `:integrity_check_failed` and `:verification_mismatch`.
5. A failed preflight prevents migrations from running and leaves the source untouched.

## Tasks / Subtasks

- [x] Add conditional preflight backup to `Bee.Store.Migrate.run_at_boot/2`.
- [x] Create backups using `VACUUM INTO`, never filesystem copy.
- [x] Verify integrity, foreign keys, and `user_version` parity before migration.
- [x] Add tests for verified backup-before-migration, no-op no-backup, and failure
  before migration.
- [x] Format and run the dedicated migration test suite.

## Dev Notes

- The source database is never copied directly. `VACUUM INTO` includes the active WAL
  state in a single consistent backup file.
- The live database is not used in tests. A prior verified snapshot lives under
  `~/.local/share/gc/backups/bee.db/`; the isolated fixture is used for manual
  rehearsal only.
- Backup paths are exclusive: an existing destination fails rather than being
  overwritten.

## Dev Agent Record

### Completion Notes List

- The runner now creates and verifies a backup only when the migration plan is ahead
  of the database version.
- Ten isolated migration tests pass, including the backup ordering and preflight
  failure boundary.

### File List

- `lib/bee/store/migrate.ex` (modified)
- `test/migrate_test.exs` (modified)

## Change Log

- 2026-07-26: Added conditional VACUUM backup and integrity preflight for Epic 2.
