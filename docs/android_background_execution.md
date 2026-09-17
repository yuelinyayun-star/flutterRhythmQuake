# Android background monitoring

## Runtime contract

- Background notifications and boot auto-start remain opt-in.
- The manifest and Dart foreground-service configuration both use `specialUse`
  for user-enabled continuous earthquake early-warning monitoring. The manifest
  documents this use case. Google Play distribution requires review of this use
  case; this declaration is not a guarantee of store approval or immortality.
- The service is not exported. Boot and watchdog receivers start it from the
  same application. No third-party service start is needed.
- Boot configuration is enabled only when both background monitoring and the
  boot preference are enabled. A headless start reloads persisted preferences
  before opening any data-source connection, and stops if monitoring is disabled.
- Do not replace this with a media, location, or exact-alarm permission merely
  to keep the process alive. Do not restart against an explicit user force-stop.

## Cross-vendor settings

The Android-only settings component reads PowerManager battery exemption and
power-save status, plus ActivityManager background restrictions (API 28+).
Unavailable status stays unknown. No OEM autostart permission is inferred.

The two actions open standard Android battery optimization settings and this
application's system details. Users make the permission choices themselves.
Some vendors place autostart settings in their separate system manager; the app
does not claim that the standard details screen grants or exposes that setting.
Status is re-read on resume and on explicit refresh, without periodic polling.
Opening a settings page does not mark any permission as granted.

## Verification still needed on devices

1. Enable background notifications and verify the ongoing notification.
2. Check readings against system settings, change the exemption and return.
3. With boot auto-start on, reboot and unlock, then verify live data reception.
4. With background monitoring off, reboot and verify no source connections.
5. Check screen-off/Doze, task dismissal, OS process reclamation and reconnection
   separately. An explicit force-stop is not the same as OS reclamation.
6. Cover Android 14, 15 and 16 and different vendor systems. Service presence
   alone does not prove current earthquake data or notifications are arriving.

## References

- https://developer.android.com/develop/background-work/services/fgs/service-types#special-use
- https://developer.android.com/develop/background-work/services/fgs/timeout
- https://developer.android.com/training/monitoring-device-state/doze-standby
