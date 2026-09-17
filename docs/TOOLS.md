# Jax developer tools: safety and portability

These are developer tools, not an end-user installer or a production sync service.
Run commands from the repository root. Read this document before using real data.
`copy_windows_data_to_android.ps1` is a **destructive one-way overwrite, not Sync**.
Filenames are retained to avoid breaking historical references.

## Invariants

- No automatic Android uninstall, `pm clear`, sandbox deletion, or destructive
  installation retry. An install failure stops after one `adb install -r`.
- Android data tools default to `com.jarrett.jax`; an explicit override allows only
  `com.jarrett.jax` or
  `com.jarrett.jax.worldfixture` package, verify exact installed identity and
  `run-as`, and refuse missing/offline/unauthorized devices. Multiple connected
  devices require an explicit serial. Copy always requires one.
- Audit/readiness/verify never open through the migrating AppDatabase entrypoint.
  Unsupported schemas fail; upgrade a disposable copy separately. Failed schema
  validation does not automatically restart an app and thereby migrate it.
- Unknown backup directories, legacy unmarked backups, malformed metadata and
  links/junctions are preserved. Ownership markers prevent accidental deletion;
  they are not authentication against a malicious local user.
- All commands return zero on success, nonzero on failure. A successful dry-run
  means a plan was displayed, not that any data was changed.

## Inventory

All paths in the table are relative to `tool/`. All tools are developer-only.
"Read-only" describes the database source, not creation of private reports.

| Tool | Purpose | Read/write | Real-data safe? | Backup / classification |
|---|---|---|---|---|
| `create_development_fixture.dart` | Create a new empty marked fixture | New DB + marker | Never target real data | No overwrite; B |
| `development_data_reset.dart` | Delete fixture business data | Dry-run; explicit destructive write | **Real Jax directory and non-fixture identity refused** | Verified automatic backup; C |
| `copy_windows_data_to_android.ps1` | One-way Android overwrite | Dry-run; explicit source/target write | **WARNING: destructive** | Source snapshot + verified target backup + rollback; C |
| `database_snapshot.dart` | Consistent snapshot or verification | Source read-only, new output | Prefer stopped writers / consistent snapshot | No migration; B |
| `sync_readiness.dart` | Current-schema readiness | Read-only | Yes; no repair | B |
| `world_node_migration_report.dart` | Inspect legacy World migration mappings | Read-only | Yes; missing legacy tables fail | Historical diagnostic; B/E |
| `read_only_database_audit.dart` | Detailed recovery audit | Read-only + new JSON | Source yes; **report contains full private rows** | B |
| `rollout_audit.dart` | Detailed rollout audit | Read-only + new JSON | Source yes; **report contains full private rows** | B |
| `sync_phase2a.ps1` | ADB acquisition and compare | Stops writer, reads DB, writes private snapshots | Authorized Debug devices only | No business writes; B |
| `sync_phase2a.dart` | Export/compare snapshots | Read-only source; JSON output | Reports private | B |
| `sync_phase2b2.ps1` | Analyze / confirmed entity-level Sync Apply | Real-data writes only with confirmation | **WARNING: backup/rollback workflow** | Verified dual backup; C |
| `sync_phase2b2.dart` | Compile/verify/internal apply and baseline commands | Depends on subcommand | **WARNING: low-level transport helper** | Apply checks live/backup fingerprint; C |
| `install_android_debug.ps1` | Single guarded Debug update | Explicit device install | No uninstall fallback; caller backs up first | B |
| `windows_debug_acceptance.ps1` | Isolated tests and normal Debug rebuild | Build files and test processes | Do not run with existing Debug app | B |
| `world_attention_fixture.dart` | Disposable UI fixture | Temporary DB | Use isolated World QA package only | B |
| `tool_locator.ps1` | Shared executable/device/output helpers | Dependency discovery | No data mutation | A, dot-source only |
| `backup_retention.ps1` | Owned-session retention helper | Default preview, explicit delete | Unknown data preserved | C, dot-source only |
| `private_tool_support.dart` | CLI read-only/output/error helpers | Depends on caller | No automatic migration | A, library only |
| `android_data_transfer_contract_test.ps1` | Copy static contract | Reads source | No devices | A |
| `install_android_debug_contract_test.ps1` | Mock installer cases | Temporary mock files | Fake ADB/AAPT only | A |
| `sync_phase2a_contract_test.ps1` | Analyze static contract | Reads source | No devices | A |
| `sync_phase2b2_contract_test.ps1` | Sync static contract | Reads source | No devices | A |
| `windows_debug_acceptance_contract_test.ps1` | Acceptance runner contract | Reads source | No devices | A |
| `tool_safety_contract_test.ps1` | Locator and retention scenarios | Temporary files/junctions | No real data | A |
| `copy_safety_contract_test.ps1` | Fake-device overwrite/rollback scenarios | Temporary fake executable/data | No real ADB | A; needs Windows .NET Framework C# compiler |

A = safe isolated helper/test; B = safe with documented boundaries;
C = dangerous operation with explicit safeguards; E = historical diagnostic.
Private operational scripts under ignored backup directories remain private-only.

## Tool discovery

PowerShell scripts use `tool_locator.ps1`:

1. Explicit `-DartPath`, `-FlutterPath`, `-AdbPath`, or installer `-AaptPath`.
2. `JAX_DART_PATH`, `JAX_FLUTTER_PATH`, `JAX_ADB_PATH`, `JAX_AAPT2_PATH`.
3. Executable on PATH.
4. Dart/Flutter under `FLUTTER_ROOT/bin`; Dart can also be derived from Flutter
   on PATH or `JAX_FLUTTER_PATH`.
5. ADB under `ANDROID_HOME/platform-tools` then `ANDROID_SDK_ROOT/platform-tools`.

An explicitly configured missing file is an error, not permission to guess a
different installation. AAPT is explicit/env/PATH; no arbitrary build-tools
version is silently selected. Missing-tool errors name the setup options.
The Windows coordinator supports injected ADB/Dart paths; ADB discovery also
uses `JAX_ADB_PATH`, PATH and Android SDK environment variables. Resolved ADB is
passed to the script so discovery and Apply use the same executable.
No author-specific drive or SDK directory is used.

PowerShell entrypoints accept `-Help` (the installer also supports `-WhatIf`).
Dart CLI entrypoints accept `--help` or `-help`. Helpers are not entrypoints.

## Private outputs and logs

Repository-local outputs must live under `.local_private/`, `.debug_backups/`
or `.debug_snapshots/`. New work should use:

```text
.local_private/
  backups/
  sync-exports/
  database-exports/
  runtime-screenshots/
  logs/
  reports/
  sessions/
```

Existing SyncStorageRoot and `%APPDATA%/Jax` compatibility layouts are retained;
this change does not move a real baseline or backups. Explicit external output
directories must be private, dedicated to Jax, and never uploaded. Paths through
links are refused by CLI output guards. Do not write data dumps into docs/assets/test.

Normal console output omits full device IDs, local paths, database hashes and
business rows. Use PowerShell `-Verbose` or Dart `--verbose` only in a private
terminal for diagnostics. Full structured reports remain private because the
Sync coordinator and recovery tools require exact values. Do not post them in
issues. `fingerprint --machine-private` is a raw internal IPC mode, not public
logging. Fixture tests can print synthetic paths/data.

## WARNING: fixture reset

```powershell
dart run tool/create_development_fixture.dart .local_private/database-exports/demo.db
dart run tool/development_data_reset.dart .local_private/database-exports/demo.db fixture-next
# Only after reviewing the plan:
dart run tool/development_data_reset.dart .local_private/database-exports/demo.db fixture-next --apply --confirm-destructive-reset
```

Reset requires a matching `.jax-fixture.json` marker, a `fixture-` dataset
generation and the current schema. The real `%APPDATA%/Jax` directory is always
refused; there is no `--allow-real-user-data` bypass. Never manufacture a marker
for a copy of real data. The marker is an accidental-use guard, not proof of data
provenance. Keep the fixture closed while resetting it.

Without both flags, no backup or data write occurs. Apply first creates a unique
backup session beside the fixture under `.local_private/backups`, exports a
consistent SQLite copy and verifies schema/integrity/FKs. Backup failure stops
reset. Reset runs transactionally; the backup remains available on failure.

## WARNING: one-way copy

```powershell
# Replace the device placeholder deliberately; default is a plan only.
./tool/copy_windows_data_to_android.ps1 -SourceDatabase .local_private/database-exports/demo.db -Device '<device-serial>' -Package com.jarrett.jax
# Add BOTH -Apply -ConfirmOverwrite only to intentionally overwrite that target.
```

No default source, device or package. Dry-run checks device/package access but
does not stop apps, install software, push files or overwrite databases. Apply:

1. Snapshot and verify the explicit source into a unique private session.
2. Stop the selected Android app; export its database plus WAL/SHM if present.
3. Normalize and verify the target backup at the current schema. Missing target
   DB or incompatible schema stops the operation; no implicit migration.
4. Stage and replace the target; re-export and verify schema/integrity/FKs and
   exact snapshot bytes.
5. On overwrite/verification failure, restore the verified target backup and
   verify its round-trip. Rollback failure is critical and returns nonzero.

The app remains stopped after copy or rollback. Backups are retained. No automatic
build/install or `RestoreLatest` selection remains; explicit recovery is separate.

## Read-only database commands

```powershell
dart run tool/database_snapshot.dart snapshot .local_private/database-exports/demo.db .local_private/database-exports/demo-copy.db
dart run tool/database_snapshot.dart verify .local_private/database-exports/demo-copy.db
dart run tool/sync_readiness.dart .local_private/database-exports/demo-copy.db
dart run tool/world_node_migration_report.dart .local_private/database-exports/legacy-copy.db
dart run tool/read_only_database_audit.dart .local_private/database-exports/demo-copy.db .local_private/reports/audit.json
dart run tool/rollout_audit.dart .local_private/database-exports/demo-copy.db .local_private/reports/rollout.json
```

Strict snapshot/verify use `AppDatabase.schemaVersion`, not a copied version
number. `snapshot-any`/`verify-any` intentionally permit historical schemas but
still verify SQLite integrity and FKs; they are not current Sync compatibility
checks. `inspect`/`inspect-any` now produce only verification status, not private
table counts. `world_node_migration_report` inspects existing legacy mappings;
it never creates them or upgrades a database. Use a disposable consistent copy
for historical investigation; copying only the main file of a live WAL database
is not a consistent snapshot.

## WARNING: Debug Sync

```powershell
./tool/sync_phase2a.ps1 -Package com.jarrett.jax -Device '<device-serial>'
./tool/sync_phase2b2.ps1 -Package com.jarrett.jax -Device '<device-serial>' -Action Analyze
```

Analyze stops writers and creates private reports; it does not Apply business
mutations. After conflict resolution, `-Action Apply` additionally requires
`-Confirmation FIRST_REAL_DUAL_DEVICE_SYNC` and `-Resolution <private-json>`.
The app UI already confirms and supplies these arguments. Existing dry-run
compilation, stale checks, two-device backups, verification, rollback and baseline
ordering remain. Other Jax installations must be closed rather than force-killed.

Low-level Dart commands:

```text
sync_phase2a.dart export <db> <private-snapshot.json>
sync_phase2a.dart compare <windows.json> <android.json> <private-plan.json> [baseline.json]
sync_phase2b2.dart resolution-template <plan.json> <private-resolution.json>
sync_phase2b2.dart compile <plan.json> <windows.json> <android.json> <resolution.json> <private-mutation.json> [baseline.json]
sync_phase2b2.dart verify <db> <mutation.json>
sync_phase2b2.dart baseline-read <baseline.json>
```

`apply-windows <db> <mutation> <verified-backup>` requires `--apply --confirm-sync`;
`baseline-write <baseline> <mutation>` requires `--apply`. These internal commands
do not replace the coordinator's backup/rollback workflow. Invoke the coordinator
for real Sync. The database path, source fingerprint and backup fingerprint must
match before the low-level Windows writer can proceed.

## Backup retention

Only direct child sessions with all of the following are eligible:

- No link/junction in the path or session descendants; never the root itself.
- `metadata.json` owner `jax-sync-backup`, metadataVersion `1`.
- Matching directory/session ID: `yyyyMMdd_HHmmss_<32 lowercase hex>`.
- Parseable creation timestamp, positive schema/protocol versions, recognized
  terminal status.

Active and critical-rollback sessions are preserved. Legacy/unknown directories
are not counted toward deletion eligibility. Automatic cleanup after Sync Apply
uses these guards. CLI helper preview is the default:

```powershell
. ./tool/backup_retention.ps1
Invoke-JaxBackupRetention -Root .local_private/backups/sync -Keep 5 -Verbose
# -Apply is required to delete the listed eligible sessions.
```

Dart `cleanupBackups()` also defaults to preview; the UI's explicit retention
setting action passes `apply: true`. Do not manually mark unrelated folders as
Jax-owned. Existing unmarked backups are deliberately left for manual review.

## Validation

Run `flutter analyze`, `flutter test`, and the `tool/*contract_test.ps1` scripts.
New tests use temporary SQLite fixtures, injected paths, fake ADB/AAPT and
temporary retention directories. They never connect to a real device. Some
fixture logs/temporary evidence are retained locally for diagnosis.
Build with `flutter build apk --debug` and `flutter build windows --release`;
building is not permission to install on a data-bearing device.

Privacy-document cleanup, Git history rewrite, release signing, package rename,
LICENSE and final README are separate phases. Debug Sync remains developer-only.
