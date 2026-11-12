# P-Alert Source Estimation

## Scope

P-Alert has its own raw-observation pick history, four-stage HYP estimator
instance, isolate and published UI state. It does not write into the NIED event
tracker. The title is shared with NIED through `sourceEstimationTitle`.
The existing `show_estimated_epicenter` setting enables both sources.
`hide_grid_on_eew` also hides P-Alert estimates matching a non-cancelled,
non-assumption CWA EEW: latitude/longitude difference at most one degree,
depth difference at most 100 km and origin-time difference at most 10 seconds.
The comparison converts the CWA source wall clock to UTC. Turning this setting
off keeps valid estimates visible; it does not bypass the quality gate.

## Inputs and Thresholds

The upstream reference is kanameishi commit
`8748cf7abc82b7d172b42ec0ef616a9116de95a1` (AGPL-3.0):

- [P-Alert profile](https://github.com/Lipomoea/kanameishi/blob/8748cf7abc82b7d172b42ec0ef616a9116de95a1/src/classes/PalertHypocenterProfile.js)
- [Station picks](https://github.com/Lipomoea/kanameishi/blob/8748cf7abc82b7d172b42ec0ef616a9116de95a1/src/classes/StationClasses.js)
- [Internal intensity levels](https://github.com/Lipomoea/kanameishi/blob/8748cf7abc82b7d172b42ec0ef616a9116de95a1/src/utils/Utils.js)

Internal PGA thresholds in Gal are:
`0.1, 0.14, 0.18, 0.25, 0.33, 0.44, 0.59, 0.8, 1.4, 2.5, 4.4, 8, 14, 25, 44`.
At PGA >= 80 Gal, internal levels use PGV thresholds in cm/s:
`15, 30, 50, 80, 140`.
Internal level 6 starts at 0.44 Gal; it does not mean CWA intensity 6.

Eight actually received source samples warm up each pick. A two-sample 1.5x rise
or single-sample 2x rise over the previous background starts a pick. At least
one rising sample must reach internal level 6. Invalid observations and gaps longer than the six-second freshness deadline reset
the pick; shorter gaps preserve only actual samples, with no invented missing
seconds. Repeated timestamps cannot advance it. A pick expires after eight
seconds of source time without a change in the two raw PGA peaks.

Only station IDs already confirmed by the application's detector enter active
inference. The existing 0.8 Gal noise floor, neighbour confirmation, CWA label
categories and continuous-estimate numeric-marker threshold are unchanged.
Display-held peaks are never used as inference observations. Missing current
PGV at high PGA is invalid rather than replaced with zero or retained PGV.

The profile adds P-Alert maximum/second-maximum level weights, inactive-station
penalties and stage-specific S/P penalties to the existing HYP core. Publication
requires at least five supporting stations, valid coordinates/depth/time,
quality score >= -3 and no invalid score sentinel. Source disconnect, expiry,
disable and worker reset clear results. Worker generations reject late output.

## Validation Boundary

This is integration with the existing application HYP search and clustering,
not a replacement of the whole engine by the latest upstream implementation.
The inherited travel-time/search baseline has not been calibrated against a
Taiwan earthquake replay. Japan-specific magnitude output is not published. The preliminary magnitude
now inverts the APP's existing Taiwan PGA attenuation model (unit site correction)
for at least five associated stations, using each raw episode peak and its own
hypocentral distance, then takes the median. The unified card uses that magnitude
with the existing Taiwan township intensity forecast and labels it `PGA 初估`.
No official P-Alert magnitude or independently calibrated waveform estimate is
claimed. Source assignment IDs prevent another concurrent source from donating
its station peaks. Missing magnitude inputs remain unknown.
Tests use explicitly labelled controlled boundary inputs, not fabricated live
observations, and verify successful computation, cleanup, settings and titles.
They do not establish real-event location/depth accuracy.

## Replay and performance (2026-10-14)

Historical station frames now enter separate replay workers before display
coalescing. Replay never publishes into live trackers or triggers automatic
recording/TTS. Stop/restart rejects pending output. Original source times and
amplitudes remain unchanged. Live EEW takes display priority, and matching CWA
EEW suppression stays within the live/replay context.

JMA source prediction now uses an exact-parameter LRU of 32 entries. No station
reduction, coordinate rounding or intensity-model change is used. Taiwan
prediction reuses the existing bounded township forecast cache.

## Live P-Alert cold start and session lifetime (2026-10-17)

The Windows P-Alert neighbor calculation now uses the station-core Rust kernel.
It retains latlong2 WGS84 Vincenty distances rounded to metres, four directional
sectors with three stations each, and Dart 3.11's equal-distance sort order.
All 787 station neighbor lists match the previous implementation exactly.
Non-Windows builds and processes still holding an older DLL retain the existing
implementation until the new Windows binary and DLL are fully restarted.

Live inference freshness and publication now belong to PAlertSourceDriver.
Quiet/detection-expiry clears visible output without destroying station warm-up
or rebuilding immutable geometry. Six-second source gaps still invalidate raw
picks; explicit disable/dispose releases the worker, and generations reject
pending output after display expiry. Quality/publication thresholds are unchanged.

The actual CWA1150077 recording contains 156 P-Alert frames, 787 stations and
15 inference outputs. Before/after inference coordinates, depth, magnitude,
support count and quality scores agree exactly. A retained 28-frame original
prefix exercises display clear before confirmation and concurrent CWA EEW card
rendering. This establishes replay behavior, not live-event location accuracy or
an equivalent reduction of the entire APP's CPU/GPU/working-set measurements.
