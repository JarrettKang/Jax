# Android data safety

## Failure mode and root cause

An installation failure can lead a development runner to uninstall an existing
package before retrying. Uninstalling removes the package data directory. A
request to install or test does not authorize that fallback.

## Safe install invariant

Build the APK separately. Validate its package name, Debug flag, explicit target
device and existing package before invoking the guarded installer. Perform
exactly one `adb install -r`. If it fails, stop and report the error. Never
automatically uninstall, clear data, retry through another installer, reset the
database or recreate a synchronization baseline.

## Isolate test devices and data

Run integration tests on an emulator or an explicitly isolated fixture package
and database. Keep ordinary `com.jarrett.jax` separate from fixture entry points.
Never install a fixture build over a package containing personal data. Use
synthetic fixtures and fake ADB tools to verify failure paths.

## Backup, integrity and rollback

Before an authorized update or import, stop the app and verify process state.
Preserve a consistent SQLite snapshot, including pending WAL data where present;
copying only the main database file is insufficient when WAL contains changes.
Preserve settings and synchronization baseline separately. Verify readability,
SHA-256, schema, SQLite integrity, foreign keys and business invariants. Keep
private backups outside the source repository.

After an authorized operation, verify the resulting snapshot before business
interaction. Distinguish migration changes, ordinary startup initialization and
user actions; do not describe all three as a zero-difference no-op. Rollback or
restore needs a verified backup and explicit authorization. Verify the restored
result; do not erase evidence to make a check pass.

This note preserves engineering safeguards, not a personal recovery timeline.
