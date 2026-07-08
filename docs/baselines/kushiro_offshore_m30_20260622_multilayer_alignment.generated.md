# NIED Event Layer Alignment

- Window: `2026-06-22T16:37:42+09:00` to `2026-06-22T16:40:12+09:00`
- Decoder: `nied_gif_layered_v2`
- Timestamps: 151
- Stations: 1630
- Station-seconds: 246130
- Complete four-layer station-seconds: 237406 (96.5%)

| Layer | Decodable station-seconds |
|---|---:|
| `jma` | 237406 |
| `acmap` | 237406 |
| `vcmap` | 237406 |
| `dcmap` | 237406 |

| Pair | Station-seconds | Position MAE | Correlation |
|---|---:|---:|---:|
| `jma_vs_acmap` | 237406 | 0.0499 | 0.5967 |
| `jma_vs_vcmap` | 237406 | 0.0348 | 0.3567 |
| `jma_vs_dcmap` | 237406 | 0.0385 | 0.0213 |

The layers are distinct physical quantities and must not be treated as interchangeable even when their color positions correlate.
