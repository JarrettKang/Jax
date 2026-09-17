# Jax Release Identity

| Identity | Canonical value |
|---|---|
| Product / app name | Jax |
| Dart package / CMake project | jax |
| Version | 0.1.0+1 (unchanged; no v1 release decision) |
| Android applicationId / namespace | com.jarrett.jax |
| Android MainActivity | com.jarrett.jax.MainActivity |
| Android Debug World fixture | com.jarrett.jax.worldfixture, label Jax World QA |
| Android normal launcher label | Jax |
| Flutter title / Windows window title | Jax |
| Windows ProductName / FileDescription | Jax |
| Windows CompanyName | Jarrett |
| Windows InternalName / OriginalFilename | jax / jax.exe |
| Copyright | 2026 Jarrett |
| Project license | MIT; third-party rights remain separate |
| Default assistantName | Butler, user-configurable |

Jax is the technical product identity. The assistant's personal name is a user
preference and may be Jax, Alfred or another name; it does not rename the app.

## Android migration boundary

The former package was com.example.jax. Changing applicationId creates a new
Android app identity and sandbox. Old Debug data is not automatically migrated.
Do not uninstall, clear or overwrite the old app to make migration appear to work.
Any later developer data migration requires its own explicit, backed-up workflow.

The Dart/Kotlin Debug Sync channel is com.jarrett.jax/debug_sync. ADB/Sync/copy/
install tools default to the new normal package and accept an explicit override
only for the approved normal/fixture identities. Device selection, debuggability,
backup, preview and destructive-confirmation protections remain in force. A
release-signed app is not thereby eligible for Debug run-as/Sync tooling.

## Signing and security

Release signing is supported through private local configuration or environment
variables. Missing credentials cause an explicit Release build failure; no Debug
signing fallback exists. Debug remains independently buildable without secrets.
See [Android release signing](ANDROID_RELEASE_SIGNING.md) for setup and backup.
Signing material is never committed. The normal Release APK has passed signature
verification against the intended key, and its certificate differs from Debug;
see current RC facts. Offline key backup still requires owner confirmation.

## Branding and third-party assets

Android and Windows launcher icons are Flutter template assets, not final Jax
artwork. This remains a release branding blocker. See
[third-party notices](THIRD_PARTY_NOTICES.md). No final brand design, README rewrite,
release tag, GitHub publication or version bump is part of this phase.
