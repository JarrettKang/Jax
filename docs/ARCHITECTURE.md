# Current architecture

This describes the public candidate at schema **24**, Sync protocol **11**, and
version **0.1.0+1**. Earlier design proposals are historical where they differ.

## Boundaries

```text
UI → Core ← Data
             ↓
           SQLite
```

Core owns entities, repository interfaces, use cases and execution/temporal rules.
Flutter UI controllers call these interfaces; data repositories implement them.
`lib/app.dart` composes the real application, while `lib/main.dart` supplies
platform storage/preferences and optional Debug developer tooling. Runtime work
flows from UI through domain use cases to repositories and SQLite.

Android and Windows share core logic and SQL repositories. Android uses sqflite;
Windows uses sqflite FFI and system winsqlite3. Platform database location,
lifecycle, preferences and native runner integration remain explicit. Jax stores
application data locally; the database is not encrypted at rest by Jax.

## Product areas

- **World**: hierarchical long-term structure, categories, lifecycle and focus.
- **Planning**: successive rounds on a WorldNode, ordered PlanItems, review notes,
  dispatch into execution and promotion of suitable steps into WorldNodes.
- **Today**: day assignments and dynamic attention across executions and routines.
- **Home**: a contextual entry using execution state, routine timing and focus.
  Recommendations are deterministic rules, not AI.
- **Routine**: scheduled/on-demand definitions, occurrences and temporal windows.
- **Record**: facts from execution segments, with explicit correction workflows.

WorldNode, Plan and Event are distinct. Events are flat execution records, not
hierarchy nodes. PlanItem dispatch and corresponding event creation are atomic.
A planned event resolves its category through its source plan and WorldNode;
standalone events can have a direct category. A World detail execution list is
scoped to that node, rather than silently combining all descendant executions.

A RunSegment represents active work. Pause/wait intervals do not add active time.
Waiting is a domain execution state, including routine waiting in schema 24.
Completion, correction, review and subsequent planning remain separate operations.

## Persistence and lifecycle

`AppDatabase` owns schema creation/migrations and foreign-key configuration.
Repositories translate storage encodings into domain entities. SQLite constraints,
transactions and targeted migration tests protect invariants; see [Data model](DATA_MODEL.md).
Preferences such as assistantName (default Butler) and collapse state are separate
from business execution. The Jax-day boundary and carry-over bookkeeping are
explicit; carry-over initialization and UI preferences are device-local.

Windows shutdown prepares running work for exit and flushes storage. Android
backgrounding/process death is not treated as a user-requested pause. See lifecycle
and native tests rather than assuming desktop close behavior applies on Android.

## Experimental developer Sync

Protocol 11 supports the Windows ↔ Android **ADB developer workflow**, with
snapshots, baselines, compare, conflict detection, explicit apply and rollback.
Dataset generation and tombstones distinguish resets/deletions from ordinary
updates. There is no cloud/LAN transport or automatic background Sync service.
Private backups and confirmed destructive operations are described in [TOOLS](TOOLS.md).

## Verification and developer utilities

Host tests, native integration tests and PowerShell tool contracts cover different
boundaries. [Reproducibility](REPRODUCIBILITY.md) records Phase 6 results and harness
limitations; [Publication checklist](PUBLICATION_CHECKLIST.md) records Phase 7.
`tool/demo_data.dart` and `tool/capture_demo.dart` are isolated synthetic-only
publication tools. They do not change production startup or its data paths.
