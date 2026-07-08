# Fukushima Aizu M3.2 Reference Event

- Truth source: JMA source and intensity information, user-provided verified catalog text
- Origin time: `2026-06-24T12:24:45+08:00` (`2026-06-24T13:24:45+09:00`)
- Hypocenter: `37.1 N, 139.4 E`
- Region: Fukushima Aizu
- Magnitude: `M3.2`
- Depth: `10 km`
- Maximum shindo: `3`
- Catalog status: `JMA verified`
- Split status: `unassigned_reference`

EQuake reports 1-5 are retained as source-estimation progression reference text
only. The final EQuake report 5 is `2026-06-24T12:24:44+08:00`,
Fukushima Aizu, `37.05 N, 139.42 E`, M3.0, depth 4 km, observed maximum shindo
2 (1.7), estimated maximum shindo 2 (1.5-2.4), quality A 77.8%, RMS 0.58 s,
azimuthal gap 31 deg, 80 triggered stations (`P:22 S:41 O:17`) and 50
magnitude stations. The benchmark truth for this case is the JMA hypocenter
above.

This event remains outside frozen detection metrics until event-level split
assignment is reviewed.

## Capture

- Directory: `tmp/captures/fukushima_aizu_m32_20260624_122445_multilayer`
- Window: `2026-06-24T13:24:15+09:00` to `2026-06-24T13:26:45+09:00`
- Timestamps: 151
- Layers: `jma/acmap/vcmap/dcmap` x surface/borehole
- GIF files: 1208/1208
- Failed files: 0
- Stations: 1630
- Station-seconds: 246130
- Complete four-layer station-seconds: 190129 (77.2%)
- Decoder: `nied_gif_layered_v2`

Layer alignment report:
[`fukushima_aizu_m32_20260624_multilayer_alignment.generated.md`](fukushima_aizu_m32_20260624_multilayer_alignment.generated.md)

Residual report:
[`fukushima_aizu_m32_residual_report.generated.md`](fukushima_aizu_m32_residual_report.generated.md)

Early-frame report:
[`fukushima_aizu_m32_early_frame_report.generated.md`](fukushima_aizu_m32_early_frame_report.generated.md)

Member-evolution report:
[`fukushima_aizu_m32_member_evolution.generated.md`](fukushima_aizu_m32_member_evolution.generated.md)

## Replay Diagnostics

- Source-specific trigger: candidate at +7 s and confirmation at +9 s.
- Current hybrid first/median/P90/final error: 1 km / 9 km / 16 km / 16 km.
- Weighted centroid median error: 25 km.
- Scratch scan median error: 167 km.
- Early-frame report: first 10 estimates keep the JMA truth inside the search
  box, all with surrounded geometry and 26 km P90 horizontal uncertainty.
- Early-frame errors: 1 km on the first estimate, then 5-15 km through the
  first 10 estimate frames.
- Candidate promotion report: no diagnostic centroid-guard candidate frames
  were emitted for this case, which is expected because the baseline solution is
  already local and surrounded.
- Residual report finding:
  `truth_has_worse_travel_time_fit_than_estimate`. This does not imply the JMA
  truth is wrong; it means the current GIF threshold-arrival proxy is not a
  true P-wave pick and may prefer a slightly shifted local solution.
- Member evolution no longer reports a production `source_event_replacement`
  after the main event tail. A later raw candidate still appears around +95 s,
  but the source-trigger continuity gate holds it as
  `source_trigger_replacement_held` against the original event ID and the tail
  candidate later times out as rejected.

## Interpretation

This is the first captured JMA-verified inland shindo-3 event in the current
multilayer replay set. It is a positive control for the current hybrid
estimator: early localization is good, geometry is surrounded, and no
centroid-guard correction is needed. Its main remaining value is now testing
late-event stability and ensuring unrelated tail activity is retained as raw
diagnostic evidence rather than replacing the production source event.
