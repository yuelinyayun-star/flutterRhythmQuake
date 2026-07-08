# NIED Event Layer Alignment

- Window: `2026-06-25T19:21:19+09:00` to `2026-06-25T19:23:49+09:00`
- Decoder: `nied_gif_layered_v2`
- Timestamps: 151
- Stations: 1630
- Station-seconds: 246130
- Complete four-layer station-seconds: 237597 (96.5%)

| Layer | Decodable station-seconds |
|---|---:|
| `jma` | 237597 |
| `acmap` | 237597 |
| `vcmap` | 237597 |
| `dcmap` | 237597 |

| Pair | Station-seconds | Position MAE | Correlation |
|---|---:|---:|---:|
| `jma_vs_acmap` | 237597 | 0.0393 | 0.5478 |
| `jma_vs_vcmap` | 237597 | 0.0267 | 0.2617 |
| `jma_vs_dcmap` | 237597 | 0.0281 | 0.0560 |

The layers are distinct physical quantities and must not be treated as interchangeable even when their color positions correlate.
