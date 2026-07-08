# Iwate offshore Residual Report

Generated from `.dart_tool\source_estimation_benchmark\20260625_iwate_offshore_m32_jma.reference.json`.
No production estimator weights are changed by this report.

- Case: `20260625_iwate_offshore_m32_jma`
- Method: `nied_gif_hybrid_v1`
- Estimate frames: 56
- Findings: `truth_has_worse_travel_time_fit_than_estimate`, `one_sided_boundary_worst_frame`

## Selected Frames

| Frame | Time | Error | Candidate | Jump | Pick count | Estimate RMS | Candidate RMS | Truth RMS | Estimate rank inv. | Candidate rank inv. | Truth rank inv. | Median dist est/cand/truth | Geometry |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `first` | 2026-06-25T19:21:57.000 | 144.0 km | 23.8 km (diagnostic) | - | 6 | 3.3 s | 7.4 s | 8.5 s | 14% | 50% | 36% | 159.2 km / 23.3 km / 27.6 km | one_sided; gap 324.3 deg; nearest 146.3 km; margin -0.3 deg; boundary; P90u 272.7 km |
| `worst` | 2026-06-25T19:21:57.000 | 144.0 km | 23.8 km (diagnostic) | - | 6 | 3.3 s | 7.4 s | 8.5 s | 14% | 50% | 36% | 159.2 km / 23.3 km / 27.6 km | one_sided; gap 324.3 deg; nearest 146.3 km; margin -0.3 deg; boundary; P90u 272.7 km |
| `largest_jump` | 2026-06-25T19:22:00.000 | 40.0 km | - | 123.0 km | 6 | 4.4 s | - | 8.5 s | 43% | - | 43% | 41.0 km / - / 27.6 km | surrounded; gap 91.0 deg; nearest 19.9 km; margin 0.9 deg; inner; P90u 26.0 km |
| `final` | 2026-06-25T19:22:52.000 | 17.0 km | - | 2.0 km | 6 | 2.9 s | - | 4.8 s | 21% | - | 36% | 131.8 km / - / 124.5 km | one_sided; gap 222.5 deg; nearest 105.3 km; margin 0.1 deg; boundary; P90u 122.3 km |

## `first` Picks

| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `IWTH01` | 0.0 s | 0.5 s / -0.5 s | 20.0 s / -20.0 s | 148.1 km / 88.0 km | 243.7 deg / 313.1 deg | -1.2 |
| `IWTH21` | 1.0 s | 7.0 s / -6.0 s | 4.5 s / -3.5 s | 172.9 km / 29.0 km | 208.9 deg / 209.6 deg | -2.2 |
| `IWT004` | 2.0 s | 0.0 s / +2.0 s | 0.0 s / +2.0 s | 146.3 km / 12.0 km | 213.3 deg / 289.2 deg | 0.3 |
| `IWT006` | 5.0 s | 6.3 s / -1.3 s | 3.7 s / +1.3 s | 170.1 km / 26.2 km | 208.1 deg / 204.2 deg | -0.1 |
| `IWT016` | 5.0 s | 7.0 s / -2.0 s | 6.8 s / -1.8 s | 172.7 km / 37.7 km | 217.5 deg / 253.0 deg | -1.7 |
| `IWTH14` | 5.0 s | 0.5 s / +4.5 s | 1.3 s / +3.7 s | 148.3 km / 17.1 km | 215.1 deg / 286.5 deg | -1.7 |

## `worst` Picks

| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `IWTH01` | 0.0 s | 0.5 s / -0.5 s | 20.0 s / -20.0 s | 148.1 km / 88.0 km | 243.7 deg / 313.1 deg | -1.2 |
| `IWTH21` | 1.0 s | 7.0 s / -6.0 s | 4.5 s / -3.5 s | 172.9 km / 29.0 km | 208.9 deg / 209.6 deg | -2.2 |
| `IWT004` | 2.0 s | 0.0 s / +2.0 s | 0.0 s / +2.0 s | 146.3 km / 12.0 km | 213.3 deg / 289.2 deg | 0.3 |
| `IWT006` | 5.0 s | 6.3 s / -1.3 s | 3.7 s / +1.3 s | 170.1 km / 26.2 km | 208.1 deg / 204.2 deg | -0.1 |
| `IWT016` | 5.0 s | 7.0 s / -2.0 s | 6.8 s / -1.8 s | 172.7 km / 37.7 km | 217.5 deg / 253.0 deg | -1.7 |
| `IWTH14` | 5.0 s | 0.5 s / +4.5 s | 1.3 s / +3.7 s | 148.3 km / 17.1 km | 215.1 deg / 286.5 deg | -1.7 |

## `largest_jump` Picks

| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `IWTH01` | 0.0 s | 6.4 s / -6.4 s | 20.0 s / -20.0 s | 48.8 km / 88.0 km | 320.9 deg / 313.1 deg | -1.2 |
| `IWTH21` | 1.0 s | 7.0 s / -6.0 s | 4.5 s / -3.5 s | 51.1 km / 29.0 km | 157.4 deg / 209.6 deg | -2.2 |
| `IWT004` | 2.0 s | 1.1 s / +0.9 s | 0.0 s / +2.0 s | 28.8 km / 12.0 km | 128.8 deg / 289.2 deg | 0.3 |
| `IWT006` | 5.0 s | 7.1 s / -2.1 s | 3.7 s / +1.3 s | 51.4 km / 26.2 km | 153.2 deg / 204.2 deg | -0.1 |
| `IWT016` | 5.0 s | 2.3 s / +2.7 s | 6.8 s / -1.8 s | 33.2 km / 37.7 km | 183.8 deg / 253.0 deg | 0.3 |
| `IWTH14` | 5.0 s | 0.0 s / +5.0 s | 1.3 s / +3.7 s | 24.5 km / 17.1 km | 134.5 deg / 286.5 deg | -1.7 |

## `final` Picks

| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `AOMH16` | 0.0 s | 0.0 s / +0.0 s | 0.3 s / -0.3 s | 105.3 km / 120.6 km | 311.3 deg / 315.0 deg | -1.0 |
| `MYG002` | 2.0 s | 6.9 s / -4.9 s | 0.0 s / +2.0 s | 131.7 km / 119.6 km | 199.9 deg / 205.3 deg | -1.0 |
| `AKTH17` | 8.0 s | 5.2 s / +2.8 s | 2.3 s / +5.7 s | 125.1 km / 128.4 km | 255.9 deg / 263.4 deg | -1.4 |
| `MYG008` | 9.0 s | 12.0 s / -3.0 s | 5.0 s / +4.0 s | 150.7 km / 138.7 km | 200.2 deg / 205.0 deg | -1.6 |
| `MYG018` | 9.0 s | 7.0 s / +2.0 s | 0.1 s / +8.9 s | 132.0 km / 119.8 km | 199.3 deg / 204.7 deg | -2.0 |
| `AOMH05` | 11.0 s | 8.5 s / +2.5 s | 9.0 s / +2.0 s | 137.4 km / 153.9 km | 325.6 deg / 327.0 deg | -1.5 |
