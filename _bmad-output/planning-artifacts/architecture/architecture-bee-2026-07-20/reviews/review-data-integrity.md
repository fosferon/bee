# Data-Integrity / Migration-Safety Review — bee Architecture Spine

**Reviewer role:** Data integrity & migration safety
**Target:** `_bmad-output/planning-artifacts/architecture/architecture-bee-2026-07-20/ARCHITECTURE-SPINE.md`
**Date:** 2026-07-20
**Method:** Spine + `lib/bee/store.ex` + design brief read against a READ-ONLY inspection of the live production database at `/Users/leonidas/.local/share/gc/bee.db`.

---

## VERDICT

**BLOCK — do not implement migration 001 as specified.**

AD-15 is the highest-risk invariant in the spine and it is currently under-specified in ways that lead to (a) a **direct contradiction with its own cited source**, (b) a **silent data-loss path for 219 rows**, (c) a **boot-brick availability risk on the one production database that matters**, and (d) **no backup or rollback story anywhere in the document**. The live schema is materially different from what `Bee.Store.init_schema/1` would produce, in ways the spine does not appear to know about.

The good news: the FTS content is fully reconstructible, referential integrity is currently clean, and the failure modes below are all fixable at the spec level. This is a "fix the spec before writing code" block, not a "the plan is wrong" block.

---

## 0. Ground truth — the ACTUAL live schema

Measured, not assumed. All figures from read-only queries against the live DB.

```
file:  /Users/leonidas/.local/share/gc/bee.db     17,391,616 bytes
       bee.db-wal                                  4,202,432 bytes  (UNCHECKPOINTED)
       bee.db-shm                                     32,768 bytes
       bee.db.bak-20260703-233311                 12,521,472 bytes  (17 DAYS STALE)

PRAGMA user_version = 0
PRAGMA journal_mode = wal
PRAGMA integrity_check = ok
FTS5 integrity: could not be run (requires write access) — UNVERIFIED
```

Row counts:

| Table | Rows | Owner |
| --- | ---: | --- |
| `issues` | **2687** | bee |
| `comments` | 2633 | bee |
| `dependencies` | 357 | bee |
| `projects` | 89 | bee (+19 consumer columns) |
| `agents` | 56 | bee |
| `issue_labels` | 7722 | bee |
| **`labels`** | **219** | **GHOST — not in `init_schema/1`, not read by bee** |
| `locks` | 0 | bee |
| `project_agents` | 0 | bee |
| `id_counter` | 1 (`GC` → 2696) | bee |
| `issues_fts` | 2687 | **consumer-injected** |
| `issues_fts_{data,idx,content,docsize,config}` | shadow | **consumer-injected** |
| `issue_project_backfill_log` | 260 | **consumer-injected** |

Note the brief and the spine both cite 2686 issues. It is **2687**. Minor, but the spine's Deferred section computes dependency density from that number.

### 0.1 The live `issues` table does NOT match `init_schema/1`

This is the finding that undermines AD-15's boot check more than anything else.

```sql
-- LIVE (sqlite_master)
CREATE TABLE issues (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT,
  status TEXT NOT NULL DEFAULT 'open',
  priority INTEGER DEFAULT 0,          -- <<< code says: priority INTEGER
  issue_type TEXT NOT NULL DEFAULT 'task',
  project_id TEXT,                     -- <<< code says: REFERENCES projects(id)
  assigned_to TEXT,                    -- <<< code says: REFERENCES agents(id)
  parent TEXT REFERENCES issues(id),
  created_at TEXT NOT NULL,
  created_by TEXT,
  updated_at TEXT NOT NULL,
  closed_at TEXT,
  close_reason TEXT
);
```

Three divergences from `lib/bee/store.ex:43-58`:
1. `priority INTEGER DEFAULT 0` — live has a default the code does not.
2. `project_id` has **no foreign key**. The code declares one.
3. `assigned_to` has **no foreign key**. The code declares one.

Similarly `locks.locked_by` in production is bare `TEXT`; `store.ex:91` declares `REFERENCES agents(id)`.

And `dependencies` appears in `sqlite_master` as `CREATE TABLE IF NOT EXISTS "dependencies"` — the **quoted** identifier is SQLite's signature of a table that has been through an `ALTER TABLE ... RENAME` (i.e. a 12-step rebuild), not an original `CREATE`.

**Implication:** the production `issues` table was rebuilt at some point by something, and lost its foreign keys in the process. Any AD-15 boot check that compares `sqlite_master` SQL text — or even normalised column/constraint sets — against `init_schema/1` **will reject the production database.** See Finding 4.

### 0.2 Indexes: live has ones the code does not create, and vice versa

| Index | In `init_schema/1`? | In prod? | Owner |
| --- | --- | --- | --- |
| `idx_issues_status` | yes | yes | bee |
| `idx_issues_project` | yes | yes | bee |
| `idx_issues_assigned` | yes | yes | bee |
| **`idx_issues_parent`** | **NO** | **yes** | unknown / consumer |
| **`idx_projects_status`** | **NO** | **yes** | consumer |
| **`idx_projects_domain`** | **NO** | **yes** | consumer (indexes a consumer column) |

`idx_projects_domain` indexes `projects.domain`, which is one of the 19 ALTERed columns. Any migration that rebuilds `projects` must drop and recreate this index or the rebuild fails / the index silently vanishes.

---

## 1. AD-15 vs the actual schema: the FTS drop/rebuild

> **AD-15:** "Migration 001 drops and rebuilds the consumer-injected FTS objects rather than adopting them in place."

### 1.1 FINDING (CRITICAL): the spine CONTRADICTS its own cited source

The spine's frontmatter lists `docs/plans/2026-07-20-bee-supercharger-design-brief.md` as a source. That brief, at **D7**, says the exact opposite:

> **"Migration 001 must ADOPT gc_daemon's injected objects, not collide with them:** `issues_fts` + 3 triggers, 19 ALTERed `projects` columns, `issue_project_backfill_log`."

And §5 restates it: "native FTS5 **(adopting existing objects)**".

AD-15 says DROP AND REBUILD. The brief says ADOPT. **These are different migrations with different risk profiles and different consumer-breakage.** One of them is wrong and the spine does not acknowledge the reversal or justify it. An implementer reading only the spine will build the destructive one; an implementer reading only the brief will build the adoptive one.

**Required:** the spine must either (a) revert to ADOPT, or (b) explicitly record the reversal with reasoning, and state what happens to the *other two* injected artefacts (the 19 columns, `issue_project_backfill_log`) which AD-15 conspicuously does not mention at all.

### 1.2 The FTS drop itself is data-safe — but only by luck

Good news, measured:

```
issues:            2687
issues_fts:        2687
missing from FTS:     0
orphaned in FTS:      0
duplicate issue_id:   0
issues_fts_content:2687 rows (c0,c1,c2)
```

The FTS table is a **standard content-owning FTS5 table** (`issues_fts_content` is populated), and its indexed columns are `issue_id UNINDEXED, title, description` — all three sourced verbatim from `issues`. **Nothing in the FTS index is unrecoverable.** A drop-and-rebuild loses zero unique data. Rebuild cost is trivial: 3,481,966 bytes of `title + description` across 2687 rows — sub-second.

This is worth stating explicitly in the spine, because it is the entire justification for choosing DROP over ADOPT and it is currently unstated.

### 1.3 FINDING (HIGH): trigger/table drop ORDERING is unspecified and the wrong order breaks all writes

The three injected triggers are defined **ON `issues`**, not on the FTS table:

```sql
CREATE TRIGGER issues_fts_ai AFTER INSERT ON issues BEGIN
  INSERT INTO issues_fts (issue_id, title, description)
  VALUES (new.id, new.title, COALESCE(new.description, ''));
END;
CREATE TRIGGER issues_fts_ad AFTER DELETE ON issues BEGIN
  DELETE FROM issues_fts WHERE issue_id = old.id;
END;
CREATE TRIGGER issues_fts_au AFTER UPDATE ON issues BEGIN
  DELETE FROM issues_fts WHERE issue_id = old.id;
  INSERT INTO issues_fts (issue_id, title, description)
  VALUES (new.id, new.title, COALESCE(new.description, ''));
END;
```

Consequences the spine must pin down:

- **If `issues_fts` is dropped before the triggers**, every subsequent `INSERT`/`UPDATE`/`DELETE` on `issues` fails with `no such table: main.issues_fts`. If the migration then aborts partway (or the boot sequence proceeds), the database is in a state where **bee cannot write at all**. Correct order is: `DROP TRIGGER` ×3 → `DROP TABLE issues_fts` → recreate → backfill → recreate triggers.
- **`issues_fts_au` fires on EVERY column update**, not just `title`/`description`. There is no `OF title, description` clause. So every status change, every reparent, every `assigned_to` write currently does a delete+reinsert into FTS. If migration 001's rebuild is implemented as `INSERT INTO issues_fts SELECT ... FROM issues` **while the `_ai` trigger is still installed**, you get nothing (trigger is on `issues`, not `issues_fts`) — but if any migration step **rewrites rows in `issues`** (e.g. a backfill of a new column via `UPDATE issues SET ...`), the still-installed `_au` trigger fires 2687 times mid-migration. Harmless if the FTS table exists; fatal if it has already been dropped.
- **SQLite ≥3.25 rewrites trigger bodies on `ALTER TABLE ... RENAME TO`.** If any migration performs a 12-step rebuild of `issues` (see Finding 2.2), the rename step will silently rewrite these consumer triggers to reference the new name, and the final `DROP TABLE issues_old` will **silently drop all three triggers**. There is no error. FTS then goes stale forever with no signal. `PRAGMA legacy_alter_table` behaviour must be explicitly chosen and documented.

**Required:** AD-15 must specify the exact DDL ordering, and every migration that touches `issues` structurally must state its interaction with these triggers.

### 1.4 FINDING (HIGH): consumer code will break at an unspecified moment

`gc_daemon/lib/gc_daemon/bee/search_index.ex:43-71` creates these objects. If bee drops and rebuilds them, gc_daemon's `search_index.ex` will — on its next run — either re-create what bee just made (name collision / duplicate triggers) or, worse, `DROP` and re-create bee's version with the consumer's definition, re-establishing the exact drift AD-14 exists to prevent.

AD-14 says "no consumer creates, alters or drops objects in bee's database" — but that is a rule for the *future*. **The spine has no sequencing statement for the changeover.** Ordering matters: gc_daemon's injection code must be removed *before or atomically with* bee's migration 001, or the two will fight. This is called out as GC-2694 ("consumer adaptation, deferred") — but deferring it means the destructive migration ships into a daemon that still actively re-injects. That is not a deferrable dependency; it is a hard ordering constraint.

---

## 2. The 19 ALTERed `projects` columns

### 2.1 FINDING (CRITICAL): they hold real data, and the spine never mentions them

AD-14 declares `projects.metadata` the sanctioned extension point and calls the 19 columns an "incident". But **the columns exist and are populated across the live 89-row `projects` table.** Measured population (non-null and not `''`/`{}`/`[]`):

| Column | Type/default | Populated |
| --- | --- | ---: |
| `canonical_path` | `TEXT` | 1 / 89 |
| `description` | `TEXT` | **65 / 89** |
| `stack` | `TEXT` | **65 / 89** |
| `domain` | `TEXT` | 19 / 89 |
| `repo_url` | `TEXT` | 19 / 89 |
| `branch` | `TEXT` | 1 / 89 |
| `binary_path` | `TEXT` | 0 / 89 |
| `launchd_service` | `TEXT` | 0 / 89 |
| `data_dir` | `TEXT` | 0 / 89 |
| `notes` | `TEXT` | **58 / 89** |
| `ports_json` | `TEXT NOT NULL DEFAULT '{}'` | 8 / 89 |
| `domains_json` | `TEXT NOT NULL DEFAULT '[]'` | 19 / 89 |
| `tags_json` | `TEXT NOT NULL DEFAULT '[]'` | 1 / 89 |
| `commands_json` | `TEXT NOT NULL DEFAULT '[]'` | 0 / 89 |
| `key_files_json` | `TEXT NOT NULL DEFAULT '[]'` | 2 / 89 |
| `related_projects_json` | `TEXT NOT NULL DEFAULT '[]'` | 2 / 89 |
| `metadata_json` | `TEXT NOT NULL DEFAULT '{}'` | **64 / 89** |
| `source` | `TEXT NOT NULL DEFAULT 'manual'` | **89 / 89** |
| `last_synced_at` | `TEXT` | **63 / 89** |

Bee's own `projects` columns are exactly six: `id, name, path, status, created_at, updated_at`. **Everything after `updated_at` in the live DDL is consumer-added.** (Answers mandate item 7.)

The spine says metadata is the extension point. It does **not** say:
- whether migration 001 leaves these 19 columns alone (safe, but permanently enshrines the drift AD-14 condemns);
- whether it migrates them into `projects.metadata` as JSON (requires a written, tested transform — and gc_daemon's `project_registry.ex:614-655` reads them by name, so it breaks the consumer on the same beat);
- whether it drops them (**catastrophic**: destroys 65 descriptions, 65 stacks, 64 metadata_json blobs, 58 notes, 89 source values, 63 sync timestamps).

**This is the single largest data-loss path in the plan, and it is an omission rather than a decision.** A silence here is the most dangerous kind — an implementer told "metadata is the extension point, consumers never touch bee's DDL" and handed a database with 19 non-conforming columns can very reasonably read that as licence to clean up.

**Required:** AD-14 or AD-15 must state, in one explicit sentence, the fate of the 19 columns. The recommendation is: **leave them in place, untouched, in migration 001. Schedule any consolidation as a separate, later, backed-up migration gated on GC-2694.**

### 2.2 FINDING (MEDIUM): `projects` cannot be rebuilt cheaply

Three of the 19 columns are `NOT NULL DEFAULT` (`ports_json`, `domains_json`, `tags_json`, `commands_json`, `key_files_json`, `related_projects_json`, `metadata_json`, `source` — eight in total). SQLite's 12-step table rebuild requires reproducing all of them exactly, plus the two consumer indexes `idx_projects_status` and `idx_projects_domain`. Any migration that needs to rebuild `projects` (e.g. to add a `metadata` column *with a check constraint*, or to restore FKs) must carry forward 25 columns and 2 indexes it does not own. Prefer `ALTER TABLE ADD COLUMN` and never rebuild `projects`.

---

## 3. Adding NOT NULL / DEFAULT columns to a 2687-row live table

The brief specifies two new `issues` columns: `issues.metadata` (JSON) and `issues.estimate`.

### 3.1 The good news

SQLite's `ALTER TABLE ADD COLUMN` with a **constant** default is an O(1) metadata-only operation — it does not rewrite the 2687 rows. `ADD COLUMN metadata TEXT NOT NULL DEFAULT '{}'` is legal and instant.

### 3.2 FINDING (MEDIUM): the pitfalls that do apply

1. **`NOT NULL` without a default is rejected outright.** `ALTER TABLE issues ADD COLUMN metadata TEXT NOT NULL` fails with `Cannot add a NOT NULL column with default value NULL`. Must be `NOT NULL DEFAULT '{}'`.
2. **Non-constant defaults are rejected.** `DEFAULT (CURRENT_TIMESTAMP)`, `DEFAULT (json('{}'))` — any expression default — is refused by `ADD COLUMN`. If a timestamp-ish column is ever wanted, it must be nullable + backfilled.
3. **A `UNIQUE` or `PRIMARY KEY` column cannot be added.** Relevant if `events.seq`-style uniqueness is ever retrofitted onto an existing table.
4. **`ADD COLUMN` with `REFERENCES` requires the default to be NULL** when `foreign_keys=ON`. So `issues.metadata` is fine; a future `ADD COLUMN owner_id TEXT NOT NULL DEFAULT 'x' REFERENCES agents(id)` is not.
5. **The `_au` trigger fires on any backfill `UPDATE`.** If `estimate` is added nullable and then backfilled via `UPDATE issues SET estimate = ...`, the still-installed `issues_fts_au` trigger performs 2687 FTS delete+reinsert cycles inside the migration transaction. Not fatal, but it bloats the WAL and it is a surprise if unaccounted. Drop the triggers first.
6. **Column-order coupling.** `store.ex` uses `SELECT * FROM issues` (`store.ex:147, 280, 289, 572, 620`) and maps results via `Enum.zip(cols, row)` in `row_to_issue/2` (`store.ex:673`). This is name-keyed, so it survives new columns — **good**. But `row_to_issue/2` builds a **fixed map** that will silently ignore `metadata` and `estimate` until it is updated. New columns will exist in SQL and be invisible through the API. That is not corruption but it is a silent-drop that AD-11's "silent truncation is forbidden" spirit should cover.
7. **`priority INTEGER DEFAULT 0` vs `priority INTEGER`.** 843 of 2687 issues have `priority IS NULL` despite the live `DEFAULT 0`, meaning they were written with an explicit NULL (which `store.ex:130` does: `Map.get(attrs, :priority)` → nil). If any migration "normalises" priority by adding `NOT NULL DEFAULT 0` via a rebuild, **843 NULLs become 0** — and `build_order_clause/1` at `store.ex:520` has a deliberate `priority IS NULL, priority DESC` NULLs-last ordering that would silently change meaning for 31% of the corpus. This is a real semantic-corruption path disguised as a cleanup.

---

## 4. `events.issue_id ... ON DELETE CASCADE` vs AD-7

The brief's DDL:
```sql
CREATE TABLE events (
  ...
  issue_id TEXT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  ...
);
CREATE TABLE measurements (
  ...
  issue_id TEXT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  ...
);
```

### 4.1 FINDING (HIGH): CASCADE quietly pre-decides a question the spine explicitly defers

The spine's Deferred table says:

> **Deletion semantics for events** — "Bee has no issue deletion today (cancel sets status). If hard delete is ever added, decide then whether events survive their issue."

But `ON DELETE CASCADE` **is** that decision, written into DDL now. The day someone adds `Bee.delete/1`, the answer is already "events do not survive" — and because it is a schema-level cascade, the deletion is silent, unlogged, and irreversible. Whoever adds hard delete will not be prompted to make the decision; they will discover it after the fact.

This directly contradicts **AD-7**, which names `events` "the analytics asset" and the substrate for all of L3. It also contradicts **AD-8**'s premise that "replay reconstructs any point in time" — replay of *what*, if the row set vanishes with its issue?

I verified: **no hard delete exists today.** `grep` over `lib/` finds no `DELETE FROM issues` or `DELETE FROM projects`; the only `DELETE FROM issues_fts` statements live in gc_daemon's trigger definitions. So the cascade is currently inert. That is precisely why it is worth fixing now — it costs nothing today and costs history later.

### 4.2 What history is already gone

The brief is candid about this and the spine should inherit the warning: on the existing production DB, only `closed_at - created_at` is recoverable. Time-in-status, rework, and blocked duration are **gone forever**. Additional measured evidence that backfilled history will be lumpy:

- **27 issues are `closed`/`cancelled` but have `closed_at IS NULL`.** Any migration that synthesises a `closed` event from `closed_at` will silently skip these, or emit events with a NULL timestamp. Both are defects. (1530 closed + 26 cancelled = 1556 terminal issues; 27 of them cannot be dated.)
- **1 issue has a non-ISO8601 timestamp.** `GC-1182` has `created_at = '2026-05-04 15:09:13'` and `updated_at = '2026-05-04 15:09:13'` — space-separated, no `T`, no `Z`. Every other row is `...T...Z`. The spine's Consistency Conventions mandate "ISO8601 UTC strings in storage" and "comparisons are SQL-side". A SQL string comparison `WHERE created_at > ?` sorts `'2026-05-04 15:09:13'` **before** `'2026-05-04T...'` because `' ' (0x20) < 'T' (0x54)`. One row is enough to produce a wrong answer in a windowed query and to break a strict-format boot validator. It must be normalised in a migration, deliberately.

### 4.3 Recommendation

Change `events.issue_id` and `measurements.issue_id` to **`ON DELETE RESTRICT`** (or drop the FK and keep `issue_id` as a soft reference with a nightly orphan report). Then the Deferred item stays genuinely deferred: the first person to write `Bee.delete/1` hits an FK error and is forced to make the decision consciously. That is the correct failure mode for an append-only analytics asset.

---

## 5. "An unexpected schema refuses to boot" — the availability risk

> **AD-15:** "**An unexpected schema refuses to boot** — never guess, never half-apply."

### 5.1 FINDING (CRITICAL): as written, the ONE production database would fail this check

"Unexpected" is undefined. Enumerate the plausible definitions against ground truth:

| Definition of "unexpected" | Does prod pass? |
| --- | --- |
| `user_version` not in the known set | **Passes** — prod is `0`, the pre-migration baseline. Good. |
| Exact `sqlite_master.sql` text match against `init_schema/1` | **FAILS** — `priority INTEGER DEFAULT 0`, missing FKs on `project_id`/`assigned_to`/`locked_by`, quoted `"dependencies"`. |
| Normalised column set + constraints per table | **FAILS** — the three missing foreign keys are real constraint-set differences. |
| Column names/types only, constraints ignored | **Passes** for `issues`; **FAILS** for `projects` (25 columns vs 6 expected). |
| No unknown tables present | **FAILS** — `labels`, `issue_project_backfill_log`, `issues_fts` + 5 shadow tables. |
| No unknown indexes present | **FAILS** — `idx_issues_parent`, `idx_projects_status`, `idx_projects_domain`. |
| No unknown triggers present | **FAILS** — `issues_fts_{ai,ad,au}`. |

**Six of seven plausible readings brick the daemon on the real database.** Only the narrowest — `user_version` gating alone — is safe, and that is the one that provides no actual protection.

This is a genuine availability risk, not a theoretical one. `gc_daemon` is the operator's primary work-tracking surface; a boot refusal takes out `gc_work`, `gc_plan`, `gc_convergence` and everything downstream, with a 17MB database and no automated restore path (see §6).

### 5.2 The deeper problem: `user_version = 0` is ambiguous

`user_version` is currently `0` on production. It will also be `0` on:
- a brand-new empty database created by `init_schema/1`;
- a database created by an **older** `init_schema/1` (with different FK constraints — exactly what prod appears to be);
- a partially-migrated database if the runner does not set `user_version` atomically with the DDL (see §7);
- a restored-from-`.bak` database.

Migration 001 must therefore be written to be correct against **every** variant of `user_version = 0` that exists in the wild, not just the one on this laptop. The moment DevMan's `.bee/bee.db` enters the picture (`prefix: "dev_man"`, cited in brief §6), there is a second `user_version = 0` database with a *different* shape — no FTS objects, no ALTERed `projects` columns, possibly no `labels` ghost.

**Required:** AD-15 must define "unexpected" precisely, and it must be a **liberal, additive-tolerant** definition:
- **Refuse to boot on:** a `user_version` **higher** than the code knows (a downgrade — the only genuinely unsafe case), or a **missing/renamed** bee-owned table or column.
- **Tolerate and log:** extra tables, extra indexes, extra triggers, extra columns, and constraint-level differences on bee-owned tables.
- **Never** compare raw `sqlite_master.sql` text.

Additive tolerance is not a compromise of AD-15's intent. AD-15 exists to prevent *silent partial migration*, which is a `user_version`/transaction problem. It does not require schema-shape fundamentalism, and schema-shape fundamentalism is what would brick the daemon.

---

## 6. Backup and rollback

### 6.1 FINDING (CRITICAL): the spine contains ZERO backup or rollback story

A case-insensitive grep of `ARCHITECTURE-SPINE.md` for `backup|rollback|restore|revert|snapshot|recover|dry.run|downgrade` returns **no matches.**

The spine specifies a **stop-the-world, destructive, irreversible** migration (`AD-15`: "stop-the-world"; Deferred: "Online (expand/contract) migrations — Deployment has a stop-the-world window") against a **17MB live production database holding 2687 issues, 2633 comments, 7722 label assignments and 357 dependency edges** — which is, in practice, the operator's entire work-tracking history — with:

- no `VACUUM INTO` / file-copy backup step before migration;
- no verification that the backup is readable before proceeding;
- no rollback procedure if migration 003 fails after 001 and 002 committed;
- no down-migrations (understandable, but then the backup is mandatory, not optional);
- no dry-run / `--check` mode;
- no post-migration verification queries (row-count parity, FTS parity, orphan check).

The best that exists is a **17-day-stale** `bee.db.bak-20260703-233311` (12.5MB vs today's 17.4MB) sitting next to the live file — evidence that someone once took a manual backup and that no automation maintains it. Restoring it today would lose roughly two and a half weeks of work.

### 6.2 Compounding: the WAL is 4.2MB and uncheckpointed

`bee.db-wal` is 4,202,432 bytes, modified at the same second as `bee.db`. A naive `cp bee.db bee.db.bak` **copies a torn database** — the main file without the WAL's committed-but-uncheckpointed pages. Any backup step in migration 001 must use `VACUUM INTO 'path'` or the SQLite Online Backup API, **not** a filesystem copy. This is exactly the kind of thing that gets discovered during the incident rather than before it.

The brief does gesture at a mitigation the spine drops entirely:

> "**Testing fixture:** a dev/mix-based daemon runs off a 2–3 day old snapshot of the real SQLite DBs. Use it for... migration testing against the real messy state (including the injected FTS objects)."

That is a good practice and it should be promoted into AD-15 as a **binding rule**, not left in a brief the implementer may not read.

### 6.3 Required additions to AD-15

1. **Mandatory pre-migration backup via `VACUUM INTO`**, to a timestamped path, with the migration **aborting** if the backup fails or the resulting file fails `PRAGMA integrity_check`.
2. **Mandatory dry-run mode** that reports the detected schema, the migration plan, and the intended DDL without executing.
3. **Post-migration verification** inside the same transaction where possible: `COUNT(*)` parity on `issues`/`comments`/`dependencies`/`issue_labels`/`projects` before vs after, FTS row-count parity, and a zero-orphan assertion. Any mismatch ⇒ `ROLLBACK`.
4. **A documented restore procedure** — one paragraph, one command.
5. **Binding rule: migration 001 must be run and verified against a copy of the live production DB before it is permitted to run against the live production DB.**

---

## 7. Transaction boundaries in the migration runner

The spine says migrations are "ordered, idempotent steps run inside the writer at boot, before anything serves" and forbids half-application. It does **not** say where `BEGIN`/`COMMIT` go. That gap admits at least four partial-application bugs.

### 7.1 FINDING (HIGH): `PRAGMA user_version` must be set INSIDE the migration transaction

SQLite honours `PRAGMA user_version = N` inside a transaction and rolls it back with the transaction. If the runner does:

```
BEGIN; <ddl for 001>; COMMIT;
PRAGMA user_version = 1;     -- <<< separate statement
```

then a crash, a power loss, or an exception between `COMMIT` and the pragma leaves the DDL applied and the version at 0. On the next boot, migration 001 re-runs. If 001 is "DROP and rebuild FTS", re-running is survivable. If any migration is `ALTER TABLE ADD COLUMN`, re-running throws `duplicate column name` and **the daemon never boots again** — the exact brick condition from §5, self-inflicted.

**Required:** `PRAGMA user_version = N` must be the last statement *inside* each migration's transaction.

### 7.2 FINDING (HIGH): one transaction per migration, not one for the whole run

If all migrations share a single transaction, a failure in 003 rolls back 001 and 002 too — arguably fine, but it means a 17MB database's worth of DDL sits in one WAL frame set and a crash mid-`COMMIT` is maximally bad. If each migration has its own transaction (recommended), then a failure in 003 leaves `user_version = 2` — a legitimate, resumable state, **provided** §7.1 holds. The spine must pick one and say so. Right now it says neither.

### 7.3 FINDING (MEDIUM): DDL that cannot be transactional

Two specific hazards for this database:

- **`PRAGMA foreign_keys` cannot be changed inside a transaction** — it is a silent no-op. `store.ex:10` sets `foreign_keys=ON` at connection setup. Any 12-step table rebuild requires `PRAGMA foreign_keys=OFF`, and that pragma must therefore be issued **before** `BEGIN`. A runner that wraps everything in `BEGIN` and then tries to disable FKs will get FK enforcement it did not expect during the rebuild. Note that the live connection I inspected reports `foreign_keys = 0` — the pragma is per-connection and not persisted, so whatever wrote this database may well have had FKs off.
- **`VACUUM` cannot run inside a transaction.** If migration 001 wants to reclaim space after dropping the FTS shadow tables, that step must sit outside the transaction and is not rollback-protected.

### 7.4 FINDING (MEDIUM): "idempotent steps" vs "fail loudly" are in tension

AD-15 asks for both "ordered, **idempotent** steps" and "**never** guess, never half-apply". Idempotency in SQLite DDL is achieved with `IF NOT EXISTS` / `IF EXISTS` — which is *precisely* the `CREATE TABLE IF NOT EXISTS` pattern AD-15's own "Prevents" clause condemns as "the current drift where schema state is unknowable". You cannot have both in the same statement. Resolve it: **`user_version` provides the idempotency at the migration level; individual statements should be strict and unconditional.** Say that explicitly, or an implementer will reach for `IF NOT EXISTS` and reintroduce exactly the defect being fixed.

---

## 8. The `labels` ghost table — an unflagged 219-row data-loss path

### 8.1 FINDING (HIGH)

Production contains a table not in `init_schema/1` and not read anywhere in `lib/`:

```sql
CREATE TABLE labels (
  issue_id TEXT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  label TEXT NOT NULL,
  PRIMARY KEY (issue_id, label)
);
```

Measured:
- **219 rows**, spanning **69 distinct issues** (`GC-1` … `GC-9` by string sort — the earliest cohort).
- **Zero orphans** — every `issue_id` resolves to a live issue.
- **All 219 rows are absent from `issue_labels`.** Not one is a duplicate. This is 219 label assignments that exist *only* here.
- **67 of the 69 issues have no `issue_labels` rows at all** — so for those, dropping `labels` erases their labelling entirely.
- Real content: `asmis` (24), `asop` (14), `workflow` (10), `grand-central` (10), `ui` (8), `student-module` (8), `extension` (8), `reliability` (5), `audit` (5)…

The brief's defect table names the adjacent bug (#12: "consumer joins table `labels`; bee's table is `issue_labels`. Queries error into a silent fallback — bee engagement signal is DEAD", citing `gc_daemon/lib/gc_daemon/engagement.ex:1296,1336`). So the *read-side* mismatch is known. What is **not** noted anywhere — brief or spine — is that **the ghost table has real, unique, non-recoverable data in it.**

Neither AD-14 nor AD-15 mentions `labels`. An implementer applying AD-14 ("no consumer objects in bee's database") and AD-15 ("unexpected schema refuses to boot") to this table has two options, and **both are wrong**:
- Drop it as an unrecognised object ⇒ **219 rows destroyed, silently**.
- Refuse to boot on it ⇒ **daemon bricked** (§5).

**Required:** migration 001 must explicitly `INSERT OR IGNORE INTO issue_labels (issue_id, label) SELECT issue_id, label FROM labels;` — merging the 219 rows — *before* dropping `labels`, and must assert the post-merge count. This is a two-line fix that is currently missing entirely because nobody looked in the table.

---

## 9. Secondary observations

- **`issue_project_backfill_log` (260 rows)** is consumer-injected and unmentioned by AD-15. It is an audit trail of `project_id` rewrites — arguably valuable provenance, arguably disposable. Decide explicitly; do not let it fall through the same crack as the 19 columns.
- **335 issues have `project_id IS NULL`** (12.5%). Any migration adding `NOT NULL` to `project_id`, or any rollup that assumes project membership, must handle these. The backfill log suggests the consumer has been actively trying to reduce this number.
- **`project_agents` is empty (0 rows)** and `locks` is empty (0 rows). Low migration risk, but also: the `AGENTS ||--o{ ISSUES` and `ISSUES ||--o| LOCKS` relationships in the spine's ER diagram are currently unexercised in production. `assigned_to` is populated and has 0 orphans against `agents` (56 rows), so that edge is real.
- **`id_counter` has one row: `GC → 2696`** against 2687 issues. A 9-id gap — consistent with a few failed creates. Any migration touching id allocation must not reset this; going backwards would cause primary-key collisions on the next create.
- **Referential integrity is currently CLEAN.** All eight orphan checks return 0 (`issues.project_id`, `issues.assigned_to`, `issues.parent`, `dependencies.issue_id`, `dependencies.depends_on_id`, `comments.issue_id`, `issue_labels.issue_id`, `labels.issue_id`). This means a migration that *restores* the missing FKs on `issues.project_id` and `issues.assigned_to` would succeed today. Worth doing — but note it changes runtime behaviour: with `foreign_keys=ON` and no `ON DELETE` clause, deleting a `projects` row would then be **restricted**, where today it silently orphans. That is a behaviour change for gc_daemon's project registry.
- **`dep_type` is 100% `'blocks'` (357/357)**, confirming brief defect #8. AD-13's expanded vocabulary is purely additive against existing data — **no migration risk**. Good.
- **FTS5 `integrity-check` could not be run** (requires write access). The FTS index may be internally corrupt in ways `PRAGMA integrity_check` does not detect. Since migration 001 rebuilds it anyway this is moot for the drop path — but it is another argument *against* the ADOPT option in D7.

---

## 10. Summary of required spine changes

| # | Severity | Change required |
| --- | --- | --- |
| 1 | **CRITICAL** | Resolve the AD-15-DROP vs brief-D7-ADOPT contradiction explicitly. |
| 2 | **CRITICAL** | State the fate of the 19 ALTERed `projects` columns. Recommend: leave untouched in 001. |
| 3 | **CRITICAL** | Define "unexpected schema" as additive-tolerant, or the live DB will not boot. |
| 4 | **CRITICAL** | Add a mandatory `VACUUM INTO` backup + verification + documented restore to AD-15. |
| 5 | **HIGH** | Merge the ghost `labels` table's 219 rows into `issue_labels` before dropping it. |
| 6 | **HIGH** | Specify FTS trigger/table DROP ordering; triggers first, always. |
| 7 | **HIGH** | Change `events`/`measurements` FK to `ON DELETE RESTRICT` — CASCADE pre-decides a deferred question and contradicts AD-7. |
| 8 | **HIGH** | `PRAGMA user_version = N` inside each migration's transaction; one transaction per migration. |
| 9 | **HIGH** | Make gc_daemon's de-injection a hard ordering constraint on migration 001, not a deferred item. |
| 10 | **MEDIUM** | Normalise `GC-1182`'s non-ISO timestamp; handle the 27 closed-without-`closed_at` issues in any event backfill. |
| 11 | **MEDIUM** | Do not "normalise" `priority` NULLs to 0 — 843 rows, and `store.ex:520` depends on NULLs-last ordering. |
| 12 | **MEDIUM** | Resolve the "idempotent steps" vs "no `IF NOT EXISTS`" tension. |
| 13 | **MEDIUM** | State that `PRAGMA foreign_keys=OFF` must precede `BEGIN` for any table rebuild. |
| 14 | **LOW** | Correct the issue count: 2687, not 2686. Decide the fate of `issue_project_backfill_log`. |

---

## Appendix — reproduction

All findings above are reproducible read-only:

```bash
DB="file:/Users/leonidas/.local/share/gc/bee.db?mode=ro"
sqlite3 "$DB" ".schema"
sqlite3 "$DB" "PRAGMA user_version;"
sqlite3 "$DB" "SELECT COUNT(*) FROM labels;"
sqlite3 "$DB" "SELECT COUNT(*) FROM labels l WHERE NOT EXISTS(
  SELECT 1 FROM issue_labels il WHERE il.issue_id=l.issue_id AND il.label=l.label);"
sqlite3 "$DB" "SELECT COUNT(*) FROM issues WHERE created_at NOT LIKE '____-__-__T%';"
sqlite3 "$DB" "SELECT COUNT(*) FROM issues WHERE status IN ('closed','cancelled') AND closed_at IS NULL;"
sqlite3 "$DB" "SELECT COUNT(*) FROM issues WHERE priority IS NULL;"
```

**No writes were performed against the production database during this review.**
