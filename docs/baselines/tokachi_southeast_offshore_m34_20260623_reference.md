# Tokachi Southeast Offshore M3.4 Reference Event

- Truth source: Hi-net automatic hypocenter, user-provided preliminary reference
- Origin time: `2026-06-23T22:13:06+08:00`
- Hypocenter: `42.497 N, 143.647 E`
- Region: Tokachi southeast offshore (`十勝地方南東沖`)
- Magnitude: `M3.4`
- Depth: `55.5 km`
- Catalog status: `reference_only`; not JMA final catalog truth
- Split status: `unassigned_reference`

EQuake final report 11 is retained as source-estimation reference text only:
`2026-06-23T22:13:05+08:00`, Tokachi offshore, `42.49 N, 143.70 E`, M3.1,
depth 61 km, quality B 73.5%, RMS 0.75 s, azimuthal gap 155 deg, 54 triggered
stations (`P:9 S:33 O:12`) and 41 magnitude stations. The benchmark truth for
this case is the Hi-net hypocenter above.

This event remains outside frozen detection and source-estimation metrics until
event-level split assignment and final-catalog linking are reviewed.

## Capture

- Directory: `tmp/captures/tokachi_southeast_offshore_m34_20260623_221306_multilayer`
- Window: `2026-06-23T23:12:36+09:00` to `2026-06-23T23:15:06+09:00`
- Timestamps: 151
- Layers: `jma/acmap/vcmap/dcmap` x surface/borehole
- GIF files: 1208/1208
- Failed files: 0
- Station-seconds: 246130
- Complete four-layer station-seconds: 190363 (77.3%)
- Decoder: `nied_gif_layered_v2`

Layer alignment report:
[`tokachi_southeast_offshore_m34_20260623_multilayer_alignment.generated.md`](tokachi_southeast_offshore_m34_20260623_multilayer_alignment.generated.md)

Residual report:
[`tokachi_southeast_offshore_m34_residual_report.generated.md`](tokachi_southeast_offshore_m34_residual_report.generated.md)

Early-frame report:
[`tokachi_southeast_offshore_m34_early_frame_report.generated.md`](tokachi_southeast_offshore_m34_early_frame_report.generated.md)

## Replay Diagnostics

- Source-specific trigger: candidate at +16 s and confirmation at +19 s.
- Maximum source active stations: 62.
- Maximum decoded shindo: 1, matching the EQuake observed maximum shindo.
- Legacy NIED detection: candidate at +13 s and confirmation at +21 s.
- Robust station trigger maximum: 28 triggered stations and 70 unique
  triggered stations; 6/19/26 unique triggered stations within 50/100/160 km.
- Network association maximum: largest connected component 22 stations,
  component diameter 246 km and trigger span 34 s.
- Local maximum connected evidence: 6 stations within 50 km, 18 within 100 km
  and 22 within 160 km.
- Weighted centroid median/P90 error: 63/162 km.
- Current hybrid median/P90 error after the P5 late-drift stability gate:
  18/45 km.
- Current hybrid frame-to-frame jump median/P90: 0/22 km.
- At +20 s, weighted centroid/hybrid errors are 31/20 km.

## Residual Diagnostics

- Residual findings:
  `truth_has_worse_travel_time_fit_than_estimate`,
  `truth_has_worse_intensity_distance_rank` and
  `one_sided_boundary_worst_frame`.
- Estimate geometry distribution: 39 surrounded frames and 17 one-sided frames.
- Median/P90 azimuthal gap: 164.6/233.2 deg.
- Median/P90 horizontal uncertainty P90: 26/59.2 km.
- First estimate: 57 km error, surrounded geometry, 174.5 deg gap and 26 km
  P90 horizontal uncertainty.
- Largest jump: +20 s frame, 20 km error but 59 km frame-to-frame jump.
- Worst and final frame: 98 km error, one-sided boundary solution, 319.2 deg
  gap, nearest station 75.3 km and 187.9 km P90 horizontal uncertainty.
- Early-frame candidate promotion report: no diagnostic candidate frames were
  emitted. The first 10 frames keep the Hi-net truth inside the search box, and
  the hybrid estimate improves to 12-13 km by frames 8-10.

This event is a useful Hokkaido offshore positive case for the current hybrid
estimator: the main body of the event is localized much better than weighted
centroid. It also keeps a late one-sided boundary drift tail, so future
candidate-region or continuity changes must improve the final tail without
breaking the good early/mid-event estimates.
