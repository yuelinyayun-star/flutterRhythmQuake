# NIED Event Layer Alignment

- Window: `2026-06-22T20:37:17+09:00` to `2026-06-22T20:39:47+09:00`
- Decoder: `nied_gif_layered_v2`
- Timestamps: 151
- Stations: 1630
- Station-seconds: 246130
- Complete four-layer station-seconds: 237503 (96.5%)

| Layer | Decodable station-seconds |
|---|---:|
| `jma` | 237503 |
| `acmap` | 237503 |
| `vcmap` | 237503 |
| `dcmap` | 237503 |

| Pair | Station-seconds | Position MAE | Correlation |
|---|---:|---:|---:|
| `jma_vs_acmap` | 237503 | 0.0306 | 0.5234 |
| `jma_vs_vcmap` | 237503 | 0.0188 | 0.2716 |
| `jma_vs_dcmap` | 237503 | 0.0197 | 0.0316 |

The layers are distinct physical quantities and must not be treated as interchangeable even when their color positions correlate.
