# International catalog identity audit

Scope: the 31 agencies in `unifiedCatalogSources`. This audit uses the existing
source contracts, unchanged WHEWS documentation examples and the unchanged
2026-09-16 Jian capture, plus unmodified 2026-09-17 live snapshots from both
WHEWS and Jian in `test/fixtures/catalog_20260917/`.
It does not claim every API was simultaneously enabled
or observed delivering the same live earthquake.

## Transport coverage

| Coverage | Agencies |
| --- | --- |
| WHEWS and Jian (16) | BMKG, GeoNet, TMD, INGV, NRCan, MMD, PHIVOLCS, GA, GSRAS, IPMA, SSN, AFAD, SED, NOA, SCSN, IGP (Jian `peru`) |
| WHEWS only in current mappings (5) | SGC, CENAIS, BGS, IAG, NEPAL |
| Jian only in current mappings (10) | IPGP, INFP, ISC, KNMI, NCEDC, LMU, KOERI, CSN, IG-EPN, Early-est |

FAN also provides GeoNet. Its former `geonet` adapter output now uses the shared
`whews_geonet` agency key, including filters, history and late-arrival policy.
The prefix is a historical storage key, not API provenance. FAN retains its own
origin/API badge and existing silent initial-load behavior.

Existing USGS, EMSC, JMA, CWA, KMA, HKO, GFZ, BCSF and USP routes remain separate
from this 31-agency late-arrival policy. Their previous timing and identity rules
are not silently replaced by this change.

## Duplicate handling

- Same agency/ID updates the same history row. INGV integer IDs and Jian's
  scientific-notation integer IDs compare identically without rewriting raw IDs.
- Different IDs can match only with identical UTC origin instants, coordinates,
  magnitude and depth. Unknown or invalid parameters cannot establish a match.
  Agencies are never merged. The narrowly scoped GA exception below handles
  the independently captured transport precision difference.
- History remembers matched ID aliases while retaining the current list, so
  subsequent revisions can update the row. Alias memory is bounded and pruned
  with list eviction; it is not a persistent cross-provider identity database.
- Identical catalog reports ignore API badges, translated place names and title
  wording for repeat-alert detection. Intensity, review state, cancellation and
  other alert state remain significant. Arrival timers are not renewed.
- Report comparison keys share the existing bounded, expiring, persisted seen
  state in foreground and Android. Replayed identical reports under alternate
  IDs therefore cannot become fresh alerts after a restart.
- Original event IDs, observation parameters and captured fixtures are retained.
  Comparison keys are derived separately; no raw capture is rewritten.

## 2026-09-17 live regression

- GA native `ga2026skxciy` and Jian
  `ga_2026-09-17_06:42:42_-14.385_-174.667` both report M5.3 at the same UTC
  second. WHEWS retains latitude -14.3846092224121, longitude
  -174.667266845703 and depth 33.9; Jian exposes -14.385, -174.667 and 34.
  Only the recognized WHEWS/Jian GA ID formats use the common three-decimal
  coordinate/integer-km comparison. Time and magnitude must still match.
- The GA comparison keys and original report keys use the existing expiring
  seen-state store on Windows and Android. They preserve arrival time and
  upstream IDs, and track both transports so a genuine same-transport revision
  is not rounded away. Unknown review metadata from Jian is not itself a new
  report; conflicting explicit review states, intensity and cancellation remain
  significant. A GA identity retains its proven transport aliases for later
  revisions of those known IDs; distinct same-transport IDs are not merged by
  the precision rule.
- Captured MMD, PHIVOLCS and SSN observations match exactly despite different
  transport IDs. NRCan, SED and NOA share the same upstream ID. GSRAS's known
  `gsras_` wrapper around an eight-digit ID compares without changing raw IDs.
  The captured GSRAS reports are from different times and are not merged.
- GSRAS `20263958` contains `Tonga Islands` and zero latitude/longitude. The
  display and voice layer now resolve exact published FE English names through
  the existing Chinese region labels. All 757 names are checked. Coordinates
  stay missing, and names outside that dictionary stay unchanged rather than
  inventing a location. Cached list rows use the same display-only lookup.

The English FE ID/name table comes from
[ObsPy names.asc](https://github.com/obspy/obspy/blob/master/obspy/geodetics/data/names.asc).
It is compiled into a small in-memory lookup; no network lookup is added to
rendering or speech.

## Remaining limits

Outside the captured GA precision rule, different IDs plus differing parameters
are not sufficient evidence of identity.
Without an already established alias or a shared upstream ID, those records may
remain separate. In particular, history aliases do not promise cross-ID alert
revision matching after changed parameters or restart. Do not describe this as
unconditional deduplication of every earthquake across every API.

Tests separate unchanged source examples/captures from explicitly synthetic
lifecycle scenarios. Coverage includes all 31 agency mappings, late arrivals,
cross-ID duplicate history and alerts, foreground/background restart suppression,
real parameter revisions, agency isolation and FAN GeoNet initial/live dispatch.
