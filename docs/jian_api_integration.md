# Jian Project integration

Protocol reference: https://api.sismotide.top/api/#overview

## Scope

- One logical `/all` connection, preferring `wss://api.sismotide.top/all`
  with failover to `wss://api.jianproject.cloud/all`, with independent Jian auth
  (not WAuth). Business feeds and `/all` require authentication. Without a saved
  credential, no socket or retry timer is started; settings show auth required.
- Access-ticket exchange is paired with the selected business host:
  `auth.sismotide.top/api/access` or `auth.jianproject.cloud/api/access`.
  Both use the saved RT in an Authorization header; each native business
  handshake uses its newly exchanged AT in a Bearer header. See
  [failover validation](jian_failover_20261101.md).
- Settings: API and data sources -> Jian Project earthquake warnings/information.
  Stored as `api_source_jian_enabled`, initially off. Existing API preferences
  remain unchanged.
- 46 earthquake feed types: six EEW feeds and 40 information/rapid-location feeds.
  `early-est` is information, not an EEW alarm.
- CENC/CWA/JMA/KMA/USGS/EMSC history requests share the same connection.
- JMA tsunami (`jma-tsunami`, VTSE41) also uses this connection and the existing
  `TsunamiMessage` pipeline on desktop and Android. It shares the JMA agency slot
  with P2PQuake/WHEWS; it is not converted into an earthquake information card.
  Forecasts (若干の海面変動, JMA codes 71/72) use the existing blue coastline
  style and tsunami sidebar, with source validity time, without warning audio.
  Original payload, event ID, serial, issue epoch and validity epoch are retained.
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
- Jian SA supplies a fixed `number = 1`, not an increasing sequence. Its original
  first-report label is retained, while changed live bodies on the same API use
  the unsequenced revision rule. Cached snapshots and undated cross-API copies
  cannot roll back an active revision. Warning/final/assumption flags also count
  as body changes on both processors.
- Jian CENC `_M` IDs share the normalized native bulletin identity in active UI
  and Android, as in history. The complete-second original is preferred over
  its otherwise identical minute-only copy in either arrival order; its original
  ID and API provenance remain together. Precision enrichment is silent in the
  foreground and retains the original arrival time.
- Review metadata comes from the retained original Jian `infoTypeName`, before
  generic agency titles. Automatic/reviewed status reaches history tags, report
  dedupe keys and foreground/background revision checks. The first reviewed
  bulletin may replace a closed automatic report once. Automatic copies cannot
  replace a reviewed card or history row; replay without a report clock can
  still enrich an automatic row with an explicit reviewed status.
- Ordinary Jian JMA information displays source correction/cancellation status,
  following the existing JMA information rule that hides ordinary report serials.

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
- Unified card/notification display converts the stored source clock to the
  computer's local timezone. The zone label uses the displayed instant's local
  offset, including historical daylight-saving changes. Identity, ordering and
  expiry continue to use the original source clock and offset.
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
- Every connection obtains a fresh `at_`. Native clients pass it in the
  WebSocket Authorization header, never in a URL or business frame. Token
  expiry does not restart a healthy socket. A reconnect fetches a new token.
- On Web, the browser opens `wss://api.sismotide.top/all` directly from the
  user's own IP, then sends the short-lived `at_` as the first text frame
  within Jian's 15-second authentication window. The HTTP token exchange uses
  the fixed same-origin auth proxy. WebSocket traffic is not relayed through
  the deployment server because Jian limits concurrent connections per IP.
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
- Both `/api/refresh` and `/api/access` can return the RT's
  `refresh_expires_at` (UTC Unix seconds) and `refresh_expires_after_min`.
  The absolute time takes precedence; remaining minutes are converted using
  request-start UTC time. Legacy refresh responses retain `expires_after_min`
  support. The AT's `expires_after_sec` never determines the RT's expiry.
- A newly redeemed refresh token and its expiry are saved together in one
  secure record. After each access exchange, returned RT expiry updates source
  status and the matching saved credential, including imported/legacy tokens.
  Missing RT-expiry metadata preserves the saved value; late responses from
  an abandoned connection cannot update it. A failed metadata save does not
  discard the credential or prevent the authenticated connection.
- The map dashboard places configured/authenticated Jian on its own line,
  retaining that line on temporary disconnect or credential failure. Other
  enabled APIs retain their order and five-per-row grouping. Remaining lifetime
  is updated locally, with an exact estimated local expiry in the tooltip;
  unknown expiry, local estimated expiry and server-confirmed expiry remain
  distinct. Only non-secret metadata is sent through background source status.
- Validation uses mocked credentials and HTTP responses plus unchanged captured
  earthquake frames. Live authenticated access requires the user's personal
  credential and is not claimed by automated tests.

### Offline recovery correction (2026-10-16)

- A failed HTTP request or response stream is a retryable network failure.
  Non-JSON/invalid UTF-8 responses, malformed tickets and unknown rejection
  envelopes are retryable `invalid_response` failures. None of these prove
  that the saved refresh token is invalid or expired.
- Missing/malformed/rejected/expired access-token responses obtain a fresh
  access token after the existing five-minute cooldown. Explicit invalid or
  expired refresh tokens and account bans still stop automatic retries.
- The saved refresh token and its expiry remain unchanged during recovery.
  Every new socket uses a newly exchanged access token; old-generation frames
  cannot invalidate the recovered connection. Disable cancels pending retries.
- Controlled regressions reproduce an established connection failing, an auth
  outage, and recovery after cooldown. These are fault-injection tests with
  non-working credentials, not an upstream outage capture. Windows native
  decoding/transport and Jian integration/settings/dashboard regression:
  162 tests passed; targeted static analysis has no issues.

A separate bounded live check on 2026-09-21 successfully redeemed the user's
login key, obtained an access token (3600 seconds, max 3 connections), and
received an `all` snapshot with 52 source entries using the Authorization
handshake header. The verification socket was closed. No credential or response
body was saved in this repository. This is a protocol check, not an Android
physical-device or packaged-app end-to-end test.

## Unified UI correction (2026-10-10)

CEA/provincial CEA/SA missing-value estimates now drive badge, header and border
colors through the application's existing reported-intensity palette. CWA EEW
uses the same existing CWA palette for the entire card. Estimates remain labeled
as estimates and never overwrite `maxIntensity`, `className` or `sourcePayload`.

Validation: 398 tests passed across 27 relevant test files, including original
Jian captures, mobile/desktop card colors, CENC arrival order and dismissal,
review upgrades, fixed-number SA revisions, Android handoff, EMSC voice lifetime,
USGS/ShakeMap filters and CWA history. New lifecycle/contract states are explicitly
separate from unchanged captured wire data. Four previews generated from original
captures are in `build/test-previews/jian_fixed_*.png`; CEA and CWA were visually
checked. No real-time warning was injected and no physical-device verification
or newly built installer is claimed. Multi-hazard scope above remains unchanged.

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
