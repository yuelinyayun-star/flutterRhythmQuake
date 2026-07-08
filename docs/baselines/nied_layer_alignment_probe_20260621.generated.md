# NIED Layer Alignment Probe

- Window: `2026-06-21T16:33:18+09:00` to `2026-06-21T16:33:18+09:00`
- Decoder: `nied_gif_layered_v2`
- Timestamps: 1
- Stations: 1630
- Station-seconds: 1630
- Complete four-layer station-seconds: 1574 (96.6%)

| Layer | Decodable station-seconds |
|---|---:|
| `jma` | 1574 |
| `acmap` | 1574 |
| `vcmap` | 1574 |
| `dcmap` | 1574 |

| Pair | Station-seconds | Position MAE | Correlation |
|---|---:|---:|---:|
| `jma_vs_acmap` | 1574 | 0.0391 | 0.5369 |
| `jma_vs_vcmap` | 1574 | 0.0238 | 0.1749 |
| `jma_vs_dcmap` | 1574 | 0.0240 | 0.0206 |

The layers are distinct physical quantities and must not be treated as interchangeable even when their color positions correlate.
