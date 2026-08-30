# Sync Phase 2B-2: Standalone ADB Debug Sync

Phase 2B-2 connects the existing snapshot, compare, resolved-plan, mutation,
validation and rollback contracts to real Windows and Android Debug databases.
It remains a developer-only ADB workflow; it is not the Phase 3 LAN transport.

## Standalone Debug Sync UI

In a Windows Debug build, open the developer-mode icon in the Jax app bar. Jax
flushes and closes the normal business instance, then starts `jax.exe
--debug-sync`. This isolated mode does not open the Windows business database,
so it can remain visible while the coordinator locks and updates that database.
No environment variables, terminal, Dart command, JSON editing, or manual ADB
command is part of the normal UI path.

The UI flow is:

1. **检查连接** discovers ADB devices and checks the selected device, Debug
   package, `run-as`, Android database access, and Windows database access.
   Multiple authorized devices require an explicit selection. Missing,
   unauthorized, offline, non-Debug, and missing-package states are shown in
   user-readable text.
2. **分析同步** asks the coordinator to stop writers temporarily, take
   transaction-consistent Windows and Android snapshots (including WAL), run
   readiness and protocol validation, load an optional persisted baseline, and
   create a fresh `SyncPlan`.
3. The UI shows summary counts, warnings, automatic records, full conflict
   context and full list order. Every manual/list conflict must be explicitly
   resolved; `暂不处理` keeps Apply disabled.
4. **Dry Run** compiles a deterministic `MutationPlan`, simulates the final
   snapshot, validates invariants, and displays per-device operation counts,
   list changes, resolved-conflict count, and expected fingerprint.
5. **执行同步** requires a second confirmation. The coordinator prevents a
   second session, stops business writers, performs a final stale check, creates
   and verifies both backups, applies entity-level transactions, validates both
   databases, verifies the common final fingerprint, writes the baseline, and
   performs a post-sync Analyze.

## Progress and failure safety

The isolated UI remains visible for connection, analysis, Windows/Android
backup, apply, validation, final verification, baseline writing, post-analysis,
and rollback stages. The coordinator writes atomic structured status/report
files; PowerShell output is not the user interface.

Normal failure paths distinguish stale plans, invalid plans, backup/apply/final
verification errors, successful two-device rollback, critical rollback failure,
and verified business synchronization followed by baseline-write failure.
Whole-database restore is used only by rollback. The first real backup artifacts
are retained under `%APPDATA%\Jax\sync_backups\<timestamp>`. The successful
canonical baseline is `%APPDATA%\Jax\sync\last_successful_sync.json`.

No uninstall, package-data clearing, database reset, automatic repair,
background sync, or automatic Apply is used. The CLI tools remain available for
regression and diagnosis, but are not required by the standalone UI path.

## Transport boundary

The Windows UI calls `DebugSyncCoordinator`; the coordinator owns the guarded
session and invokes the ADB Debug transport. Sync snapshots, comparison,
resolution, mutation planning and validation contain no UI or ADB commands.
Phase 3 replaces the ADB transport/connection experience with LAN transport
without changing those sync contracts.

## Current acceptance note

Automated fixture/widget coverage and Windows build validation are complete.
The final real-device Analyze must be repeated whenever the target phone is
reconnected; a disconnected phone never causes an old plan to be reused.

