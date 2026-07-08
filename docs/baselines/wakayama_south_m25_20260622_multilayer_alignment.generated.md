# NIED Event Layer Alignment

- Window: `2026-06-22T09:50:47+09:00` to `2026-06-22T09:53:17+09:00`
- Decoder: `nied_gif_layered_v2`
- Timestamps: 151
- Stations: 1630
- Station-seconds: 246130
- Complete four-layer station-seconds: 237316 (96.4%)

| Layer | Decodable station-seconds |
|---|---:|
| `jma` | 237316 |
| `acmap` | 237316 |
| `vcmap` | 237316 |
| `dcmap` | 237316 |

| Pair | Station-seconds | Position MAE | Correlation |
|---|---:|---:|---:|
| `jma_vs_acmap` | 237316 | 0.0532 | 0.6377 |
| `jma_vs_vcmap` | 237316 | 0.0388 | 0.4215 |
| `jma_vs_dcmap` | 237316 | 0.0449 | 0.0059 |

The layers are distinct physical quantities and must not be treated as interchangeable even when their color positions correlate.
