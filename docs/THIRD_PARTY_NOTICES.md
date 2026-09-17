# Third-party assets and license status

The root MIT License covers Jax project-authored code. It does not relicense
Flutter, dependencies, plugins, system libraries, fonts or template artwork.

## Asset provenance

- The five Android launcher PNGs are byte-identical to the installed Flutter
  Android app templates.
- The Windows ICO is byte-identical to the flutter_template_images Windows
  template asset. It is not an original Jax brand asset.
- Both are classified as Flutter template assets. Their branding must be replaced
  or explicitly reviewed before public distribution; no final logo was created.
- pubspec.yaml declares no custom third-party image/font asset directories.
  Material icons/fonts are supplied by Flutter. The installed Material Icons
  license is Creative Commons Attribution 4.0; preserve its generated notices.
- No external replacement artwork was downloaded or introduced in Phase 5.

## Dependency notices

The resolved package inventory was checked for license files. Flutter SDK test
packages inherit the Flutter root license rather than each duplicating LICENSE.
The built APK contains generated assets/flutter_assets/NOTICES.Z; preserve it.
The dependency tree is not all MIT. A distribution-level review of native/transitive
licenses and accessible attribution remains a release preparation task; this
source/asset inventory is not a legal opinion or a complete distribution audit.

Source references: [Flutter license](https://github.com/flutter/flutter/blob/master/LICENSE),
[Flutter Android release guide](https://docs.flutter.dev/deployment/android).

## Flutter template notice

The following upstream notice is retained separately from Jax's MIT License:

Copyright 2014 The Flutter Authors. All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google Inc. nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
