# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-08-16

### Added

- Composable coordination queries for projects, agents, intents, measurements,
  candidates, allocation, critical paths, and recent issue activity.
- Bounded projections and explicit result limits suitable for MCP consumers.

### Fixed

- Coordination events now count as issue activity.
- Creation timestamps remain stable across updates and query projections.

## [0.1.0] - 2026-07-30

First public release.

### Added

- **Work DAG** — issues with a typed dependency vocabulary: gating (`blocks`,
  `waits_for`, `conditional_blocks`), non-gating (`related`, `discovered_from`,
  `replies_to`), and structural (`parent_child`). Cycle detection at write time.
- **Allocation tree** — projects, agents, assignments, project membership, with
  `who_blocks_whom/1`, `agent_load/1`, and `bottlenecks/0`.
- **Query engine** — composable specs (`status`, `project_id`, `assigned_to`,
  `labels`, `order_by`, `limit`/`offset`, `include`, `detail`, `transforms`)
  that return matched issues **plus** a `withheld` report and a `refine` hint.
- **Detail levels** — `:minimal | :compact | :standard | :full` projection presets.
- **Intents** — `ask/2` resolves a built-in (`:what_next`) or a registered name to
  a query spec; intents are persisted via `register_intent/3`.
- **Graph operations** — `ready/0`, `traverse/2` (`:blockers` / `:dependents`),
  `candidates/1`, memoized `critical_path/0`, and `rollup/2`
  (`:tree | :closure | :critical_path`).
- **Measurements × dimensions** — `register_measure/3` and `measure/3` for opaque
  numeric signal with schemaless, indexable JSON dimensions (required `"kind"` of
  `"estimate"` or `"actual"`).
- **Event log** — append-only, per-issue monotonic sequence capturing every
  mutation; the global id cursor enables tailing.
- **Locks** — `lock/2` / `unlock/1` with TTL, holder, `force`, and a background
  sweeper that releases expired locks.
- **Versioned migrations** — ordered, idempotent, run at boot behind
  `PRAGMA user_version`.
- **Two first-class surfaces** — the `Bee.*` module API and a versioned `Bee.Repo`
  GenServer message protocol.
- **Reader pool** — a two-lane (`:fast` / `:compute`) NimblePool of read-only
  connections over WAL snapshots; writes serialised through a single writer.
- **Import / export** — JSONL export (debounced, flushed on orderly shutdown) and
  `import_jsonl/1`, with first-boot seeding from an empty database.

[0.2.0]: https://github.com/fosferon/bee/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/fosferon/bee/releases/tag/v0.1.0
