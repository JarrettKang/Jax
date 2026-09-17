# Jax Release Candidate

## Candidate identity

Verification dates: 2026-09-17 (baseline/native tests) and 2026-09-18 (release signing). This is a local public-source candidate, not a
published release. Phase 4 froze 161 commits at
`1c202e00d207b4f2e379523ae749f4ddb4b74362` (160 cleaned historical commits plus
one RC consolidation). Phase 5 adds one normal commit,
`Establish Jax release identity and MIT licensing`, for a total of 162 commits.
Resolve that commit with git log; its exact hash is recorded in the private final
report. No historical commit has been rewritten again.
Author and committer identity remains Jarrett <212651844+JarrettKang@users.noreply.github.com>.

Phase 5 establishes product name **Jax**, Android applicationId and namespace
**com.jarrett.jax**, and the root **MIT License, Copyright (c) 2026 Jarrett**.
The version remains **0.1.0+1**. The configurable assistantName still defaults to
**Butler**. Windows technical executable/package identifiers remain jax/jax.exe.
See [Release identity](RELEASE_IDENTITY.md) and
[Android release signing](ANDROID_RELEASE_SIGNING.md).

Release signing is configured independently of Debug, with private environment
or ignored local configuration. Missing credentials fail explicitly; there is
no Debug fallback. The normal Release APK builds successfully, passes apksigner
verification, matches the configured release key certificate and differs from
Debug. Release is not debuggable. Key-backup completion still requires owner
confirmation; successful signing is not proof of offline backup.
No remote, tag or GitHub push was created. Private audit evidence, keystores,
passwords, raw logs, databases and backups remain outside the public source tree.

## Supported platforms

The application supports Android and Windows. Local SQLite is the source of
truth; Windows uses sqflite FFI with system winsqlite3, Android uses sqflite.
These results describe local toolchains and an isolated API 36 emulator, not
physical-device or clean-machine release certification.

## Toolchain

| Item | Source / observed fact |
|---|---|
| Dart package | `jax` in pubspec.yaml |
| Android applicationId / namespace | `com.jarrett.jax` / `com.jarrett.jax` |
| Windows native window title / executable | `Jax` / `jax.exe` |
| Flutter used | 3.47.1 stable, revision 6655482ec06e547f90abf8ae7590466f4415978d |
| Flutter lower bound | pubspec.lock reports >=3.44.0; no separate Flutter constraint in pubspec.yaml; lower bound not runtime-tested |
| Dart constraint / used | ^3.13.1 / 3.13.1 |
| Android min / compile / target SDK | 24 / 36 / 36, resolved from installed FlutterExtension.kt |
| NDK | 28.2.13676358, resolved Flutter default |
| Java compile target | Java/Kotlin JVM 17 |
| JDK used | OpenJDK 25.0.2, Android Studio bundled runtime |
| AGP / Kotlin plugin declaration | 9.1.0 / 2.4.0 in settings.gradle.kts; Kotlin Android plugin is declared apply-false |
| Gradle wrapper | 9.3.1 |
| Windows CMake source minimum / used | 3.14; policy compatibility 3.14...3.25 / 3.31.6-msvc6 |
| Windows C++ | C++17 |
| Windows compiler environment | Visual Studio Community 2022 17.14.33, v143; Desktop development with C++ |
| Flutter VS discovery minimum | VS 2019 (major 16) in this SDK; only VS 2022 was tested |
| Windows SDK | 10.0.26100.0, confirmed in generated jax.vcxproj |

The Dart constraint must also be satisfied; the lockfile Flutter floor is not a
claim that Flutter 3.44.0 can build this candidate.

Flutter doctor reports unresolved Android license status. This run does not accept
licenses on the user's behalf. Local cached builds are not proof of a fully fresh
SDK/dependency installation or an offline build.

## Data Model

Schema **24**, from AppDatabase.schemaVersion. JaxDay uses local **23:00** as the
boundary; a displayed day spans the preceding calendar day's 23:00 to that day's
23:00. Default assistantName is **Butler**; the device-local preference is editable
and not part of business Sync. Timestamps are stored as UTC; display uses local time.
New-database and historical migration checks are recorded below. No migration was
added in Phase 3.

## Sync Protocol

Protocol **11**, from syncProtocolVersion. Developer ADB Debug workflow only.
Fixture tests exercise snapshot, baseline, compare, conflict, apply, rollback,
stale detection and fingerprint contracts. Fake ADB checks do not establish real
device transport reliability. **Real-device sync manual verification pending.**

## Verified Features

| Implemented capability | Code and automated evidence |
|---|---|
| Home, World, Planning, Today, Routine, Record, Settings | app.dart/page implementations; app_shell, mobile_pages, responsive_shell and page tests |
| Local-first persistence and editable assistantName | platform_database, file_app_preferences_store; persistence and app_preferences/assistant_name tests |
| Single running execution, RunSegment, pause/resume and waiting | execution_segment_service/repositories; transaction, routine_waiting and execution tests |
| Complete directly from paused/waiting | paused_completion/routine_waiting data and UI tests |
| Corrected pause/completion time | execution_segment_service; corrected_pause and completion tests |
| PlanItem to WorldNode promotion | planning promotion repository/controller; planning_promotion and sync tests |
| Focused WorldNode projected Today | projected_today data tests and UI workflows |
| Temporal routine lifecycle and cross-JaxDay occurrences | temporal_routine service, data/sync/UI tests |
| Dynamic Today and category-based Home choices | today_temporal_view/home_view_state; dynamic_today, home_category and home_work tests |

These are implementation and automated-test facts, not a claim that every page
has received physical-device subjective acceptance. Recommendations are rules
implemented in local code; no AI service is present.

## Phase 5 verification results

Fresh checks after the identity/signing changes: `flutter analyze` reported no
issues; `flutter test` completed **695 passed, 0 failed, 0 skipped**, across
129 files, with no late error events. No database schema/business behavior was
changed for Phase 5.

All seven PowerShell tool contract groups passed: android_data_transfer,
copy_safety, install_android_debug, sync_phase2a, sync_phase2b2, tool_safety and
windows_debug_acceptance. Installer cases additionally verify the new default
package and rejection of the legacy package before ADB invocation. These are
isolated fixture checks, not real-user-device Sync acceptance.

### Native verification

All executions below were rerun for Phase 5, using isolated synthetic data.
Android started on a fresh API 36 emulator with the new package absent.

| Scenario | Windows | Android API 36 emulator |
|---|---|---|
| Clean real main entry, defaults, schema and navigation | Pass | Pass |
| Native SQLite persistence contract | Not applicable | Pass with DDS |
| Today execution, Record and database restart | Pass | Pass |
| Routine management | Pass | Pass |
| Routine rapid/alternating reorder persistence | Pass | Pass |
| Compact World leaves business fingerprint unchanged | Pass | Pass |
| World focus gestures | Pass | Pass |
| Legacy category preference compatibility | Pass | Pass |

**7 Windows and 8 Android executions passed**, with zero failed/skipped cases.
No VM-service-disappearance exception occurred in these runs. That observation
does not erase the earlier intermittent harness limitation described below.
No old-package data migration, real-device uninstall, clear-data operation or
real database overwrite was performed.

The following three-layer database evidence is retained from Phase 4/4A;
the SQLite integration contract additionally passed in the Phase 5 run above.

### Three layers of database evidence

1. **Host data layer: 212 passed, 0 failed, 0 skipped**, in 47 files. Coverage
   includes database creation, migration, transactions, FK/integrity and Sync
   fixtures. This is a subset of the 695-case baseline, not an additional total.
2. **Independent Android real SQLite smoke: 3/3 consecutive passes.** An isolated
   ordinary-app entry calls the real sqflite MethodChannel and production
   AppDatabase/SqliteEventRepository, without Home/Today/Sync or integration-test
   VM orchestration. Each fresh process/database checks schema 24, foreign-key
   enforcement, integrity=ok, write/read and close/reopen persistence. Extracted
   closed synthetic databases also passed independent read-only integrity checks.
3. **Original Android SQLite contract: one complete DDS-mode pass.** The old
   case remains in the public test suite.

**Known automated test harness limitation:** earlier attempts reported
VmServiceDisappearedException during Flutter extension discovery, before SQLite
assertions, although the application remained alive. Direct VM RPC later
succeeded. Binding-only reductions also exposed a golden-stream protocol error;
DDS did not make every reduced run reliable. This is classified as Flutter
integration-test harness/protocol instability, not evidence of a Jax database
or sqflite bug. The exact underlying intermittent RPC cause is not fully closed.
The database-specific RC blocker was explicitly released based on the three
independent evidence layers; the limitation has not been hidden or called fixed.

## Phase 5 build results

| Artifact / check | Result and boundary |
|---|---|
| Android Debug APK | Pass without signing secrets; normal lib/main.dart entry restored after native tests |
| Android Release without credentials | Expected failure with explicit missing-signing-credentials message; no Debug fallback |
| Android Release with real credentials | Pass; normal entry, valid signature matching intended key and distinct from Debug; not debuggable |
| Package / label / version | com.jarrett.jax / Jax / 0.1.0+1 |
| Windows Release | Fresh x64 build passed |
| Windows metadata | ProductName/FileDescription Jax; CompanyName Jarrett; Copyright (C) 2026 Jarrett; jax.exe; 0.1.0+1 |

The earlier Phase 4 APK used the old package and Debug signing; it is not a
Phase 5 Release artifact. The Phase 5 Release certificate was verified against both the intended
private key and Debug certificate. This is a locally release-signed APK, not a
Play Store submission or real-device Release-runtime acceptance claim.
Local installed SDKs and dependency caches were used; clean-machine setup
remains outside this phase.

## Privacy and Git boundary

One combined selective history cleanup removed private recovery evidence and
sanitized known private environment/device values while retaining 160 commits,
messages, dates and topology, and applying the confirmed author identity.
The consolidation adds current approved RC work without squashing that history.
Privacy rules and cleaned historical object IDs remained frozen throughout final
verification. Known sensitive values and private database fingerprints were
checked against reachable history and the staged tree before committing; the
full post-commit scan and Git integrity/ref checks are recorded in the final
verification report. Private mappings and logs are not part of this tree.

Ignore rules and safety tools may mention generic private-output directories or
synthetic fixtures. Such policy references do not include those directories or
private evidence in Git. They are distinguished from sensitive-value hits.

## Phase 6 reproducibility and branding

Phase 6 adds one normal commit, `Document reproducible builds and replace template branding`,
for 163 total commits while preserving the exact 162-commit Phase 5 history.
The clean checkout passed analyze, the 695-case host baseline, all eight Android
and seven Windows native cases, and seven PowerShell tool contract groups.
Android Debug built without secrets; missing-secret Release rejected explicitly.
A separate clean candidate Release build retained the Phase 5 signing certificate.

See [Building Jax](BUILDING.md) for canonical prerequisites and commands, and
[Reproducibility evidence](REPRODUCIBILITY.md) for the clean checkout method,
current checks, network recovery and limitations. Original MIT-licensed Jax
launcher assets replace the Android/Windows Flutter templates; framework and
third-party attribution remain intact. Phase5 facts above are historical results;
Phase6 results are recorded separately and do not imply a fresh Windows VM.

## Remaining release work

- Confirm offline key backup with its owner; a checklist alone is not backup evidence.
- Original Jax placeholder icons now replace template launcher assets; final brand design is a separate decision.
- Complete distribution-level dependency/license review; see THIRD_PARTY_NOTICES.md.
- Rewrite README and reconcile stale public architecture/data-model links.
- Prepare synthetic-data screenshots and CI; no publishing has happened.
- Verify clean-machine setup, packaging/installer and scoped manual acceptance.
- Keep real-device Sync validation and subjective UI acceptance distinct from
  automated emulator/fixture evidence.

These are publication/distribution gates, not unresolved failures in the verified
RC database layer. Do not describe this local candidate as a production-signed
release, a Play Store submission or a public GitHub release.

## Manual acceptance and product limits

Preserve DESIGN.md's mixed validation status: earlier Android Home/World/Planning
acceptance does not imply universal sign-off for Today, Routine, Record, Settings,
Windows polish or later compact-density work. No new user acceptance was inferred.

No cloud/LAN/background sync or AI recommendation service is implemented. The
SQLite database is not encrypted by this application. Developer Sync remains a
Debug/ADB tool, not a consumer sync service. Dark theme, installer, public CI and
final release documentation remain outside this verification. Future features
require separate scope.
