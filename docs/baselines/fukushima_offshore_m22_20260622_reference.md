# Fukushima Offshore M2.2 EQuake Reference Event

- Reference source: EQuake source-estimation report 4, user-provided
- Reference time: `2026-06-22T14:36:56+08:00`
- Reference hypocenter: `37.38 N, 141.27 E`
- Magnitude/depth: `M2.2`, `23 km`
- EQuake quality: C, 75%, RMS 0.2 s, azimuthal gap 281 degrees
- EQuake support: 5 magnitude stations; 12 triggers (`P:1/S:8/O:3`)
- Catalog status: `reference_only`; not Hi-net or JMA catalog truth
- Split status: `unassigned_reference`

The EQuake coordinates are retained for prompt capture and diagnostics only.
They must not enter frozen error metrics until linked to an independent catalog.

## Capture

- Directory: `tmp/captures/fukushima_offshore_m22_20260622_143656_multilayer`
- Window: `2026-06-22T15:36:26+09:00` to `2026-06-22T15:38:56+09:00`
- Timestamps: 151
- Layers: `jma/acmap/vcmap/dcmap` x surface/borehole
- GIF files: 1208/1208
- Failed files: 0
- Station-seconds: 246130
- Complete four-layer station-seconds: 189991 (77.2%)
- Decoder: `nied_gif_layered_v2`

Layer alignment report:
[`fukushima_offshore_m22_20260622_multilayer_alignment.generated.md`](fukushima_offshore_m22_20260622_multilayer_alignment.generated.md)

## Replay Diagnostics

- Legacy NIED detection adapter: candidate at +21 s, no confirmation.
- Source-specific trigger: candidate at +49 s, no confirmation.
- The 145-161 km chain fails the 120 km initial compact-core gate and is
  rejected at +57 s after eight candidate frames.
- Rejected member stations remain quarantined until they leave the triggered
  state, preventing the same chain from rearming as a smaller subset.
- Source trigger maximum: 14 active stations.
- Robust station trigger maximum: 19 triggered stations and 77 unique
  triggered stations; only 1/4/7 unique triggered stations are within
  50/100/160 km of the EQuake reference.
- Network association maximum: 7 connected stations, 161 km component
  diameter and 22 s trigger span.
- Local observability maximum connected evidence: 1 station within 50 km and
  3 stations within both 100 km and 160 km. No local radius reaches candidate
  or confirmed evidence thresholds.
- Source estimates after the new gate: 0.

The false association is now rejected before source estimation. Keep this case
as a regression counterexample for compact-core persistence and rejected-member
quarantine.
