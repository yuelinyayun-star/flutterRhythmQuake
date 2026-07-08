# PLUM Tohoku mismatch/one_sided/compact Mode Runtime-Score Diagnostic

- Status: `pass`
- Method: `PLUM Tohoku mismatch/one_sided/compact mode runtime-score diagnostic`
- Frozen test evaluated: `true`
- Production ready: `false`
- Production UI connected: `false`
- Diagnostic only: `true`
- Parameters tuned: `false`
- Suppression applied: `false`
- Raw predicted intensity mutated: `false`

## Coverage

| Slice | Count |
| --- | ---: |
| `validation target modes` | 299 |
| `validation near-threshold positives` | 216 |
| `validation false middle-transition` | 83 |
| `remainder target modes` | 45 |
| `remainder near-threshold positives` | 30 |
| `remainder false middle-transition` | 15 |

## Score Definition

- Weights: supportGeometry `0.450`, concentration `0.350`, evidenceProximity `0.200`.
- Validation anchors: q25 `0.238`, q50 `0.381`, q75 `0.468`.

## Mode Score Means

| Mode | Count | Support Geometry | Concentration | Evidence Proximity | Runtime Score |
| --- | ---: | ---: | ---: | ---: | ---: |
| `validationNearThresholdPositive` | 216 | 0.581 | 0.034 | 0.593 | 0.392 |
| `validationFalseMiddleTransition` | 83 | 0.405 | 0.000 | 0.564 | 0.295 |
| `remainderNearThresholdPositive` | 30 | 0.431 | 0.000 | 0.347 | 0.264 |
| `remainderFalseMiddleTransition` | 15 | 0.241 | 0.000 | 0.204 | 0.149 |

## Validation-Anchored Band Transfer

| Band | Val Count | Val Near | Val False | Val Near Rate | Rem Count | Rem Near | Rem False | Rem Near Rate | Rem False Rate | Rem Near Capture | Rem False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `low` | 76 | 39 | 37 | 51.3% | 22 | 11 | 11 | 50.0% | 50.0% | 36.7% | 73.3% |
| `mid_low` | 74 | 58 | 16 | 78.4% | 14 | 11 | 3 | 78.6% | 21.4% | 36.7% | 20.0% |
| `mid_high` | 74 | 58 | 16 | 78.4% | 5 | 4 | 1 | 80.0% | 20.0% | 13.3% | 6.7% |
| `high` | 75 | 61 | 14 | 81.3% | 4 | 4 | 0 | 100.0% | 0.0% | 13.3% | 0.0% |

## Remainder Quartiles

| Quartile | Score Min | Score Max | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.000 | 0.060 | 11 | 7 | 4 | 63.6% | 36.4% | 23.3% | 26.7% |
| 2 | 0.060 | 0.203 | 11 | 4 | 7 | 36.4% | 63.6% | 13.3% | 46.7% |
| 3 | 0.240 | 0.360 | 11 | 8 | 3 | 72.7% | 27.3% | 26.7% | 20.0% |
| 4 | 0.360 | 0.618 | 12 | 11 | 1 | 91.7% | 8.3% | 36.7% | 6.7% |

## Remainder Monotonicity

- High quartile near-positive rate: `91.7%`; low quartile near-positive rate: `63.6%`.
- High-to-low near-positive lift: `1.44x`.
- Low quartile false rate: `36.4%`; high quartile false rate: `8.3%`.
- High/low false-rate ratio: `0.23x`.
- Positive non-decreasing adjacent pairs: `2`; positive decreasing pairs: `1`.
- Negative non-increasing adjacent pairs: `2`; negative increasing pairs: `1`.

## Decision

- This report remains diagnostic-only. It tests whether a soft runtime score can rank the two within-family remainder modes without turning that distinction into a suppression gate.
- It does not tune PLUM, suppress predictions, or authorize production UI/wording/notification changes.
