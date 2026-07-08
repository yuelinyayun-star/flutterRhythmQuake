# Static Intensity Calibration

- Status: `pass`
- Split: `validation`
- Frozen test evaluated: `false`
- Production ready: `false`

## Decision

- This is a validation-only global additive intensity-offset scan.
- It uses final peak station intensity with synthetic reveal masks, so it is not realtime lead-time validation.
- The recommended offset is diagnostic-only and must not be consumed by production UI, notifications or warning wording.

## Baseline vs Recommended

| Metric | Baseline offset 0.00 | Recommended |
| --- | ---: | ---: |
| Offset | `0.00` | `-0.20` |
| Max class MAE | 0.61 | 0.77 |
| Numeric max MAE | 0.62 | 0.81 |
| Station MAE | 0.67 | 0.59 |
| Underestimate rate | 52.8% | 65.8% |
| High-shindo objective | 1.44 | 1.39 |

## Threshold Tradeoff

| Offset | Shindo3 P/R/F1 | Shindo4 P/R/F1 | Shindo5- P/R/F1 | Max MAE | Under |
| ---: | ---: | ---: | ---: | ---: | ---: |
| `-1.00` | 65.1% / 54.7% / 59.4% | 55.5% / 44.9% / 49.7% | 76.0% / 7.8% / 14.1% | 1.61 | 99.9% |
| `-0.90` | 62.4% / 58.3% / 60.3% | 53.2% / 51.9% / 52.5% | 69.7% / 17.4% / 27.8% | 1.55 | 99.7% |
| `-0.80` | 59.0% / 61.9% / 60.4% | 51.7% / 60.5% / 55.7% | 61.6% / 27.9% / 38.4% | 1.48 | 99.3% |
| `-0.70` | 55.9% / 65.1% / 60.2% | 48.4% / 66.6% / 56.0% | 54.1% / 36.2% / 43.4% | 1.40 | 98.3% |
| `-0.60` | 52.5% / 69.8% / 59.9% | 44.8% / 69.5% / 54.5% | 44.2% / 40.4% / 42.2% | 1.32 | 96.9% |
| `-0.50` | 48.2% / 73.7% / 58.2% | 41.4% / 71.9% / 52.6% | 38.0% / 43.7% / 40.6% | 1.20 | 92.3% |
| `-0.40` | 44.6% / 76.9% / 56.5% | 39.2% / 76.6% / 51.9% | 30.9% / 45.8% / 36.9% | 1.07 | 86.2% |
| `-0.30` | 42.3% / 79.6% / 55.2% | 36.6% / 80.2% / 50.3% | 26.4% / 53.1% / 35.2% | 0.92 | 77.0% |
| `-0.20` | 40.4% / 82.0% / 54.1% | 33.5% / 83.0% / 47.7% | 22.4% / 57.2% / 32.2% | 0.77 | 65.8% |
| `-0.10` | 38.6% / 84.4% / 53.0% | 30.8% / 86.4% / 45.4% | 19.3% / 68.3% / 30.2% | 0.67 | 58.1% |
| `0.00` | 36.7% / 86.5% / 51.5% | 28.3% / 88.6% / 42.9% | 17.2% / 74.9% / 27.9% | 0.61 | 52.8% |
| `0.10` | 34.4% / 88.3% / 49.5% | 25.9% / 90.2% / 40.3% | 15.6% / 82.1% / 26.2% | 0.55 | 48.6% |
| `0.20` | 32.2% / 90.1% / 47.4% | 23.7% / 92.3% / 37.7% | 14.1% / 89.1% / 24.4% | 0.49 | 43.0% |
| `0.30` | 29.7% / 92.2% / 44.9% | 21.6% / 93.7% / 35.1% | 12.3% / 91.6% / 21.8% | 0.43 | 37.9% |
| `0.40` | 27.3% / 93.5% / 42.3% | 19.1% / 94.8% / 31.9% | 11.0% / 92.3% / 19.7% | 0.38 | 31.4% |
| `0.50` | 25.2% / 94.6% / 39.8% | 16.8% / 95.7% / 28.6% | 9.9% / 92.4% / 17.8% | 0.35 | 25.0% |

## Next Step

- Use this report to choose explicit acceptance criteria, then rerun on a surface-default-aligned recalibrated model before opening the frozen test split.

