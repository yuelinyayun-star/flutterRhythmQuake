# PLUM-Like Replay Lead-Time Diagnostic

- Status: `pass`
- Split: `diagnostic_replay`
- Frozen test evaluated: `false`
- Production ready: `false`
- Production UI connected: `false`
- Source independent: `true`
- Input layer: `jma_s`

## Summary

| Metric | Value |
| --- | ---: |
| Cases | 6 |
| Decoded frames | 906 |
| Station frames | 1476780 |
| Max observed shindo | 5.3 |

## Thresholds

| Threshold | Actual stations | Early/on-time | Missed | False alarms | Median case lead | Recall | False alarm ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `shindo1` | 427 | 335 | 49 | 112 | 4.0s | 78.5% | 22.9% |
| `shindo2` | 212 | 181 | 15 | 77 | 5.0s | 85.4% | 28.1% |
| `shindo3` | 85 | 79 | 5 | 65 | 5.0s | 92.9% | 44.8% |
| `shindo4` | 32 | 27 | 4 | 27 | 3.5s | 84.4% | 49.1% |
| `shindo5-` | 4 | 2 | 1 | 19 | 1.0s | 50.0% | 86.4% |

## Evidence Gate Comparison

| Gate | Shindo1 recall/false alarms | Shindo2 recall/false alarms | Shindo3 recall/false alarms | Shindo4 recall/false alarms | Shindo5- recall/false alarms |
| --- | ---: | ---: | ---: | ---: | ---: |
| `min_evidence_1` | 78.5%/112 | 85.4%/77 | 92.9%/65 | 84.4%/27 | 50.0%/19 |
| `min_evidence_2` | 78.5%/112 | 85.4%/77 | 92.9%/65 | 84.4%/27 | 50.0%/19 |
| `min_evidence_3` | 78.5%/112 | 85.4%/77 | 92.9%/65 | 84.4%/27 | 50.0%/19 |

## Persistence Gate Comparison

| Gate | Shindo1 recall/false alarms | Shindo2 recall/false alarms | Shindo3 recall/false alarms | Shindo4 recall/false alarms | Shindo5- recall/false alarms |
| --- | ---: | ---: | ---: | ---: | ---: |
| `persist_1f` | 78.5%/112 | 85.4%/77 | 92.9%/65 | 84.4%/27 | 50.0%/19 |
| `persist_2f` | 75.9%/112 | 80.7%/73 | 88.2%/65 | 81.3%/27 | 25.0%/19 |
| `persist_3f` | 72.6%/112 | 73.1%/73 | 83.5%/65 | 71.9%/27 | 0.0%/19 |

## Radius/Damping/Guard Grid Comparison

| Config | Radius | Damping | Shindo1 recall/false alarms | Shindo2 recall/false alarms | Shindo3 recall/false alarms | Shindo4 recall/false alarms | Shindo5- recall/false alarms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `r15_d0.25` | 15.0 km | 0.3 / 10km | 48.5%/58 | 54.7%/31 | 62.4%/33 | 46.9%/19 | 25.0%/5 |
| `r20_d0.25` | 20.0 km | 0.3 / 10km | 66.0%/81 | 73.6%/53 | 82.4%/50 | 68.8%/25 | 50.0%/9 |
| `r30_d0.25_baseline` | 30.0 km | 0.3 / 10km | 78.5%/112 | 85.4%/77 | 92.9%/65 | 84.4%/27 | 50.0%/19 |
| `r15_d0.50` | 15.0 km | 0.5 / 10km | 37.9%/37 | 44.8%/21 | 52.9%/26 | 40.6%/11 | 25.0%/5 |
| `r20_d0.50` | 20.0 km | 0.5 / 10km | 51.1%/42 | 58.0%/30 | 64.7%/32 | 56.3%/14 | 25.0%/5 |
| `r30_d0.50` | 30.0 km | 0.5 / 10km | 60.0%/51 | 68.9%/37 | 78.8%/36 | 62.5%/17 | 25.0%/5 |
| `r30_d0.50_local_contrast_r20_w3.0` | 30.0 km | 0.5 / 10km | 60.0%/51 | 68.9%/37 | 78.8%/36 | 40.6%/12 | 25.0%/5 |
| `r15_d0.75` | 15.0 km | 0.8 / 10km | 29.7%/22 | 34.9%/16 | 38.8%/17 | 28.1%/5 | 25.0%/2 |
| `r20_d0.75` | 20.0 km | 0.8 / 10km | 37.0%/23 | 45.8%/19 | 49.4%/23 | 34.4%/7 | 25.0%/2 |
| `r30_d0.75` | 30.0 km | 0.8 / 10km | 40.5%/26 | 50.5%/20 | 54.1%/23 | 46.9%/7 | 25.0%/2 |
| `r15_d1.00` | 15.0 km | 1.0 / 10km | 22.5%/18 | 28.3%/13 | 34.1%/10 | 18.8%/1 | 25.0%/1 |
| `r20_d1.00` | 20.0 km | 1.0 / 10km | 26.9%/18 | 33.5%/13 | 40.0%/11 | 21.9%/2 | 25.0%/1 |
| `r30_d1.00` | 30.0 km | 1.0 / 10km | 29.5%/19 | 36.8%/13 | 41.2%/12 | 21.9%/2 | 25.0%/1 |

## Cases

| Case | Type | Frames | Max observed | No-prediction rate | Shindo1 lead/recall | Shindo2 lead/recall | Shindo3 lead/recall |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `20260624_fukushima_aizu_m32_jma_eq5` | `event` | 151 | 1.7 | 0.6% | 4.0s/33.3% | -s/0.0% | -s/0.0% |
| `20260627_fukushima_aizu_m36_jma_equake17` | `event` | 151 | 1.7 | 0.6% | 4.5s/55.6% | -s/0.0% | -s/0.0% |
| `20260625_iwate_offshore_m32_jma` | `event` | 151 | 1.4 | 0.6% | -s/0.0% | -s/0.0% | -s/0.0% |
| `20260628_iwate_offshore_m41_jma` | `event` | 151 | 1.2 | 0.6% | -1.0s/12.5% | -s/0.0% | -s/0.0% |
| `20260622_kushiro_offshore_m30_jma` | `event` | 151 | 1.1 | 0.6% | -2.0s/0.0% | -s/0.0% | -s/0.0% |
| `20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21` | `event` | 151 | 5.3 | 0.6% | 4.0s/81.4% | 5.0s/86.6% | 5.0s/92.9% |

## Skipped

| Case | Reason |
| --- | --- |
| `20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8` | `capture_manifest_failed_gifs` |

## Decision

- This is the first real replay-frame PLUM-like diagnostic and does not use source coordinates.
- It measures station-threshold lead time inside local GIF captures, not JMA final catalog station intensity.
- Evidence-count, persistence, radius and damping gates are diagnostic only; select an operating point only after expanding the replay set.
- Next step is to use the radius/damping grid to choose a false-positive control gate before frozen-test evaluation.

