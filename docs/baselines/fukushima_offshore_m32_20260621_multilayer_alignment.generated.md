# NIED Event Layer Alignment

- Window: `2026-06-21T23:40:38+09:00` to `2026-06-21T23:43:08+09:00`
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
| `jma_vs_acmap` | 237476 | 0.0188 | 0.4430 |
| `jma_vs_vcmap` | 237476 | 0.0108 | 0.2219 |
| `jma_vs_dcmap` | 237476 | 0.0105 | 0.0408 |

The layers are distinct physical quantities and must not be treated as interchangeable even when their color positions correlate.
