# Initial public source release

The source of **Jax 0.1.0+1** is public at [JarrettKang/Jax](https://github.com/JarrettKang/Jax).
This publication does not create a GitHub Release, tag or v1.0 stability claim.

Jax is a local-first personal planning, execution and life-management app for
Windows and Android. World structures long-term intentions; Planning turns them
into rounds and steps; Today and Home support current attention; execution segments
and Record support review and adjustment. The current UI is Chinese.

Implemented capabilities include World hierarchy, PlanItem execution/promotion,
dynamic Today, temporal scheduled/on-demand Routines, pause/wait/resume, corrections,
review notes and configurable assistantName (default Butler). SQLite is local and
is not encrypted at rest by Jax.

The Phase 6 candidate passed 695 Flutter tests, Android native verification 8/8,
Windows native verification 7/7 and tool contracts 7/7. These counts describe that
candidate, not coverage. [Publication checklist](PUBLICATION_CHECKLIST.md) records
Phase 7 and Phase 8 results; the public checkout passed 698 host tests. Android
harness instability was observed; independent SQLite smoke and subsequent native
verification passed. This is not a diagnosed database defect.

Windows Release and Android Debug builds are verified from public inputs; local
Android Release signing was separately verified, with no Debug fallback. See
[BUILDING](BUILDING.md) and [REPRODUCIBILITY](REPRODUCIBILITY.md). No prebuilt installer,
APK download or store distribution is promised by this source publication. A future
Release APK must use proper Release signing; Debug APKs are not release assets.

ADB Sync is an experimental developer workflow with snapshot/baseline/compare,
conflict detection, explicit apply and rollback. No cloud, LAN or automatic
background sync, collaboration or dark mode is implemented. The first
[successful public CI run](https://github.com/JarrettKang/Jax/actions/runs/35491066377)
passed analysis, host tests, Windows Release and Android Debug builds after a
runner temporary-path configuration fix. Product code and tests were unchanged.

Jarrett leads product direction, requirements, architecture, validation and
maintenance. OpenAI Codex is used extensively as an AI-assisted development tool
for implementation, testing, refactoring and release preparation.

Code and original project assets are under the [MIT License](../LICENSE).
