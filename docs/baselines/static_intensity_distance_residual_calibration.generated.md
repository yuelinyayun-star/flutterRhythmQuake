# Static Intensity Distance Residual Calibration

- Status: `pass`
- Split: `validation`
- Frozen test evaluated: `false`
- Production ready: `false`

## Decision

- This is a validation-only station-distance residual correction diagnostic.
- It must not be applied to runtime intensity fields, UI, notifications or warning wording.
- It uses final peak station intensity with synthetic reveal masks, so it is not realtime lead-time validation.

## Overall

| Metric | Baseline | All-distance corrected | `gt_200km` corrected |
| --- | ---: | ---: | ---: |
| Max class MAE | 0.61 | 0.95 | 0.61 |
| Numeric max MAE | 0.62 | 0.89 | 0.62 |
| Station MAE | 0.67 | 0.50 | 0.56 |
| Underestimate rate | 52.8% | 76.2% | 52.8% |
| Exact accuracy | 47.2% | 23.8% | 47.2% |
| Within-one accuracy | 92.7% | 82.7% | 92.7% |

## High-Shindo Thresholds

| Threshold | Baseline P/R/F1 | All-distance P/R/F1 | `gt_200km` P/R/F1 |
| --- | ---: | ---: | ---: |
| `shindo3` | 36.7% / 86.5% / 51.5% | 54.8% / 71.2% / 61.9% | 45.9% / 78.6% / 58.0% |
| `shindo4` | 28.3% / 88.6% / 42.9% | 52.9% / 68.2% / 59.6% | 46.2% / 74.7% / 57.1% |
| `shindo5-` | 17.2% / 74.9% / 27.9% | 53.0% / 45.5% / 49.0% | 33.3% / 71.1% / 45.3% |

## Distance Buckets

| Bucket | Count | Mean residual | Correction | Targeted correction | MAE | Shindo4 P/R/F1 | Shindo5- P/R/F1 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `0_50km` | 12366 | 0.05 | -0.05 | 0.00 | 0.37 | 46.2% / 5.8% / 10.3% | 0.0% / 0.0% / 0.0% |
| `50_100km` | 38666 | 0.24 | -0.24 | 0.00 | 0.45 | 54.3% / 84.5% / 66.1% | 29.2% / 88.9% / 43.9% |
| `100_200km` | 94748 | 0.48 | -0.48 | 0.00 | 0.61 | 44.9% / 88.9% / 59.7% | 35.0% / 71.3% / 46.9% |
| `gt_200km` | 39914 | 1.09 | -1.09 | -1.09 | 1.14 | 15.4% / 96.4% / 26.5% | 1.7% / 82.6% / 3.4% |

## Next Step

- If residual correction reduces high-shindo false positives without damaging maximum-shindo metrics, convert it into a probability calibration feature. Otherwise keep raw intensity unchanged and use distance only as confidence metadata.

