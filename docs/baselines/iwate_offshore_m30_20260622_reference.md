# Iwate Northeast Offshore M3.4 Reference Event

- Truth source: Hi-net hypocenter, user-provided
- Origin time: `2026-06-22T08:28:23+08:00`
- Hypocenter: `40.392 N, 142.341 E`
- Region: `岩手県北東沖`
- Magnitude: `M3.4`
- Depth: `50.2 km`
- EQuake reference: final report 10, `2026-06-22T08:28:23+08:00`,
  `岩手県沖`, `40.38 N, 142.39 E`, `M3.0`, `22 km`
- EQuake quality: `A`, 80.8%, RMS 0.72 s, azimuthal gap 234 deg
- EQuake trigger summary: 52 stations (`P:4`, `S:38`, `O:10`)
- Maximum observed intensity: 0 (`-0.4`)
- Catalog status: Hi-net label linked
- Split status: `unassigned_reference`

The EQuake values are retained as a source-estimation reference and trigger
summary only. The benchmark truth for this case is the Hi-net hypocenter above.
This event remains outside frozen detection and source-estimation metrics until
its event-level split is reviewed.

## Capture

- Directory: `tmp/captures/iwate_offshore_m30_20260622_082823_multilayer`
- Window: `2026-06-22T09:27:53+09:00` to `2026-06-22T09:30:23+09:00`
- Timestamps: 151
- Layers: `jma/acmap/vcmap/dcmap` x surface/borehole
- GIF files: 1208/1208
- Failed files: 0
- Station-seconds: 246130
- Complete four-layer station-seconds: 190067 (77.2%)
- Decoder: `nied_gif_layered_v2`

Layer alignment report:
[`iwate_offshore_m30_20260622_multilayer_alignment.generated.md`](iwate_offshore_m30_20260622_multilayer_alignment.generated.md)

## Replay Diagnostics

- Legacy NIED detection adapter: candidate only, no confirmed event.
- Source-estimation trigger gate:
  `spatiotemporal_event_detector_v1_source_trigger`.
- Source-estimation trigger result: first candidate 26 s after origin, first
  confirmed 29 s after origin.
- Robust station trigger maximum: 41 triggered stations, 119 unique triggered
  stations, 1 unique triggered station within 50 km, 10 within 100 km and
  24 within 160 km.
- Network association maximum: largest connected component 22 stations,
  component diameter 232 km, trigger span 29 s.
- Local observability: within 50 km, maximum connected evidence is 1 station
  and does not satisfy candidate evidence; within 100 km, maximum connected
  evidence is 10 stations; within 160 km, maximum connected evidence is
  22 stations.
- Current estimator diagnostics against Hi-net truth after the P5 late-drift
  stability gate:
  `weighted_centroid_baseline` median/P90 error 90/228.4 km,
  `nied_gif_hybrid_v1` median/P90 error 24/54.4 km,
  `scratch_scan_v1` median/P90 error 538/538 km.
- Current `nied_gif_hybrid_v1` frame-to-frame jump median/P90 is 0/22 km.

This event has better near-offshore observability than the previous
Miyagi/Fukushima offshore case. Use it for trigger, geometry and multi-layer
diagnostics; do not move it into frozen metrics until split assignment is
reviewed.
