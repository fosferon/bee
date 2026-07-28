# Review — Version / Reality Check

**Target:** `_bmad-output/planning-artifacts/architecture/architecture-bee-2026-07-20/ARCHITECTURE-SPINE.md`
**Reviewer role:** Version & reality-check (web-verified, no training-data assertions)
**Date:** 2026-07-20
**Method:** every Stack entry checked against hex.pm API; every SQLite claim checked against sqlite.org primary docs; every claim cross-checked against the actual repo (`mix.exs`, `mix.lock`, `lib/`, `deps/exqlite`).

---

## Verdict

**The stack is real, current, and correctly chosen — but the spine states it as fact without disclosing that three of five entries are *proposals*, not the current state of the repo.** The four load-bearing SQLite claims all verify against primary sources, with one materially incomplete: AD-9's expression-index claim is true but omits the exact-textual-match requirement that the entire decision depends on.

No blockers. Two HIGH findings, four MEDIUM, three LOW.

---

## 1. Stack table — verification

| Claim | Exists? | Current? | Fits? | Verdict |
| --- | --- | --- | --- | --- |
| Elixir `~> 1.19` | Yes — v1.19.0 released 2025-10-16 | Superseded: v1.20.0 released 2026-06-03 | Yes | **OK, with note** |
| exqlite `~> 0.39` | Yes — 0.39.0 released 2026-07-16 (4 days before this spine) | Yes, latest | Yes | **OK, but not what the repo has** |
| nimble_pool `~> 1.1` | Yes — 1.1.0 | Latest, but released **2024-03-25** (28 months old) | Yes, per official docs | **OK, with caveats** |
| jason `~> 1.4` | Yes — 1.4.5 released 2026-05-05 | Yes (1.5.0-alpha.2 is pre-release only) | Yes | **OK, but possibly unnecessary** |
| SQLite WAL + FTS5 "bundled with exqlite" | Yes | SQLite 3.53.3 as of exqlite 0.38 | Yes | **Confirmed in-repo** |

### Detail

**Elixir `~> 1.19`.** Verified: v1.19 shipped 2025-10-16 (type inference for anonymous functions, protocol type checking, up to 4x faster compilation, requires OTP 28.1+). v1.20.0 shipped 2026-06-03. Hex's `~> 1.19` resolves to `>= 1.19.0 and < 2.0.0`, so the requirement already admits 1.20 — the constraint is not broken. But the spine presents 1.19 as the current line when it is one minor behind, and nothing in the spine says whether OTP 28.1+ is an accepted floor. This matters because it is a hard requirement inherited from Elixir 1.19, not a preference.

**exqlite `~> 0.39`.** Verified current: 0.39.0 (2026-07-16), preceded by 0.38.0 (2026-06-29), 0.37.0 (2026-06-03), 0.36.0 (2026-03-27), 0.35.0 (2026-02-25). Changelog for that range shows **no breaking changes**, and three additions that are directly relevant to this architecture and go unmentioned in the spine:

- **0.37.0** added `cancel/1`, `set_busy_timeout/2`, and `set_progress_handler_steps/2`. These are the primitives for bounding a runaway `:compute`-lane query (AD-3) — the spine has no cancellation or timeout story at all.
- **0.38.0** refined `:mode` for opening databases (e.g. `[:readwrite]` without implicit CREATE). AD-2's "read-only connections" needs exactly this, and the mode vocabulary changed inside the version range the spine is jumping across.
- **0.36.0** added `set_authorizer/2` — a genuine enforcement mechanism for AD-14 ("no consumer creates, alters or drops objects in bee's database"), which the spine currently states as a policy with no technical enforcement.

**nimble_pool `~> 1.1`.** Package exists, is maintained by Dashbit, 55.8M total downloads, ~18.8k/day. But 1.1.0 is from **March 2024**. That is not abandonment (it is a small, finished library), yet the spine should not be read as claiming a freshly-maintained dependency.

**jason `~> 1.4`.** Latest stable 1.4.5 (2026-05-05). Correct and current.

---

## 2. Is nimble_pool the right pooling choice? (web-verified, not asserted)

**Short answer: yes, it is defensible and arguably the best available fit — but the spine reaches that conclusion without showing the work, and it omits that a pooling library is already in the dependency tree.**

### Evidence for

The official NimblePool documentation states its purpose almost verbatim for this use case:

> "You should consider using NimblePool whenever you have to manage sockets, ports, or **NIF resources** and you want the client to perform one-off operations on them."

`Exqlite.Sqlite3` handles are precisely NIF resource references. The pooled-resource-plus-client-side-work model is the right shape: the checked-out connection is used directly by the calling process, so a slow rollup query occupies a *connection*, not the pool manager. That is the property AD-3 needs.

The docs also say what it is *not* for — processes, and multiplexed resources such as HTTP/2 connections. Neither exclusion applies here.

### Evidence the spine failed to surface

1. **`db_connection` is already a dependency.** `mix.lock` shows `db_connection 2.9.0` present, pulled in as a **non-optional** dependency of exqlite. `Exqlite.Connection` is a `DBConnection` implementation with a `pool_size` option (default 5) and documented `busy_timeout`, `journal_mode`, and `wal_auto_check_point` options. The spine adds a second pooling library while the first is already compiled into the build, and never mentions the overlap. That is a real decision that deserves an explicit "we chose NimblePool *over* DBConnection because…" line.

2. **The alternatives were genuinely checked and genuinely do not fit better:**
   - **Ecto's SQLite3 adapter (`ecto_sqlite3`)** cannot express a read/write pool split within one repo. The community thread on exactly this problem ("Ecto_sqlite different read and write pools") reached **no consensus**; the workaround is two repos (writer `pool_size: 1`, reader larger), which breaks Ecto's SQL sandbox for tests. Bee is a library, not a Phoenix app; adopting Ecto for this would be a large dependency for a capability it does not provide.
   - **poolboy** is the legacy option and has no advantage over NimblePool for NIF resources.
   - So: NimblePool is the right call. The spine's *conclusion* survives review; its *justification* is missing.

3. **NimblePool's own documented bottleneck is not acknowledged.** The docs warn: "because all resources are under a single process, any resource management operation will happen on this single process, which is more likely to become a bottleneck." Checkout/checkin is cheap, so this is unlikely to bite at the sizes AD-3 proposes — but AD-3's entire stated purpose is *eliminating* head-of-line blocking, and it introduces a new single process without noting it.

4. **Dirty-scheduler capacity is an unverified assumption (see Finding H-2).** exqlite executes SQLite calls on the **dirty NIF scheduler** ("maintaining each SQLite connection's command pool is complicated and error prone" — project README). AD-3 proposes `:fast` = `System.schedulers_online()` capped at 8, plus `:compute` 1–2, plus the writer. On an 8-core machine the BEAM's default dirty-CPU scheduler count is also 8. Up to 11 connections contending for 8 dirty schedulers means the pool sizing does not actually bound concurrency the way AD-3 implies. Nothing in the spine shows this was measured.

5. **Related, and now partly stale:** exqlite issue #192 ("Replace DirtyNIF execution model") is the canonical statement of this limitation. It remains **open**, assigned to the 1.0 milestone. But note the progress-handler work it proposed has *partly landed* in 0.37.0 (`cancel/1`, `set_progress_handler_steps/2`) — so anyone citing #192 as an unmitigated blocker would be working from stale information.

---

## 3. The four SQLite claims — verified against sqlite.org

### 3.1 Does WAL genuinely allow concurrent readers without blocking the single writer? — **CONFIRMED**

Primary source, `sqlite.org/wal.html`:

> "WAL provides more concurrency as readers do not block writers and a writer does not block readers. Reading and writing can proceed concurrently."

> "Because writers do nothing that would interfere with the actions of readers, writers and readers can run at the same time. However, since there is only one WAL file, there can only be one writer at a time."

AD-2's model (one writer, N readers, WAL mandatory) is exactly what the documentation describes. **This claim is not folklore.** It is also already true in the repo — `lib/bee/store.ex:9` sets `PRAGMA journal_mode=WAL`.

**Two documented caveats the spine does not carry:**

- **Same-host requirement.** "All processes using a database must be on the same host computer; WAL does not work over a network filesystem. This is because WAL requires all processes to share a small amount of memory." AD-2 says "WAL is mandatory" without stating that this makes network-filesystem deployment impossible. For a library whose consumers include a daemon, that constraint belongs in the spine.
- **Read-only opening is subtler than AD-2 implies.** "It is not possible to open read-only WAL databases. The opening process must have write privileges for the `-shm` wal-index shared memory file… or else write access on the directory." Relaxed in SQLite 3.22.0+ only when `-shm` and `-wal` already exist or can be created, or the database is `immutable`. AD-2's phrase "pooled read-only connections" reads as `SQLITE_OPEN_READONLY`; combined with WAL, that requires the writer to have already created the `-shm`/`-wal` files. Boot ordering (writer opens first, then readers) therefore becomes load-bearing and is currently unstated.

### 3.2 Can SQLite index a `json_extract()` expression, and will the planner USE it? — **CONFIRMED, BUT AD-9 IS MATERIALLY INCOMPLETE**

Both halves verify:

- **Is it allowed?** `sqlite.org/json1.html`: "All of the functions listed below have the `SQLITE_INNOCUOUS` and `SQLITE_DETERMINISTIC` flags." `sqlite.org/expridx.html` permits any deterministic function in an index expression. So `CREATE INDEX ... ON issues(json_extract(dims,'$.k'))` is legal.
- **Will the planner use it?** Yes — **but only under a condition AD-9 does not state.** From `expridx.html`:

  > "The query planner will consider using an index on an expression when the expression that is indexed appears in the WHERE clause or in the ORDER BY clause of a query, **exactly** as it is written in the CREATE INDEX statement."

  SQLite performs no algebraic equivalence matching. The doc's own example: with `CREATE INDEX t2xy ON t2(x+y)`, the query `WHERE y+x=22` does **not** use the index; `WHERE x+y=22` does.

**Why this is a HIGH finding rather than a footnote:** AD-4 mandates that *all* SQL is generated by `Bee.Query.Interpreter` from a spec. AD-9 then makes measurement query performance depend on expression indexes. Those two decisions only compose if the interpreter emits the indexed expression **byte-for-byte identically** to the DDL that created the index — same function spelling, same path string, same quoting, same column reference. That is a hard, silent constraint on the code generator: get it slightly wrong and you get a full table scan with no error, which is precisely the "silent failure" the Consistency Conventions forbid. AD-9 currently reads as though creating the index is sufficient.

Two corollaries also missing:

- **`->>` and `json_extract()` are not interchangeable for index matching.** They are semantically near-equivalent but textually different, so an index built on one will not serve a query written with the other. If the interpreter ever emits `->>` for ergonomics, every measurement index silently dies.
- **Affinity/collation.** `json_extract` on a text dimension yields text; comparison affinity mismatches can defeat an index. I could not confirm the exact behaviour for this schema from documentation alone — this needs an empirical `EXPLAIN QUERY PLAN` check against real data, not an assertion either way. Flagging as unverified rather than as a defect.

**Recommendation:** AD-9 should state the exact-match rule as a rule (one canonical expression-rendering function in the interpreter, shared with the migration that creates the index), and the spine should require an `EXPLAIN QUERY PLAN` assertion in tests for every hot-dimension index.

### 3.3 Is `PRAGMA user_version` the standard migration-versioning mechanism? — **CONFIRMED**

`sqlite.org/pragma.html`:

> "The user_version pragma will get or set the value of the user-version integer at offset 60 in the database header. The user-version is an integer that is available to applications to use however they want. **SQLite makes no use of the user-version itself.**"

Explicitly application-owned and safe to write. Contrast with `schema_version`, which SQLite manages and which the docs warn against setting ("may cause SQL statements to run using an obsolete schema, which can lead to incorrect answers and/or database corruption"). AD-15 picks the correct one.

*Precision note:* "standard" is convention, not specification — SQLite does not designate `user_version` as *the* migration mechanism; it designates it as a free integer, and the ecosystem converged on using it for migrations. AD-15's usage is correct and idiomatic. No change needed beyond, optionally, not calling it a standard.

### 3.4 Does FTS5 support the external-content / trigger-sync pattern AD-15 implies? — **CONFIRMED**

`sqlite.org/fts5.html` documents external content tables (`content=t1, content_rowid=d`) and gives the trigger-sync pattern verbatim:

> "It is still the responsibility of the user to ensure that the contents of an external content FTS5 table are kept up to date with the content table. One way to do this is with triggers."

…followed by the canonical `_ai` / `_ad` / `_au` AFTER INSERT/DELETE/UPDATE trigger trio, using the `INSERT INTO fts_idx(fts_idx, rowid, …) VALUES('delete', …)` idiom for removals.

**Directly supports AD-15's "Migration 001 drops and rebuilds the consumer-injected FTS objects."** The docs supply the exact escape hatch: "in any other situation where the FTS index and its content table have become inconsistent, the `'rebuild'` command may be used to completely discard the contents of the FTS index and rebuild it based on the current contents of the content table" (`INSERT INTO fts_idx(fts_idx) VALUES('rebuild');`). Worth naming explicitly in AD-15 — a full drop-and-recreate of the virtual table is more expensive than a `rebuild`, and the spine should say which it means.

**FTS5 availability confirmed in-repo, not assumed:** `deps/exqlite/Makefile:109` contains `CFLAGS += -DSQLITE_ENABLE_FTS5=1` (alongside FTS3/FTS4, RTREE, STAT4, GEOPOLY, MATH_FUNCTIONS). The Stack table's "bundled with exqlite" is accurate.

---

## 4. Findings by severity

### HIGH

**H-1 — The Stack table conflates *proposed* with *actual*; three of five entries are not in the repo.**
`mix.exs` currently declares only `{:exqlite, "~> 0.34"}` and `{:jason, "~> 1.4"}`. `mix.lock` pins `exqlite 0.34.0`. There is **no `nimble_pool`** in `mix.exs` or `mix.lock`, and **no explicit `db_connection`** (it arrives transitively). The spine presents the Stack as description; it is in fact a change set. A reader implementing from this document will not know that adopting it requires a dependency addition and a 5-minor driver bump.
Two consequences worth calling out:
- `~> 0.34` already permits 0.39.0, so the "bump" is a lockfile update (`mix deps.update exqlite`), not a constraint change. The spine should say so.
- `db_connection 2.9.0` is a compiled, present dependency and belongs in the Stack table whether or not bee uses it directly — it is the thing NimblePool is being chosen *instead of*.

**H-2 — AD-9's expression-index decision omits the exact-match requirement it entirely depends on.**
See §3.2. The claim is *true* but incomplete in the way that makes it dangerous: a spec-driven SQL generator (AD-4) will silently fall back to full table scans if the emitted expression text drifts from the index DDL by so much as a quote style. No test obligation, no canonical-rendering rule, and no `EXPLAIN QUERY PLAN` verification is specified anywhere in the spine.

### MEDIUM

**M-1 — AD-3's pool sizing is asserted, never measured, and may not bound what it claims to bound.**
`:fast` = `schedulers_online()` capped at 8, `:compute` = 1–2, plus the writer, gives up to 11 connections issuing **dirty-NIF** calls against a BEAM whose default dirty-CPU scheduler count equals the online scheduler count. The lane split may therefore not deliver the isolation AD-3 promises. No source, no benchmark, no reference to exqlite's dirty-NIF model appears in the spine. Needs measurement before it is stated as a rule.

**M-2 — No WAL checkpoint policy, while AD-3 deliberately introduces long-running readers.**
`wal.html`: "if a database has many concurrent overlapping readers and there is always at least one active reader, then no checkpoints will be able to complete and hence **the WAL file will grow without bound**… This scenario can be avoided by ensuring that there are 'reader gaps'… one might also consider running manual checkpoints with `SQLITE_CHECKPOINT_RESTART` or `SQLITE_CHECKPOINT_TRUNCATE`." AD-3's `:compute` lane exists specifically to host long traversals and rollups — exactly the workload that starves the checkpointer. exqlite exposes `wal_auto_check_point`. The spine says "WAL is mandatory" and stops there.

**M-3 — AD-2's "read-only connections" under WAL needs a stated boot ordering and a stated mode.**
See §3.1. Read-only WAL opening requires the `-shm`/`-wal` files to exist or be creatable (SQLite 3.22.0+). exqlite 0.38.0 changed the `:mode` vocabulary within the version range being adopted. Which mode the reader pool opens with, and that the writer must open first, are load-bearing and unspecified.

**M-4 — WAL's same-host constraint is not recorded as a deployment invariant.**
"All processes using a database must be on the same host computer; WAL does not work over a network filesystem." AD-2 makes WAL mandatory, which makes this a permanent property of bee. It belongs in the spine, not in a future incident report.

### LOW

**L-1 — `jason` may be redundant.** Elixir 1.18+ ships a built-in `JSON` module (backed by OTP 27's `json`). With an Elixir `~> 1.19` floor, a zero-dependency JSON path exists. Not a defect — Jason is faster for some workloads and `Jason.Encoder` protocol adoption is real — but "we keep jason because X" is a decision the spine currently makes silently. Worth one line, especially for a library that presumably wants a small dependency surface.

**L-2 — `~> 0.39` on a 0.x driver is a loose constraint.** In Hex, `~> 0.39` means `>= 0.39.0 and < 1.0.0`, so it will happily pick up 0.40, 0.50, and any breaking change a pre-1.0 driver ships. Given exqlite's cadence (five minors in five months) and an open 1.0 milestone that plans to replace the execution model (#192), `~> 0.39.0` (patch-only) is the more honest constraint for a library.

**L-3 — Unsourced empirical claims in Deferred.** "Measured dependency density is ~13% (357 edges / 2,686 issues)", "largest subtree is 69 nodes", "sub-millisecond". These are plausible and clearly came from somewhere, but the spine gives no query, date, or database. They are load-bearing (they justify deferring sequencing/LP optimisation and rollup caching). A one-line provenance note would make them re-checkable when someone revisits the deferral. Similarly, AD-17's "the on-disk JSONL format is a consumer contract (DevMan)" is an external claim I could not verify from this repo.

---

## 5. Claims that survived the check cleanly

Recorded so a later reader does not re-litigate them:

- WAL reader/writer concurrency and the single-writer constraint (AD-2) — verbatim match with `sqlite.org/wal.html`.
- `PRAGMA user_version` as an application-owned migration counter (AD-15) — verbatim match with `sqlite.org/pragma.html`, and correctly chosen over `schema_version`.
- FTS5 external-content tables with trigger sync, and the `'rebuild'` command for re-syncing (AD-15) — verbatim match with `sqlite.org/fts5.html`.
- Expression indexes on deterministic functions including the JSON functions (AD-9) — permitted per `expridx.html` + `json1.html`; only the planner's exact-match rule is missing.
- FTS5 compiled into exqlite's bundled SQLite — verified in `deps/exqlite/Makefile`.
- NimblePool as a fit for NIF resources — verified against its own documentation.
- AD-15's premise that the current schema uses `CREATE TABLE IF NOT EXISTS` and is therefore in an unknowable state — verified in `lib/bee/store.ex`; the spine is describing the real repo, not a strawman.
- Every named package exists on hex.pm at or above the stated version.

---

## Sources

- [SQLite: Write-Ahead Logging](https://www.sqlite.org/wal.html)
- [SQLite: Indexes On Expressions](https://www.sqlite.org/expridx.html)
- [SQLite: JSON Functions And Operators](https://www.sqlite.org/json1.html)
- [SQLite: PRAGMA Statements](https://www.sqlite.org/pragma.html)
- [SQLite: FTS5](https://www.sqlite.org/fts5.html)
- [hex.pm — exqlite](https://hex.pm/packages/exqlite)
- [hex.pm — nimble_pool](https://hex.pm/packages/nimble_pool)
- [hex.pm — jason](https://hex.pm/packages/jason)
- [NimblePool documentation](https://hexdocs.pm/nimble_pool/NimblePool.html)
- [exqlite CHANGELOG](https://github.com/elixir-sqlite/exqlite/blob/main/CHANGELOG.md)
- [exqlite issue #192 — Replace DirtyNIF execution model](https://github.com/elixir-sqlite/exqlite/issues/192)
- [Exqlite.Connection docs](https://hexdocs.pm/exqlite/Exqlite.Connection.html)
- [Elixir v1.19 released](https://elixir-lang.org/blog/2025/10/16/elixir-v1-19-0-released/)
- [Elixir Forum — Ecto_sqlite different read and write pools](https://elixirforum.com/t/ecto-sqlite-different-read-and-write-pools/63588)
- In-repo: `mix.exs`, `mix.lock`, `lib/bee/store.ex`, `deps/exqlite/Makefile`
