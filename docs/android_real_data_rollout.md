# Android Debug rollout: NO_AUTO_UNINSTALL_REAL_DATA

This is a hard rule for every device containing real Jax data. Never uninstall
or clear app data as an installation failure fallback. On failure, stop and
report the exact error. A separate explicit user authorization saying
“允许卸载并清除 App Data” is required for any destructive uninstall. Permission
to install/update, retry installation, or test is not permission to uninstall.

Do not run `flutter run`, `flutter install`, or a Flutter device-test runner
against the real-data package: their installation recovery may uninstall it.
Build separately, then use `tool/install_android_debug.ps1`. It validates the
APK package, Debug flag, device and existing real-data package; performs exactly
one `adb install -r`; and has no retry/uninstall/clear path. Do not bypass a
rejection by trying Flutter's installer. Never reset a database or baseline to
make installation or verification pass.

Before updates: force-stop, check there is no process, inspect SQLite sidecars,
and export a current frozen snapshot. If WAL contains pending data, preserve a
consistent SQLite snapshot instead of copying only the main file. Verify SHA-256,
integrity, foreign keys, schema, generation and business fingerprint. Preserve
the Windows database and Last Successful Sync Baseline hashes. After updating,
check a no-op launch and compare the database before any business interaction.

Example (supply the installed SDK tool paths and exact device serial):

```powershell
flutter build apk --debug
.\tool\install_android_debug.ps1 -Device <device-serial> `
  -ApkPath build\app\outputs\flutter-apk\app-debug.apk `
  -AdbPath <toolchain-path> `
  -AaptPath <toolchain-path>
```

## Isolated World gesture QA

Build with `flutter build apk --debug --target=tool/world_attention_fixture.dart`.
Gradle derives isolation from the fixture entry point. This produces Debug package
`com.example.jax.worldfixture`, displayed as **Jax World QA**. Use the guarded
installer with `-Package com.example.jax.worldfixture`. The fixture creates its
own temporary SQLite database in that separate package's sandbox. Never install
a fixture entry point into `com.example.jax`. A normal `flutter build apk --debug`
builds the ordinary main-entry APK. Fixture release builds are rejected.

Safety regression: `powershell -File tool/install_android_debug_contract_test.ps1`.
Read-only snapshot audit (does not call AppDatabase migrations):
`dart run tool/read_only_database_audit.dart <export.db> <new-report.json>`.
Restoration is a separately authorized operation; do not automatically restore,
merge, Sync Apply, change generation, or recreate a baseline.
