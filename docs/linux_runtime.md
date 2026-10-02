# Linux runtime

The manual `Flutter Linux build` GitHub Actions workflow creates an x64 release
bundle. Download the artifact and verify its `.tar.gz.sha256` file before
extracting the entire archive. Keep the executable, `lib`, and `data` together.
This is a portable bundle, not a `.deb` installer.

## Ubuntu 24.04 dependencies

```bash
sudo apt-get update
sudo apt-get install -y \
  libgtk-3-0 libsecret-1-0 libnotify4 libayatana-appindicator3-1 \
  libsqlite3-dev gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
  gstreamer1.0-libav fonts-noto-cjk
```

The current SQLite native asset resolves `libsqlite3.so`, so `libsqlite3-0`
alone is insufficient on Ubuntu. `libsqlite3-dev` supplies that library name.

Launch from the extracted bundle directory in a graphical user session:

```bash
cd /path/to/extracted/bundle
./flutterrhythmquake
```

Do not run the application as root. Use the same directory on later launches:
the current desktop database path is relative to the working directory.

## WSL testing

Use WSL 2 with WSLg and a regular Linux user. No complete Linux desktop is
required to display the application window. Extract the bundle into the Linux
filesystem rather than running it directly from a Windows-mounted directory.

If the test environment has no session bus, install `dbus-x11` and launch with:

```bash
dbus-run-session -- ./flutterrhythmquake
```

This creates an isolated D-Bus session; it does not configure or unlock a
credential keyring, nor does it provide a desktop notification server.
Credential storage requires an available, unlocked Secret Service, for example
GNOME Keyring. Desktop notifications require a notification service in the
graphical session. An existing Linux desktop session should use its own bus
instead of creating an isolated one.

## Validation limits

The 2026-10-02 Ubuntu 24.04 WSLg smoke test verified the application window,
map tile rendering, upstream earthquake lists, map dragging, and settings
navigation after adding Linux notification initialization. With the SQLite
runtime dependency installed, the history database and schema were created
successfully and SQLite's integrity check returned `ok`. No synthetic event
was inserted, and persistence of a newly received event was not validated.
The test did not import any existing Windows credentials.

- The current `flutter_tts` dependency has no Linux system TTS implementation.
  System speech is not supported by this bundle. GPT-SoVITS is a separate path
  and was not validated in this smoke test.
- Authorization and credential persistence were not verified: the fresh WSL
  user's Secret Service could not unlock its keyring.
- Desktop notification delivery, audio playback, and OBS recording were not
  validated end to end.
- The test environment used Mesa llvmpipe software rendering. Its CPU usage
  and frame rate are not a hardware-accelerated native Linux benchmark.
