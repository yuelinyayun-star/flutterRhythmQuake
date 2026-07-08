# Fukushima Aizu Residual Report

Generated from `.dart_tool\source_estimation_benchmark\20260624_fukushima_aizu_m32_jma_eq5.reference.json`.
No production estimator weights are changed by this report.

- Case: `20260624_fukushima_aizu_m32_jma_eq5`
- Method: `nied_gif_hybrid_v1`
- Estimate frames: 61
- Findings: `truth_has_worse_travel_time_fit_than_estimate`

## Selected Frames

| Frame | Time | Error | Candidate | Jump | Pick count | Estimate RMS | Candidate RMS | Truth RMS | Estimate rank inv. | Candidate rank inv. | Truth rank inv. | Median dist est/cand/truth | Geometry |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `first` | 2026-06-24T13:24:54.000 | 1.0 km | - | - | 6 | 1.3 s | - | 1.2 s | 36% | - | 43% | 23.7 km / - / 23.8 km | surrounded; gap 152.6 deg; nearest 10.9 km; margin 0.7 deg; inner; P90u 26.0 km |
| `worst` | 2026-06-24T13:25:35.000 | 28.0 km | - | 3.0 km | 6 | 4.3 s | - | 8.2 s | 8% | - | 23% | 70.6 km / - / 63.7 km | surrounded; gap 127.8 deg; nearest 41.6 km; margin 1.1 deg; inner; P90u 26.0 km |
| `largest_jump` | 2026-06-24T13:25:36.000 | 12.0 km | - | 39.0 km | 6 | 1.7 s | - | 1.8 s | 77% | - | 77% | 65.1 km / - / 66.8 km | surrounded; gap 123.0 deg; nearest 59.4 km; margin 1.4 deg; inner; P90u 26.0 km |
| `final` | 2026-06-24T13:25:54.000 | 16.0 km | - | 0.0 km | 6 | 1.6 s | - | 3.8 s | 87% | - | 80% | 132.2 km / - / 136.5 km | surrounded; gap 135.5 deg; nearest 114.5 km; margin 1.4 deg; inner; P90u 43.9 km |

## `first` Picks

| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `FKSH07` | 0.0 s | 0.0 s / +0.0 s | 0.0 s / +0.0 s | 10.9 km / 10.2 km | 191.3 deg / 192.3 deg | -0.3 |
| `FKS027` | 2.0 s | 3.8 s / -1.8 s | 3.9 s / -1.9 s | 25.3 km / 25.1 km | 99.2 deg / 97.5 deg | 0.4 |
| `FKS028` | 3.0 s | 3.0 s / +0.0 s | 3.3 s / -0.3 s | 22.2 km / 22.9 km | 351.3 deg / 351.5 deg | 0.0 |
| `FKSH06` | 3.0 s | 0.5 s / +2.5 s | 0.8 s / +2.2 s | 12.9 km / 13.3 km | 55.6 deg / 52.9 deg | -1.3 |
| `FKSH21` | 4.0 s | 4.3 s / -0.3 s | 4.7 s / -0.7 s | 27.2 km / 28.0 km | 344.0 deg / 344.4 deg | -1.7 |
| `TCGH07` | 4.0 s | 3.8 s / +0.2 s | 3.8 s / +0.2 s | 25.5 km / 24.7 km | 169.2 deg / 168.9 deg | -1.3 |

## `worst` Picks

| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `FKSH10` | 0.0 s | 3.9 s / -3.9 s | 0.0 s / +0.0 s | 56.5 km / 61.8 km | 110.6 deg / 83.4 deg | -1.0 |
| `NIGH07` | 9.0 s | 0.0 s / +9.0 s | 0.6 s / +8.4 s | 41.6 km / 64.1 km | 330.2 deg / 349.0 deg | -1.7 |
| `NIG023` | 10.0 s | 10.9 s / -0.9 s | 1.3 s / +8.7 s | 83.0 km / 66.8 km | 244.2 deg / 261.9 deg | -2.0 |
| `TCG001` | 10.0 s | 7.0 s / +3.0 s | 0.3 s / +9.7 s | 68.3 km / 63.1 km | 130.3 deg / 105.8 deg | -1.8 |
| `NIGH19` | 10.0 s | 11.8 s / -1.8 s | 0.4 s / +9.6 s | 86.3 km / 63.4 km | 227.2 deg / 239.8 deg | -2.0 |
| `TCGH19` | 10.0 s | 8.2 s / +1.8 s | 1.3 s / +8.7 s | 73.0 km / 66.8 km | 131.4 deg / 108.6 deg | -1.8 |

## `largest_jump` Picks

| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `NIG023` | 0.0 s | 2.2 s / -2.2 s | 1.0 s / -1.0 s | 67.7 km / 66.8 km | 272.3 deg / 261.9 deg | -2.0 |
| `TCG001` | 0.0 s | 0.0 s / +0.0 s | 0.0 s / +0.0 s | 59.4 km / 63.1 km | 95.0 deg / 105.8 deg | -1.8 |
| `NIGH19` | 0.0 s | 0.0 s / -0.0 s | 0.1 s / -0.1 s | 59.6 km / 63.4 km | 250.6 deg / 239.8 deg | -2.0 |
| `TCGH19` | 0.0 s | 0.8 s / -0.8 s | 1.0 s / -1.0 s | 62.5 km / 66.8 km | 98.5 deg / 108.6 deg | -1.8 |
| `TCGH13` | 1.0 s | 3.7 s / -2.7 s | 4.5 s / -3.5 s | 73.6 km / 80.2 km | 112.7 deg / 120.2 deg | -1.6 |
| `IBRH12` | 4.0 s | 5.9 s / -1.9 s | 6.2 s / -2.2 s | 82.0 km / 86.7 km | 101.8 deg / 109.5 deg | -1.4 |

## `final` Picks

| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `FKSH12` | 0.0 s | 0.0 s / +0.0 s | 0.0 s / +0.0 s | 114.5 km / 104.5 km | 75.8 deg / 82.5 deg | -1.4 |
| `NIG004` | 3.0 s | 4.5 s / -1.5 s | 6.0 s / -3.0 s | 131.5 km / 127.3 km | 316.1 deg / 309.3 deg | -1.3 |
| `IBRH17` | 3.0 s | 4.8 s / -1.8 s | 9.1 s / -6.1 s | 132.8 km / 139.1 km | 137.5 deg / 143.8 deg | -0.8 |
| `IBR013` | 5.0 s | 6.3 s / -1.3 s | 10.1 s / -5.1 s | 138.3 km / 142.8 km | 130.4 deg / 136.8 deg | -0.6 |
| `NIG027` | 5.0 s | 3.9 s / +1.1 s | 8.5 s / -3.5 s | 129.3 km / 136.8 km | 273.0 deg / 266.9 deg | -1.6 |
| `IBRH18` | 8.0 s | 5.3 s / +2.7 s | 8.3 s / -0.3 s | 134.5 km / 136.1 km | 119.8 deg / 126.6 deg | -1.1 |
