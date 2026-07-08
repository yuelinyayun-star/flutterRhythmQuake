# Kushiro offshore Residual Report

Generated from `.dart_tool/source_estimation_benchmark/20260622_kushiro_offshore_m30_jma.reference.json`.
No production estimator weights are changed by this report.

- Case: `20260622_kushiro_offshore_m30_jma`
- Method: `nied_gif_hybrid_v1`
- Estimate frames: 42
- Findings: `one_sided_boundary_worst_frame`

## Selected Frames

| Frame | Time | Error | Candidate | Jump | Pick count | Estimate RMS | Candidate RMS | Truth RMS | Estimate rank inv. | Candidate rank inv. | Truth rank inv. | Median dist est/cand/truth | Geometry |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `first` | 2026-06-22T16:38:23.000 | 102.0 km | 10.6 km (diagnostic) | - | 6 | 2.4 s | 4.2 s | 3.5 s | 53% | 60% | 80% | 109.6 km / 18.1 km / 19.2 km | one_sided; gap 326.5 deg; nearest 102.9 km; margin 0.0 deg; boundary; P90u 194.4 km |
| `worst` | 2026-06-22T16:38:30.000 | 139.0 km | 24.1 km (diagnostic) | 6.0 km | 6 | 2.5 s | 4.8 s | 3.5 s | 67% | 40% | 80% | 148.1 km / 20.8 km / 19.2 km | one_sided; gap 310.5 deg; nearest 141.6 km; margin -0.4 deg; boundary; P90u 242.3 km |
| `largest_jump` | 2026-06-22T16:38:28.000 | 136.0 km | 22.5 km (diagnostic) | 253.0 km | 6 | 2.5 s | 5.4 s | 3.5 s | 73% | 47% | 80% | 144.8 km / 16.8 km / 19.2 km | one_sided; gap 315.8 deg; nearest 138.3 km; margin -0.4 deg; boundary; P90u 248.9 km |
| `final` | 2026-06-22T16:39:04.000 | 33.0 km | - | 3.0 km | 6 | 5.3 s | - | 6.9 s | 21% | - | 36% | 111.2 km / - / 109.4 km | surrounded; gap 155.8 deg; nearest 82.6 km; margin 1.1 deg; inner; P90u 33.6 km |

## `first` Picks

| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `HKD086` | 0.0 s | 0.9 s / -0.9 s | 1.1 s / -1.1 s | 106.3 km / 12.6 km | 311.6 deg / 246.3 deg | 0.0 |
| `KSRH07` | 1.0 s | 1.8 s / -0.8 s | 7.6 s / -6.6 s | 109.5 km / 37.4 km | 338.0 deg / 45.3 deg | 1.1 |
| `KSRH09` | 1.0 s | 1.8 s / -0.8 s | 0.3 s / +0.7 s | 109.6 km / 9.6 km | 320.9 deg / 352.3 deg | -0.3 |
| `HKD091` | 4.0 s | 3.5 s / +0.5 s | 5.5 s / -1.5 s | 116.2 km / 29.6 km | 304.4 deg / 250.1 deg | -0.4 |
| `HKD085` | 5.0 s | 0.0 s / +5.0 s | 0.0 s / +5.0 s | 102.9 km / 8.6 km | 322.8 deg / 41.3 deg | -0.6 |
| `KSRH02` | 6.0 s | 3.1 s / +2.9 s | 4.5 s / +1.5 s | 114.8 km / 25.8 km | 329.8 deg / 22.7 deg | 0.8 |

## `worst` Picks

| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `HKD086` | 0.0 s | 0.0 s / +0.0 s | 1.1 s / -1.1 s | 141.6 km / 12.6 km | 323.6 deg / 246.3 deg | 0.0 |
| `KSRH07` | 1.0 s | 2.7 s / -1.7 s | 7.6 s / -6.6 s | 151.9 km / 37.4 km | 342.6 deg / 45.3 deg | 1.1 |
| `KSRH09` | 1.0 s | 1.7 s / -0.7 s | 0.3 s / +0.7 s | 148.0 km / 9.6 km | 330.2 deg / 352.3 deg | -0.3 |
| `HKD091` | 4.0 s | 1.7 s / +2.3 s | 5.5 s / -1.5 s | 148.2 km / 29.6 km | 317.4 deg / 250.1 deg | -0.4 |
| `HKD085` | 5.0 s | 0.1 s / +4.9 s | 0.0 s / +5.0 s | 142.0 km / 8.6 km | 332.0 deg / 41.3 deg | -0.6 |
| `KSRH02` | 6.0 s | 3.7 s / +2.3 s | 4.5 s / +1.5 s | 155.6 km / 25.8 km | 336.5 deg / 22.7 deg | 0.8 |

## `largest_jump` Picks

| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `HKD086` | 0.0 s | 0.0 s / +0.0 s | 1.1 s / -1.1 s | 138.3 km / 12.6 km | 325.5 deg / 246.3 deg | 0.0 |
| `KSRH07` | 1.0 s | 3.2 s / -2.2 s | 7.6 s / -6.6 s | 150.3 km / 37.4 km | 344.6 deg / 45.3 deg | 1.1 |
| `KSRH09` | 1.0 s | 1.8 s / -0.8 s | 0.3 s / +0.7 s | 145.3 km / 9.6 km | 332.1 deg / 352.3 deg | -0.3 |
| `HKD091` | 4.0 s | 1.6 s / +2.4 s | 5.5 s / -1.5 s | 144.4 km / 29.6 km | 319.0 deg / 250.1 deg | -0.4 |
| `HKD085` | 5.0 s | 0.3 s / +4.7 s | 0.0 s / +5.0 s | 139.3 km / 8.6 km | 334.0 deg / 41.3 deg | -0.6 |
| `KSRH02` | 6.0 s | 4.0 s / +2.0 s | 4.5 s / +1.5 s | 153.4 km / 25.8 km | 338.4 deg / 22.7 deg | 0.8 |

## `final` Picks

| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `NMRH02` | 0.0 s | 6.1 s / -6.1 s | 5.2 s / -5.2 s | 105.7 km / 116.3 km | 58.0 deg / 41.7 deg | -1.1 |
| `HKD099` | 9.0 s | 0.0 s / +9.0 s | 0.0 s / +9.0 s | 82.6 km / 96.4 km | 262.2 deg / 281.9 deg | -0.7 |
| `HKD103` | 9.0 s | 14.0 s / -5.0 s | 11.5 s / -2.5 s | 135.8 km / 140.2 km | 248.8 deg / 262.7 deg | -1.7 |
| `KSRH10` | 9.0 s | 5.3 s / +3.7 s | 0.2 s / +8.8 s | 103.0 km / 97.0 km | 87.7 deg / 68.9 deg | -1.2 |
| `HKD113` | 10.0 s | 11.0 s / -1.0 s | 1.6 s / +8.4 s | 124.6 km / 102.5 km | 200.6 deg / 213.4 deg | -1.7 |
| `HKD066` | 12.0 s | 9.0 s / +3.0 s | 7.5 s / +4.5 s | 116.7 km / 124.7 km | 62.2 deg / 46.8 deg | -0.9 |
