# Tokachi southeast offshore Residual Report

Generated from `.dart_tool/source_estimation_benchmark/20260623_tokachi_southeast_offshore_m34_hinet.reference.json`.
No production estimator weights are changed by this report.

- Case: `20260623_tokachi_southeast_offshore_m34_hinet`
- Method: `nied_gif_hybrid_v1`
- Estimate frames: 56
- Findings: `truth_has_worse_travel_time_fit_than_estimate`, `truth_has_worse_intensity_distance_rank`, `one_sided_boundary_worst_frame`

## Selected Frames

| Frame | Time | Error | Candidate | Jump | Pick count | Estimate RMS | Candidate RMS | Truth RMS | Estimate rank inv. | Candidate rank inv. | Truth rank inv. | Median dist est/cand/truth | Geometry |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `first` | 2026-06-23T23:13:25.000 | 57.0 km | - | - | 5 | 1.3 s | - | 4.4 s | 20% | - | 10% | 24.3 km / - / 43.3 km | surrounded; gap 174.5 deg; nearest 17.8 km; margin 0.7 deg; inner; P90u 26.0 km |
| `worst` | 2026-06-23T23:14:18.000 | 98.0 km | - | 38.0 km | 6 | 2.1 s | - | 2.9 s | 7% | - | 33% | 86.9 km / - / 170.3 km | one_sided; gap 319.2 deg; nearest 75.3 km; margin -0.2 deg; boundary; P90u 187.9 km |
| `largest_jump` | 2026-06-23T23:13:26.000 | 20.0 km | - | 59.0 km | 6 | 3.8 s | - | 4.4 s | 0% | - | 14% | 49.0 km / - / 39.9 km | one_sided; gap 240.8 deg; nearest 37.0 km; margin 0.6 deg; inner; P90u 58.8 km |
| `final` | 2026-06-23T23:14:20.000 | 98.0 km | - | 0.0 km | 6 | 2.1 s | - | 2.9 s | 7% | - | 33% | 86.9 km / - / 170.3 km | one_sided; gap 319.2 deg; nearest 75.3 km; margin -0.2 deg; boundary; P90u 187.9 km |

## `first` Picks

| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `TKCH07` | 0.0 s | 1.7 s / -1.7 s | 0.5 s / -0.5 s | 24.3 km / 36.5 km | 202.3 deg / 343.5 deg | -0.5 |
| `HKD091` | 1.0 s | 1.3 s / -0.3 s | 0.0 s / +1.0 s | 22.9 km / 34.7 km | 174.8 deg / 1.6 deg | -0.3 |
| `HKD092` | 1.0 s | 0.0 s / +1.0 s | 4.2 s / -3.2 s | 17.8 km / 50.6 km | 237.8 deg / 341.4 deg | -1.3 |
| `KSRH08` | 2.0 s | 2.3 s / -0.3 s | 11.0 s / -9.0 s | 26.7 km / 76.4 km | 52.3 deg / 15.2 deg | -2.0 |
| `HKD086` | 4.0 s | 2.0 s / +2.0 s | 2.3 s / +1.7 s | 25.5 km / 43.3 km | 134.1 deg / 23.4 deg | -1.7 |

## `worst` Picks

| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `HKD071` | 0.0 s | 2.7 s / -2.7 s | 0.0 s / +0.0 s | 85.5 km / 154.9 km | 93.2 deg / 57.6 deg | -1.2 |
| `NMRH02` | 2.0 s | 0.0 s / +2.0 s | 3.8 s / -1.8 s | 75.3 km / 169.2 km | 53.8 deg / 38.7 deg | -1.1 |
| `HKD070` | 4.0 s | 3.3 s / +0.7 s | 2.9 s / +1.1 s | 87.9 km / 165.9 km | 82.0 deg / 52.9 deg | -1.6 |
| `HKD066` | 5.0 s | 2.8 s / +2.2 s | 5.8 s / -0.8 s | 85.8 km / 176.9 km | 60.0 deg / 42.4 deg | -1.5 |
| `HKD072` | 11.0 s | 8.3 s / +2.7 s | 4.3 s / +6.7 s | 106.9 km / 171.3 km | 94.6 deg / 62.4 deg | -2.0 |
| `HKD074` | 13.0 s | 14.3 s / -1.3 s | 12.0 s / +1.0 s | 129.5 km / 200.4 km | 85.1 deg / 60.4 deg | -1.7 |

## `largest_jump` Picks

| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `TKCH07` | 0.0 s | 1.9 s / -1.9 s | 0.5 s / -0.5 s | 44.0 km / 36.5 km | 317.2 deg / 343.5 deg | -0.4 |
| `HKD091` | 1.0 s | 0.0 s / +1.0 s | 0.0 s / +1.0 s | 37.0 km / 34.7 km | 329.8 deg / 1.6 deg | -0.3 |
| `HKD092` | 1.0 s | 5.4 s / -4.4 s | 4.2 s / -3.2 s | 57.7 km / 50.6 km | 321.8 deg / 341.4 deg | -1.3 |
| `KSRH08` | 2.0 s | 9.0 s / -7.0 s | 11.0 s / -9.0 s | 71.0 km / 76.4 km | 0.4 deg / 15.2 deg | -2.0 |
| `HKD086` | 4.0 s | 0.0 s / +4.0 s | 2.3 s / +1.7 s | 37.1 km / 43.3 km | 356.3 deg / 23.4 deg | -0.4 |
| `HKD100` | 5.0 s | 4.5 s / +0.5 s | 0.4 s / +4.6 s | 54.0 km / 36.1 km | 241.2 deg / 229.7 deg | -0.6 |

## `final` Picks

| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `HKD071` | 0.0 s | 2.7 s / -2.7 s | 0.0 s / +0.0 s | 85.5 km / 154.9 km | 93.2 deg / 57.6 deg | -1.2 |
| `NMRH02` | 2.0 s | 0.0 s / +2.0 s | 3.8 s / -1.8 s | 75.3 km / 169.2 km | 53.8 deg / 38.7 deg | -1.1 |
| `HKD070` | 4.0 s | 3.3 s / +0.7 s | 2.9 s / +1.1 s | 87.9 km / 165.9 km | 82.0 deg / 52.9 deg | -1.6 |
| `HKD066` | 5.0 s | 2.8 s / +2.2 s | 5.8 s / -0.8 s | 85.8 km / 176.9 km | 60.0 deg / 42.4 deg | -1.5 |
| `HKD072` | 11.0 s | 8.3 s / +2.7 s | 4.3 s / +6.7 s | 106.9 km / 171.3 km | 94.6 deg / 62.4 deg | -2.0 |
| `HKD074` | 13.0 s | 14.3 s / -1.3 s | 12.0 s / +1.0 s | 129.5 km / 200.4 km | 85.1 deg / 60.4 deg | -1.7 |
