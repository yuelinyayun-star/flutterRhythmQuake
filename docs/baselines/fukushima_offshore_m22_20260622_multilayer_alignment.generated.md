# NIED Event Layer Alignment

- Window: `2026-06-22T15:36:26+09:00` to `2026-06-22T15:38:56+09:00`
- Decoder: `nied_gif_layered_v2`
- Timestamps: 151
- Stations: 1630
- Station-seconds: 246130
- Complete four-layer station-seconds: 237397 (96.5%)

| Layer | Decodable station-seconds |
|---|---:|
| `jma` | 237397 |
| `acmap` | 237397 |
| `vcmap` | 237397 |
| `dcmap` | 237397 |

| Pair | Station-seconds | Position MAE | Correlation |
|---|---:|---:|---:|
| `jma_vs_acmap` | 237397 | 0.0508 | 0.6255 |
| `jma_vs_vcmap` | 237397 | 0.0361 | 0.3716 |
| `jma_vs_dcmap` | 237397 | 0.0401 | 0.0210 |

The layers are distinct physical quantities and must not be treated as interchangeable even when their color positions correlate.
