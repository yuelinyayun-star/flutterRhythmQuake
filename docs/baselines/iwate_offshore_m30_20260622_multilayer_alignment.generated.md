# NIED Event Layer Alignment

- Window: `2026-06-22T09:27:53+09:00` to `2026-06-22T09:30:23+09:00`
- Decoder: `nied_gif_layered_v2`
- Timestamps: 151
- Stations: 1630
- Station-seconds: 246130
- Complete four-layer station-seconds: 237476 (96.5%)

| Layer | Decodable station-seconds |
|---|---:|
| `jma` | 237476 |
| `acmap` | 237476 |
| `vcmap` | 237476 |
| `dcmap` | 237476 |

| Pair | Station-seconds | Position MAE | Correlation |
|---|---:|---:|---:|
| `jma_vs_acmap` | 237476 | 0.0531 | 0.6395 |
| `jma_vs_vcmap` | 237476 | 0.0400 | 0.4135 |
| `jma_vs_dcmap` | 237476 | 0.0463 | 0.0074 |

The layers are distinct physical quantities and must not be treated as interchangeable even when their color positions correlate.
