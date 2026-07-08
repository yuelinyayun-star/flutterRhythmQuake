# NIED Event Layer Alignment

- Window: `2026-06-22T11:26:20+09:00` to `2026-06-22T11:28:50+09:00`
- Decoder: `nied_gif_layered_v2`
- Timestamps: 151
- Stations: 1630
- Station-seconds: 246130
- Complete four-layer station-seconds: 237286 (96.4%)

| Layer | Decodable station-seconds |
|---|---:|
| `jma` | 237286 |
| `acmap` | 237286 |
| `vcmap` | 237286 |
| `dcmap` | 237286 |

| Pair | Station-seconds | Position MAE | Correlation |
|---|---:|---:|---:|
| `jma_vs_acmap` | 237286 | 0.0511 | 0.6483 |
| `jma_vs_vcmap` | 237286 | 0.0372 | 0.4117 |
| `jma_vs_dcmap` | 237286 | 0.0426 | 0.0205 |

The layers are distinct physical quantities and must not be treated as interchangeable even when their color positions correlate.
