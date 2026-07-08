# Tomakomai South Offshore M3.5 Reference Event

- Truth source: Hi-net automatic hypocenter, user-provided preliminary reference
- Origin time: `2026-06-22T19:37:47+08:00`
- Hypocenter: `42.063 N, 141.347 E`
- Region: Tomakomai south offshore (`苫小牧南方沖`)
- Magnitude: `M3.5`
- Depth: `100.0 km`
- Catalog status: `reference_only`; not JMA final catalog truth
- Split status: `unassigned_reference`

This event remains outside frozen detection and source-estimation metrics until
event-level split assignment and final-catalog linking are reviewed.

## Capture

- Directory: `tmp/captures/tomakomai_south_offshore_m35_20260622_193747_multilayer`
- Window: `2026-06-22T20:37:17+09:00` to `2026-06-22T20:39:47+09:00`
- Timestamps: 151
- Layers: `jma/acmap/vcmap/dcmap` x surface/borehole
- GIF files: 1208/1208
- Failed files: 0
- Station-seconds: 246130
- Complete four-layer station-seconds: 190089 (77.2%)
- Decoder: `nied_gif_layered_v2`

Layer alignment report:
[`tomakomai_south_offshore_m35_20260622_multilayer_alignment.generated.md`](tomakomai_south_offshore_m35_20260622_multilayer_alignment.generated.md)

Residual report:
[`tomakomai_south_offshore_m35_residual_report.generated.md`](tomakomai_south_offshore_m35_residual_report.generated.md)

## Replay Diagnostics

- Legacy NIED detection adapter: candidate only, no confirmed event.
- Source-estimation trigger gate:
  `spatiotemporal_event_detector_v1_source_trigger`.
- Source-estimation trigger result: first candidate 22 s and first confirmed
  29 s after origin.
- Robust station trigger maximum: 35 triggered stations and 74 unique
  triggered stations; 5/20/28 unique triggered stations within 50/100/160 km.
- Network association maximum: largest connected component 25 stations,
  component diameter 251 km and trigger span 23 s.
- Local observability maximum connected evidence: 5 stations within 50 km,
  19 within 100 km and 24 within 160 km.
- Current estimator diagnostics against the Hi-net reference after the P5
  late-drift stability gate:
  `weighted_centroid_baseline` median/P90 error 32/101.3 km,
  `nied_gif_hybrid_v1` median/P90 error 13/55 km and `scratch_scan_v1`
  median/P90 error 713/713 km.
- Current `nied_gif_hybrid_v1` frame-to-frame jump median/P90 is 0/27 km.

## Residual Diagnostics

- Countercase flags: `hybrid_one_sided_boundary_solution`,
  `hybrid_high_geometry_uncertainty` and `slow_first_estimate`.
- Large-error frames: 3/42; all three are covered by geometry risk.
- Worst frame: `2026-06-22T20:38:18.000`, 137 km error, 87 km jump,
  one-sided boundary geometry, 282.1 degree azimuth gap and P90 horizontal
  uncertainty 195.6 km.
- Residual report findings:
  `truth_has_worse_travel_time_fit_than_estimate` and
  `one_sided_boundary_worst_frame`.
- Final frame recovers to 7 km error with surrounded geometry and P90
  horizontal uncertainty 26 km.
- Offshore geometry experiment: `centroid_guard` improves this case's P90 from
  55 km to 31 km, but the same variant worsens other offshore references, so it
  remains an experiment rather than a production default.
- Narrow guard experiment:
  `centroid_guard_high_uncertainty` also improves this case from 55 km to
  31 km P90, preserves the Iwate M3.4 baseline P90, and keeps the Kushiro M3.0
  improvement from 118.2 km to 40 km. This is the better candidate for the next
  gated experiment.
- Diagnostic-only narrow guard:
  `centroid_guard_high_uncertainty_diagnostic` leaves this case's production
  estimate at the baseline 55 km P90 while emitting 3 candidate corrections.
  Those candidate corrections have 27.8 km median/P90 error against the
  preliminary Hi-net reference and `candidateAppliedFrameCount` remains 0.

This deep offshore Hokkaido event is useful as a high-depth reference case. The
source-specific trigger confirms the event with moderate delay, and the current
GIF hybrid estimator stays within 55 km P90 against the preliminary Hi-net
hypocenter. Because depth is 100 km and the label is not final-catalog verified,
do not use it to tighten shallow/offshore coordinate thresholds without a
separate final-catalog link.
