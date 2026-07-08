# Static Intensity Stratified Calibration

- Status: `pass`
- Split: `validation`
- Frozen test evaluated: `false`
- Production ready: `false`
- Changed strata: `1/3`

## Decision

- This is a validation-only stratified offset scan by predicted maximum class and location-uncertainty bucket.
- It remains diagnostic-only: no production coordinate, UI, notification or warning wording may consume these offsets.
- It uses final peak station intensity with synthetic reveal masks, so it is not realtime lead-time validation.

## Overall

| Metric | Baseline | Stratified |
| --- | ---: | ---: |
| Max class MAE | 0.61 | 0.56 |
| Numeric max MAE | 0.62 | 0.53 |
| Station MAE | 0.67 | 0.70 |
| Underestimate rate | 52.8% | 48.7% |
| Exact / within-one | 47.2% / 92.7% | 51.1% / 93.9% |

## High-Shindo Thresholds

| Threshold | Baseline P/R/F1 | Stratified P/R/F1 |
| --- | ---: | ---: |
| `shindo3` | 36.7% / 86.5% / 51.5% | 36.6% / 86.9% / 51.5% |
| `shindo4` | 28.3% / 88.6% / 42.9% | 28.3% / 88.6% / 42.9% |
| `shindo5-` | 17.2% / 74.9% / 27.9% | 17.2% / 74.9% / 27.9% |

## Strata

| Stratum | Cases | Offset | Baseline MAE | Selected MAE | Baseline under | Selected under |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `pred_3/p90_50_100km` | 101 | `0.00` | 0.78 | 0.78 | 63.4% | 63.4% |
| `pred_ge_4/p90_50_100km` | 24 | `0.00` | 1.04 | 1.04 | 66.7% | 66.7% |
| `pred_le_2/p90_50_100km` | 2563 | `0.10` | 0.60 | 0.54 | 52.2% | 47.9% |

## Station Distance Diagnostics

| Distance | Count | Mean residual | MAE | Shindo4 P/R/F1 | Shindo5- P/R/F1 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `0_50km` | 12366 | 0.05 | 0.37 | 46.2% / 5.8% / 10.3% | 0.0% / 0.0% / 0.0% |
| `50_100km` | 38666 | 0.24 | 0.45 | 54.3% / 84.5% / 66.1% | 29.2% / 88.9% / 43.9% |
| `100_200km` | 94748 | 0.48 | 0.61 | 44.9% / 88.9% / 59.7% | 35.0% / 71.3% / 46.9% |
| `gt_200km` | 39914 | 1.09 | 1.14 | 15.4% / 96.4% / 26.5% | 1.7% / 82.6% / 3.4% |

## Next Step

- If the stratified offsets improve high-shindo precision without materially increasing underestimation, promote the same buckets to a probability-calibration experiment. Otherwise keep the baseline and add more features rather than hiding the error with offsets.

