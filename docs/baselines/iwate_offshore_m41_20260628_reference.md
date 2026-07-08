# Iwate Offshore M4.1 JMA Reference Event

- Truth source: JMA source and intensity information, user-provided
- Origin time: `2026-06-28T13:39:37+08:00`
- JST time: `2026-06-28T14:39:37+09:00`
- Hypocenter: `40.1 N, 142.4 E`
- Region: Iwate offshore (`岩手県沖`)
- Magnitude: `M4.1`
- Depth: `40 km`
- Maximum intensity: JMA shindo 1
- Tsunami: no concern
- Catalog status: JMA verified, user-provided
- Split status: `unassigned_reference`
- EQuake reference: final report 13, `2026-06-28T13:39:31+08:00`,
  `岩手県沖`, `40.14 N, 142.45 E`, `M4.0`, `22 km`
- EQuake quality: `A`, 80.5%, RMS 0.87 s, azimuthal gap 163 deg
- EQuake trigger summary: 196 stations (`P:87`, `S:83`, `O:26`)
- EQuake observed/estimated maximum intensity: observed shindo 1 (`1.2`),
  estimated shindo 2 (`1.5` to `2.4`)

This event now has an independent JMA source/intensity label and a complete
local NIED two-layer replay package. It remains outside frozen detection,
source-estimation and intensity metrics until event-level split assignment is
reviewed.

The EQuake values are retained as source-estimation reference text and trigger
summary only. The benchmark truth for this case remains the JMA source and
intensity label above.

## Capture

- Directory: `tmp/captures/20260628_iwate_offshore_m41_jma`
- Window: `2026-06-28T14:39:07+09:00` to
  `2026-06-28T14:41:37+09:00`
- Timestamps: 151
- Layers: `jma_s`, `jma_b`
- GIF files: 302/302
- Failed files: 0
- Decoder: `nied_gif_layered_v2`
- Sensor selection policy: `surface_jma_s_primary_v1`

This capture intentionally records only the two standard shindo GIF layers.
It must not be described as a multi-layer physical replay package.

## Notes

- User-provided JMA text:
  `岩手県沖`, `40.1N, 142.4E`, `M4.1`, depth `40 km`, maximum shindo 1,
  origin `2026-06-28 13:39:37 UTC+8`.
- User-provided EQuake final report 13:
  `岩手県沖`, `40.14N, 142.45E`, `M4.0`, depth `22 km`, quality `A`,
  confidence `80.5%`, RMS `0.87 s`, azimuthal gap `163 deg`, 196 triggered
  stations (`P:87`, `S:83`, `O:26`), 87 magnitude stations, observed maximum
  shindo 1 (`1.2`) and estimated maximum shindo 2 (`1.5` to `2.4`).
- Other information: `この地震による津波の心配はありません。`
- Capture rule applied: the event was still inside the public KMoni replay
  window, so local `jma_s/jma_b` GIF capture was completed before writing the
  reference record.
