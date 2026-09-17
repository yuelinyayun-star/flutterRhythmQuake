# International catalog identity audit

Scope: the 31 agencies in `unifiedCatalogSources`. This audit uses the existing
source contracts, unchanged WHEWS documentation examples and the unchanged
2026-09-16 Jian capture. It does not claim every API was simultaneously enabled
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
  There is no time or distance tolerance, and agencies are never merged.
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

## Limits

Different IDs plus differing parameters are not sufficient evidence of identity.
Without an already established alias or a shared upstream ID, those records may
remain separate. In particular, history aliases do not promise cross-ID alert
revision matching after changed parameters or restart. Do not describe this as
unconditional deduplication of every earthquake across every API.

Tests separate unchanged source examples/captures from explicitly synthetic
lifecycle scenarios. Coverage includes all 31 agency mappings, late arrivals,
cross-ID duplicate history and alerts, foreground/background restart suppression,
real parameter revisions, agency isolation and FAN GeoNet initial/live dispatch.
