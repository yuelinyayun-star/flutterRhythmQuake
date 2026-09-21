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

Eight consecutive source seconds warm up each pick. A two-sample 1.5x rise
or single-sample 2x rise over the previous background starts a pick. At least
one rising sample must reach internal level 6. Missing observations and time
gaps reset the pick; repeated timestamps cannot advance it. A pick expires
after eight updates without a change in the two raw PGA peaks.

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
Taiwan earthquake replay. Japan-specific magnitude output is not published.
Tests use explicitly labelled controlled boundary inputs, not fabricated live
observations, and verify successful computation, cleanup, settings and titles.
They do not establish real-event location/depth accuracy.
