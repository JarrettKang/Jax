# Building Jax

This is the canonical developer build guide for the Android and Windows source.
Product name is Jax; Android identity is com.jarrett.jax. The assistant name is
user-configurable and defaults to Butler. Version remains 0.1.0+1.

## Requirements

Use the checked-in pubspec.lock and Gradle wrapper version. Do not upgrade the
toolchain or dependencies merely to reproduce the recorded build.

| Component | Declaration / prerequisite | Tested configuration |
|---|---|---|
| Host | Windows for the Windows target and the recorded full test workflow | Windows x64 |
| Flutter | SDK on PATH; compatible bundled Dart required | 3.47.1 stable |
| Dart | ^3.13.1 (>=3.13.1 <4.0.0); use Flutter's bundled SDK | 3.13.1 |
| Android SDK | Platform 36, Build Tools 36.0.0, platform-tools; command-line tools for SDK/license management | API 36 |
| Android min/compile/target | Flutter defaults in this SDK | 24 / 36 / 36 |
| Android NDK | Resolved Flutter default | 28.2.13676358 |
| JDK runtime | AGP requires at least17; choose a version compatible with the wrapper | OpenJDK 25.0.2 |
| JVM compilation target | Java/Kotlin 17 | 17 |
| Gradle | Wrapper 9.3.1 | 9.3.1 |
| AGP / Kotlin declaration | 9.1.0 / 2.4.0 | unchanged checked-in declarations |
| Visual Studio | Desktop development with C++, MSVC v143, C++ CMake tools, Windows SDK | VS 2022 17.14.33 |
| CMake | CMakeLists declares >=3.14; generator/toolchain can impose a higher floor | 3.31.6-msvc6 from VS |
| Windows SDK | Install via Visual Studio | 10.0.26100.0 |

JDK 25 is **tested**, not a unique project requirement. JDK 17 is the upstream
minimum, not a claim that Jax has been tested on every JDK 17+ release. Check the
[AGP compatibility table](https://developer.android.com/build/releases/agp-9-1-0-release-notes)
and [Gradle Java matrix](https://docs.gradle.org/current/userguide/compatibility.html)
when selecting another JDK. Compilation target17 and the JVM running Gradle are
separate settings. Flutter may prefer Android Studio's bundled JDK; verify its
selection with flutter doctor -v. An explicit flutter config --jdk-dir setting
is a local developer choice, never a tracked machine path.

The lockfile's Flutter >=3.44.0 floor is not independently established as Jax's
minimum: the bundled Dart must also satisfy ^3.13.1. The verified combination is
Flutter 3.47.1/Dart 3.13.1; no broader Flutter support matrix is claimed.

For Windows, VS Code alone is insufficient. Install the
[Visual Studio C++ workload](https://docs.flutter.dev/platform-integration/windows/setup).
The verified build uses the Visual Studio CMake generator; a separate Ninja
installation is not a Jax prerequisite. Enable Windows Developer Mode if Flutter
reports that plugin symlinks are unavailable. A fresh end-user machine may also
need the matching Microsoft Visual C++ runtime; see Flutter's Windows deployment
guidance before distributing a bundle.

## Flutter setup

```powershell
git clone <repository-url> <project-root>
cd <project-root>
flutter --version
flutter doctor -v
flutter pub get
```

Install Flutter and add <flutter-sdk>/bin to PATH. Android Studio is convenient
for SDK installation, but public source does not encode any author's SDK path.
Set ANDROID_HOME to <android-sdk>; ANDROID_SDK_ROOT is a supported legacy fallback
and, if also set, must identify the same SDK. ANDROID_HOME is the preferred
[Android environment variable](https://developer.android.com/tools/variables).
For example, in your own PowerShell session:

```powershell
$env:ANDROID_HOME = '<android-sdk>'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
flutter doctor -v
flutter doctor --android-licenses
```

Review and accept applicable SDK licenses yourself. Required packages can be
installed with SDK Manager: platform-tools, platforms;android-36,
build-tools;36.0.0 and ndk;28.2.13676358. An emulator/system image is needed only
for native device tests, not APK compilation.

Dependencies use pub.dev, Google Maven, Maven Central and the Gradle Plugin
Portal. Gradle downloads its declared distribution from services.gradle.org;
Flutter artifacts use public Flutter storage. Network access is expected on a
first build. No private mirror, credentials or offline cache is required by the
project. Remove private PUB_HOSTED_URL/FLUTTER_STORAGE_BASE_URL overrides when
reproducing the public-source run. No build_runner or extra application codegen
step exists.

Flutter generates .dart_tool, platform registrants, plugin links, wrapper helper
files and android/local.properties. Do not copy these from another developer.
Gradle settings reads flutter.sdk from local.properties, so use the Flutter CLI
for initial Android bootstrap before invoking Gradle directly. That local file
is ignored and must not be committed. The sqlite3 native hook on Windows uses
system winsqlite3; it does not require downloading a separate SQLite DLL.

## Android Debug Build

```powershell
flutter pub get
flutter build apk --debug
```

Output: build/app/outputs/flutter-apk/app-debug.apk. No key.properties, release
keystore or signing environment is required. Use a dedicated test device or
emulator for installation; the new package has its own sandbox. Do not clear or
uninstall an old app with real data to make a test pass.

## Android Release Signing

Follow [Android release signing](ANDROID_RELEASE_SIGNING.md). Four private
values come from environment variables or ignored android/key.properties, with
nonblank environment values taking precedence per field. The committed
android/key.properties.example contains placeholders only. Store the real key
outside the checkout, use forward slashes in properties paths, and never commit
credentials. Jax does not generate or guess a release key during builds.

## Android Release Build

```powershell
flutter build apk --release
```

With complete private configuration, output is
build/app/outputs/flutter-apk/app-release.apk. Without it, Release deliberately
fails with `Release signing credentials not configured.` This is the expected
clean-contributor behavior, not a reason to substitute Debug signing. Certificate
verification and offline key-backup instructions are in the signing guide.

## Windows Build

```powershell
flutter pub get
flutter build windows --release
```

Keep the **entire** build/windows/x64/runner/Release bundle together: jax.exe,
flutter_windows.dll, plugin/native libraries when present, and data/ including
icudtl.dat and flutter_assets. Copying just jax.exe is not a supported package.
Use a synthetic/isolated data profile for verification; do not point test runs
at a real user's APPDATA. See [reproducibility evidence](REPRODUCIBILITY.md) for
what was and was not verified on an isolated profile.

## Tests

```powershell
flutter analyze
flutter test
```

The current baseline is 695 passing host tests. Native integration tests are
separate: use a dedicated Android emulator and an isolated Windows APPDATA
beneath .local_private/rc, passing --dart-define=JAX_RC_ISOLATED=true to the
clean-start case. Run cases individually with --dds; see the eight Android and
seven Windows scenarios in RELEASE_CANDIDATE.md. Existing intermittent Flutter
harness limitations remain documented there and are not hidden by a host pass.

Use PowerShell 7 (pwsh) for the developer tools and seven contract groups in
tool/*_contract_test.ps1; that is the tested shell, not Windows PowerShell 5.1. They use fake
ADB/synthetic fixtures. See [Tools](TOOLS.md) for actual Debug ADB/Sync workflows.
Those tools resolve explicit paths, JAX_*_PATH overrides, PATH and standard SDK
variables; aapt2 needs an explicit path or PATH entry. They require a debuggable
approved Jax package and retain backup/preview/confirmation safeguards.

## Troubleshooting

- SDK not found: verify ANDROID_HOME and flutter doctor; regenerate ignored
  local.properties through Flutter instead of hardcoding another machine's path.
- Java/Gradle errors: check the JVM selected by Flutter and wrapper compatibility;
  target JVM 17 does not itself choose the Gradle runtime.
- Dependency resolution fails: check access to public sources and local proxy/TLS
  policy; Java/Gradle can use different proxy discovery from a browser. Configure
  any needed proxy locally, never commit its credentials. During this verification
  a slow wrapper download was replaced by a fresh download of the same official
  distribution, checked against its official .sha256, in the new wrapper cache.
  This is a documented network recovery, not an extra application dependency.
  Do not copy someone's private caches or substitute an unverified mirror.
- Release signing missing: expected without private configuration; Debug remains
  available. Never add a Debug fallback or expose secret values in diagnostic logs.
- Windows toolchain or symlink errors: install the VS workload/components and
  enable Developer Mode as required by Flutter; restart the terminal.
- To reproduce from scratch, use a fresh tracked-only checkout with empty
  PUB_CACHE and GRADLE_USER_HOME, isolated APPDATA/LOCALAPPDATA/TEMP, and no signing
  environment. Installed SDK/toolchain artifacts are still prerequisites; this
  is not a hermetic or offline build claim.

Branding assets are committed; normal builds do not run the icon generator.
See [branding source](../assets/branding/README.md) only when changing artwork.
