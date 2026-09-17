# Jax placeholder icon

jax_icon.svg is original project artwork: a geometric J in muted slate and warm
cream, drawn from paths rather than a font. Copyright (c) 2026 Jarrett; released
under the root MIT License. It contains no downloaded image, third-party logo,
Flutter mark, OpenAI mark or external font. This is a simple release placeholder,
not a claim of trademark registration or final brand design.

On Windows with PowerShell 5.1+ and System.Drawing, from the project root:

```powershell
powershell -NoProfile -File tool/generate_branding.ps1
```

The generator reads the SVG's colors, stroke and M/H/V/C path subset. Keep the
source in that subset or extend the generator deliberately. No package install
or network access is needed. Committed resources are the build inputs; ordinary
Flutter builds do not need to regenerate them.

Outputs:

- Android legacy and round PNGs at 48/72/96/144/192 pixels.
- Android adaptive foreground/background at 108dp with the mark in the central
  safe area, normal/round definitions for API 26+, and monochrome for API 33+.
- Windows ICO with 16/24/32/48/64/128/256 pixel PNG entries.

Pure-color legacy launch backgrounds remain; Android's system launch surface
uses the new app icon. No splash animation was added. Review tiny sizes,
round/squircle masks and platform-rendered icons when changing the source.
