# Jian Project integration

Protocol reference: https://api.sismotide.top/api/#overview

## Scope

- One `wss://api.sismotide.top/all` connection, with independent Jian auth
  (not WAuth). Business feeds and `/all` require authentication. Without a saved
  credential, no socket or retry timer is started; settings show auth required.
- Settings: API and data sources -> Jian Project earthquake warnings/information.
  Stored as `api_source_jian_enabled`, initially off. Existing API preferences
  remain unchanged.
- 46 earthquake feed types: six EEW feeds and 40 information/rapid-location feeds.
  `early-est` is information, not an EEW alarm.
- CENC/CWA/JMA/KMA/USGS/EMSC history requests share the same connection.
- Weather, GDACS, JMA volcano, IFRC, USGS volcano and VONA are deliberately not
  coerced into earthquake models. CENC intensity-report and station endpoints
  are separate protocols and are not enabled by this switch.

## Single processing route

`JianService -> QuakeEventAdapter.convertJian -> UnifiedQuakeData`

- Desktop: existing `QuakeProvider._handleUnifiedEvent`.
- Android connection host: existing `BackgroundEventProcessor`, serialized
  unified event handoff, then the same provider entrypoint.
- Transport cannot write lists, map layers, notifications, audio or OBS directly.
- Agency keys are shared with existing sources. `origin = 4` and `apiTypeLabel`
  identify the transport separately. Historical `whews_*` catalog keys are
  retained as agency storage keys to preserve preferences and existing lists.
- All information feeds have source/magnitude filtering, source timestamps for
  expiry and the existing body/report ordering checks. New agency enum entries
  are appended; saved indexes are not reordered.
- EEW uses existing report sequence handling, expiry, countdown, map-fill and
  domestic extra-sound suppression. Independent agency EEWs remain independent.
- KMA EEW does not supply a report number. It is explicitly unsequenced, not a
  fabricated first report: changed live bodies on the same API may update the
  shared active slot. Duplicates, reconnect snapshots and undated cross-API
  revisions cannot roll it backward. This rule is shared by both processors.

## Replay and timestamps

- Initial aggregate information and list responses carry `isHistory` through
  serialization. They pass filters, then update history only. They never create
  an active card, play sounds, speak, notify, trigger OBS or move the camera.
- An initial EEW still enters normal expiry/report checks; a genuinely current
  EEW is not hidden solely because it was in the initial snapshot.
- Lists sort before the 50-item trim; replay cannot replace a newer revision.
  An undated replay cannot replace an existing record with no ordering evidence.
- Epoch milliseconds are absolute instants, localized once into the existing
  source-wall-clock model. JMA/KMA use UTC+9; other sources use UTC+8.
- No fabricated issue time, event-ID-derived origin time or local-time fallback.
  Unknown EEW origin time is expired under the source-time policy.
- Original payload is retained in `sourcePayload`, including JMA telegram,
  headline and tsunami comment. Earthquake comments do not become standalone
  tsunami warnings. KMA zero depth means unknown as documented.

## Connection behavior

- Only one connection is opened per host owner. The existing Android ownership
  mechanism is unchanged. Token concurrency and IP limits both apply.
- 30-second ping; reconnect after over 90 seconds without incoming frames.
- Normal retry spacing: 45, 90, 180, then 300 seconds. Attempt spacing persists
  across settings reloads and isolate restarts.
- Server rejection: five-minute cooldown. An explicit IP-ban message causes a
  conservative 24-hour cooldown because the server can extend bans up to 24 hours.
- Disable/dispose cancels subscriptions, timers and in-flight generations.
  Late handshake completion cannot revive a disabled source.

## Authentication (2026-09-21)

Reference: https://api.sismotide.top/api/#auth

- The Jian entry in Settings > API/data sources > Account/API authorization
  accepts a personal email `lk_` login key or
  existing `rt_` refresh token. Registration opens https://auth.sismotide.top/;
  the app does not send email or accept privacy terms for the user.
- `POST /api/refresh` redeems `lk_` (five minutes, single-use) for `rt_`
  (180 days). `POST /api/access` exchanges `rt_` for `at_` (~one hour).
  Both requests use an Authorization bearer header, no JSON body and no
  redirects. All tokens and server error bodies are excluded from diagnostics.
- Only `rt_` is stored using FlutterSecureStorage (the existing platform
  secure-storage dependency). Neither preferences nor cross-isolate messages
  carry credentials. Failed secure writes retain a redeemed token in the
  dialog for retry without consuming the login key a second time.
- Every actual handshake obtains a fresh `at_`, passed in the native
  WebSocket Authorization header, never in a URL or business frame. Token
  expiry does not restart a healthy socket. A reconnect fetches a new token.
- Invalid/expired credentials and account bans stop automatic retries. Network
  failures, rate/concurrency limits and rejected access tokens use cooldowns.
  A configured but rejected credential never silently becomes anonymous.
- Clearing the credential requires confirmation; it stops business connections
  until a credential is configured again. Editing credentials reloads the current connection
  owner, including the Android foreground service, without starting a second
  main-isolate socket or restarting other sources. Existing retry spacing
  remains in force.
- The current protocol permits an access token in the handshake, or within 15
  seconds after connecting. We use the handshake header, so no post-connect
  token message or `type:auth` command is sent. `/kmoni`, `/s-net` and
  `/kma-station` are exempt station endpoints, not routes opened by this service.
- The documented refresh-token concurrency limit is three across devices, also
  subject to IP limits. We retain one aggregate socket per owner and a five-minute
  cooldown for `conn_limit`; a healthy socket is not rotated when its ticket expires.
- Authentication status travels alongside existing source connection status;
  Android UI attachment can request the current status without reconnecting.
- A newly redeemed refresh token and its estimated expiry are saved together
  in one secure record, using the returned lifetime and request-start UTC time.
  Older raw tokens and manually imported tokens retain unknown expiry. Access
  ticket renewal does not extend the stored refresh-token expiry.
- The map dashboard places configured/authenticated Jian on its own line,
  retaining that line on temporary disconnect or credential failure. Other
  enabled APIs retain their order and five-per-row grouping. Remaining lifetime
  is updated locally, with an exact estimated local expiry in the tooltip;
  unknown expiry, local estimated expiry and server-confirmed expiry remain
  distinct. Only non-secret metadata is sent through background source status.
- Validation uses mocked credentials and HTTP responses plus unchanged captured
  earthquake frames. Live authenticated access requires the user's personal
  credential and is not claimed by automated tests.

A separate bounded live check on 2026-09-21 successfully redeemed the user's
login key, obtained an access token (3600 seconds, max 3 connections), and
received an `all` snapshot with 52 source entries using the Authorization
handshake header. The verification socket was closed. No credential or response
body was saved in this repository. This is a protocol check, not an Android
physical-device or packaged-app end-to-end test.

The authentication regression run passed 202 tests across Jian protocol/UI,
dashboard layout, background reload planning, multi-API catalog handling and
WAuth. The credential dialogs were exercised at 1280x900, 390x844 and 320x568.

## Evidence and tests

`test/fixtures/jian/all.json` and `jmalist_response.json` are unmodified UTF-8
wire frames captured on 2026-09-16 around 10:01 UTC. One bounded 35-second probe
received an aggregate with 52 source entries, 50 JMA history entries and a
heartbeat. This is not evidence of long-term reliability or a live EEW test.

Reproduce a bounded read-only probe with a current `at_` supplied privately via
the `JIAN_ACCESS_TOKEN` environment variable (never commit it or place it in a
command-line argument). Missing credentials exit locally without a connection:

```powershell
dart run tools/probe_jian_api.dart
```

An optional output directory saves raw frames. Avoid repeated rapid probes on
the same public IP. Automated tests use those raw captures unchanged and
separately named synthetic lifecycle scenarios. Tests cover filters, expiry,
replay isolation, original-data preservation, timestamp conversion, report
sequence, reconnect, cooldown and stale-handshake cancellation.

Validation on 2026-09-16: 101 Jian-focused tests and 293 tests in the combined
regression run passed. The regression set includes WHEWS, Android handoff,
source reload planning, list storage/UI, timestamps, voice/countdown,
domestic EEW effect suppression and OBS. Full `lib` analysis has no errors;
six warnings remain in unrelated boundary/weather-layer files. No Windows or
Android installer has been built for this change, and no real-time EEW or
physical-device audio verification is claimed.
