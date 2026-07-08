# PLUM Confidence Gate Diagnostic

- Status: `pass`
- Split: `validation`
- Frozen test evaluated: `false`
- Production ready: `false`
- Raw intensity field mutated: `false`
- Recommended for replay validation: `plum_r20_d0_50_only`
- Station forecasts: `185694`

## Method

- Baseline raw signal is `max(JMA-style, PLUM r30/d0.50)`.
- Confidence gates do not change the predicted intensity field; they only decide whether a high-threshold prediction is considered confidence-supported.

## Evaluation

| Gate | Shindo4 P/R/F1 | Shindo4 FP/FN | Shindo5- P/R/F1 | Shindo5- FP/FN |
| --- | ---: | ---: | ---: | ---: |
| `baseline_raw_threshold` | 55.9% / 72.5% / 63.1% | 3015 / 1453 | 58.8% / 46.9% / 52.2% | 322 / 519 |
| `jma_or_plum_r20_d0_50` | 56.0% / 72.0% / 63.0% | 2990 / 1479 | 58.7% / 45.5% / 51.3% | 313 / 533 |
| `jma_or_plum_r30_d0_75` | 58.3% / 66.3% / 62.0% | 2498 / 1780 | 70.3% / 36.0% / 47.6% | 149 / 626 |
| `plum_r20_d0_50_only` | 69.6% / 60.7% / 64.8% | 1399 / 2076 | 58.0% / 44.1% / 50.1% | 312 / 547 |
| `two_of_jma_r20_d0_50_r30_d0_75` | 76.2% / 55.1% / 64.0% | 907 / 2367 | 69.5% / 34.6% / 46.2% | 148 / 640 |

## Decision

- Production remains blocked.
- Frozen test remains closed.
- A recommended gate must pass real replay validation before any future acceptance criteria are written.

