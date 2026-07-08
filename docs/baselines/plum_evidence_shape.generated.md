# PLUM Evidence Shape Diagnostic

- Status: `pass`
- Split: `validation`
- Frozen test evaluated: `false`
- Production ready: `false`
- Raw production intensity mutated: `false`
- Recommended for replay validation: `none`
- Station forecasts: `185694`

## Method

- Baseline is `max(JMA-style, PLUM r30/d0.50)` on validation only.
- Shape candidates suppress only diagnostic PLUM high-threshold predictions when nearby strong evidence is isolated or not spatially spread.
- Production predicted intensity, UI, notifications and wording remain disconnected.

## Evaluation

| Config | Suppressed | Shindo4 P/R/F1 | Shindo4 FP/FN | Shindo5- P/R/F1 | Max MAE | Under |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `baseline_no_shape_gate` | 0 | 55.9% / 72.5% / 63.1% | 3015 / 1453 | 58.8% / 46.9% / 52.2% | 0.44 | 20.2% |
| `shape_t4_min2_r30_margin0_5_spread0` | 325 | 56.6% / 70.9% / 62.9% | 2864 / 1538 | 58.8% / 46.6% / 52.0% | 0.45 | 20.7% |
| `shape_t4_min2_r30_margin0_5_spread10` | 574 | 57.3% / 70.0% / 63.0% | 2753 / 1584 | 59.1% / 46.1% / 51.8% | 0.45 | 20.9% |
| `shape_t4_min3_r30_margin0_5_spread10` | 803 | 57.7% / 69.1% / 62.9% | 2674 / 1629 | 59.1% / 45.1% / 51.2% | 0.45 | 21.1% |
| `shape_t5_min2_r30_margin0_5_spread10` | 130 | 55.8% / 72.1% / 63.0% | 3011 / 1470 | 62.0% / 41.7% / 49.9% | 0.44 | 20.2% |

## Decision

- Production remains blocked.
- Frozen test remains closed.
- Any recommended shape candidate must be checked on real replay before wording, UI, notification, or frozen-test criteria work.

