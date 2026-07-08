# PLUM Confidence-Band Frozen Evaluation

- Status: `pass`
- Split: `test`
- Frozen test evaluated: `true`
- One-shot: `true`
- Production UI connected: `false`
- Raw predicted intensity mutated: `false`
- Outcome: `fail`

## Method

- This is the single one-shot frozen evaluation of the shindo4 confidence-band wording layer. Band labels are looked up from the validation calibration table only; they are not recomputed on test.
- Raw predicted intensity is not modified. The band is a separate diagnostic field layered on top.
- F1-F4 are pre-registered in the roadmap acceptance section and were not tuned after seeing frozen results.

## Validation Reference (shindo4)

| Band | Validation precision | Validation pred+ |
| --- | ---: | ---: |
| `high` | 82.2% | 2635 |
| `medium` | 62.5% | 1156 |
| `low` | 30.2% | 2993 |
| `insufficient` | 60.0% | 55 |

## Frozen Test (shindo4)

- Station forecasts: `179844`
- Total predicted positives: `6288`
- Baseline P/R: `38.0% / 57.2%`

| Band | Frozen pred+ | Frozen TP | Frozen FP | Frozen precision |
| --- | ---: | ---: | ---: | ---: |
| `high` | 782 | 425 | 357 | 54.3% |
| `medium` | 2605 | 1110 | 1495 | 42.6% |
| `low` | 2795 | 809 | 1986 | 28.9% |
| `insufficient` | 106 | 45 | 61 | 42.5% |

## Criteria Checks (F1-F4)

| Check | Status | Actual | Required |
| --- | --- | ---: | ---: |
| `F1_band_monotonicity` | `pass` | high=54.3% / medium=42.6% / low=28.9% | `frozen band monotonicity P(high)>P(medium)>P(low)` |
| `F2_high_precision_hold` | `fail` | 54.3% | `frozen P(high) >= validation P(high) (82.2%) - 5.0%` |
| `F3_no_collapse_high` | `fail` | 54.3% | `frozen P(high) >= validation P(high) (82.2%) - 15.0%` |
| `F3_no_collapse_medium` | `fail` | 42.6% | `frozen P(medium) >= validation P(medium) (62.5%) - 15.0%` |
| `F3_no_collapse_low` | `pass` | 28.9% | `frozen P(low) >= validation P(low) (30.2%) - 15.0%` |
| `F4_coverage_hold` | `pass` | 53.9% | `frozen share(high+medium) >= 50.0% * validation share(high+medium) (55.4%)` |

## Decision

- Advance to production UI: `false`
- Next action: `block_ui_wording_keep_confidence_band_validation_only`

This is the single one-shot frozen evaluation for the shindo4 confidence-band wording layer. It does not authorize production UI, notifications or warning wording.

