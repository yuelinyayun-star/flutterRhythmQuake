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

The edition is part of the output filename. The two Windows builds currently
share one installer app ID, and the two Android builds share one application ID.
They replace each other when installed; they cannot coexist on one device.
The public edition is a feature-limited client build, not a way to keep private
code or credentials secret from someone inspecting the binary.
