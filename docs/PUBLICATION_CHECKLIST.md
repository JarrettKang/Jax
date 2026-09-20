# Publication checklist

Phase 8 source-only publication was verified on 2026-09-20 at
[JarrettKang/Jax](https://github.com/JarrettKang/Jax).
Phase 7's audited starting point was `08add6feaf6e6bdafa664a6f767b27c88c4c4e2e`
with 164 commits and 424 tracked public files. Its complete history is preserved.

## Repository publication — PASS

- Repository created empty as **Public**; no extra initialization commit.
- Canonical owner: **JarrettKang**; display/commit name: **Jarrett**.
- Remote: **origin**; default branch: **master**.
- Only master was pushed. No mirror, all-refs, force or tag push was used.
- Initial remote HEAD matched the audited Phase 7 HEAD exactly.
- A separate clone fetched public master with no tags; its initial 164 commits
  and all 3,119 reachable objects matched the candidate exactly.
- The local Phase 7 all-object scan contained 3,124 objects; the five additional
  local objects were not part of the published reachable history.
- All initial remote commits associated with the **JarrettKang** GitHub profile.
  Author and committer remain Jarrett <212651844+JarrettKang@users.noreply.github.com>.
- Remote refs contain only master; verification-clone refs add only origin/master.
  No codex, backup, replace or tag refs were published.

## CI — PASS actual hosted verification

GitHub Actions first successful public run: **PASS**.

[Run 35491066377](https://github.com/JarrettKang/Jax/actions/runs/35491066377)
verified `fbbcec5adc7a0f908c8af5756298bc8f9c9c7e3e` on `windows-2022`.
The single **verify** job passed dependency resolution, `flutter analyze`, the
full host test suite, Windows Release and Android Debug smoke builds.
Flutter is pinned to 3.47.1 with bundled Dart; JDK is 25. Action revisions remain pinned.

The original [run 35490467889](https://github.com/JarrettKang/Jax/actions/runs/35490467889)
failed four tests because the runner's short temporary-directory alias differed
from resolved long paths, so existing safety checks refused the fixtures.
CI now sets TEMP and TMP to `runner.temp` at the host-test step.
The first configuration attempt placed this at job scope and was rejected before
any job ran ([run 35490927176](https://github.com/JarrettKang/Jax/actions/runs/35490927176));
the follow-up moved it to supported step scope. Both are normal commits.
No product code, test, safety guard, schema or protocol was changed or bypassed.

Permissions remain **contents: read**, with checkout **persist-credentials: false**.
No private signing material, PAT, Release signing, deployment, artifact upload,
tag creation or GitHub Release step is present.

## Remote privacy and secrets — PASS

The independent public checkout was scanned: **424 tracked public files** and
**3,119 Git objects**, including the complete reachable initial history.
Known sensitive values, device identifiers, private email/path literals,
signing secrets and private signing-file hashes had **zero hits**.
Token/private-path/email checks on the prepared material also had zero hits.
No key.properties, keystore, private database, private backup or raw private log
was published. Git fsck passed. Scan rules and detailed logs remain private.

## Fresh public checkout builds and tests — PASS

A separate checkout obtained from GitHub passed:

- `flutter pub get`
- `flutter analyze`: no issues
- `flutter test`: **698 passed, 0 failed, 0 skipped, 0 error events**
- `flutter build apk --debug`, without private signing credentials
- `flutter build windows --release`

These local fresh-checkout results supplement the actual hosted CI above.
Phase 6 native verification remains Android **8/8**, Windows **7/7**, and tool
contracts **7/7**; Phase 7 also verified tool contracts **7/7**. Native integration
matrices were not rerun in Phase 8 because product/native inputs did not change.
Known Android integration-test harness instability remains a separate historical
observation, not a diagnosed database defect or a claim of hosted native coverage.

## README, screenshots and community files — PASS

GitHub renders the README title, tables, code block, documentation and license
links. All README document/image links returned HTTP 200 at verification.
The four public PNGs returned HTTP 200 and matched the audited image hashes.
Browser screenshots confirmed README/image rendering; full-size clone images were
also visually inspected. No real user data, private path, Debug banner or Flutter
branding was present. There is no preconfigured CI badge to misrepresent status.

Screenshots are actual Windows JaxApp views with synthetic data and a fixed 2030
demo clock. See [SCREENSHOTS](SCREENSHOTS.md). No user database was accessed.
GitHub recognizes the MIT license and security policy. Private vulnerability
reporting is enabled and the Security pages expose the reporting entry.
Issues are enabled. The PR template is recognized; no issue template was prepared.

## Metadata and identity — PASS

- Description: **Local-first planning, execution, and life-management app for Windows and Android.**
- Topics: `flutter`, `dart`, `sqlite`, `productivity`, `personal-management`, `windows`, `android`, `local-first`.
- Website field: empty. No unprepared social preview was uploaded.
- License: MIT, Copyright 2026 Jarrett.
- Version: **0.1.0+1**; Android identity **com.jarrett.jax**; Windows **jax.exe**.
- Schema **24**, Sync protocol **11**, configurable assistantName default **Butler**.
- Jarrett directs and maintains the project; OpenAI Codex is disclosed as an
  extensively used AI-assisted development tool.

## Retained limitations and release boundary

This is an initial public **source-only** release in active development.
No APK, Windows binary, installer, tag or GitHub Release has been published.
Build from source; store distribution and a stable release series are not promised.
The UI is Chinese. Sync remains an experimental developer-oriented Windows/Android
ADB workflow. There is no cloud/LAN/background automatic sync, collaboration or
dark mode. Jax does not encrypt SQLite contents at rest.

Existing Android Release signing was verified in Phases 5/6, with a certificate
distinct from Debug and explicit failure without credentials. Signing materials
remain private. Owner confirmation of offline key backup is still separate and
non-blocking for source publication. Private source, audit backups and keys are retained.

See [BUILDING](BUILDING.md), [REPRODUCIBILITY](REPRODUCIBILITY.md),
[SECURITY](../SECURITY.md) and [initial public source notes](FIRST_PUBLIC_RELEASE.md).
