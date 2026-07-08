# Iwate East Offshore M3.0 Reference Event

- Truth source: Hi-net automatic hypocenter, user-provided preliminary reference
- Origin time: `2026-06-22T10:26:50+08:00`
- Hypocenter: `39.910 N, 142.347 E`
- Region: Iwate east offshore (`岩手県東方沖`)
- Magnitude: `M3.0`
- Depth: `42.4 km`
- Catalog status: `reference_only`; not JMA final catalog truth
- Split status: `unassigned_reference`

This event remains outside frozen detection and source-estimation metrics until
event-level split assignment and final-catalog linking are reviewed.

## Capture

- Directory: `tmp/captures/iwate_east_offshore_m30_20260622_102650_multilayer`
- Window: `2026-06-22T11:26:20+09:00` to `2026-06-22T11:28:50+09:00`
- Timestamps: 151
- Layers: `jma/acmap/vcmap/dcmap` x surface/borehole
- GIF files: 1208/1208
- Failed files: 0
- Station-seconds: 246130
- Complete four-layer station-seconds: 189782 (77.1%)
- Decoder: `nied_gif_layered_v2`

Layer alignment report:
[`iwate_east_offshore_m30_20260622_multilayer_alignment.generated.md`](iwate_east_offshore_m30_20260622_multilayer_alignment.generated.md)

## Replay Diagnostics

- Legacy NIED detection adapter: candidate only, no confirmed event.
- Source-estimation trigger gate:
  `spatiotemporal_event_detector_v1_source_trigger`.
- Source-estimation trigger result: first candidate 15 s and first confirmed
  18 s after origin.
- Robust station trigger maximum: 33 triggered stations and 100 unique
  triggered stations; 4/15/20 unique triggered stations within 50/100/160 km.
- Network association maximum: largest connected component 18 stations,
  component diameter 207 km and trigger span 27 s.
- Local observability maximum connected evidence: 4 stations within 50 km,
  14 within 100 km and 18 within 160 km.
- Current estimator median/P90 errors against the Hi-net reference after the
  P5 late-drift stability gate:
  `weighted_centroid_baseline` 65/201.4 km,
  `nied_gif_hybrid_v1` 40/51.0 km and `scratch_scan_v1` 478/484 km.
- Current `nied_gif_hybrid_v1` frame-to-frame jump median/P90 is
  0/16.3 km.

This offshore event confirms that source-specific triggering can obtain local
network support without relying on legacy confirmation. It was the primary
late-frame drift countercase before P5; the stability gate now suppresses the
tail jump, but the event remains outside production accuracy claims until split
assignment and more offshore validation cases are reviewed.
