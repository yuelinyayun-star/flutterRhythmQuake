# Static Intensity Probability Gate

- Status: `pass`
- Split: `validation`
- Frozen test evaluated: `false`
- Production ready: `false`
- Raw intensity field mutated: `false`
- `gt_200km` correction used only as a threshold-gate feature: `-1.09`

## Decision

- This is a validation-only threshold probability/confidence gate diagnostic.
- It does not change the raw predicted intensity field or maximum-shindo display.
- It uses final peak station intensity with synthetic reveal masks, so it is not realtime lead-time validation.

## Threshold Comparison

| Threshold | Raw P/R/F1 | Hard `gt_200km` P/R/F1 | Gate P/R/F1 | Gate score |
| --- | ---: | ---: | ---: | ---: |
| `shindo3` | 36.7% / 86.5% / 51.5% | 45.9% / 78.6% / 58.0% | 41.6% / 84.6% / 55.8% | `0.40` |
| `shindo4` | 28.3% / 88.6% / 42.9% | 46.2% / 74.7% / 57.1% | 55.1% / 63.6% / 59.0% | `0.70` |
| `shindo5-` | 17.2% / 74.9% / 27.9% | 33.3% / 71.1% / 45.3% | 33.3% / 71.1% / 45.3% | `0.50` |

## Distance Residuals

| Bucket | Count | Mean residual | MAE |
| --- | ---: | ---: | ---: |
| `0_50km` | 12366 | 0.05 | 0.37 |
| `50_100km` | 38666 | 0.24 | 0.45 |
| `100_200km` | 94748 | 0.48 | 0.61 |
| `gt_200km` | 39914 | 1.09 | 1.14 |

## Next Step

- If the probability gate beats both raw and hard correction on validation with acceptable recall, freeze acceptance criteria before opening the frozen test split.

