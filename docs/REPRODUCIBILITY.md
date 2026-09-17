# Reproducibility evidence

Phase 6 verification date: 2026-09-18. Scope is **clean checkout / isolated
environment verification**, not a completely fresh machine, clean Windows VM,
offline or hermetic build, or byte-identical APK reproduction.

## Method

Started from the 162-commit Phase 5 freeze
15deaeff493f28570b87ddc72a07e7c0ad75423e. Each Git-tracked file was exported by
object identity into an independent directory. Only reviewed Phase 6 public icon
source/resources were overlaid before compilation. A private file/hash manifest
records the inputs, later compared with the final committed build inputs.

No build/, .dart_tool/, .gradle/, .local_private/, Android Studio settings,
local.properties, key.properties, keystore, logs or editor cache was copied.
PUB_CACHE and GRADLE_USER_HOME were initially empty; APPDATA, LOCALAPPDATA and
temporary data were isolated. Release-signing and author-specific tool override
environment variables were removed. The public pub.dev and Flutter storage
endpoints were selected explicitly. No private dependency mirror was used.

Installed Flutter/engine artifacts, Android SDK/NDK, JDK and Visual Studio were
reused as declared prerequisites. These SDK installations, machine OS settings,
compiler/runtime installations and host network/proxy configuration were not
rebuilt in a fresh VM. No claim is made that every SDK-level cache was absent.
See [Building Jax](BUILDING.md) for versions, requirements and commands.

## Commands and results

| Check | Result |
|---|---|
| flutter clean | Pass in the independent tracked-only checkout |
| flutter pub get | Pass from empty PUB_CACHE via pub.dev; no private mirror |
| flutter analyze | Pass, no issues |
| flutter test | 695 passed, 0 failed, 0 skipped; no error events |
| Android normal Debug without release configuration | Pass; normal lib/main.dart entry restored after native tests |
| Android Release without release configuration | Pass: explicit missing-credentials rejection, no Release artifact or Debug fallback |
| Android signed Release in the candidate | Pass after flutter clean; same certificate as Phase 5, distinct from Debug, verified install/launch |
| Windows Release in clean checkout | Pass; full bundle generated from public inputs |
| Windows Release launch | Pass with isolated synthetic data; title Jax; schema 24/integrity/FK checks passed |
| Windows native matrix | 7/7 passed |
| Android native matrix | 8/8 final passes; harness attempts described below |
| PowerShell tool contracts | 7/7 passed with PowerShell 7 |

The original J icon was visually confirmed in the installed Android launcher
and in the Windows executable resource. The signed Release opened the real main
entry with default Butler and empty synthetic data. Private inspection captures
were not prepared as public marketing screenshots.

The Windows bundle contains jax.exe, flutter_windows.dll, data/icudtl.dat and
flutter_assets plus any generated libraries. Native executable metadata and the
embedded J icon were inspected; launching verified startup dependencies on the
tested host. This does not replace a fresh end-user runtime/installer check.

## Network and shell observations

The first Gradle distribution download made slow progress and was interrupted
for diagnosis. A direct wrapper diagnostic also exceeded its 240-second observation
limit. The same gradle-9.3.1-all.zip was then freshly downloaded from the official
services.gradle.org endpoint using host-standard proxy discovery and verified
against the official SHA-256 before placement in the new wrapper cache. Wrapper
bootstrap succeeded. No author cache or private mirror was used. This is a
recorded manual network recovery, not evidence of a fully unattended first build
under arbitrary proxy configurations.

An initial tool-contract run under Windows PowerShell 5.1 failed two groups;
PowerShell 7, used by the existing tool verification baseline, passed all seven.
The guide now names the tested shell. No product/Sync semantics were changed to
make those tests pass.

## Native harness observation

The first Android Today/Record attempt waited after installation without entering
the test body. The app stayed alive, advertised its VM service and showed no
Android fatal exception. It was interrupted for a bounded retry; the same case
then passed all assertions. The interrupted attempt is retained in private
evidence. The World attention gesture case also had two DDS-startup failures
before assertions; a subsequent verbose diagnostic run completed all its
assertions successfully. Its final pass is taken from that actual run, not from
a previous-phase baseline. No production or test source was changed. These
observations are consistent with the
previously recorded Flutter harness limitations, not proof of a shared root cause
or evidence that the intermittent issue is fixed.

## Branding and boundaries

Original MIT-licensed assets/branding/jax_icon.svg replaces the Flutter launcher
assets for Android and Windows. The generator and committed outputs are public;
normal builds do not require the generator. Android includes legacy/round,
adaptive and monochrome resources; the legacy splash is pure color. Historical
Flutter icons remain in unchanged Git history, not in current launcher resources.
Required Flutter/dependency license notices and generated framework identifiers
remain; they are not Jax-facing template branding.

No business logic, schema 24, Sync protocol 11, applicationId, license, signing key,
assistant default or UI structure changed. Physical-device Sync, final subjective
UI acceptance, offline key-backup confirmation, final README, public screenshots,
CI, fresh-machine installation and GitHub publication remain outside this phase.
