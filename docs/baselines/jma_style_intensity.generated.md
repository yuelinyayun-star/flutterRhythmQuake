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
| Max-shindo underestimation rate | 26.8% |
| Exact max-shindo class accuracy | 60.3% |
| Within 1 class accuracy | 97.2% |

## P3-Estimated Source Summary

| Metric | Value |
| --- | ---: |
| Cases | 2688 |
| Station forecasts | 185694 |
| Max-shindo class MAE | 0.60 classes |
| Max-shindo numeric MAE | 0.57 shindo |
| Station intensity MAE | 0.62 shindo |
| Max-shindo underestimation rate | 30.4% |
| Exact max-shindo class accuracy | 48.1% |
| Within 1 class accuracy | 92.6% |

## Oracle Source Thresholds

| Threshold | Precision | Recall | F1 | TP | FP | FN |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `shindo1` | 100.0% | 92.6% | 96.1% | 57304 | 0 | 4594 |
| `shindo2` | 58.6% | 73.0% | 65.0% | 16657 | 11790 | 6171 |
| `shindo3` | 71.9% | 52.9% | 60.9% | 3462 | 1350 | 3087 |
| `shindo4` | 78.5% | 27.9% | 41.1% | 490 | 134 | 1269 |
| `shindo5-` | 54.2% | 4.0% | 7.4% | 13 | 11 | 313 |

## P3-Estimated Source Thresholds

| Threshold | Precision | Recall | F1 | TP | FP | FN |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `shindo1` | 100.0% | 94.9% | 97.4% | 176220 | 0 | 9474 |
| `shindo2` | 51.1% | 79.7% | 62.3% | 54604 | 52181 | 13880 |
| `shindo3` | 46.6% | 64.4% | 54.1% | 12651 | 14512 | 6996 |
| `shindo4` | 56.7% | 51.2% | 53.8% | 2703 | 2066 | 2574 |
| `shindo5-` | 83.8% | 8.5% | 15.4% | 83 | 16 | 895 |

## Coverage

- Skipped missing-magnitude events: `0`
- Skipped source-error variants without source estimate: `0`
- Default ARV rate: `0.1%`
- P3-estimated source default ARV rate: `0.1%`

## Decision

- Keep this diagnostic separate from production UI and notifications.
- Next comparison should add a PLUM-like observed-shaking path before any frozen test decision.

