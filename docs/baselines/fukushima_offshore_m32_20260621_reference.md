# Miyagi Southeast Offshore M3.2 Reference Event

- Truth source: Hi-net hypocenter, user-provided
- Origin time: `2026-06-21T22:41:12+08:00`
- Hypocenter: `37.616 N, 142.279 E`
- Region: `宮城県南東沖`
- Magnitude: `M3.2`
- Depth: `29.8 km`
- EQuake reference: final report 6, `2026-06-21T22:41:08+08:00`,
  `福島県沖`, `37.66 N, 142.47 E`, `M3.2`, `30 km`
- EQuake quality: `B`, 78.1%, RMS 0.8 s, azimuthal gap 263 deg
- EQuake trigger summary: 35 stations (`P:0`, `S:29`, `O:6`)
- Maximum observed intensity: 0 (`-0.9`)
- Catalog status: Hi-net label linked
- Split status: `unassigned_reference`

The EQuake values are retained as a source-estimation reference and trigger
summary only. The benchmark truth for this case is the Hi-net hypocenter above.
This event remains outside frozen detection and source-estimation metrics until
its event-level split is reviewed.

## Capture

- Directory: `tmp/captures/fukushima_offshore_m32_20260621_224108_multilayer`
- Window: `2026-06-21T23:40:38+09:00` to `2026-06-21T23:43:08+09:00`
- Timestamps: 151
- Layers: `jma/acmap/vcmap/dcmap` x surface/borehole
- GIF files: 1208/1208
- Failed files: 0
- Station-seconds: 246130
- Complete four-layer station-seconds: 190062 (77.2%)
- Decoder: `nied_gif_layered_v2`

Layer alignment report:
[`fukushima_offshore_m32_20260621_multilayer_alignment.generated.md`](fukushima_offshore_m32_20260621_multilayer_alignment.generated.md)

## Replay Diagnostics

- Legacy NIED detection adapter: candidate only, no confirmed event.
- Source-estimation trigger gate:
  `spatiotemporal_event_detector_v1_source_trigger`.
- Source-estimation trigger result: first candidate at +37 s and first
  confirmed at +38 s after the Hi-net origin time.
- Robust station trigger maximum: 20 triggered stations, 51 unique triggered
  stations, 15 unique triggered stations within 160 km.
- Network association maximum: largest connected component 15 stations,
  component diameter 197 km, trigger span 27 s.
- Local observability: no triggered stations within 50 km or 100 km of the
  Hi-net hypocenter; within 160 km, maximum connected evidence is 14 stations.
- Current estimator diagnostics against Hi-net truth after the P5 late-drift
  stability gate:
  `weighted_centroid_baseline` median/P90 error 132/322 km,
  `nied_gif_hybrid_v1` median/P90 error 165/354 km,
  `scratch_scan_v1` median/P90 error 236/236 km.
- Current `nied_gif_hybrid_v1` frame-to-frame jump median/P90 is 0/41 km.

This offshore geometry is useful for trigger/observability validation, but must
not be used to hand-tune source weights. The large error is consistent with weak
near-source station coverage and the current land-biased estimator assumptions.
Unlike the Iwate and Wakayama cases, P5 stability does not solve the absolute
location error here. This remains the main offshore geometry failure case for
the next algorithm step.
