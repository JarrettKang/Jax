# Public screenshots and synthetic data

The four PNGs in `images/` are actual Flutter-rendered Windows Jax views, captured
from the normal `JaxApp` widget tree by a developer-only entry. No UI mockup or
product layout replacement is involved. Only app pixels are captured: there is
no desktop, taskbar, window title bar, account or notification surface.

All names, projects, categories, work intervals and dates are fictional. The
clock is fixed to **2030-04-15 10:30 local time**; these are not user activity dates.
The dataset covers a portfolio website, conversational Japanese, fitness, morning
review, an evening walk and organizing a downloads folder. No existing DB is read.
The current Chinese product labels are intentionally retained.

## Reproduce on Windows

Run from the repository root, using Flutter 3.47.1:

```powershell
flutter pub get
# Optional: create a standalone demo fixture (always use a fresh filename).
dart run tool/demo_data.dart .local_private/demo/manual/fixture.db

# Capture creates its OWN fresh DB; do not use the already-created filename.
flutter build windows --release --target tool/capture_demo.dart --dart-define=JAX_DEMO_DB=.local_private/demo/capture-01/fixture.db
# Launch from the repository root; it exits after capturing all four pages.
& .\build\windows\x64\runner\Release\jax.exe

# After inspection, copy the four captures into docs/images.
# Restore the normal product entry before any ordinary build/distribution.
flutter build windows --release --target lib/main.dart
```

The capture directory is `.local_private/demo/capture-01/captures`. The tool
requires an explicit new `.db` below the repository's `.local_private/demo`, refuses
path escapes, links, real Jax user-data directories, existing DBs and sidecars.
It has **no overwrite option**; use a fresh directory for each run. Preferences
remain in memory; production data-location resolution is never called.
Do not ship the developer capture executable as a normal Jax release.

The application clock and rows are deterministic for the same timezone. SQLite
file bytes, system fonts and rasterization may vary across hosts; byte-identical
images are not promised. Captures use 1.5× pixel density from the native Windows
client area. The Jax launcher icon remains the original project J icon; client-only
captures naturally omit the OS window icon.

Before publishing, inspect all four full-resolution images for private text,
paths, serials, account information, notifications, overlays and Debug/Flutter
branding. Commit only reviewed PNGs and seed source, never fixture databases or
raw logs. The screenshots contain project UI and synthetic data under MIT, with
no downloaded third-party artwork. See [publication checks](PUBLICATION_CHECKLIST.md).
