# NIED Event Layer Alignment

- Window: `2026-06-24T13:24:15+09:00` to `2026-06-24T13:26:45+09:00`
- Decoder: `nied_gif_layered_v2`
- Timestamps: 151
- Stations: 1630
- Station-seconds: 246130
- Complete four-layer station-seconds: 237543 (96.5%)

| Layer | Decodable station-seconds |
|---|---:|
| `jma` | 237543 |
| `acmap` | 237543 |
| `vcmap` | 237543 |
| `dcmap` | 237543 |

| Pair | Station-seconds | Position MAE | Correlation |
|---|---:|---:|---:|
| `jma_vs_acmap` | 237543 | 0.0531 | 0.6142 |
| `jma_vs_vcmap` | 237543 | 0.0397 | 0.3875 |
| `jma_vs_dcmap` | 237543 | 0.0453 | 0.0090 |

The layers are distinct physical quantities and must not be treated as interchangeable even when their color positions correlate.
