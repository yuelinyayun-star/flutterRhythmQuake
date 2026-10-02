# Edition builds

The codebase produces two editions from the same version and commit. The
compile-time `RQ_EDITION` value is `personal` by default. Use the explicit
`public` value for a public release.

| Edition | P-Alert stations and source estimate | GlobalQuake EEW | ICL EEW (Jian and China EEW) |
| --- | --- | --- | --- |
| `personal` | Available under existing settings | Available under existing settings | Available under existing settings |
| `public` | Disabled and hidden | Disabled and hidden | Disabled and hidden |

Windows installers:

```powershell
.\package_windows.ps1 -Edition public
.\package_windows.ps1 -Edition personal
```

Android APKs:

```powershell
.\build_android_edition.ps1 -Edition public
.\build_android_edition.ps1 -Edition personal
```

Linux x64 bundles (run with the Linux Flutter SDK):

```bash
flutter pub get
bash build_linux_edition.sh public
bash build_linux_edition.sh personal
```

The manual `Flutter Linux build` GitHub Actions workflow builds with Flutter
3.41.1 on Ubuntu 22.04 and saves the complete bundle as a `.tar.gz` archive with
a SHA-256 checksum. It does not publish a GitHub Release automatically.
Extract the entire archive, including `lib` and `data`, before running the
`flutterrhythmquake` executable. Runtime validation requires a Linux graphical
session; WSL 2 with WSLg can be used for local smoke tests. Compilation alone
does not validate text-to-speech, authentication, notifications, or OBS capture.

The edition is part of the output filename. The two Windows builds currently
share one installer app ID, and the two Android builds share one application ID.
They replace each other when installed; they cannot coexist on one device.
The public edition is a feature-limited client build, not a way to keep private
code or credentials secret from someone inspecting the binary.
