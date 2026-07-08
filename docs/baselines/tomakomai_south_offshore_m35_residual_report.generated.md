# Tomakomai south offshore Residual Report

Generated from `.dart_tool/source_estimation_benchmark/20260622_tomakomai_south_offshore_m35_hinet.reference.json`.
No production estimator weights are changed by this report.

- Case: `20260622_tomakomai_south_offshore_m35_hinet`
- Method: `nied_gif_hybrid_v1`
- Estimate frames: 42
- Findings: `truth_has_worse_travel_time_fit_than_estimate`, `one_sided_boundary_worst_frame`

## Selected Frames

| Frame | Time | Error | Candidate | Jump | Pick count | Estimate RMS | Candidate RMS | Truth RMS | Estimate rank inv. | Candidate rank inv. | Truth rank inv. | Median dist est/cand/truth | Geometry |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `first` | 2026-06-22T20:38:16.000 | 55.0 km | - | - | 5 | 1.9 s | - | 6.9 s | 56% | - | 11% | 42.5 km / - / 45.4 km | one_sided; gap 203.3 deg; nearest 30.0 km; margin 0.7 deg; inner; P90u 46.8 km |
| `worst` | 2026-06-22T20:38:18.000 | 137.0 km | 27.8 km (diagnostic) | 87.0 km | 6 | 4.3 s | 9.6 s | 7.2 s | 46% | 0% | 8% | 117.0 km / 46.8 km / 46.7 km | one_sided; gap 282.1 deg; nearest 100.9 km; margin -0.4 deg; boundary; P90u 195.6 km |
| `largest_jump` | 2026-06-22T20:38:18.000 | 137.0 km | 27.8 km (diagnostic) | 87.0 km | 6 | 4.3 s | 9.6 s | 7.2 s | 46% | 0% | 8% | 117.0 km / 46.8 km / 46.7 km | one_sided; gap 282.1 deg; nearest 100.9 km; margin -0.4 deg; boundary; P90u 195.6 km |
| `final` | 2026-06-22T20:38:57.000 | 7.0 km | - | 0.0 km | 6 | 2.4 s | - | 2.8 s | 73% | - | 53% | 91.1 km / - / 93.7 km | surrounded; gap 167.7 deg; nearest 84.1 km; margin 1.0 deg; inner; P90u 26.0 km |

## `first` Picks

| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `HKD131` | 0.0 s | 1.5 s / -1.5 s | 3.9 s / -3.9 s | 35.8 km / 45.4 km | 55.8 deg / 331.2 deg | -1.7 |
| `HKD157` | 1.0 s | 3.3 s / -2.3 s | 1.4 s / -0.4 s | 42.5 km / 35.8 km | 150.9 deg / 240.8 deg | -0.9 |
| `IBUH06` | 1.0 s | 0.0 s / +1.0 s | 4.6 s / -3.6 s | 30.0 km / 48.1 km | 50.4 deg / 323.9 deg | -1.4 |
| `IBUH04` | 4.0 s | 3.9 s / +0.1 s | 14.4 s / -10.4 s | 44.9 km / 85.3 km | 354.2 deg / 319.2 deg | -2.0 |
| `HKD158` | 10.0 s | 7.1 s / +2.9 s | 0.0 s / +10.0 s | 56.9 km / 30.6 km | 142.2 deg / 214.0 deg | -0.9 |

## `worst` Picks

| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `HKD131` | 0.0 s | 5.1 s / -5.1 s | 3.9 s / -3.9 s | 120.3 km / 45.4 km | 71.7 deg / 331.2 deg | -1.7 |
| `HKD157` | 1.0 s | 1.8 s / -0.8 s | 1.4 s / -0.4 s | 107.7 km / 35.8 km | 100.5 deg / 240.8 deg | -0.9 |
| `IBUH06` | 1.0 s | 3.4 s / -2.4 s | 4.6 s / -3.6 s | 113.8 km / 48.1 km | 71.2 deg / 323.9 deg | -1.4 |
| `IBUH04` | 4.0 s | 0.0 s / +4.0 s | 14.4 s / -10.4 s | 100.9 km / 85.3 km | 52.2 deg / 319.2 deg | -2.0 |
| `HKD158` | 10.0 s | 5.9 s / +4.1 s | 0.0 s / +10.0 s | 123.2 km / 30.6 km | 102.8 deg / 214.0 deg | -0.9 |
| `AOM008` | 12.0 s | 18.6 s / -6.6 s | 20.7 s / -8.7 s | 171.6 km / 109.1 km | 130.1 deg / 184.0 deg | -2.0 |

## `largest_jump` Picks

| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `HKD131` | 0.0 s | 5.1 s / -5.1 s | 3.9 s / -3.9 s | 120.3 km / 45.4 km | 71.7 deg / 331.2 deg | -1.7 |
| `HKD157` | 1.0 s | 1.8 s / -0.8 s | 1.4 s / -0.4 s | 107.7 km / 35.8 km | 100.5 deg / 240.8 deg | -0.9 |
| `IBUH06` | 1.0 s | 3.4 s / -2.4 s | 4.6 s / -3.6 s | 113.8 km / 48.1 km | 71.2 deg / 323.9 deg | -1.4 |
| `IBUH04` | 4.0 s | 0.0 s / +4.0 s | 14.4 s / -10.4 s | 100.9 km / 85.3 km | 52.2 deg / 319.2 deg | -2.0 |
| `HKD158` | 10.0 s | 5.9 s / +4.1 s | 0.0 s / +10.0 s | 123.2 km / 30.6 km | 102.8 deg / 214.0 deg | -0.9 |
| `AOM008` | 12.0 s | 18.6 s / -6.6 s | 20.7 s / -8.7 s | 171.6 km / 109.1 km | 130.1 deg / 184.0 deg | -2.0 |

## `final` Picks

| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `AOM005` | 0.0 s | 0.3 s / -0.3 s | 0.8 s / -0.8 s | 85.1 km / 86.3 km | 192.9 deg / 188.3 deg | -1.6 |
| `AOM007` | 0.0 s | 3.4 s / -3.4 s | 4.2 s / -4.2 s | 97.1 km / 99.5 km | 182.0 deg / 178.2 deg | -1.5 |
| `HKD127` | 0.0 s | 3.7 s / -3.7 s | 3.9 s / -3.9 s | 98.1 km / 98.2 km | 19.2 deg / 23.1 deg | -0.8 |
| `HKD184` | 0.0 s | 0.1 s / -0.1 s | 0.0 s / +0.0 s | 84.5 km / 83.5 km | 9.8 deg / 14.4 deg | -0.9 |
| `HKD125` | 1.0 s | 3.9 s / -2.9 s | 4.6 s / -3.6 s | 99.0 km / 101.0 km | 35.8 deg / 39.5 deg | -1.4 |
| `HDKH06` | 1.0 s | 0.0 s / +1.0 s | 1.5 s / -0.5 s | 84.1 km / 89.1 km | 65.6 deg / 68.7 deg | -1.7 |
