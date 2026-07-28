# Data-Integrity / Migration-Safety Review v2 — bee Architecture Spine (revised)

**Reviewer role:** Data integrity & migration safety
**Target:** `ARCHITECTURE-SPINE.md` (revised — AD-15, AD-19, AD-22, AD-23, new "Migration Plan" section)
**Predecessor:** `reviews/review-data-integrity.md` (verdict: BLOCK, 14 required changes)
**Date:** 2026-07-20
**Method:** Spine diff + `lib/bee/store.ex` + `lib/bee/export.ex` + `gc_daemon/lib/gc_daemon/bee/search_index.ex` + `gc_daemon/mix.exs`, read against READ-ONLY inspection of the live production DB.

**No writes were performed against the production database during this review.**

---

## VERDICT

**The original BLOCK is LIFTED.** All 14 required changes are addressed: **10 CLOSED, 4 PARTIAL, 0 OPEN.** The revision is substantive and honest — it adopted the recommendations rather than arguing with them, and AD-15 is now the strongest AD in the document.

**A new, narrower BLOCK is raised on Migration 002 only.**

Migration 002 as specified cannot be written. It produces a **different schema on a live database than on a fresh one**, and the mechanism it needs (conditional DDL) is explicitly forbidden by AD-15's own "no `IF NOT EXISTS`" rule. This is the latent-disaster class: two databases both reporting `user_version = 2` with materially different `projects` tables, and no way for the boot check to tell them apart. Migrations 001, 003 and 004 are sound and can proceed.

---

## JOB A — Closure audit of the 14 required changes

| # | Prev. severity | Required change | Status | Where closed |
| --- | --- | --- | --- | --- |
| 1 | CRITICAL | Resolve AD-15-DROP vs brief-D7-ADOPT contradiction | **CLOSED** | Migration Plan row 001: "Reverses the brief's 'adopt in place' **deliberately**", with the three-part reasoning (stop-the-world window exists, FTS is content-owning and fully reconstructible, integrity unverifiable read-only). The reversal is now recorded, not silent. |
| 2 | CRITICAL | State the fate of the 19 ALTERed `projects` columns | **PARTIAL** | 001 "Touches **none** of the 19"; 002 "adopt the useful … fold the rest into `projects.metadata`". A decision now exists — but "useful" is an undefined set, the mechanism is unimplementable, and it collides with the existing `metadata_json`. See **N1**. |
| 3 | CRITICAL | Define "unexpected schema" as additive-tolerant | **CLOSED** | AD-15 bullet 4, which enumerates the exact production divergences (19 columns, `labels`, `issue_project_backfill_log`, `priority INTEGER DEFAULT 0`, missing FKs) and states "a stricter reading refuses to boot against production." Directly answers §5 of v1. |
| 4 | CRITICAL | Mandatory `VACUUM INTO` backup + verification + restore | **CLOSED** | AD-15 bullets on backup (with the WAL/`cp` rationale), dry-run, post-migration verification, "run against a copy first", plus the four-step **Restore procedure** line after the Migration Plan table. The "every assertion computed at runtime, never a hardcoded number" clause is a good addition I did not ask for. |
| 5 | HIGH | Merge ghost `labels` 219 rows before dropping | **CLOSED** | Migration Plan row 001, `INSERT OR IGNORE` then drop. |
| 6 | HIGH | Specify FTS trigger/table DROP ordering | **CLOSED** | AD-15 "**Drop triggers before the table**, always"; 001 row restates "drop FTS **triggers then table**". |
| 7 | HIGH | `events`/`measurements` FK → `ON DELETE RESTRICT` | **CLOSED** | Migration Plan row 003; Deferred row "Hard delete semantics — AD-15's RESTRICT forces an explicit decision if one is ever added." Failure mode is now the correct one. |
| 8 | HIGH | `user_version` inside txn; one txn per migration | **CLOSED** | AD-15 bullet 2, verbatim including the brick rationale. |
| 9 | HIGH | gc_daemon de-injection as hard ordering constraint | **PARTIAL** | The "**Hard ordering constraint**" paragraph states it. But it is stated, not enforced — and `gc_daemon/mix.exs:72` pins bee as an **unpinned git dep**. See **N6**, and the restart-window analysis in **N3**. |
| 10 | MEDIUM | Normalise GC-1182; handle 27 closed-without-`closed_at` | **PARTIAL** | GC-1182 named in Consistency Conventions → Dates. The 27 rows moved to Deferred with "not in scope for 001–004" — acceptable, since no event backfill is in scope. But the 004 row says only "date normalisation" with no spec; the real scope is far larger than GC-1182. See **N4**. |
| 11 | MEDIUM | Do not normalise `priority` NULLs to 0 | **CLOSED** | Consistency Conventions → Ordering: "843 rows have NULL priority and must **not** be normalised to 0." |
| 12 | MEDIUM | Resolve "idempotent" vs "no `IF NOT EXISTS`" tension | **CLOSED** | AD-15 bullet 3: idempotency at the migration level via `user_version`; statements strict and unconditional; `IF NOT EXISTS` forbidden. Correctly resolved — and it is precisely this correct resolution that makes Migration 002 unwritable (**N1**). |
| 13 | MEDIUM | `PRAGMA foreign_keys=OFF` must precede `BEGIN` | **PARTIAL** | AD-15 states it. Silent on the other two halves of the 12-step procedure: `PRAGMA foreign_key_check` before `COMMIT`, and re-enabling `foreign_keys=ON` after. See **N5**. |
| 14 | LOW | Correct issue count to 2687; decide `issue_project_backfill_log` | **CLOSED** | Spine now cites 2,687 consistently (AD-10, Deferred). `issue_project_backfill_log` has its own Deferred row: "Left untouched by 001; decide its fate with gc_daemon's de-injection." |

**Tally: 10 CLOSED · 4 PARTIAL · 0 OPEN.** No required change was ignored or argued away. The original block is liftable on its own terms.

---

## JOB B — Attacking the new 4-migration plan

### Ground truth re-measured for this review

```
dependencies:  357 rows, PRIMARY KEY (issue_id, depends_on_id)
               DDL is CREATE TABLE "dependencies" (quoted — already rebuilt once)
               FKs OUT: issue_id, depends_on_id → issues(id) ON DELETE CASCADE
               FKs IN:  NONE (verified: no table DDL references dependencies)
               triggers/views referencing dependencies: NONE
               indexes: sqlite_autoindex_dependencies_1 only (the PK)
               dep_type: 357/357 = 'blocks', 0 NULL
               duplicates under the NEW 3-col PK: 0
               orphans (both directions): 0

projects:      6 bee columns + 19 consumer columns = 25
               8 of the 19 are NOT NULL DEFAULT
               consumer indexes: idx_projects_status, idx_projects_domain
               NO column named `metadata`; there IS `metadata_json` (64/89 populated)

timestamps:    issues.created_at   len 19→1, len 24→68,  len 27→2618
               issues.updated_at   len 19→1, len 20→2, len 24→647, len 27→2037
               issues.closed_at    NULL→1156, len 24→276, len 27→1255
               comments.created_at len 19→3, len 24→43, len 27→2588
               dependencies.created_at len 20→1, len 24→6, len 27→350
```

---

### N1 — **CRITICAL / BLOCKING.** Migration 002 produces divergent schemas depending on starting state

This is the question the task flagged as key, and the answer is worse than "it's a no-op."

**Physically, "adopt the useful consumer `projects` columns as first-class bee columns" has no single implementation that works on both databases.**

On the **live** database, `description`, `stack`, `domain`, `notes`, `source`, `last_synced_at` etc. already exist:

```sql
ALTER TABLE projects ADD COLUMN description TEXT;
-- Error: duplicate column name: description
```

On a **fresh** database (`DevMan`'s `.bee/bee.db`, any test fixture, any new install) they do not exist, so the same statement is **required**. SQLite has no `ADD COLUMN IF NOT EXISTS` and no `DROP COLUMN IF EXISTS`. There is no DDL text that is simultaneously legal on both.

The three escape hatches are each closed:

1. **`IF NOT EXISTS`** — not available for `ADD COLUMN` at all, and AD-15 bullet 3 forbids the pattern outright.
2. **Conditional logic reading `pragma_table_info`** — this is *exactly* the "guess the current shape and half-apply" behaviour AD-15 exists to abolish, and it is what `gc_daemon/lib/gc_daemon/project_registry.ex:636` already does (`ALTER TABLE projects ADD COLUMN #{column} #{type_sql}` in a probe-then-add loop). Reproducing the consumer's anti-pattern inside `Bee.Store.Migrate` would be a bitter outcome.
3. **Rebuild `projects` to a canonical shape** — v1 §2.2 already showed why this is the expensive option: 25 columns, 8 of them `NOT NULL DEFAULT`, plus two consumer indexes (`idx_projects_status`, `idx_projects_domain`, the latter indexing a column that is a candidate for folding). It is *possible* — and it is the only convergent option — but the Migration Plan does not say it, and a rebuild of `projects` is a materially different risk profile than the `ADD COLUMN` the row implies.

**The failure is not that 002 errors. The failure is that it "works" on one path and errors on the other, so the two paths get patched separately and permanently diverge.** After that, `user_version = 2` means two different `projects` tables, AD-15's boot check has no way to distinguish them (it tolerates extra columns *by design* — item #3 above), and every later migration that touches `projects` inherits the ambiguity.

**Two further problems inside the same row:**

- **`projects.metadata` vs `projects.metadata_json`.** AD-14 mandates adding `projects.metadata` as *the* sanctioned extension point. `projects.metadata_json` already exists, is `NOT NULL DEFAULT '{}'`, and is populated on 64/89 rows. Migration 002 as written would leave **two JSON extension columns with near-identical names**, both live, both readable by gc_daemon. That is a duplicate-truth violation of AD-18's own principle ("no relationship has two homes"), applied to the extension point itself. Either `metadata_json` is folded into `metadata` and dropped (a rebuild, and a consumer read-path break at `project_registry.ex:614-655`), or `metadata_json` **is** the adopted first-class column and AD-14 should name it — but it cannot be both.
- **`issues.estimate` contradicts AD-12.** AD-12 states "Effort is a registered measurement (`measure: "effort"`), latest value per issue — `metadata` is never a source of numbers bee computes on", and the rollup aggregates over the measurement. Migration 002 adds an `issues.estimate` column that AD-12 forbids the rollup from reading. It is either dead weight on 2,687 rows or an undeclared second home for effort. Decide, or drop it from 002.

**Required before 002 ships:**

1. Name the "useful" columns **explicitly**, as an enumerated list in the spine. It is 19 columns; enumerate them.
2. Introduce a **baseline migration (000)** — see N2 — whose entire job is to converge a live legacy DB and a fresh DB onto one defined `user_version = 1` shape. Conditional detection is legitimate *there and only there*, keyed on an explicit "is this database empty" test, not on per-object `IF EXISTS` probing. AD-15 should carve out that exception in one sentence rather than leave implementers to violate it silently.
3. Resolve `metadata` vs `metadata_json` in writing.
4. Justify or delete `issues.estimate`.

---

### N2 — **CRITICAL.** `user_version = 0` denotes two different databases and the plan has no baseline

Restating v1 §5.2 because the revision closed the *symptom* (boot tolerance) without closing the *cause*. Production is `user_version = 0`. So is:

- a brand-new empty file;
- DevMan's `.bee/bee.db` (`prefix: "dev_man"`), which has **no** FTS objects, **no** ghost `labels`, **no** 19 consumer columns, **no** `issue_project_backfill_log`;
- anything restored from the `.bak`.

Migration 001 as specified does `DROP TRIGGER issues_fts_ai` and `DROP TABLE labels` **unconditionally** (AD-15: "individual statements are strict and unconditional"). Against DevMan's database those objects do not exist and **migration 001 hard-fails on statement 1**, taking `Bee.Store.Migrate` with it and — per AD-22 — failing the supervision tree. DevMan never boots again.

So AD-15's strictness rule and Migration 001's content are mutually incompatible on the second real database in the system. The revision fixed boot tolerance for *reads* and left it broken for *writes*.

**Required:** a baseline migration 000 that lands every `user_version = 0` variant on one known shape, after which 001–004 can be strict and unconditional as AD-15 demands. Without it the "strict statements" rule is unshippable, and the pressure to reach for `IF EXISTS` will be irresistible at implementation time.

---

### N3 — **HIGH.** Migration 001's FTS rebuild silently changes search behaviour, and its safety depends on an undocumented name match

`gc_daemon/lib/gc_daemon/bee/search_index.ex:44-49` creates:

```sql
CREATE VIRTUAL TABLE IF NOT EXISTS issues_fts USING fts5(
  issue_id UNINDEXED, title, description,
  tokenize='porter unicode61'
)
```

AD-15 mandates tokenizer `unicode61 remove_diacritics 2`.

**These are not the same tokenizer.** The consumer's index applies **Porter stemming**; bee's does not. After migration 001, a `gc_work` search for `"running"` stops matching `"run"`, `"migrations"` stops matching `"migrate"`, and every stored relevance score changes. gc_daemon's search is the operator's primary issue-finding surface, and this is a user-visible quality regression that the Migration Plan describes only as "rebuild `issues_fts`". Either bee adopts `porter unicode61` (preserving behaviour), or the spine states the regression as a deliberate, accepted change. Note AD-15 already recognises the general principle — "the tokenizer must match so scores stay comparable" — it just does not notice that it is *changing* the tokenizer right now.

**The undocumented safety property.** `SearchIndex.bootstrap/0` runs at **every gc_daemon boot** as a supervised child, and is deliberately non-fatal on error (`init/1` logs a warning and returns `{:ok, ...}`). Because `:bee` is an OTP application dependency of `:gc_daemon`, bee's `Bee.Store.Migrate` runs **before** `SearchIndex.bootstrap`. So on the first boot after migration 001, bootstrap will run:

- `CREATE VIRTUAL TABLE IF NOT EXISTS issues_fts` → no-op (bee's exists)
- `CREATE TRIGGER IF NOT EXISTS issues_fts_ai` / `_ad` / `_au` → **no-op only if bee used those exact three names**
- `INSERT INTO issues_fts (issue_id, title, description) SELECT … WHERE id NOT IN (SELECT issue_id FROM issues_fts)` → **works only if bee's FTS table exposes a column literally named `issue_id`**

If bee's migration 001 names its triggers anything else — `bee_issues_fts_insert`, say — then **six triggers are installed**, both `_ai` sets fire on every insert, and every issue is indexed **twice**. Search returns duplicates and BM25 ranking is silently wrong. If bee switches to an external-content or contentless FTS5 table, the consumer's `INSERT INTO issues_fts (issue_id, …)` inside the still-installed trigger fails, which means **every `INSERT`/`UPDATE`/`DELETE` on `issues` fails** — bee cannot write at all.

So the entire changeover is safe *by coincidence of naming*, and the spine documents neither the coincidence nor the requirement. **Required:** AD-15 must pin the FTS table name, the column names (`issue_id UNINDEXED, title, description`), and the three trigger names as a compatibility contract until GC-2694 lands.

**On the restart-window question.** Because bee is a library inside the gc_daemon release, there is no window where "the daemon restarts old code against a new schema" in the ordinary sense — a restart reloads both together. The real windows are two:

1. **`rebuild_search_index`** (`work_handler.ex:543` → `SearchIndex.rebuild/0`) is an operator lever, callable at any time, that opens its **own read-write connection** to `bee.db` (`GcDaemon.SQLite.with_conn(path, :readwrite, …)` — already an AD-2 violation today) and does `DROP TABLE issues_fts` → recreate with **porter** → recreate triggers → repopulate. One operator invocation after migration 001 silently reverts bee's FTS to the consumer's definition. This is not a boot-ordering problem and the "same release" constraint does not address it. `rebuild/0` and the `rebuild_search_index` action must be deleted in the same release, not merely `bootstrap/0`.
2. **Downgrading bee** while the DB is at `user_version = 4`. AD-15's "refuse on a higher user_version" covers bee itself — but `SearchIndex.bootstrap/0` is outside bee's control and non-fatal, so it will still open its own connection and touch the database even in a release where bee refused to start.

---

### N4 — **HIGH.** Migration 004's "date normalisation" is far larger than the spine implies, and normalising without fixing the writer regresses

The 004 row says only "date normalisation", and the Conventions row cites "one known bad row (`GC-1182`)". **That understates the scope by two orders of magnitude.** Measured, there are *four* live timestamp formats, not two:

| Form | Example | `issues.created_at` | `issues.updated_at` | `comments.created_at` | `dependencies.created_at` |
| --- | --- | ---: | ---: | ---: | ---: |
| space-separated, no TZ (19) | `2026-05-04 15:09:13` | 1 | 1 | 3 | – |
| second precision + `Z` (20) | `2026-02-24T22:58:39Z` | – | 2 | – | 1 |
| **millisecond + `Z` (24)** | `2026-02-24T22:58:14.658Z` | **68** | **647** | **43** | 6 |
| microsecond + `Z` (27) | `2026-02-25T18:00:18.809011Z` | 2618 | 2037 | 2588 | 350 |

The millisecond cohort is the finding. `.123Z` and `.123456Z` are **not lexically comparable**: at the differing byte, `'Z'` (0x5A) sorts *after* any digit, so `2026-01-01T00:00:00.500Z` sorts **later** than `2026-01-01T00:00:00.500001Z` — the reverse of the truth. Since `store.ex:482` defaults every list to `ORDER BY created_at ASC` and `@order_columns` permits `created_at`/`updated_at`, this is live ordering corruption, not a hypothetical.

Measured, by normalising in a CTE and comparing pair orderings:

- **8 pairs** of issues where lexical order of `updated_at` disagrees with temporal order.
- **57 pairs** of comments where lexical order of `created_at` disagrees with temporal order.

So the Conventions row's "one known bad row" should read: **one malformed row, plus ~700 rows in a second precision class that is silently mis-ordering against the first.** Normalising is now clearly *necessary*, not cosmetic. Good — but the plan needs four things it does not have:

1. **Scope.** Normalisation must cover `issues.{created_at, updated_at, closed_at}`, `comments.created_at`, `dependencies.created_at`, `projects.{created_at, updated_at, last_synced_at}`, `agents.updated_at`, `locks.{locked_at, expires_at}`. The 004 row names none of them. `issues.closed_at` alone has 276 millisecond-precision rows and 1,156 NULLs.
2. **A direction rule.** Padding `.658Z` → `.658000Z` is lossless and monotone. Truncating microseconds to milliseconds is lossy. The spine says "microsecond precision, one canonical form" — say **pad, never truncate**, explicitly, or someone will `strftime` the whole corpus and destroy sub-millisecond ordering on 2,618 rows.
3. **The writer is not bee.** The 24-char cohort ranges `2026-02-24 → 2026-07-03`, i.e. it is not a legacy artefact — something has been writing millisecond timestamps into bee's tables for five months. `store.ex:810` (`DateTime.utc_now() |> DateTime.to_iso8601()`) yields microseconds, so bee is not the source. **Normalising in 004 without stopping that writer means the corpus re-diverges immediately.** The "hard ordering constraint" paragraph covers gc_daemon's *DDL* injection; it says nothing about *DML*. This needs to be part of the same constraint.
4. **The 27 closed-without-`closed_at` rows and the 335 NULL `project_id` rows** are correctly Deferred and correctly untouched — no migration adds `NOT NULL` to either, so nothing breaks. That is the right call and I have no objection.

**What the rewrite breaks, specifically:**

- **`id_counter`: unaffected.** 004 does not touch `issues.id`, and `GC → 2696` is not derived from timestamps. No collision risk. ✅
- **The FTS index: fully rewritten as a side effect.** By the time 004 runs, migration 001 has installed bee-owned `AFTER UPDATE ON issues` triggers with **no `OF title, description` clause** (matching the consumer's). A single `UPDATE issues SET created_at = …, updated_at = …` across 2,687 rows therefore fires 2,687 delete+reinsert cycles into `issues_fts` inside the migration transaction. Not incorrect — the FTS content is unchanged — but it multiplies WAL growth by roughly the size of the whole index for a change that touches no indexed column. **Mitigation:** either add `OF title, description` to bee's `_au` trigger (correct, and strictly better than the consumer's version bee is replacing), or drop-and-reinstall the triggers around 004 the way 001 does. Neither is currently specified.
- **DevMan's JSONL contract: every line changes.** `export.ex:19-21` emits `created_at`/`updated_at` **verbatim from the row**, so normalising 004 rewrites the content of all 2,687 JSONL lines on the next debounced export. AD-17 says "the JSONL format is a consumer contract … and does not change without updating it" — the *format* does not change, but the *values* do, for the whole corpus at once. Any DevMan-side incremental sync, content hash, or "changed since" watermark sees a full-corpus churn. Worth one line in the plan so it is expected rather than diagnosed. (Separately: `export.ex:38` already emits a hardcoded `"created_at": "0001-01-01T00:00:00Z"` for every dependency, so the JSONL's dep timestamps are fiction today — 004 is a good moment to fix that, since it is rebuilding `dependencies` anyway.)
- **Consumer caching timestamps.** `projects.last_synced_at` (63/89 populated, all microsecond — clean) is a consumer sync watermark. If normalisation touches `projects.updated_at` but a consumer compares it against a cached value, the comparison flips once. Low impact given 89 rows, but it should be in the verification list.

---

### N5 — Migration 004's `dependencies` PK rebuild: **safe**, with two omissions in AD-15

The task asked whether the PK change against 357 live rows with FK references is safe. **Measured: yes, and it is the least risky of the four migrations.** The specific reasons:

- **No FKs point AT `dependencies`.** Verified across all table DDL in `sqlite_master` — nothing references it. So the rebuild's `DROP TABLE` cannot orphan anything, and there is no parent-side cascade to consider.
- **No triggers or views reference `dependencies`.** The only three triggers in the database (`issues_fts_ai/_ad/_au`) are all `ON issues` and mention only `issues` and `issues_fts`. This matters because it neutralises the v1 §1.3 hazard: SQLite ≥3.25 rewrites trigger and view bodies on `ALTER TABLE … RENAME TO`, and with nothing referencing `dependencies` there is nothing to rewrite or silently drop. **`PRAGMA legacy_alter_table` is a non-issue for 004 specifically** — but should still be pinned in AD-15, because it will matter for any future rebuild of `issues`.
- **Zero duplicates under the new key.** `SELECT COUNT(*) FROM (… GROUP BY issue_id, depends_on_id, dep_type HAVING COUNT(*)>1)` = **0**. The 357 rows transfer 1:1. `dep_type` is `NOT NULL DEFAULT 'blocks'` with 0 NULLs, so the third PK column is safe to promote.
- **Zero orphans in both directions**, so `PRAGMA foreign_key_check` after the rebuild will pass.
- Only one index to recreate — `sqlite_autoindex_dependencies_1`, which SQLite regenerates automatically from the PK. Nothing hand-rolled to carry forward. Contrast with `projects` (N1), which has two consumer indexes and 25 columns.

**Exact procedure required (SQLite's 12-step, reduced to what actually applies):**

```
PRAGMA foreign_keys = OFF;            -- OUTSIDE the transaction (AD-15 covers this) ✅
BEGIN;
  CREATE TABLE dependencies_new (
    issue_id      TEXT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
    depends_on_id TEXT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
    dep_type      TEXT NOT NULL DEFAULT 'blocks',
    created_at    TEXT NOT NULL,
    PRIMARY KEY (issue_id, depends_on_id, dep_type)
  );
  INSERT INTO dependencies_new SELECT issue_id, depends_on_id, dep_type, created_at
    FROM dependencies;
  -- assert transferred == source count, read inside this transaction (AD-15's runtime-assertion rule)
  DROP TABLE dependencies;
  ALTER TABLE dependencies_new RENAME TO dependencies;
  CREATE INDEX idx_dependencies_blocker ON dependencies(depends_on_id, dep_type);
  PRAGMA foreign_key_check;           -- <<< MISSING FROM AD-15
  PRAGMA user_version = 4;
COMMIT;
PRAGMA foreign_keys = ON;             -- <<< MISSING FROM AD-15
```

**Does AD-15's "`PRAGMA foreign_keys=OFF` before `BEGIN`" rule cover it? Partially — it covers one of three steps.** Two omissions:

1. **`PRAGMA foreign_key_check` before `COMMIT` is not mentioned anywhere in the spine.** It is step 10 of SQLite's own documented procedure and the only thing that catches a botched transfer while rollback is still possible. Without it, FK enforcement is off, the DDL succeeds, and violations surface later as query anomalies.
2. **Re-enabling `foreign_keys=ON` after `COMMIT` is not mentioned.** `Bee.Store.Migrate` runs on the writer connection (AD-22 child 1, before `Bee.Repo`) — or, if it opens its own, that connection is discarded and the omission is harmless. But if it shares the writer's connection, leaving `foreign_keys=OFF` means **the single write connection runs with FK enforcement disabled for the entire process lifetime**, silently contradicting AD-23's "every connection sets `foreign_keys=ON`". Given v1 measured the live database already reporting `foreign_keys = 0`, this is the exact failure that has already happened once here. AD-15 must say: re-enable after `COMMIT`, and AD-23's guarantee is re-asserted after every rebuild.

**One cosmetic consequence worth pinning:** after the rename, `dependencies` will appear in `sqlite_master` as `CREATE TABLE "dependencies"` — quoted, as it already is today. AD-15's "different shape" boot test must be immune to quoting. AD-15 no longer says "never compare raw `sqlite_master.sql` text" (v1 asked for that phrasing and the revision replaced it with "different shape than the target version expects"). "Shape" is loose enough that a literal-text comparison could creep back in. Restore the explicit prohibition.

---

### N6 — **MEDIUM.** The "same release" ordering constraint is not enforceable as the dependency is currently declared

```elixir
# gc_daemon/mix.exs:72
{:bee, git: "https://github.com/fosferon/bee.git"},
```

No `tag:`, no `ref:`, no `branch:`. `mix.lock` pins a SHA in the checked-in state, but `mix deps.update bee` — or a fresh clone whose lock is stale, or any CI that regenerates the lock — resolves to bee's default branch **HEAD**. The moment migrations 001–004 land on bee's `master`, any gc_daemon build that updates the dep acquires them, regardless of whether `SearchIndex` and `project_registry`'s `ALTER TABLE` loop have been removed from that gc_daemon tree.

The Migration Plan's "Hard ordering constraint" is therefore a statement of intent with no mechanism behind it. Two cheap fixes: pin bee by `tag:` in gc_daemon, and have `Bee.Store.Migrate` **refuse to proceed if the consumer's objects are re-created after migration** (i.e. a post-migration boot assertion that `issues_fts`'s tokenizer is bee's, failing loudly rather than drifting).

---

### N7 — **LOW/informational.** Nothing in the plan restores the missing FKs on `issues.project_id` / `issues.assigned_to` — and that is the right call

The task asked whether any migration restores them. **It does not.** 001 touches FTS and `labels`; 002 adds columns; 003 creates new tables; 004 rebuilds `dependencies`. `issues` is never rebuilt, so `project_id` and `assigned_to` remain FK-free.

That is the safe choice and I endorse it. Restoring them would succeed today (v1 measured zero orphans on both), but with `foreign_keys=ON` and no `ON DELETE` clause, deleting a `projects` row would become **RESTRICTED** where today it silently orphans — a live behaviour change for gc_daemon's project registry, delivered as a side effect of a migration that never mentions it. Correctly avoided.

But it is **silence, not decision.** AD-15's tolerance bullet lists "missing FKs on `project_id`/`assigned_to`" among the divergences it tolerates, which is the right runtime posture, and the effect is that AD-23's `foreign_keys=ON` enforces nothing on the two most-used reference columns in the schema — permanently, on the production database, with no plan to change it. That deserves a one-line Deferred row saying so, so that the next person to read AD-23 does not assume `issues.project_id` is protected.

---

### N8 — Verification checklist the plan should adopt

AD-15 mandates post-migration verification with runtime-computed assertions. Concretely, per migration:

| Migration | Assert |
| --- | --- |
| 001 | `COUNT(issues_fts) == COUNT(issues)`; 0 FTS orphans; 0 duplicate `issue_id` in FTS; `COUNT(issue_labels)` after ≥ before; `(labels ∖ issue_labels)` = ∅ **before** dropping `labels`; `issues_fts` tokenizer string matches the target; exactly 3 triggers on `issues` |
| 002 | Column set of `projects` is **identical** on a live-migrated DB and a fresh-migrated DB (this is the assertion that catches N1 — run it in CI against both) |
| 003 | New tables exist with `ON DELETE RESTRICT`; `PRAGMA foreign_key_check` clean |
| 004 | `COUNT(dependencies)` before == after; `PRAGMA foreign_key_check` clean; **zero rows in any timestamp column matching `NOT LIKE '____-__-__T__:__:__.______Z'`** across all nine columns listed in N4; `COUNT(issues_fts) == COUNT(issues)` still |

The N4 assertion is the important one — it is the only cheap, total check that date normalisation actually covered every column, and it doubles as a permanent boot-time invariant.

---

## Summary of new required changes

| # | Severity | Change |
| --- | --- | --- |
| N1 | **CRITICAL — BLOCKING** | Migration 002 is unwritable as specified. Enumerate the "useful" columns; resolve `metadata` vs `metadata_json`; justify or drop `issues.estimate`; make 002 produce an identical `projects` schema on live and fresh databases, and assert it in CI. |
| N2 | **CRITICAL** | Add a baseline migration 000. `user_version = 0` currently denotes three different databases, and 001's unconditional `DROP TRIGGER`/`DROP TABLE labels` hard-fails on DevMan's `.bee/bee.db`. |
| N3 | **HIGH** | 001 changes the FTS tokenizer `porter unicode61` → `unicode61 remove_diacritics 2`, a silent search-quality regression. Pin the FTS table name, column names and the three trigger names as a compatibility contract. Delete `SearchIndex.rebuild/0` and the `rebuild_search_index` action in the same release, not just `bootstrap/0`. |
| N4 | **HIGH** | Specify 004's date normalisation: nine columns across six tables, ~700 millisecond-precision rows (measured 8 + 57 real mis-ordering pairs), pad-never-truncate, plus stopping the consumer that is still writing millisecond timestamps. Note the full-index FTS rewrite and the 2,687-line JSONL churn. |
| N5 | **MEDIUM** | AD-15 must add `PRAGMA foreign_key_check` before `COMMIT` and `PRAGMA foreign_keys=ON` after it. Restore the explicit "never compare raw `sqlite_master.sql` text" prohibition. |
| N6 | **MEDIUM** | Pin `{:bee, git: …}` by tag in `gc_daemon/mix.exs`, and add a post-migration boot assertion that the consumer has not re-injected. |
| N7 | **LOW** | Add a Deferred row recording that `issues.project_id` / `issues.assigned_to` remain FK-free by decision, so AD-23 is not misread as covering them. |

**Migrations 001, 003 and 004 are approved to proceed** once N3/N4/N5 are folded in. **Migration 002 is blocked** pending N1 and N2.

---

## Appendix — reproduction

```bash
DB="file:/Users/leonidas/.local/share/gc/bee.db?mode=ro"

# N5 — dependencies rebuild safety
sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE sql LIKE '%REFERENCES dependencies%';"   # empty
sqlite3 "$DB" "SELECT COUNT(*) FROM (SELECT 1 FROM dependencies GROUP BY issue_id,depends_on_id,dep_type HAVING COUNT(*)>1);"  # 0
sqlite3 "$DB" "SELECT type,name,tbl_name FROM sqlite_master WHERE type IN ('trigger','view');"

# N1 — projects column reality
sqlite3 "$DB" "SELECT sql FROM sqlite_master WHERE name='projects';"

# N4 — timestamp precision classes
sqlite3 "$DB" "SELECT LENGTH(updated_at) l, COUNT(*) FROM issues GROUP BY l;"
sqlite3 "$DB" "
WITH n AS (SELECT id, updated_at AS raw,
  CASE WHEN LENGTH(updated_at)=27 THEN updated_at
       WHEN LENGTH(updated_at)=24 THEN substr(updated_at,1,23)||'000Z'
       WHEN LENGTH(updated_at)=20 THEN substr(updated_at,1,19)||'.000000Z'
       ELSE replace(updated_at,' ','T')||'.000000Z' END AS norm FROM issues)
SELECT COUNT(*) FROM n a JOIN n b ON a.id<b.id WHERE (a.raw<b.raw) <> (a.norm<b.norm);"   # 8
```

**No writes were performed against the production database during this review.**
