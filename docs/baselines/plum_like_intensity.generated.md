# PLUM-Like Intensity Diagnostic

- Status: `pass`
- Split: `validation`
- Frozen test evaluated: `false`
- Production ready: `false`
- Source independent: `true`

## Method

- This report evaluates observed-shaking propagation from retained stations to target stations.
- It excludes the target station itself from evidence to avoid direct final-peak leakage.
- It scans radius, damping and minimum evidence count. The selected configuration maximizes `shindo4 F1 + 0.5 * shindo5- F1` on validation.
- It still uses synthetic reveal of final peak station intensity, so it is not realtime lead-time validation.

## Selected Config

| Parameter | Value |
| --- | ---: |
| Radius | 30.00 km |
| Damping | 0.25 shindo / 10 km |
| Minimum evidence stations | 1 |

## Selected Summary

| Metric | Value |
| --- | ---: |
| Cases | 2688 |
| Station forecasts | 185694 |
| Max-shindo class MAE | 0.37 classes |
| Max-shindo numeric MAE | 0.34 shindo |
| Station intensity MAE | 0.64 shindo |
| Max-shindo underestimation rate | 34.3% |
| Exact max-shindo class accuracy | 65.7% |
| Within 1 class accuracy | 97.6% |
| No-prediction station rate | 5.3% |

## Selected Thresholds

| Threshold | Precision | Recall | F1 | TP | FP | FN |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `shindo1` | 100.0% | 87.1% | 93.1% | 161684 | 0 | 24010 |
| `shindo2` | 66.1% | 81.8% | 73.1% | 55997 | 28719 | 12487 |
| `shindo3` | 59.4% | 82.3% | 69.0% | 16164 | 11054 | 3483 |
| `shindo4` | 57.4% | 78.9% | 66.5% | 4166 | 3095 | 1111 |
| `shindo5-` | 43.8% | 67.4% | 53.1% | 659 | 845 | 319 |

## Top Configs

| Radius | Damping/10km | Min evidence | Score | Shindo4 P/R/F1 | Shindo5- P/R/F1 |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 30.00 | 0.25 | 1 | 0.93 | 57.4% / 78.9% / 66.5% | 43.8% / 67.4% / 53.1% |
| 50.00 | 0.25 | 2 | 0.92 | 55.4% / 81.4% / 66.0% | 43.0% / 69.3% / 53.1% |
| 50.00 | 0.25 | 1 | 0.92 | 55.4% / 81.4% / 65.9% | 43.0% / 69.3% / 53.1% |
| 30.00 | 0.25 | 2 | 0.92 | 57.2% / 77.9% / 66.0% | 43.7% / 66.7% / 52.8% |
| 80.00 | 0.25 | 1 | 0.92 | 55.0% / 81.8% / 65.8% | 42.7% / 69.5% / 52.9% |
| 80.00 | 0.25 | 2 | 0.92 | 55.0% / 81.8% / 65.8% | 42.7% / 69.5% / 52.9% |
| 50.00 | 0.50 | 1 | 0.92 | 69.7% / 63.0% / 66.2% | 58.1% / 45.5% / 51.0% |
| 50.00 | 0.50 | 2 | 0.92 | 69.7% / 63.0% / 66.2% | 58.1% / 45.5% / 51.0% |
| 80.00 | 0.50 | 1 | 0.92 | 69.7% / 63.0% / 66.2% | 58.1% / 45.5% / 51.0% |
| 80.00 | 0.50 | 2 | 0.92 | 69.7% / 63.0% / 66.2% | 58.1% / 45.5% / 51.0% |
| 30.00 | 0.50 | 1 | 0.92 | 69.7% / 62.8% / 66.1% | 58.1% / 45.5% / 51.0% |
| 30.00 | 0.50 | 2 | 0.91 | 69.5% / 62.1% / 65.6% | 58.1% / 45.3% / 50.9% |

## Decision

- Keep this diagnostic separate from source estimation, production UI and notifications.
- Next comparison should evaluate `max(traditional, PLUM-like)` and then replace synthetic reveal with real per-frame observations.

