# Jian Project integration

Protocol reference: https://api.sismotide.top/api/#overview

## Scope

- One public `wss://api.sismotide.top/all` connection, no WAuth requirement.
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

- `/all` costs three connection points; only one connection is opened per host
  owner. The existing Android ownership mechanism is unchanged.
- 30-second ping; reconnect after over 90 seconds without incoming frames.
- Normal retry spacing: 45, 90, 180, then 300 seconds. Attempt spacing persists
  across settings reloads and isolate restarts.
- Server rejection: five-minute cooldown. An explicit IP-ban message causes a
  conservative 24-hour cooldown because the server can extend bans up to 24 hours.
- Disable/dispose cancels subscriptions, timers and in-flight generations.
  Late handshake completion cannot revive a disabled source.

## Evidence and tests

`test/fixtures/jian/all.json` and `jmalist_response.json` are unmodified UTF-8
wire frames captured on 2026-09-16 around 10:01 UTC. One bounded 35-second probe
received an aggregate with 52 source entries, 50 JMA history entries and a
heartbeat. This is not evidence of long-term reliability or a live EEW test.

Reproduce a bounded read-only probe with:

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
