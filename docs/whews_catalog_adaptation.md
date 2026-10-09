# WHEWS catalog adaptation audit

Checked 2026-09-15 against https://api.beecld.com/ and its published
`/assets/index-BvB8mAYx.js` documentation bundle.

## Scope

New dedicated earthquake catalog identities:

| Source | Institution |
| --- | --- |
| GSRAS | 俄罗斯地球物理局 |
| BGS | 英国地质调查局 |
| IPMA | 葡萄牙气象局 |
| SSN | 墨西哥国家地震局 |
| AFAD | 土耳其灾害与应急管理局 |
| SED | 瑞士地震服务中心 |
| NOA | 希腊国家天文台 |
| SCSN | 南加州地震台网 |
| IAG | 蒙古地球物理与天文研究所 |
| IGP | 秘鲁地球物理研究所 |
| NEPAL | 尼泊尔地震信息 |

The existing BMKG, GeoNet, TMD, INGV, NRCan, MMD, PHIVOLCS, SGC, GA and
CENAIS catalog adapters now share the same identity registry, location
mapping, filters, history routing and lifecycle checks.

This is the earthquake-catalog batch, not a claim that every WHEWS endpoint
is integrated. Dedicated station streams, CMT, cenc_int, typhoon, NEA,
cheji, CAT tsunami and JMA offshore tsunami observations require their own
product contracts; they are not reclassified as earthquakes here.
Existing EEW, weather and tsunami processing is retained.

## Early-est information integration (2026-10-08)

WHEWS `/ws/early_est` is routed to the existing `earlyEst` information identity,
per the application's display policy. It remains `isEew: false`, shares Jian's
information UI, history bucket and filters, and retains `apiTypeLabel: WHEWS`.
This application policy differs from the upstream documentation's warning category.

Read the original `shockTime` and `createTime` as UTC+8, retain `id`, and display
the supplied `updates` as report sequence. The common magnitude display selects
the first available nonnegative finite value in `Mwp`, `Mwpd`, `mb` order;
this is an application display preference, not an upstream precedence rule.
All three original measurements remain in the untouched `sourcePayload`.
Location uses the existing Chinese region conversion, and estimated intensity
uses the existing information-card estimator when magnitude and depth permit it.

`test/fixtures/whews_early_est_documented_20261008.json` is the unchanged public
documentation example. Its published `createTime` predates `shockTime`; neither
timestamp is corrected or injected as a current event during validation.

For the same proven Early-est event, foreground cards, Android background
processing and historical rows compare report sequence before publication time.
A lower sequence cannot replace a higher one even if delivered later or carrying
a later timestamp. Same-sequence corrections cannot roll back a known publication
time; absent times retain the existing correction rules. A higher sequence may update unchanged parameters
without being suppressed by cross-API observation deduplication. Different
earthquakes retain the existing event-identity and chronological slot rules.

The 2026-10-09 running APP capture also verifies Jian's
`EARLY_event_1791522664003` and WHEWS's `1791522664003` as the same upstream
identity. Jian report 6 and WHEWS report 9 differ in magnitude and longitude;
matching coordinates must not be required for subsequent revisions. Comparison
strips only Jian's known `EARLY_event_` prefix on a 13-digit ID, without changing
the original event. Shared foreground/background identity comparison handles
previously cached prefixed identities. History compares all already stored
matching rows, keeps the highest report and removes legacy duplicates even when
the next incoming row is an older replay. The unchanged APP records are captured
in `test/fixtures/early_est_history_20261009.original.json`.

## Data and behavior

- Preserve original input maps. Prefer documented id, shockTime and updateTime.
  Empty compatibility fields must not mask usable values.
- These catalog endpoints document UTC+8 wall-clock times, independently of
  the institution's local timezone. Do not infer timestamps from ids.
- Preserve upstream Chinese location names. Map foreign-language names through
  the existing offline geographic regions; do not send a geocoding request per
  event. Invalid or absent coordinates retain the source name and no map point.
- Parse numeric and Roman reported intensity consistently for the current
  card, history and map conversion. Missing intensity retains the existing
  CSIS estimate only when magnitude and depth allow that estimate.
- Each source has its own existing-style magnitude threshold and disabled
  state; the same preference key is used in foreground and Android background.
  New enum values are appended, preserving all existing enum indexes.
- New catalog sources are recognized, so the unadapted default-disable rule no
  longer applies to them. Truly unknown sources remain disabled by default.
- Live catalog deliveries first received less than 30 minutes after the
  earthquake can enter the current UI. The 30-minute admission bound is an
  application policy, not an upstream standard. The original 5/10/15/20-minute
  severity windows then run from first local acceptance, not earthquake time.
  Revisions retain that arrival time. Initial/reconnect snapshots retain their
  original earthquake-time windows; explicit history never creates an alert.
  Unknown origin times and events outside the admission bound do not trigger
  current alerts. Foreground and Android use the same lifetime helper.
  Valid dated expired entries can still populate foreground history.
- Repeated frames are suppressed by the existing aggregate dedupe. Same-report
  body corrections update UI without repeating effects. Older history revisions
  do not overwrite newer ones.
- Reuse the aggregate socket. Retain at most 50 entries per source and the
  existing 100-entry flattened history limit. Show source chips only after a
  source has records; source controls remain available in settings.
- Chinese voice agency names and mapped place names are shared with display;
  ML/L/Mw metadata is not read as a report type. OBS agency selectors also
  recognize the new sources.
- Fix WHEWS volcano data being rejected as an unadapted earthquake; retain a
  15-minute product window (one minute for cancellation) and volcano speech.
- Exempt WHEWS CENC revisions from the older non-WHEWS 30-second throttle.
  Preserve normal non-WHEWS CENC throttling and all EEW behavior.

## Evidence and limitations

`test/fixtures/whews_catalog_official_examples.json` contains 20 parsed
documentation examples with their original field values, not live observations.
The fixture does not imply that these events actually occurred as described.

- The published PHIVOLCS example is invalid JSON at its depth/md5 boundary;
  it is not repaired or represented as an official valid fixture.
- The IGP description says Peru, but its example says Vietnam and provides
  coordinates there. Preserve those values and map the provided coordinates;
  do not substitute Peruvian coordinates based on the institution name.
- Lifecycle tests explicitly construct test scenarios separately from the
  unmodified documentation fixtures.
- Tests cover all 21 identities, foreground/background filtering, stale
  revisions, same-report corrections, speech text, aggregate replay, invalid
  coordinates and mobile/desktop history filtering.
- No authenticated live feed soak, actual phone audio test or release
  installation is part of this change.
