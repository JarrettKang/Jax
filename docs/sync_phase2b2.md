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

All Flutter/coordinator interchange uses JSON encoded as strict UTF-8 without a
BOM. Status/result files are atomically staged and renamed. The PowerShell
launch prefix fixes console stdout/stderr to UTF-8 before invoking the script;
Dart decodes those diagnostic streams strictly and never enables malformed-byte
replacement. Snapshot and SyncPlan JSON use the same UTF-8 contract.

Normal failure paths distinguish stale plans, invalid plans, backup/apply/final
verification errors, successful two-device rollback, critical rollback failure,
and verified business synchronization followed by baseline-write failure.
Whole-database restore is used only by rollback.

## Sync Storage

All durable coordinator artifacts resolve from one device-local
`SyncStorageRoot`. With no setting file, existing installations retain the
legacy root `%APPDATA%\Jax`: the baseline remains at
`sync\last_successful_sync.json` and existing session backups remain under
`sync_backups\`. This compatibility mode prevents an upgrade from appearing to
lose the Last Successful Sync Baseline.

After a user-selected migration, the chosen directory itself is the root and
uses this versioned layout:

```text
<SyncStorageRoot>\
  baseline\last_successful_sync.json
  backups\<timestamp>\windows_before_sync.db
  backups\<timestamp>\android_before_sync.db
  sessions\...
  logs\...
```

The low-frequency storage panel in the standalone UI displays the exact root,
opens it in Explorer, and lets the user select a directory with the native
Windows folder picker. A change always offers **迁移并使用新位置**; there is no
path-only switch that could silently discard three-way history. The migration
is `validate -> copy -> SHA-256/readability verification -> baseline fingerprint
verification -> persist setting -> reopen baseline -> clean old copies`. Backup
SQLite files are opened read-only and exported through the snapshot adapter as
part of verification. If any step fails, the exact old setting remains active,
the old baseline/backups are untouched, and incomplete target artifacts are
removed. Moving to the same, ancestor, or descendant root is rejected.

The small root/layout/retention setting remains at
`%APPDATA%\Jax\sync_storage.json`; it is a Windows-only preference and is never
included in a Sync Snapshot or sent to Android. The Windows business database
also remains `%APPDATA%\Jax\jax.db`; it is not a sync artifact and is not moved
by this feature. Flutter passes the resolved root, layout version, and retention
to PowerShell, while direct CLI use reads the same setting unless explicit
`-StorageRoot`, `-StorageLayoutVersion`, `-BackupRetention`, `-Baseline`, or
`-BackupRoot` overrides are supplied.

Backup retention defaults to the most recent five sessions and accepts 1–50.
Both device databases and metadata are retained or deleted as a whole session
directory. Cleanup runs only after a terminal Apply result (or an explicit safe
retention-setting change), never during Apply or rollback. The current backup
is retained, recent failed/rolled-back sessions participate in the same newest-N
policy, and `CRITICAL_ROLLBACK_FAILURE` evidence is never automatically deleted.
Analyze/session reports and every reported baseline/backup path use the resolved
root rather than a UI hard-coded AppData path.

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
