# NIED Event Layer Alignment

- Window: `2026-06-21T22:07:24+09:00` to `2026-06-21T22:09:54+09:00`
- Decoder: `nied_gif_layered_v2`
- Timestamps: 151
- Stations: 1630
- Station-seconds: 246130
- Complete four-layer station-seconds: 237451 (96.5%)

| Layer | Decodable station-seconds |
|---|---:|
| `jma` | 237451 |
| `acmap` | 237451 |
| `vcmap` | 237451 |
| `dcmap` | 237451 |

| Pair | Station-seconds | Position MAE | Correlation |
|---|---:|---:|---:|
| `jma_vs_acmap` | 237451 | 0.0217 | 0.4680 |
| `jma_vs_vcmap` | 237451 | 0.0129 | 0.2181 |
| `jma_vs_dcmap` | 237451 | 0.0126 | 0.0415 |

The layers are distinct physical quantities and must not be treated as interchangeable even when their color positions correlate.
