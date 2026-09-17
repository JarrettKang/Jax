# Jax Release Candidate

## Candidate identity

Verification date: 2026-09-17. This is a local public-source candidate, not a
published release. The candidate consists of **160 cleaned historical commits
plus one RC consolidation commit: 161 commits**. The historical base is
`cab33a7d1d1f604aea9aa002b4ceb91c811bc031`; no historical commit was rewritten again.
Author and committer are Jarrett <212651844+JarrettKang@users.noreply.github.com>.

Final candidate reference: **HEAD, the commit adding this document update**, with
subject `Prepare release candidate for public source`. Resolve its exact object
ID using `git rev-parse HEAD` at this freeze, or locate that subject after later
work. A commit cannot embed its own final hash; the exact hash and post-commit
scan results are recorded in the separate final verification report, avoiding
another documentation-only commit or an amend cycle.

The approved public tree contains **389 files**. Product source, platform files,
unit/widget tests, approved native tests, Phase 2 safety tooling, selected public
documents and ignore rules are included. Private audit material, replacement/blob
maps, old-to-new commit maps, raw logs, databases, backups and runtime screenshots
are excluded. Two temporary Phase 4A diagnostic entrypoints remain in private
verification evidence rather than extending the frozen public Include List.

The existing package version remains `0.1.0+1`; package identity, license,
production signing and publication are later decisions. No remote, tag or GitHub
push was created.

## Supported platforms

The application supports Android and Windows. Local SQLite is the source of
truth; Windows uses sqflite FFI with system winsqlite3, Android uses sqflite.
These results describe local toolchains and an isolated API 36 emulator, not
physical-device or clean-machine release certification.

## Toolchain

| Item | Source / observed fact |
|---|---|
| Dart package | `jax` in pubspec.yaml |
| Android applicationId / namespace | `com.example.jax` / `com.example.jax` |
| Windows native window title / executable | `jax` / `jax.exe` |
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

## Final verification results

The final candidate source was freshly checked with `flutter analyze` and
`flutter test`: **No issues found; 695 passed, 0 failed, 0 skipped**, across
129 test files. The count is unchanged; native visibility fixes and host async completion
synchronization update existing tests without adding cases. Parameterized tests account for the
difference between source declarations and executed cases.

Seven PowerShell tool contract groups passed: android_data_transfer, copy_safety,
install_android_debug, sync_phase2a, sync_phase2b2, tool_safety and
windows_debug_acceptance. These use isolated fake/fixture dependencies; they do
not establish real-user-device Sync acceptance.

### Native verification

| Scenario | Windows | Android API 36 emulator |
|---|---|---|
| Clean real main entry, defaults, schema and navigation | Pass, retained baseline | Pass, retained baseline |
| Native SQLite persistence contract | Not applicable | Pass once with DDS, Phase 4A |
| Today execution, Record and database restart | Pass, rerun after visibility fix | Pass, final run |
| Routine management | Pass, rerun after final visibility fix | Pass, final run |
| Routine rapid/alternating reorder persistence | Pass, retained baseline | Pass, final run |
| Compact World leaves business fingerprint unchanged | Pass, retained baseline | Pass, final run |
| World focus gestures | Pass, retained baseline | Pass, final run |
| Legacy category preference compatibility | Pass, retained baseline | Pass, final run |

Final evidence covers **7 Windows and 8 Android platform executions**, with
0 unresolved case failures and 0 skipped cases. This combines unchanged-code
baseline evidence with the explicitly identified reruns; it is not a claim that
all 15 executions occurred in this final invocation.

The first Android Today/Record and Routine management attempts missed controls
outside the visible scrolling viewport or behind bottom navigation. Test-only
fixes scroll controls into view and assert hit-testability before tapping. After
scrolling to reactivate a routine, the test also scrolls back to the lazily built
creation control. All business-state, database, duration, restart and integrity
assertions remain; no product UI or database code was changed. The affected
Windows tests were rerun. Initial failures remain in private verification records.

The first final host run emitted 695 success events but subsequently failed on
a PlanningController notification after the test disposed the app. It is not
counted as a pass. The affected home-category navigation test used a fixed delay
for native database work; it now waits for both controllers to finish loading
before teardown and checks for framework exceptions. The affected file and the
complete final suite were rerun. This test-only synchronization does not claim
to prove production cancellation semantics for disposal during a pending load.

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

## Build results

The final Android build sequence was `flutter clean`, `flutter pub get`,
`flutter analyze`, `flutter build apk --debug`, then `flutter build apk --release`.
Both APKs were generated from the normal **lib/main.dart** entry, replacing the
previous diagnostic/test APK. A fresh final analyze and full test followed.

| Artifact / check | Result and boundary |
|---|---|
| Android Debug APK | Pass, clean normal-entry build |
| Android Release APK | Pass; **uses Debug signing**, not production signed or Play Store ready |
| Package / version | com.example.jax; 0.1.0+1, unchanged |
| Windows native verification | Seven-case baseline passed; both changed test paths rerun successfully |
| Windows Release | Prior Phase 4 x64 build and complete bundle verification retained; product and Windows platform code unchanged |
| Windows fresh-data startup | Retained isolated Release launch survived startup, created schema24, integrity=ok, FK violations=0 |

The Windows Release process was explicitly stopped after inspection; this is not
proof of graceful release shutdown. Its complete verified bundle was retained
privately before the final clean. Tests that changed only test helpers do not
invalidate the unchanged production Release binary. No final Android Release
runtime or physical-device claim is made. Local installed SDKs and dependency
caches were used; a fresh Windows VM/dependency installation remains unverified.

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

## Remaining release work (Phase 5)

- Decide LICENSE, final package identity/version and production signing.
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
