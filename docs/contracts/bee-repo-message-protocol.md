# Bee.Repo Message Protocol Contract

**Protocol version:** 1.0.0
**Status:** current baseline
**Owner:** `Bee.Repo`

`Bee.Repo`'s public GenServer message protocol is a supported contract, equal to
the `Bee.*` in-process module API. It is the node-crossing interface used by
`gc_daemon`; it is not a private implementation detail.

This document owns the public request grammar, reply shapes, protocol version, and
breaking-change ledger. `Bee.*` remains the in-process facade for embedders.

## Compatibility policy

Every change to this protocol is classified before release:

- **Additive:** introduces a new optional field and no existing consumer pattern
  breaks. It does not require consumer coordination.
- **Breaking:** changes an existing request, field, or reply shape. It increments
  the protocol major version and requires consumer coordination.

The protocol version is independent of the `bee` package version. Version 1.0.0
freezes the literal wire grammar below. In particular, bare requests remain bare;
they are not rewritten into a synthetic `{verb, args}` envelope.

## Public requests and replies

`id`, `issue_id`, and `blocker_id` accept the identifier forms currently resolved
by `Bee.Repo`. `opts` is a keyword list and `attrs` is a map unless noted otherwise.
The listed replies are the current baseline, not a promise that a malformed message
can never fail outside the protocol's declared validation boundary.

| Request | Success reply | Current declared error reply |
| --- | --- | --- |
| `{:get, id}` | `{:ok, issue}` | `{:error, :not_found}` |
| `{:ready, opts}` | `{:ok, issues}` | none |
| `{:list, opts}` | `{:ok, issues}` | `{:error, reason}` for invalid boundary options |
| `{:count, opts}` | `{:ok, count}` | `{:error, reason}` for invalid boundary options |
| `{:tree_page, opts}` | `{:ok, %{roots: roots, issues: issues, total_roots: total_roots}}` | `{:error, reason}` for invalid boundary options |
| `{:create, title, opts}` | `{:ok, issue}` | none |
| `{:update, id, attrs}` | `:ok` | `{:error, :not_found \| :self_parent \| :parent_cycle}` |
| `{:comment, id, text, opts}` | `:ok` | `{:error, reason}`, including `:not_found` |
| `{:block, id, blocker_id}` | `:ok` | `{:error, :cycle}` |
| `{:unblock, id, blocker_id}` | `:ok` | none |
| `{:lock, id, opts}` | `{:ok, lock}` | `{:error, :already_locked \| :not_found \| reason}` |
| `{:unlock, id}` | `:ok` | none |
| `{:register_project, id, attrs}` | `{:ok, project}` | none |
| `{:register_agent, id, attrs}` | `{:ok, agent}` | none |
| `{:assign, issue_id, agent_id}` | `:ok` | none |
| `{:join_project, agent_id, project_id}` | `:ok` | none |
| `:who_blocks_whom` | `[{blocker_agent_id, blocked_agent_id}]` | none |
| `{:agent_load, agent_id}` | non-negative integer | none |
| `:bottlenecks` | `[{agent_id, load, project_ids}]` | none |
| `{:import_jsonl, path}` | `{:ok, imported_count}` | `{:error, reason}` |

Boundary validation follows AD-25: `Bee.*` raises `ArgumentError` in its caller for
structural errors, while raw invalid messages return `{:error, reason}` from
`Bee.Repo` and must not raise inside `handle_call/3`.

## Non-public handler messages

- `:conn` is retired. It exposes the writer connection and is not part of this
  contract.
- `:prefix` is implementation-private. It is intentionally excluded until a future
  contract change either makes it public or removes it.

## Initial breaking-change ledger

The following `gc_daemon` operational sites currently discard a Bee reply and
report success even when the protocol returns `{:error, reason}`. Before a new
error reply is relied upon for these requests, the consumer must propagate that
error instead of claiming success:

| Consumer site | Request | Required adaptation |
| --- | --- | --- |
| `lib/gc_daemon/api/work_handler.ex:272` | `{:update, id, done_attrs}` | return `{:error, reason}` rather than always reporting `closed: true` |
| `lib/gc_daemon/api/work_handler.ex:294` | `{:comment, id, note, []}` | return `{:error, reason}` rather than always reporting `commented: true` |
| `lib/gc_daemon/api/work_handler.ex:326` | `{:block, id, depends_on}` | return `{:error, reason}` rather than always reporting `blocked: true` |
| `lib/gc_daemon/api/work_handler.ex:331` | `{:unblock, id, depends_on}` | return `{:error, reason}` rather than always reporting `unblocked: true` |
| `lib/gc_daemon/api/work_handler.ex:345` | `{:unlock, id}` | return `{:error, reason}` rather than always reporting `released: true` |
| `lib/gc_daemon/api/work_handler.ex:356-359` | `{:update, id, cancelled_attrs}` | return `{:error, reason}` rather than always reporting `cancelled: true` |
| `lib/gc_daemon/api/work_handler.ex:1144` | `{:register_project, id, attrs}` | propagate the registration result instead of discarding it |

The 34 operational call-site corpus, including its propagated and intentional
fallback cases, is recorded in Bee work item `GC-3412`. Its two preview-only
`{:get, id}` calls are not operational protocol adaptations.

## Verification

Story 1.5 turns this contract and the `GC-3412` corpus into the standing
machine-checked parity harness. Until then, a protocol change must be reviewed
against this table and ledger before release.
