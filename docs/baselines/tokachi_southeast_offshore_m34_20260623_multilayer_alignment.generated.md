# NIED Event Layer Alignment

- Window: `2026-06-23T23:12:36+09:00` to `2026-06-23T23:15:06+09:00`
- Decoder: `nied_gif_layered_v2`
- Timestamps: 151
- Stations: 1630
- Station-seconds: 246130
- Complete four-layer station-seconds: 237777 (96.6%)

| Layer | Decodable station-seconds |
|---|---:|
| `jma` | 237777 |
| `acmap` | 237777 |
| `vcmap` | 237777 |
| `dcmap` | 237777 |

| Pair | Station-seconds | Position MAE | Correlation |
|---|---:|---:|---:|
| `jma_vs_acmap` | 237777 | 0.0212 | 0.4846 |
| `jma_vs_vcmap` | 237777 | 0.0132 | 0.2707 |
| `jma_vs_dcmap` | 237777 | 0.0137 | 0.0660 |

The layers are distinct physical quantities and must not be treated as interchangeable even when their color positions correlate.
