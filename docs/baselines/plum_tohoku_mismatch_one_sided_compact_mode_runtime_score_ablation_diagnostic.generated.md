# PLUM Tohoku mismatch/one_sided/compact Mode Runtime-Score Ablation Diagnostic

- Status: `pass`
- Method: `PLUM Tohoku mismatch/one_sided/compact mode runtime-score ablation diagnostic`
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

## Variant Summary

| Variant | Val Mean Gap | Rem Mean Gap | Low False Capture | Low Near Capture | High Near Rate | High False Rate | High/Low Near Lift | High/Low False Ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `support_geometry_only` | 0.176 | 0.191 | 60.0% | 26.7% | 100.0% | 0.0% | 1.53x | 0.37x |
| `support_geometry_plus_proximity` | 0.132 | 0.176 | 73.3% | 36.7% | 100.0% | 0.0% | 1.44x | 0.23x |
| `full_score` | 0.097 | 0.114 | 73.3% | 36.7% | 100.0% | 0.0% | 1.44x | 0.23x |

## `support_geometry_only`

- Weights: `{"supportGeometry":1.0}`
- Validation anchors: q25 `0.333`, q50 `0.538`, q75 `0.667`.

### Mode Score Means

| Mode | Count | Score |
| --- | ---: | ---: |
| `validationNearThresholdPositive` | 216 | 0.581 |
| `validationFalseMiddleTransition` | 83 | 0.405 |
| `remainderNearThresholdPositive` | 30 | 0.431 |
| `remainderFalseMiddleTransition` | 15 | 0.241 |

### Validation-Anchored Band Transfer

| Band | Val Count | Val Near | Val False | Rem Count | Rem Near | Rem False | Rem Near Rate | Rem False Rate | Rem Near Capture | Rem False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `low` | 77 | 37 | 40 | 17 | 8 | 9 | 47.1% | 52.9% | 26.7% | 60.0% |
| `mid_low` | 75 | 50 | 25 | 11 | 7 | 4 | 63.6% | 36.4% | 23.3% | 26.7% |
| `mid_high` | 90 | 79 | 11 | 14 | 12 | 2 | 85.7% | 14.3% | 40.0% | 13.3% |
| `high` | 57 | 50 | 7 | 3 | 3 | 0 | 100.0% | 0.0% | 10.0% | 0.0% |

### Remainder Quartiles

| Quartile | Score Min | Score Max | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.000 | 0.067 | 11 | 6 | 5 | 54.5% | 45.5% | 20.0% | 33.3% |
| 2 | 0.067 | 0.407 | 11 | 6 | 5 | 54.5% | 45.5% | 20.0% | 33.3% |
| 3 | 0.417 | 0.578 | 11 | 8 | 3 | 72.7% | 27.3% | 26.7% | 20.0% |
| 4 | 0.593 | 1.000 | 12 | 10 | 2 | 83.3% | 16.7% | 33.3% | 13.3% |

### Remainder Monotonicity

- High quartile near-positive rate: `83.3%`; low quartile near-positive rate: `54.5%`.
- High-to-low near-positive lift: `1.53x`.
- Low quartile false rate: `45.5%`; high quartile false rate: `16.7%`.
- High/low false-rate ratio: `0.37x`.

## `support_geometry_plus_proximity`

- Weights: `{"supportGeometry":0.7,"evidenceProximity":0.3}`
- Validation anchors: q25 `0.369`, q50 `0.571`, q75 `0.704`.

### Mode Score Means

| Mode | Count | Score |
| --- | ---: | ---: |
| `validationNearThresholdPositive` | 216 | 0.585 |
| `validationFalseMiddleTransition` | 83 | 0.453 |
| `remainderNearThresholdPositive` | 30 | 0.406 |
| `remainderFalseMiddleTransition` | 15 | 0.230 |

### Validation-Anchored Band Transfer

| Band | Val Count | Val Near | Val False | Rem Count | Rem Near | Rem False | Rem Near Rate | Rem False Rate | Rem Near Capture | Rem False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `low` | 75 | 38 | 37 | 22 | 11 | 11 | 50.0% | 50.0% | 36.7% | 73.3% |
| `mid_low` | 75 | 59 | 16 | 12 | 9 | 3 | 75.0% | 25.0% | 30.0% | 20.0% |
| `mid_high` | 76 | 60 | 16 | 7 | 6 | 1 | 85.7% | 14.3% | 20.0% | 6.7% |
| `high` | 73 | 59 | 14 | 4 | 4 | 0 | 100.0% | 0.0% | 13.3% | 0.0% |

### Remainder Quartiles

| Quartile | Score Min | Score Max | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.000 | 0.093 | 11 | 7 | 4 | 63.6% | 36.4% | 23.3% | 26.7% |
| 2 | 0.093 | 0.316 | 11 | 4 | 7 | 36.4% | 63.6% | 13.3% | 46.7% |
| 3 | 0.371 | 0.549 | 11 | 8 | 3 | 72.7% | 27.3% | 26.7% | 20.0% |
| 4 | 0.549 | 0.952 | 12 | 11 | 1 | 91.7% | 8.3% | 36.7% | 6.7% |

### Remainder Monotonicity

- High quartile near-positive rate: `91.7%`; low quartile near-positive rate: `63.6%`.
- High-to-low near-positive lift: `1.44x`.
- Low quartile false rate: `36.4%`; high quartile false rate: `8.3%`.
- High/low false-rate ratio: `0.23x`.

## `full_score`

- Weights: `{"supportGeometry":0.45,"concentration":0.35,"evidenceProximity":0.2}`
- Validation anchors: q25 `0.238`, q50 `0.381`, q75 `0.468`.

### Mode Score Means

| Mode | Count | Score |
| --- | ---: | ---: |
| `validationNearThresholdPositive` | 216 | 0.392 |
| `validationFalseMiddleTransition` | 83 | 0.295 |
| `remainderNearThresholdPositive` | 30 | 0.264 |
| `remainderFalseMiddleTransition` | 15 | 0.149 |

### Validation-Anchored Band Transfer

| Band | Val Count | Val Near | Val False | Rem Count | Rem Near | Rem False | Rem Near Rate | Rem False Rate | Rem Near Capture | Rem False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `low` | 76 | 39 | 37 | 22 | 11 | 11 | 50.0% | 50.0% | 36.7% | 73.3% |
| `mid_low` | 74 | 58 | 16 | 14 | 11 | 3 | 78.6% | 21.4% | 36.7% | 20.0% |
| `mid_high` | 74 | 58 | 16 | 5 | 4 | 1 | 80.0% | 20.0% | 13.3% | 6.7% |
| `high` | 75 | 61 | 14 | 4 | 4 | 0 | 100.0% | 0.0% | 13.3% | 0.0% |

### Remainder Quartiles

| Quartile | Score Min | Score Max | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.000 | 0.060 | 11 | 7 | 4 | 63.6% | 36.4% | 23.3% | 26.7% |
| 2 | 0.060 | 0.203 | 11 | 4 | 7 | 36.4% | 63.6% | 13.3% | 46.7% |
| 3 | 0.240 | 0.360 | 11 | 8 | 3 | 72.7% | 27.3% | 26.7% | 20.0% |
| 4 | 0.360 | 0.618 | 12 | 11 | 1 | 91.7% | 8.3% | 36.7% | 6.7% |

### Remainder Monotonicity

- High quartile near-positive rate: `91.7%`; low quartile near-positive rate: `63.6%`.
- High-to-low near-positive lift: `1.44x`.
- Low quartile false rate: `36.4%`; high quartile false rate: `8.3%`.
- High/low false-rate ratio: `0.23x`.

## Decision

- This report remains diagnostic-only. It compares score ablations for ranking the two within-family remainder modes without introducing suppression.
- It does not tune PLUM, suppress predictions, or authorize production UI/wording/notification changes.
