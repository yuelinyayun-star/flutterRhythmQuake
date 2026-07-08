# Static Intensity Forecast Validation

- Status: `pass`
- Model: `static_intensity_attenuation_v1`
- Split: `validation`
- Frozen test evaluated: `false`
- Production ready: `false`

## Summary

| Metric | Value |
| --- | ---: |
| Cases | 2688 |
| Station forecasts | 185694 |
| Max-shindo class MAE | 0.61 classes |
| Max-shindo numeric MAE | 0.62 shindo |
| Station intensity MAE | 0.67 shindo |
| Max-shindo underestimation rate | 52.8% |
| Exact max-shindo class accuracy | 47.2% |
| Within 1 class accuracy | 92.7% |

## Thresholds

| Threshold | Precision | Recall | F1 | TP | FP | FN |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `shindo1` | 100.0% | 98.6% | 99.3% | 183020 | 0 | 2674 |
| `shindo2` | 54.2% | 88.1% | 67.1% | 60310 | 50889 | 8174 |
| `shindo3` | 36.7% | 86.5% | 51.5% | 16995 | 29349 | 2652 |
| `shindo4` | 28.3% | 88.6% | 42.9% | 4673 | 11834 | 604 |
| `shindo5-` | 17.2% | 74.9% | 27.9% | 733 | 3541 | 245 |

## By Mask Rate

| Mask | Cases | Max class MAE | Station MAE | Underestimate rate |
| ---: | ---: | ---: | ---: | ---: |
| `20pct` | 896 | 0.58 | 0.79 | 52.3% |
| `50pct` | 896 | 0.61 | 0.70 | 52.9% |
| `80pct` | 896 | 0.63 | 0.53 | 53.0% |

## Decision

- This is a validation-only forecast metric report for the static intensity baseline.
- It uses final peak station intensity with synthetic reveal masks, so it must not be described as realtime measured lead time.
- Frozen test remains unopened and production UI/notification wording must not consume this report directly.

