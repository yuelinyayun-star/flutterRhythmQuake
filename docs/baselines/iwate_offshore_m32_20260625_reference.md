# Iwate Offshore M3.2 JMA Reference Event

- Truth source: JMA source and intensity information, user-provided
- Origin time: `2026-06-25T18:21:49+08:00`
- JST time: `2026-06-25T19:21:49+09:00`
- Hypocenter: `39.7 N, 142.1 E`
- Region: Iwate offshore (`岩手県沖`)
- Magnitude: `M3.2`
- Depth: `50 km`
- Maximum intensity: JMA shindo 1
- Tsunami: no concern
- Catalog status: JMA verified, user-provided
- Split status: `unassigned_reference`
- EQuake reference: final report 14, `2026-06-25T18:21:43+08:00`,
  `岩手県沖`, `39.65 N, 142.08 E`, `M3.5`, `36 km`
- EQuake quality: `A`, 82.6%, RMS 1.18 s, azimuthal gap 224 deg
- EQuake trigger summary: 89 stations (`P:27`, `S:50`, `O:12`)
- EQuake observed/estimated maximum intensity: observed shindo 1 (`1.4`),
  estimated shindo 2 (`1.5` to `2.4`)

This event has an independent JMA source and intensity label and a complete
local NIED multi-layer replay package. It remains outside frozen detection and
source-estimation metrics until event-level split assignment is reviewed.

The EQuake values are retained as source-estimation reference text and trigger
summary only. The benchmark truth for this case remains the JMA source and
intensity label above.

## Capture

- Directory: `tmp/captures/iwate_offshore_m32_20260625_182149_multilayer`
- Window: `2026-06-25T19:21:19+09:00` to
  `2026-06-25T19:23:49+09:00`
- Timestamps: 151
- Layers: `jma/acmap/vcmap/dcmap` x surface/borehole
- GIF files: 1208/1208
- Failed files: 0
- Station-seconds: 246130
- Complete four-layer station-seconds: 190183 (77.3%)
- Decoder: `nied_gif_layered_v2`

Layer alignment report:
[`iwate_offshore_m32_20260625_multilayer_alignment.generated.md`](iwate_offshore_m32_20260625_multilayer_alignment.generated.md)

Member-evolution report:
[`iwate_offshore_m32_20260625_member_evolution.generated.md`](iwate_offshore_m32_20260625_member_evolution.generated.md)

## Replay Diagnostics

- Source-specific trigger candidate/confirmation: +7/+8 s.
- Maximum source active stations: 103.
- Maximum decoded shindo: 1, matching the JMA maximum intensity.
- `weighted_centroid_baseline` median/P90 error: 63.5/86 km.
- `nied_gif_hybrid_v1` median/P90 error: 25/66 km.
- `nied_gif_hybrid_v1` frame-to-frame jump median/P90: 2/24.8 km.
- `nied_gif_hybrid_v1` error at +10/+20 s: 123/26 km.
- Early-frame diagnostics show one-sided boundary geometry in frames 1-3:
  baseline errors are 144/123/123 km, while diagnostic candidate errors are
  23.8/29.1/30.0 km. The candidate is still diagnostic-only and does not
  replace production coordinates.
- Member-evolution diagnostics show an important contrast with the
  Fukushima/Miyagi false candidate: the initial Iwate source members are local
  to the JMA truth, with member-centroid distance about 29 km and truth inside
  the estimator search box. Fukushima/Miyagi's first estimate starts with a
  member-centroid distance about 138 km and truth outside the search box.
- Candidate-region tracker refresh: the first three candidate frames remain
  rejected by the rank/attenuation residual gate, then the pending region is
  recovered by diagnostic local member support at `2026-06-25T19:22:00 JST`.
  The recovery uses member-count growth from 6 to 11, estimate-to-member
  distance shrinking from 156.5 km to 19.1 km, 137.4 km convergence and
  `surrounded` geometry. Production coordinate switching remains disabled.

## Notes

- User-provided JMA text:
  `岩手県沖`, `39.7N, 142.1E`, `M3.2`, depth `50 km`, maximum shindo 1,
  origin `2026-06-25 18:21:49 UTC+8`.
- User-provided EQuake final report 14:
  `岩手県沖`, `39.65N, 142.08E`, `M3.5`, depth `36 km`, quality `A`,
  confidence `82.6%`, RMS `1.18 s`, azimuthal gap `224 deg`, 89 triggered
  stations (`P:27`, `S:50`, `O:12`), 68 magnitude stations, observed maximum
  shindo 1 (`1.4`) and estimated maximum shindo 2 (`1.5` to `2.4`).
- Other information: `この地震による津波の心配はありません。`
- Next action: add this event to the late one-sided offshore reliability
  comparison with Tokachi, Kushiro and Tomakomai. The important regression
  target is to preserve the good +20 s hybrid estimate while exposing or
  delaying the better early diagnostic candidate region. Local member support
  remains metadata-only until the wider offshore replay set is reviewed.
