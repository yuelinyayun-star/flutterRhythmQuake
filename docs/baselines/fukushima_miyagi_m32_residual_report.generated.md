# Miyagi southeast offshore Residual Report

Generated from `.dart_tool/source_estimation_benchmark/20260621_fukushima_offshore_m32_eq6.reference.json`.
No production estimator weights are changed by this report.

- Case: `20260621_fukushima_offshore_m32_eq6`
- Method: `nied_gif_hybrid_v1`
- Estimate frames: 47
- Findings: `truth_has_worse_travel_time_fit_than_estimate`, `large_travel_time_residuals_even_at_estimate`, `truth_has_worse_intensity_distance_rank`, `one_sided_boundary_worst_frame`, `catastrophic_location_error`

## Selected Frames

| Frame | Time | Error | Candidate | Jump | Pick count | Estimate RMS | Candidate RMS | Truth RMS | Estimate rank inv. | Candidate rank inv. | Truth rank inv. | Median dist est/cand/truth | Geometry |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `first` | 2026-06-21T23:41:50.000 | 120.0 km | 138.1 km (diagnostic) | - | 5 | 1.6 s | 6.2 s | 7.8 s | 56% | 56% | 67% | 138.0 km / 36.5 km / 129.5 km | one_sided; gap 329.9 deg; nearest 113.5 km; margin -0.4 deg; boundary; P90u 240.2 km |
| `worst` | 2026-06-21T23:41:55.000 | 313.0 km | 131.1 km (diagnostic) | 3.0 km | 6 | 5.9 s | 14.9 s | 15.3 s | 29% | 50% | 71% | 167.8 km / 38.5 km / 154.9 km | one_sided; gap 306.3 deg; nearest 127.6 km; margin -0.4 deg; boundary; P90u 216.4 km |
| `largest_jump` | 2026-06-21T23:41:51.000 | 307.0 km | 136.7 km (diagnostic) | 278.0 km | 6 | 6.3 s | 14.2 s | 15.3 s | 29% | 43% | 71% | 160.7 km / 37.8 km / 154.9 km | one_sided; gap 304.2 deg; nearest 125.7 km; margin -0.4 deg; boundary; P90u 228.3 km |
| `final` | 2026-06-21T23:43:08.000 | 168.0 km | - | 0.0 km | 6 | 10.8 s | - | 12.4 s | 69% | - | 77% | 53.2 km / - / 153.3 km | one_sided; gap 188.2 deg; nearest 15.0 km; margin 1.0 deg; inner; P90u 43.0 km |

## `first` Picks

| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `MYGH07` | 0.0 s | 0.0 s / +0.0 s | 8.2 s / -8.2 s | 113.5 km / 156.9 km | 342.9 deg / 294.1 deg | -1.5 |
| `MYG014` | 5.0 s | 3.9 s / +1.1 s | 10.0 s / -5.0 s | 128.2 km / 163.8 km | 344.8 deg / 298.9 deg | -1.1 |
| `MYG008` | 9.0 s | 11.1 s / -2.1 s | 1.0 s / +8.0 s | 155.6 km / 129.5 km | 13.1 deg / 325.1 deg | -1.3 |
| `MYG010` | 9.0 s | 6.5 s / +2.5 s | 0.0 s / +9.0 s | 138.0 km / 125.7 km | 9.5 deg / 316.3 deg | -1.7 |
| `MYGH11` | 9.0 s | 9.2 s / -0.2 s | 1.0 s / +8.0 s | 148.4 km / 129.4 km | 10.8 deg / 320.9 deg | -1.1 |

## `worst` Picks

| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `MYG009` | 0.0 s | 9.0 s / -9.0 s | 7.2 s / -7.2 s | 161.7 km / 152.9 km | 138.7 deg / 307.6 deg | -1.0 |
| `IWT026` | 1.0 s | 0.0 s / +1.0 s | 22.0 s / -21.0 s | 127.6 km / 209.4 km | 104.1 deg / 331.0 deg | -1.1 |
| `MYGH07` | 12.0 s | 12.2 s / -0.2 s | 8.2 s / +3.8 s | 173.9 km / 156.9 km | 150.5 deg / 294.1 deg | -1.5 |
| `MYG014` | 17.0 s | 8.7 s / +8.3 s | 10.0 s / +7.0 s | 160.5 km / 163.8 km | 148.0 deg / 298.9 deg | -1.1 |
| `MYG008` | 21.0 s | 15.7 s / +5.3 s | 1.0 s / +20.0 s | 187.2 km / 129.5 km | 124.9 deg / 325.1 deg | -1.3 |
| `MYG010` | 21.0 s | 15.7 s / +5.3 s | 0.0 s / +21.0 s | 187.1 km / 125.7 km | 131.0 deg / 316.3 deg | -1.7 |

## `largest_jump` Picks

| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `MYG009` | 0.0 s | 7.8 s / -7.8 s | 7.2 s / -7.2 s | 155.2 km / 152.9 km | 136.5 deg / 307.6 deg | -1.0 |
| `IWT026` | 1.0 s | 0.0 s / +1.0 s | 22.0 s / -21.0 s | 125.7 km / 209.4 km | 100.2 deg / 331.0 deg | -1.1 |
| `MYGH07` | 12.0 s | 10.7 s / +1.3 s | 8.2 s / +3.8 s | 166.3 km / 156.9 km | 149.0 deg / 294.1 deg | -1.5 |
| `MYG014` | 17.0 s | 7.2 s / +9.8 s | 10.0 s / +7.0 s | 153.1 km / 163.8 km | 146.2 deg / 298.9 deg | -1.1 |
| `MYG008` | 21.0 s | 14.9 s / +6.1 s | 1.0 s / +20.0 s | 182.3 km / 129.5 km | 122.7 deg / 325.1 deg | -1.3 |
| `MYG010` | 21.0 s | 14.7 s / +6.3 s | 0.0 s / +21.0 s | 181.5 km / 125.7 km | 128.9 deg / 316.3 deg | -1.7 |

## `final` Picks

| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `MYGH07` | 0.0 s | 0.0 s / +0.0 s | 4.9 s / -4.9 s | 15.0 km / 156.9 km | 69.4 deg / 294.1 deg | -1.0 |
| `FKSH19` | 15.0 s | 16.2 s / -1.2 s | 0.0 s / +15.0 s | 76.7 km / 138.2 km | 163.8 deg / 263.7 deg | -1.8 |
| `MYGH14` | 15.0 s | 8.5 s / +6.5 s | 0.8 s / +14.2 s | 47.4 km / 141.2 km | 60.8 deg / 305.2 deg | -2.0 |
| `FKS002` | 18.0 s | 4.9 s / +13.1 s | 3.1 s / +14.9 s | 33.7 km / 149.8 km | 161.7 deg / 280.3 deg | -2.0 |
| `FKS019` | 22.0 s | 11.6 s / +10.4 s | 6.3 s / +15.7 s | 59.0 km / 162.2 km | 183.6 deg / 270.1 deg | -1.8 |
| `TCGH16` | 24.0 s | 43.4 s / -19.4 s | 23.8 s / +0.2 s | 179.8 km / 228.7 km | 191.6 deg / 239.4 deg | 0.0 |
