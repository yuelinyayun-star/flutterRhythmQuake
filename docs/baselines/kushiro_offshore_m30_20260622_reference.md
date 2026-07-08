# Kushiro Offshore M3.0 JMA Reference Event

- Truth source: JMA source and intensity information
- Origin time: `2026-06-22T15:38:12+08:00`
- Hypocenter: `42.9 N, 144.0 E`
- Region: Kushiro offshore (`釧路沖`)
- Magnitude: `M3.0`
- Depth: `50 km`
- Maximum intensity: JMA shindo 1
- Tsunami: no concern
- Catalog status: JMA verified
- Split status: `unassigned_reference`

This event has an independent JMA source and intensity label. It remains
outside frozen metrics only until event-level split assignment is reviewed.

## Capture

- Directory: `tmp/captures/kushiro_offshore_m30_20260622_153812_multilayer`
- Window: `2026-06-22T16:37:42+09:00` to `2026-06-22T16:40:12+09:00`
- Timestamps: 151
- Layers: `jma/acmap/vcmap/dcmap` x surface/borehole
- GIF files: 1208/1208
- Failed files: 0
- Station-seconds: 246130
- Complete four-layer station-seconds: 190003 (77.2%)
- Decoder: `nied_gif_layered_v2`

Layer alignment report:
[`kushiro_offshore_m30_20260622_multilayer_alignment.generated.md`](kushiro_offshore_m30_20260622_multilayer_alignment.generated.md)

## Replay Diagnostics

- Source-specific trigger: candidate at +9 s and confirmation at +11 s after
  the compact core persists for two frames.
- Maximum source active stations: 60.
- Maximum decoded shindo: 1, matching the JMA maximum intensity.
- Legacy NIED detection: candidate at +2 s and confirmation at +9 s.
- Robust station trigger maximum: 38 triggered stations and 102 unique
  triggered stations; 8/21/28 unique triggered stations within 50/100/160 km.
- Network association maximum: 24 connected stations, 294 km component
  diameter and 30 s trigger span.
- Local maximum connected evidence: 8 stations within 50 km, 19 within 100 km
  and 24 within 160 km.
- Weighted centroid median/P90 error: 16.5/22.9 km.
- Current hybrid median/P90 error after the P5 late-drift stability gate:
  28/118.2 km.
- Current hybrid frame-to-frame jump median/P90: 3/30 km.
- At +20 s, weighted centroid/hybrid errors are 18/62 km.

This is a valid positive offshore/depth event. The source trigger has coherent
local support, unlike the Fukushima M2.2 false-association countercase. The
weighted centroid currently outperforms the hybrid estimator, so future
stability changes must preserve this case and suppress late hybrid drift.
