# WHEWS FUNVISIS / CAT / CWA adaptation

Verified against the public WHEWS documentation on 2026-10-08:
[FUNVISIS](https://api.beecld.com/#ws-funvisis),
[CAT](https://api.beecld.com/#ws-cat-tsunami),
[CWA](https://api.beecld.com/#ws-cwa-tsunami).
The three sources reuse the existing `/ws/all` subscription. No cloud code or
additional production connection is required.

## FUNVISIS

- Append `QuakeSourceType.funvisis`; keep saved enum indexes stable.
- Register `whews_funvisis` in the existing catalog agency registry. Existing
  foreground/background magnitude filters, history, Chinese location conversion,
  map epicenter and speech use the shared catalog path.
- WHEWS has already converted HLV UTC-4 into UTC+8. Read `shockTime` and
  `updateTime` as UTC+8, with no second HLV conversion.
- `infoTypeName: Mw` is magnitude metadata, never a bulletin report number.
- Preserve original raw fields in `sourcePayload`. A dated monthly record outside
  the existing display admission window fills history without being made live.

## CAT and CWA tsunami products

- Add independent `TsunamiSource.cat` and `.cwa` state, labels and speech agency
  names. Route both through the tsunami stream rather than an unadapted quake.
- Retain `id`, upstream `eventId`, positive `updates`, headline, description,
  coordinates, quake parameters, level, source expiry and the entire raw payload.
- CAT uses the existing international bulletin parser and its real bulletin/CAP
  link. CWA does not supply an upstream URL; no URL is fabricated.
- UTC+8 source wall clocks are kept in the model; report and arrival times are
  converted to the computer timezone for display.
- Map Information to information, Advisory/Watch to watch, Warning/Alert to
  warning and explicit Cancellation to cancellation. Source values remain raw.
- Reuse the existing tsunami sidebar carousel, auto-popup rule for active
  warnings, international epicenter marker and NMEFC observation marker styling.
  CWA warning area details and station names, IDs, coordinates, wave-height text,
  arrival times and status are retained and displayed. Invalid positions are not
  rendered. Bare or placeholder wave-height strings are not assigned a unit.
- For a proven identical `eventId`, report sequence precedes publication time.
  Lower reports cannot overwrite higher reports or revive a cancellation.
  Different events retain chronological ordering. Initial aggregate selection
  follows the same report precedence, with existing snapshot silence and dedupe.
- Information uses the existing display lifetime: source `expires` when valid,
  otherwise three hours from issue time (a presentation policy). The new sources'
  active warnings also hide at an explicit source expiry. No alert is generated
  merely to show an expired documentation example.
- The Android foreground handoff and local decoder serialize the new identities,
  report sequence, observation details and untouched raw payload.

## Verification

125 regression tests passed, including unchanged FUNVISIS/CWA documentation
examples, the CAT frame extracted unchanged from the saved 2026-09-17 aggregate,
stream dispatch, serialization, lifecycle ordering, filters and map rendering.
The current CAT documentation example has malformed URL strings; it was not
repaired. Separate application-model test scenarios do not claim to be live data.

See `test/fixtures/whews_three_sources_20261008.README.md` for fixture provenance.
No actual Android device background/audio validation is claimed by unit tests.

The running Windows APP was restarted to load the complete source/UI changes.
Its original WHEWS aggregate connection actually received all three sources:
FUNVISIS `funvisis_29128`, CAT `BOLETIN_INFORMATIVO_002_20261007_020306`
and CWA event `115005`, report 2. Both cached tsunami messages are Information
and outside their display lifetime; they are not presented as current alerts.
The CWA raw description quotes removal of a Pacific threat, which does not
override its explicit Information level. Observed APP state is saved in
`tmp/whews_document_audit_20261008/app-three.actual.json`.
