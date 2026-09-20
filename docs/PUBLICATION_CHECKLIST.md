# Publication checklist

Phase 7 prepares a **source-only** initial publication. It does not authorize
creating a repository, adding a remote, pushing, tagging or publishing binaries.
Baseline: 163 commits at `f79cbcf3a88bf72cf2db449724330893522398e4`.
Normal Phase 7 commits preserve this entire history. Final commit identity/count
are recorded by the accompanying local completion report; do not rewrite history
just to embed a document's own commit hash.

## Identity — PASS

Jax; Android applicationId/namespace `com.jarrett.jax`; version **0.1.0+1**;
Windows product Jax / executable jax.exe. Author and committer:
Jarrett <212651844+JarrettKang@users.noreply.github.com>.
Schema **24**, Sync protocol **11**, assistantName default **Butler** remain unchanged.

## License — PASS

Root MIT License, Copyright 2026 Jarrett. Original J icon and synthetic screenshots
are project assets. No downloaded illustration/logo or outside screenshot was added.

## Privacy — PASS

All public files, all Git objects (including reachable history), the synthetic
fixture, image bytes/metadata and new CI/docs are scanned before and after commit.
Known sensitive literals, device identifiers, signing passwords/private paths and
private signing-file hashes produced **zero hits**. New material also receives token,
personal-email and private-path pattern checks. Only the confirmed noreply identity
is allowed. No real database or binary fixture is committed.

## Build — PASS

Normal `lib/main.dart` Android Debug and Windows Release builds passed in Phase 7.
The screenshot-only executable was replaced by a successful normal Windows build.
Full build instructions: [BUILDING](BUILDING.md). Phase 6 clean-checkout evidence:
[REPRODUCIBILITY](REPRODUCIBILITY.md).

## Test — PASS

`flutter analyze`, full `flutter test`, new demo safety tests and all seven
PowerShell 7 tool-contract groups passed. Phase 7: **698 passed, 0 failed, 0 skipped**,
including three added demo safety tests; analyze reported no issues; tool contracts **7/7**.
Four additional CLI scenarios verified missing-path/escape refusal, successful new
fixture creation and rejection of an existing fixture with its hash unchanged. The Phase 6 baseline is 695 host tests,
Android native 8/8 and Windows native 7/7. Product code/native inputs are unchanged
in Phase 7, so the entire native matrix is not repeated. The added Windows capture
entry is built and run against a fresh synthetic DB as its affected runtime check.
Counts are verification observations, not coverage percentages.

## Docs — PASS

English [README](../README.md), current [ARCHITECTURE](ARCHITECTURE.md),
[DATA_MODEL](DATA_MODEL.md), canonical build/signing guides, tool safety,
[CONTRIBUTING](../CONTRIBUTING.md), [SECURITY](../SECURITY.md) and
[first public release draft](FIRST_PUBLIC_RELEASE.md) are prepared. DESIGN retains
its mixed manual-acceptance status; the old RC report is marked historical.
All 51 relative links in the prepared/updated documents resolved before commit.

## Screenshots — PASS

Four actual Windows JaxApp views: [Home](images/home.png),
[Planning](images/planning.png), [Today](images/today.png), [Record](images/record.png).
All use newly generated fictional data and a fixed 2030 demo clock. Visual review
found no personal data, paths, serials, accounts, notifications, developer overlays,
Debug banner or Flutter branding. PNGs have no text metadata. No private database
was read. [Reproduction and safe tooling](SCREENSHOTS.md).

## CI — PASS configuration / PENDING hosted run

[ci.yml](../.github/workflows/ci.yml) runs on push and pull_request, one
`windows-2022` job, pinned Flutter 3.47.1/bundled Dart, JDK 25, analysis, full host
tests, Windows Release and Android Debug smoke builds. Permissions are only
`contents: read`; checkout does not persist credentials. Zero signing secrets,
private tokens, Release signing, deployment or artifact publication steps.

Windows is deliberate: the project's SQLite hook loads winsqlite3. Ubuntu host
commands are not claimed tested or configured. Native emulator matrices are not CI.
YAML parsing, expected commands, permissions and exact action commit pins are
locally checked; actions were resolved from their official repositories:
[checkout](https://github.com/actions/checkout),
[setup-java](https://github.com/actions/setup-java),
[flutter-action](https://github.com/subosito/flutter-action).
The [Windows 2022 runner inventory](https://github.com/actions/runner-images/blob/main/images/windows/Windows2022-Readme.md)
was reviewed for VS 2022, Android SDK 36 and NDK 28.2.13676358. Hosted images can
change; a real first GitHub run remains pending. No green badge is asserted.

## Signing — PASS existing verification / PENDING owner backup confirmation

Phase 5/6 verified Release signing, a certificate distinct from Debug, and explicit
failure without Release credentials. No signing identity/configuration changed.
No passwords, key.properties contents, private keystore paths or fingerprints are
published. Signing remains local. Owner confirmation of offline key backup remains
separate; it does not block source-only publication. No unsigned/Debug APK is
proposed as a public Release asset.

## Repo metadata — PASS prepared / PENDING owner approval

- Proposed owner/name: **JarrettKang/Jax** (owner authentication/availability unverified).
- Visibility: **Public**, subject to explicit final confirmation.
- Default branch: keep **master**; no rename is needed.
- Description: **Local-first planning, execution, and life-management app for Windows and Android.**
- Topics: `flutter`, `dart`, `sqlite`, `productivity`, `personal-management`, `windows`, `android`, `local-first`.
- Version: retain **0.1.0+1**; no v1.0 claim or version blocker.
- First publication: source only; no tag, Release, APK or installer.

## Known limitations — PASS disclosed

Experimental developer ADB Sync only; no cloud/LAN/background automatic sync,
collaboration or dark mode. SQLite is not encrypted at rest by Jax. Current UI
is Chinese. Store/installer distribution is not established. Known Android test
harness instability is documented separately from successful SQLite/native checks.
None of these disclosed limitations is a source-publication blocker.

## Final publish steps — PENDING explicit user confirmation

No remote, push, tag, GitHub repository or Release was created in Phase 7.
After the owner confirms **account, Jax, Public and master**, run the following
from this audited candidate only, stopping after any failed command. Confirm a
clean working tree and the reported final HEAD before executing.

```powershell
git status --short
git rev-parse HEAD
gh auth status
gh repo create JarrettKang/Jax --public --description "Local-first planning, execution, and life-management app for Windows and Android."
git remote add origin https://github.com/JarrettKang/Jax.git
git push -u origin master
gh repo edit JarrettKang/Jax --default-branch master --add-topic flutter,dart,sqlite,productivity,personal-management,windows,android,local-first
```

These are **prepared commands, not executed commands**. Do not initialize GitHub
with another README/license/commit. Do not use `--mirror`, `--all`, `--tags` or a
force push. If the proposed repository already exists or any identity differs,
stop and inspect instead of overwriting it.

After the first push, inspect the hosted CI run and enable GitHub private
vulnerability reporting in repository settings. Verify the Security reporting UI
before claiming it is available. Check rendered README/image links and metadata.
No tag or GitHub Release is included in these steps.
Command references: [gh repo create](https://cli.github.com/manual/gh_repo_create),
[gh repo edit](https://cli.github.com/manual/gh_repo_edit).

## Readiness — READY TO PUBLISH (source only)

All required local gates passed; no publication blocker remains within this scope.
No product feature, schema, Sync protocol, package identity, signing identity or
historical commit was changed. Publication itself stays pending owner approval.
The hosted CI run and enabling private vulnerability reporting necessarily remain
post-publication checks, not claims of work already performed.
