# JMA-Style Intensity Diagnostic

- Status: `pass`
- Split: `validation`
- Frozen test evaluated: `false`
- Production ready: `false`
- PLUM included: `false`

## Method

- This report evaluates a JMA-style traditional source-parameter PGV attenuation path using catalog source and magnitude.
- It includes an oracle-source diagnostic and a P3-estimated-source variant to expose source-location error sensitivity.
- Site amplification uses nearest JMA intensity station ARV within 5 km; otherwise ARV falls back to 1.0.

## Oracle Source Summary

| Metric | Value |
| --- | ---: |
| Cases | 896 |
| Station forecasts | 61898 |
| Max-shindo class MAE | 0.43 classes |
| Max-shindo numeric MAE | 0.42 shindo |
| Station intensity MAE | 0.61 shindo |
| Max-shindo underestimation rate | 28.0% |
| Exact max-shindo class accuracy | 60.6% |
| Within 1 class accuracy | 97.1% |

## P3-Estimated Source Summary

| Metric | Value |
| --- | ---: |
| Cases | 2688 |
| Station forecasts | 185694 |
| Max-shindo class MAE | 0.59 classes |
| Max-shindo numeric MAE | 0.57 shindo |
| Station intensity MAE | 0.62 shindo |
| Max-shindo underestimation rate | 31.0% |
| Exact max-shindo class accuracy | 48.8% |
| Within 1 class accuracy | 92.9% |

## Oracle Source Thresholds

| Threshold | Precision | Recall | F1 | TP | FP | FN |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `shindo1` | 100.0% | 92.6% | 96.1% | 57296 | 0 | 4602 |
| `shindo2` | 58.7% | 73.0% | 65.0% | 16655 | 11738 | 6173 |
| `shindo3` | 72.1% | 52.6% | 60.8% | 3442 | 1331 | 3107 |
| `shindo4` | 78.3% | 27.5% | 40.7% | 484 | 134 | 1275 |
| `shindo5-` | 65.0% | 4.0% | 7.5% | 13 | 7 | 313 |

## P3-Estimated Source Thresholds

| Threshold | Precision | Recall | F1 | TP | FP | FN |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `shindo1` | 100.0% | 94.9% | 97.4% | 176220 | 0 | 9474 |
| `shindo2` | 51.2% | 79.7% | 62.3% | 54557 | 52067 | 13927 |
| `shindo3` | 46.7% | 64.1% | 54.0% | 12597 | 14402 | 7050 |
| `shindo4` | 56.5% | 51.0% | 53.6% | 2693 | 2075 | 2584 |
| `shindo5-` | 87.8% | 8.1% | 14.8% | 79 | 11 | 899 |

## Coverage

- Skipped missing-magnitude events: `0`
- Skipped source-error variants without source estimate: `0`
- Default ARV rate: `0.1%`
- P3-estimated source default ARV rate: `0.1%`

## Decision

- Keep this diagnostic separate from production UI and notifications.
- Next comparison should add a PLUM-like observed-shaking path before any frozen test decision.

