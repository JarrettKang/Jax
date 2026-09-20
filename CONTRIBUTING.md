# Contributing

Jax is an early Windows/Android project. Issues and focused pull requests are
welcome; there is no support SLA. Describe the problem and intended behavior before
proposing large changes.

1. Follow [BUILDING](docs/BUILDING.md), using Flutter 3.47.1 and bundled Dart.
2. On Windows run `flutter pub get`, `flutter analyze` and `flutter test`.
3. Build affected platforms; use native integration checks when runtime behavior changes.
4. Run relevant PowerShell 7 tool contracts for developer-tool changes.

Keep PRs small. Explain what changed, why, tests performed and data/migration impact.
Schema changes require migration/invariant tests; Sync changes require compatibility
and conflict/apply/rollback tests. Do not silently revise stored data semantics.

Use invented data only in fixtures, screenshots and issue attachments. Never include
real databases, user tasks, contacts, raw private logs, device serials, private paths,
keystores, signing properties, passwords or tokens. Review diffs before committing.
[Demo instructions](docs/SCREENSHOTS.md) provide reproducible synthetic data.

Destructive tools must preserve explicit targets, default preview/no-overwrite,
confirmation boundaries, verified backups and rollback. No automatic uninstall,
app-data clearing or destructive retry. Read [TOOLS](docs/TOOLS.md).

Contributions are provided under the project's [MIT License](LICENSE). Identify
third-party material and its license. Describe substantial AI assistance honestly;
contributors remain responsible for reviewing changes and verifying results.
