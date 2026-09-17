# Android release signing

## Configuration

Release uses a dedicated signing configuration. For each field, a nonempty
environment variable takes precedence over the ignored android/key.properties:

| Environment | Local property |
|---|---|
| JAX_KEYSTORE_PATH | storeFile |
| JAX_KEYSTORE_PASSWORD | storePassword |
| JAX_KEY_ALIAS | keyAlias |
| JAX_KEY_PASSWORD | keyPassword |

All four values are required. Relative storeFile paths resolve from android/;
absolute paths and forward slashes work across developer machines. No author-machine
path is hardcoded. Copy android/key.properties.example only into the ignored local
file and replace placeholders privately. Never send credentials in chat or put
actual values in tracked files, command arguments, shell history or public logs.

Without credentials, Debug works and Release reports:
`Release signing credentials not configured.` Release never falls back to Debug.
The validation also applies to aggregate Gradle tasks that include Release.

## Create a key locally, only if no release key exists

Run keytool in your own interactive terminal. Choose an external private directory
and enter passwords at keytool's hidden prompts; do not add password arguments.
Do not overwrite or regenerate an already-used key. For example, after creating
a private directory outside the repository:

```text
keytool -genkeypair -storetype JKS -keystore <private-directory>/jax-release.jks -alias jax-release -keyalg RSA -keysize 3072 -validity 10000 -dname CN=Jarrett
```

Use a password manager for the password; the command's placeholder is a path,
not a value to paste literally. Use the existing key instead when available.
No home address, phone number or invented organization is needed in the certificate.
The key may serve different roles depending on a future distribution channel;
this setup is not Play App Signing enrollment or proof of Play Store readiness.

For one-session environment use in PowerShell, read secrets interactively rather
than writing them into command history:

```powershell
$env:JAX_KEYSTORE_PATH = '<private-keystore-path>'
$env:JAX_KEY_ALIAS = 'jax-release'
$storeSecret = Read-Host 'Keystore password' -AsSecureString
$keySecret = Read-Host 'Key password' -AsSecureString
try {
    $env:JAX_KEYSTORE_PASSWORD = [System.Net.NetworkCredential]::new('', $storeSecret).Password
    $env:JAX_KEY_PASSWORD = [System.Net.NetworkCredential]::new('', $keySecret).Password
    flutter build apk --release
} finally {
    Remove-Item Env:JAX_KEYSTORE_PASSWORD, Env:JAX_KEY_PASSWORD -ErrorAction SilentlyContinue
    $storeSecret.Dispose()
    $keySecret.Dispose()
}
```

This intentionally exposes secrets only to the local build process environment;
it is not a secret vault. Avoid environment dumps, shell tracing, Gradle debug
logs and build-cache exports containing private signing configuration. Keep any
local key.properties accessible only to your account; do not share it as an artifact.

## Verification

Use the Android SDK's apksigner verify --print-certs on both Debug and Release
APKs. Release must verify successfully; its certificate must match the intended
release key and differ from Debug. Keep full fingerprints in private verification
records for now, not public RC facts. Confirm applicationId com.jarrett.jax.

## Release Signing Backup Checklist

- [ ] Retain a verified primary keystore outside the repository.
- [ ] Make a separate encrypted/offline backup; verify it can be restored/read.
- [ ] Store password and recovery details separately in a password manager.
- [ ] Record alias and certificate fingerprint privately.
- [ ] Never upload keystore/key.properties/passwords to Git or public cloud shares.
- [ ] Do not casually regenerate a key used for released APKs; continuity affects updates.
- [ ] Record who controls the key and the restore procedure before distribution.

A checklist is not evidence that offline backup has happened. Confirm backup
completion separately with the key owner. Root ignore rules cover *.jks,
*.keystore and key.properties; the example contains placeholders only.

References: [Flutter signing guide](https://docs.flutter.dev/deployment/android),
[Android app signing](https://developer.android.com/studio/publish/app-signing).
