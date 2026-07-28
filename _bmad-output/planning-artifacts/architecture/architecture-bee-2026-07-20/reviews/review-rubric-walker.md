# Rubric Walker Review — ARCHITECTURE-SPINE.md (bee)

**Reviewer role:** Rubric Walker
**Date:** 2026-07-20
**Artifact:** `_bmad-output/planning-artifacts/architecture/architecture-bee-2026-07-20/ARCHITECTURE-SPINE.md`
**Driving input:** `docs/plans/2026-07-20-bee-supercharger-design-brief.md`
**Decision log:** `.memlog.md` (same directory)
**Brownfield read:** `lib/bee.ex`, `lib/bee/{repo,store,graph,world,lock,export,agents,id}.ex`, `mix.exs`

**Verdict: PASS-WITH-FINDINGS.**

This is a genuinely good spine. It is short, the ADs are mostly sharp and testable, the paradigm is stated once and holds, and several decisions are grounded in measurement rather than assertion (AD-12/Deferred rollup caching, the sequencing deferral). It fails the checklist in a specific and recoverable way: a cluster of *concrete schema-level* divergence points that the epics layer will hit on day one are unruled, and one whole dimension — the process/supervision and operational envelope of an embedded library — is silent.

---

## 1. Does it fix the real divergence points for the level below, and miss none?

**Mostly, with four material misses.** The spine correctly nails the big ones: one execution path (AD-4), enrichment opt-in (AD-10), withheld accounting (AD-11), one rollup aggregator (AD-12), migrations (AD-15), export debounce (AD-17). Those are exactly the places two story authors would otherwise diverge, and each rule is decidable.

### F1 (CRITICAL) — `parent` is modelled twice and the spine picks neither

AD-13 (spine:137) declares `parent-child` a member of the `dep_type` vocabulary. Meanwhile `issues.parent` is a real column with an FK (`store.ex:52`), the ER diagram keeps it as a distinct relation (`spine:249` `ISSUES ||--o{ ISSUES : parent`), AD-12 makes "the parent tree" the rollup unit (spine:131), and `repo.ex:296-327` implements parent-cycle detection as a separate recursive walk over that column.

So: when a story creates a child issue, does it (a) set `issues.parent`, (b) insert a `dependencies` row with `dep_type='parent-child'`, or (c) both? Each choice produces a different `tree`, a different `rollup`, a different `ready`. AD-13's own rule — "Readiness is computed from edge type" — cannot even be implemented for `parent-child` unless the answer is (b) or (c), yet AD-12's rollup and `tree_page` (`store.ex`, `repo.ex:85`) read the column. This is the single highest-value missing ruling in the document.

### F2 (CRITICAL) — the `dependencies` primary key forbids the new vocabulary

`store.ex:70-77`: `PRIMARY KEY (issue_id, depends_on_id)`. AD-13 introduces seven edge types. Two issues can legitimately carry both `related` and `blocks`, or `discovered-from` and `blocks` — the current PK makes that impossible, and `insert_dependency` (`store.ex:435`) is `INSERT OR IGNORE`, so the second edge is *silently dropped*. AD-13 says nothing about whether `dep_type` joins the PK. Two story authors will resolve this differently, and one of them will ship silent data loss on a table AD-13 makes load-bearing. The brief flagged the missing `(depends_on_id, dep_type)` index (`brief:180`) but not this; the spine inherits the blind spot.

### F3 (HIGH) — `effort` is the base primitive of AD-12 and is never defined

AD-12 (spine:131): "total effort is the base additive primitive over a node set." Nothing in the spine says what `effort` *is*. The brief specified a column — `issues.estimate` — "so declared can later be measured against earned" (`brief:174`). The spine drops `estimate` entirely: it appears in no AD, no convention, no ER diagram, no structural seed. Candidates a story author will pick from: an `issues.estimate` column, a `measure` row in `measurements` (AD-9), a `bee:` key in `metadata` (AD-14), or a count of nodes. Each gives a different rollup and a different L3 calibration story. Note this also silently drops the brief's "earned vs declared" thread (`brief:232-236`), which the brief calls "the moat".

### F4 (HIGH) — the in-memory `:digraph` layer has no ruling: keep, or retire?

`Bee.Repo` holds two live `:digraph` structures in GenServer state (`repo.ex:23-24, 34-42`). `Bee.Graph` (124 LOC) and `Bee.World` (200 LOC) — 16% of the library — operate on them exclusively. They back `ready` (`graph.ex:63`), `critical_path` (`graph.ex:87`), `who_blocks_whom`, `agent_load`, `bottlenecks`, `available_in_project` (`world.ex:99-157`), and, critically, **cycle prevention on `block/2`** (`graph.ex:36` — the `:acyclic` digraph is the only cycle check).

The spine's structural seed (`spine:214-218`) replaces `Bee.Graph` with SQL-shaped modules (`traverse.ex`, `ready.ex`, `critical_path.ex`, `rollup.ex`) and AD-2 says "all reads go through `Bee.Read`" — which reads like retirement. But it is never stated, and two consequences are left dangling:

- **Where does cycle detection live after the digraph goes?** AD-2's own *Prevents* clause names "DAG cycle checks" as a reason for the single writer, so the spine is aware the check exists — but never says it becomes a recursive CTE inside the writer, nor whether the new non-blocking edge types (`related`, `replies-to`) participate in cycle checking at all. A `replies-to` cycle is legal; a `blocks` cycle is not. Unruled.
- **`Bee.World` is architecturally homeless.** It appears in no AD, no layer table, no capability map, no structural seed — see F8.

---

## 2. Is every AD's Rule enforceable, and does it prevent its stated divergence?

Rule quality is above average. Concretely testable: AD-2, AD-3 (`schedulers_online()` capped at 8; `:compute` 1–2; classification from `via:`/rollup scope/stats selector — a reviewer can check this from the spec struct alone), AD-8, AD-10 (the four detail atoms, `:compact` default, the named never-auto-loaded relations), AD-11, AD-13's vocabulary enumeration, AD-15's `user_version` gate, AD-17.

Weak or unenforceable:

- **AD-1 (spine:65)** — half a rule. "A module may depend only on its own layer or one below" is checkable; "Any upward need is a signal the abstraction is misplaced — raise it, don't invert it" is a platitude with no mechanism. This is the one AD that could trivially be made mechanical (`mix xref graph --format cycles` / a layer-boundary test in CI) and isn't. Note also it is the only unmarked AD besides AD-7 and AD-13 — the `[ADOPTED]` tagging is inconsistent (AD-1, AD-7, AD-13 lack it) with no legend explaining what the absence means. **(MEDIUM)**

- **AD-14 (spine:143)** — "No consumer creates, alters or drops objects in bee's database" is unenforceable *by bee* as written: consumers hold the file handle. The actual enforcement mechanism exists elsewhere in the document (AD-15's "an unexpected schema refuses to boot") but the two ADs are never linked, and that linkage is load-bearing — see F5. **(MEDIUM)**

- **AD-5 (spine:89)** — the *rule* is enforceable, but the mechanism the memlog uses to justify an open catalogue is missing. `.memlog.md:26` resolves the "an open catalogue rots" objection with: "Every `ask/2` call is an event; intent name is a dimension. Usage counts make registration reversible." The spine keeps the open catalogue and **drops the pruning evidence mechanism**. Worse, it is not merely omitted — as specified it is *unimplementable*: the `events` table has `issue_id TEXT NOT NULL` (`brief:139`), so an intent-invocation event has no home; and the only other channel, `[:bee, :query, :stop]` telemetry (`spine:176`), is ephemeral and counts nothing. AD-5 as it stands therefore reintroduces the exact "work_handler.ex 2.0" failure it claims to prevent. **(HIGH)**

### F5 (CRITICAL) — AD-15 fail-loud vs. the live production DB: bee refuses to boot

AD-15 (spine:149): "**An unexpected schema refuses to boot** — never guess, never half-apply. Migration 001 drops and rebuilds the consumer-injected FTS objects."

The brief lists *three* categories of consumer injection to handle (`brief:113`): `issues_fts` + 3 triggers, **19 ALTERed `projects` columns**, and **`issue_project_backfill_log`**. `.memlog.md:33` confirms all three present in the live 16MB DB. AD-15 rules on the FTS objects only. The 19 extra `projects` columns and the stray table get no ruling anywhere in the spine — so on first boot against the real database, "unexpected schema" fires and **bee does not start**. Given the operator's deployment path is "stop live daemon → redeploy" (`brief:225`), this is a first-contact production failure, and it is exactly the case the artifact was written to handle. The spine also never defines what "unexpected" *means* (unknown `user_version`? unknown table? unknown column? extra index?) — which is itself the ruling that has to exist before AD-15 is implementable at all.

---

## 3. Could anything under Deferred let two units diverge?

The Deferred table (`spine:275-283`) is largely well-reasoned — L3, sequencing, rollup caching and online migrations each carry a measured or structural justification and a named revisit trigger. Those are correct deferrals.

Two problems:

### F6 (MEDIUM) — decided items were lost in distillation rather than deferred

`.memlog.md:38` records OPEN-4 as **resolved**: "Event retention: KEEP FOREVER, no compaction ladder", with volume math (~20k events / ~7MB) and an explicit rejection of DevMan's LOD ladder. The spine carries forward only the *payload discipline* half into AD-8 and states the retention decision nowhere — not as an AD, not as a convention, not in Deferred. A story author reading only the spine and the DevMan precedent will build the compaction ladder that was explicitly rejected. Same class of loss: the brief's `issues.estimate` (F3) and the intent-usage counting (AD-5 above).

### F7 (LOW) — "Deletion semantics for events" is fine; "consumer adaptation" is scope, not deferral

`spine:283` (deletion) is a correct deferral — no deletion exists today, `cancel` sets status. `spine:282` (consumer adaptation → GC-2694) is really a scope boundary and reads oddly in a Deferred table, but it does not create divergence.

---

## 4. Is named tech verified-current?

**PASS.** Verified live against hex.pm on 2026-07-20:

| Spine (spine:180-186) | hex.pm latest | Verdict |
|---|---|---|
| exqlite `~> 0.39` | 0.39.0 (2026-07-16) | current; correctly bumps `mix.exs`'s stale `~> 0.34` |
| nimble_pool `~> 1.1` | 1.1.0 (2024-03-25) | current (stable, not stale) |
| jason `~> 1.4` | 1.5.0-alpha.2 (prerelease) | `~> 1.4` correct — 1.4.x is latest stable |
| Elixir `~> 1.19` | — | matches `mix.exs:8` |

The memlog (`:31-32`) shows the verification was actually performed rather than asserted. Good. Minor note: "SQLite WAL + FTS5 (bundled with exqlite)" is accurate — exqlite ships SQLite compiled with `SQLITE_ENABLE_FTS5` — but no SQLite version is pinned or named, and FTS5 tokenizer choice (`unicode61` vs `porter`, and whether `bm25()` ranking is used, which `brief:241` explicitly calls out as the improvement over DevMan) is unstated. That is arguably an epics-level detail; flagging as LOW.

---

## 5. Does it ratify rather than contradict the brownfield?

**Largely ratifies.** The single-writer GenServer is preserved rather than rewritten (AD-2 vs `repo.ex:8-43`), WAL is already on (`store.ex:9`), the id-prefix convention matches `resolve_id/2` (`repo.ex:251-264` → `spine:169`), the `dep_type` column already exists to be populated (`store.ex:74`), and the export contract is preserved verbatim for DevMan (AD-17 vs `export.ex`). The `maybe_export` per-write dump (`repo.ex:236-245`, `export.ex:5`) is correctly identified and correctly replaced, and the memlog's measurement that it is a *landmine, not an active fire* (`:39`, `jsonl_path` nil for gc_daemon) is exactly the right kind of grounding.

Contradictions, in descending order: **F1** (parent double-modelled), **F2** (dependencies PK), **F4** (digraph fate + cycle check), **F5** (fail-loud vs. real injected schema), plus:

### F8 (HIGH) — `Bee.World` and the allocation domain are unmapped

`world.ex` (200 LOC) plus the public API it backs — `who_blocks_whom/0`, `agent_load/1`, `bottlenecks/0`, `register_agent/2`, `register_project/2`, `join_project/2`, `assign/2` (`bee.ex:32-39`) — appears **nowhere** in the spine: not in the layer table (`spine:26-31`), not in any AD, not in the Capability → Architecture Map (`spine:257-271`), not in the structural seed (`spine:190-222`). `AGENTS` survives only as an ER box (`spine:247`). `Bee.Lock` similarly survives only as `store/locks.ex` with no AD, and `import_jsonl/1` (`bee.ex:42`, `repo.ex:208`) plus the first-boot JSONL seeding path (`repo.ex:333-344`) are unmentioned while AD-17 rules on export only.

The consequence is concrete: `bottlenecks/0` calls `Bee.Graph.critical_path/1` on the in-memory digraph (`world.ex:125`), which AD-12 assigns to `Bee.Graph.CriticalPath`. So a whole existing public surface sits astride the exact modules being rewritten, with no ruling on whether it is retired, ported to SQL, or folded into intents (`:who_blocks_whom` and `:bottlenecks` are obvious Core-intent candidates under AD-5, and saying so would close this cleanly). The Capability Map is the spine's own completeness check and it is missing ~30% of the current public API.

---

## 6. Does it cover the driving brief's scope?

Brief §8 open items: **6/6 resolved and traceable** (OPEN-1→AD-5, OPEN-2→AD-3, OPEN-3→AD-12/Deferred, OPEN-4→AD-8 *partially, see F6*, OPEN-5→AD-17, OPEN-6→AD-15). Brief §3 decisions D1–D9 all land in ADs. Brief §2 defects: #1→AD-14/15, #2→AD-10, #3→AD-4, #4→AD-10, #5→AD-10, #6→AD-12/CriticalPath, #8→AD-13, #9→AD-17, #10→AD-2/3, #11→AD-15. Defects #7 and #12 are consumer-side and correctly out of scope.

Gaps against the brief:

- **F3** — `issues.estimate` (`brief:174`) and the whole "earned vs declared" thread (`brief:232`) dropped.
- **F5** — only 1 of 3 injected-object categories ruled (`brief:113`).
- **F9 (MEDIUM) — the snapshot/backup obligation is dropped.** `brief:54` and `.memlog.md:10` both state D1 "retires the stop-repo-to-snapshot hack in `gc_daemon/workflow/snapshot.ex:61-81`". The spine mentions snapshot, backup, and `VACUUM INTO` exactly zero times. Under the new design this is *not* automatic: with WAL plus N pooled readers plus a separate writer process, a consistent on-disk copy needs a defined mechanism (`VACUUM INTO`, the SQLite backup API, or a checkpointed file copy). The spine has retired the consumer's mechanism without supplying a replacement.
- **F10 (MEDIUM) — the verification/benchmark gate is absent.** `brief:220-223` mandates the 2–3-day-old snapshot fixture for both performance benchmarking *and* migration testing against real messy state, with the instruction "**Prove improvements, don't claim them**"; `brief:243` adds DevMan's parity-test harness for de-risking a storage swap. The spine has no testing, benchmarking or verification convention anywhere. For an artifact whose central claims are performance claims (105 round-trips → batched; exponential → memoized; serialized → two lanes), the absence of a stated proof obligation is a real omission at this altitude — it is precisely the thing the epics layer will otherwise skip.

---

## 7. Is every dimension this altitude owns decided, deferred, or an open question?

Data model, query/retrieval, graph semantics, extension points, migrations, naming, error shape, and dependency direction are all covered. The gaps cluster in one place, and it is the place the checklist warns about.

### F11 (HIGH) — the process/supervision topology is silent

Today bee is one GenServer, started by the consumer, with every public function taking an explicit `server` argument defaulting to `Bee.Repo` (`bee.ex:6-42`) and `start_link` honouring a `:name` option (`repo.ex:8-9`). There is no `application.ex` and no supervision tree in the library.

The spine replaces this with **at least four collaborating processes** — `Bee.Write.Server`, two `Bee.Read.Pool` lanes, and AD-17's export debouncer — and says nothing about:

- **Supervision.** Who supervises them, in what order, with what restart strategy? Migrations "run inside the writer at boot, before anything serves" (AD-15) — so readers must not accept checkouts until the writer signals migration complete. That is a startup-ordering invariant the spine implies but never states, and getting it wrong means readers querying a pre-migration schema.
- **Instance naming.** With one named GenServer, `Bee.start_link(name: ...)` supports multiple instances in a VM (and the whole public API is written for it). With a writer plus two named pools plus a debouncer, per-instance naming becomes a design decision. Unruled, this breaks either multi-instance support or the test suite (`test/bee_test.exs`).
- **Crash semantics.** Writer dies mid-transaction — what happens to the in-flight caller, to the `Bee.Export` debounce buffer holding unflushed state (AD-17 promises "a flush on terminate", which a `:brutal_kill` or a crash does not deliver), and to any writer-held cache? Reader connection dies — does the pool re-open it, and does a lane at zero connections block or error?

### F12 (MEDIUM) — failure modes and the operational envelope are undecided

Not exhaustively required for an embedded library, but these are real and unaddressed:

- **`SQLITE_BUSY` / lock contention.** No `busy_timeout` PRAGMA is set today (`store.ex:9-11` sets `journal_mode`, `foreign_keys`, `synchronous` only). With a pool of readers plus a writer plus a checkpointer, `busy_timeout` and WAL `wal_autocheckpoint` become required settings, not optional ones. The spine says "WAL is mandatory" (AD-2) and stops there.
- **Pool checkout timeout and saturation behaviour.** AD-3 accepts, in writing, that "under an all-analytics burst, a heavy query queues behind another heavy query" (`.memlog.md:29`). That accepted cost makes queue-depth behaviour a first-class concern — yet there is no checkout timeout, no queue bound, and no defined error when the `:compute` lane (1–2 connections!) is saturated. The most likely production symptom of this architecture has no defined response.
- **WAL file growth.** Long-lived pooled read snapshots pin WAL frames and prevent checkpointing — a known SQLite failure mode directly caused by AD-2/AD-3, unmentioned.
- **Observability.** Telemetry covers reads only (`spine:176`: `[:bee, :query, :stop]`). No event for writes, migration steps (the fail-loud path especially — you want to know *which* step refused), export flushes, pool checkout wait time, or lane queue depth. Given AD-3's whole justification is lane isolation, lane queue depth is the metric that proves or disproves the architecture, and it is not emitted.
- **Not applicable / correctly out of scope:** deployment targets, infra/provider strategy, and multi-node concerns — bee is an embedded in-process library over a local file, and the spine is right not to invent an envelope for them. AD-15's boot-time stop-the-world is the correct and sufficient deployment ruling. Security is likewise adequately handled by AD-5's "registered intents can express anything `Bee.query` can and nothing more", which is a real injection-safety argument, not a hand-wave.

---

## Findings summary

| # | Sev | Finding |
|---|---|---|
| F1 | critical | `parent` modelled twice — `issues.parent` column (`store.ex:52`) vs AD-13's `parent-child` dep_type (`spine:137`); no ruling on which is authoritative. Divergent `tree`/`rollup`/`ready`. |
| F2 | critical | `dependencies PRIMARY KEY (issue_id, depends_on_id)` (`store.ex:70-77`) cannot hold AD-13's 7-type vocabulary; `INSERT OR IGNORE` (`store.ex:435`) silently drops the second edge. |
| F5 | critical | AD-15 fail-loud (`spine:149`) rules only on injected FTS objects; the 19 ALTERed `projects` columns and `issue_project_backfill_log` (`brief:113`, `.memlog.md:33`) are unruled ⇒ bee refuses to boot on the live DB. "Unexpected schema" is also undefined. |
| F3 | high | AD-12's base primitive "effort" (`spine:131`) is never defined; `issues.estimate` (`brief:174`) and "earned vs declared" dropped entirely. |
| F4 | high | Fate of the in-memory `:digraph` (`repo.ex:23`, `graph.ex`, `world.ex`) unstated; cycle detection currently lives *only* in `:digraph.add_edge` (`graph.ex:36`) and has no replacement home. |
| F8 | high | `Bee.World` (200 LOC) + `who_blocks_whom`/`agent_load`/`bottlenecks`/agent-project registration/`import_jsonl` (`bee.ex:32-42`) absent from every layer table, AD, capability map and structural seed. |
| F11 | high | Process/supervision topology silent: 4+ new processes, no supervision, no startup ordering vs AD-15 migrations, no instance naming, no crash semantics (AD-17's terminate-flush promise is unbacked). |
| AD-5 | high | Pruning-by-evidence (`.memlog.md:26`) dropped, and unimplementable as specified — `events.issue_id` is `NOT NULL` (`brief:139`), telemetry is ephemeral. Open catalogue with no reversal mechanism. |
| F9 | medium | Snapshot/backup: D1 retires the consumer's stop-repo hack (`brief:54`) and the spine supplies no replacement (`VACUUM INTO` / backup API) for a WAL + pooled-reader design. |
| F10 | medium | No testing/benchmark/verification convention despite the brief's explicit snapshot-fixture mandate and "prove improvements, don't claim them" (`brief:220-223, 243`). |
| F12 | medium | Failure/ops envelope: no `busy_timeout`, no pool checkout timeout or saturation error, no WAL-growth ruling, write/migration/pool telemetry missing (lane queue depth in particular). |
| F6 | medium | Decisions lost in distillation: event retention "keep forever, no compaction" (`.memlog.md:38`) appears nowhere — a story author will build the rejected LOD ladder. |
| AD-1 | medium | Rule half-platitude ("raise it, don't invert it") with no mechanism, despite being trivially mechanisable (`mix xref`). `[ADOPTED]` tagging inconsistent (AD-1, AD-7, AD-13 unmarked) with no legend. |
| AD-14 | medium | "No consumer touches bee's DDL" is unenforceable by bee; its only real enforcement is AD-15's fail-loud, and the two are never linked. |
| F7 | low | Deferred row "consumer adaptation → GC-2694" is a scope boundary, not a deferral. Harmless. |
| §4 | low | No SQLite version pinned; FTS5 tokenizer and `bm25()` ranking (`brief:241`) unspecified. |

## Recommended minimum to reach PASS

Four new or amended ADs close everything critical/high:

1. **Amend AD-13** — rule that `issues.parent` is the sole representation of hierarchy and `parent-child` is *derived* for readiness purposes (or the converse, explicitly); and rule `dep_type` into the `dependencies` primary key, replacing `INSERT OR IGNORE`.
2. **New AD** — cycle detection and graph state: the `:digraph` pair is retired; cycle checking becomes a recursive CTE inside the writer; name which `dep_type`s participate.
3. **Amend AD-15** — define "unexpected schema" precisely, and rule on all three injected-object categories, not just FTS.
4. **New AD** — process topology: supervision tree, startup ordering (migrations complete before any reader serves), instance naming, and crash/terminate semantics including the export flush guarantee.

Plus three one-line additions: define `effort`/`estimate` (AD-12), restore the retention ruling (AD-8), and add a Consistency Convention row for the snapshot-fixture benchmark gate.
