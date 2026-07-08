# Static Intensity Probability Gate Acceptance

- Status: `pass`
- Split: `validation`
- Frozen test evaluated: `false`
- Production ready: `false`
- Ready for frozen test: `false`
- Requires manual decision: `true`

## Criteria

| Criterion | Value |
| --- | ---: |
| Minimum precision gain | 10.0% |
| Minimum F1 gain | 10.0% |
| Maximum recall loss | 18.0% |
| Maximum false-negative ratio | 3.00x |

## Threshold Decisions

| Threshold | Status | Precision gain | Recall loss | F1 gain | FN ratio | Notes |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `shindo3` | `info` | 4.9% | 1.9% | 4.3% | 1.14x | precision_gain_below_minimum; f1_gain_below_minimum |
| `shindo4` | `warn` | 26.8% | 24.9% | 16.1% | 3.18x | recall_loss_above_limit; false_negative_ratio_above_limit |
| `shindo5-` | `pass` | 16.1% | 3.9% | 17.4% | 1.16x |  |

## Decision

- `shindo4` and `shindo5-` are the production-relevant high-shindo gates.
- A `warn` means the gate improves precision/F1 but the recall loss needs explicit product decision before frozen test.
- A `fail` blocks frozen-test evaluation until the validation gate is changed or acceptance criteria are deliberately revised.

