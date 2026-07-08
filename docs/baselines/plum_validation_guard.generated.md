# PLUM Validation Guard Diagnostic

- Status: `pass`
- Split: `validation`
- Frozen test evaluated: `false`
- Production ready: `false`
- Diagnostic only: `true`
- Recommended for further validation: `local_contrast_r20_w3_0_m1_cap0_5`
- Station forecasts: `185694`

## Method

- Baseline is `max_jma_style_plum_like_r30_d0_50` on validation only.
- Guard candidates cap only the PLUM branch when the nearest retained neighbor inside a local radius is weak.
- JMA-style and raw observed station values are not mutated; production UI and notifications remain disconnected.

## Evaluation

| Config | Triggered | Shindo4 P/R/F1 | Shindo4 FP/FN | Shindo5- P/R/F1 | Max MAE | Under |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `baseline_no_guard` | 0 | 55.9% / 72.5% / 63.1% | 3015 / 1453 | 58.8% / 46.9% / 52.2% | 0.44 | 20.2% |
| `local_contrast_r20_w2_5_m1_cap0_5` | 292 | 56.3% / 72.3% / 63.3% | 2957 / 1464 | 58.9% / 43.4% / 49.9% | 0.44 | 20.2% |
| `local_contrast_r20_w3_0_m1_cap0_5` | 490 | 56.9% / 71.9% / 63.5% | 2872 / 1483 | 59.0% / 43.4% / 50.0% | 0.44 | 20.3% |
| `local_contrast_r30_w2_5_m1_cap0_5` | 293 | 56.3% / 72.3% / 63.3% | 2957 / 1464 | 58.9% / 43.4% / 49.9% | 0.44 | 20.2% |
| `local_contrast_r30_w3_0_m1_cap0_5` | 491 | 56.9% / 71.9% / 63.5% | 2872 / 1483 | 59.0% / 43.4% / 50.0% | 0.44 | 20.3% |
| `local_contrast_r30_w3_0_m2_cap0_5` | 477 | 56.9% / 71.9% / 63.5% | 2877 / 1483 | 59.0% / 43.4% / 50.0% | 0.44 | 20.3% |

## Decision

- Production remains blocked.
- Frozen test remains closed for this guard family.
- If a guard is recommended, the next step is real replay validation, not production wiring.

