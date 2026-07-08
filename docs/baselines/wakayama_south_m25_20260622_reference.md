# Wakayama South M2.5 Reference Event

- Truth source: Hi-net hypocenter, user-provided
- Origin time: `2026-06-22T08:51:17+08:00`
- Hypocenter: `33.580 N, 135.791 E`
- Region: `和歌山県南部`
- Magnitude: `M2.5`
- Depth: `28.1 km`
- Catalog status: Hi-net label linked
- Split status: `unassigned_reference`

This event is a catalog-labeled small inland/near-coastal event. It remains
outside frozen detection and source-estimation metrics until event-level split
assignment is reviewed.

## Capture

- Directory: `tmp/captures/wakayama_south_m25_20260622_085117_multilayer`
- Window: `2026-06-22T09:50:47+09:00` to `2026-06-22T09:53:17+09:00`
- Timestamps: 151
- Layers: `jma/acmap/vcmap/dcmap` x surface/borehole
- GIF files: 1208/1208
- Failed files: 0
- Station-seconds: 246130
- Complete four-layer station-seconds: 189984 (77.2%)
- Decoder: `nied_gif_layered_v2`

Layer alignment report:
[`wakayama_south_m25_20260622_multilayer_alignment.generated.md`](wakayama_south_m25_20260622_multilayer_alignment.generated.md)

## Replay Diagnostics

- Legacy NIED detection adapter: candidate only, no confirmed event.
- Source-estimation trigger gate:
  `spatiotemporal_event_detector_v1_source_trigger`.
- Source-estimation trigger result: first candidate 15 s and first confirmed
  16 s after origin.
- Robust station trigger maximum: 31 triggered stations, 93 unique triggered
  stations, 10 unique triggered stations within 50 km, 15 within 100 km and
  18 within 160 km.
- Network association maximum: largest connected component 14 stations,
  component diameter 120 km, trigger span 26 s.
- Local observability: within 50 km, maximum connected evidence is 9 stations;
  within 100 km and 160 km, maximum connected evidence is 14 stations.
- Current estimator diagnostics against Hi-net truth after the P5 late-drift
  stability gate:
  `weighted_centroid_baseline` median/P90 error 30/386.6 km,
  `nied_gif_hybrid_v1` median/P90 error 5/6.8 km,
  `scratch_scan_v1` median/P90 error 111/112 km.
- Current `nied_gif_hybrid_v1` frame-to-frame jump median/P90 is 0/10.4 km.

This case has substantially better local station observability than the
offshore-only cases. The P5 stability gate suppresses the previous late-frame
drift on this case, but it remains outside frozen metrics until event-level
split assignment is reviewed.
