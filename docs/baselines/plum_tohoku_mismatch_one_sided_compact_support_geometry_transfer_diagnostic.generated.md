# PLUM Tohoku mismatch/one_sided/compact Support-Geometry Transfer Diagnostic

- Status: `pass`
- Method: `PLUM Tohoku mismatch/one_sided/compact support-geometry transfer diagnostic`
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
| `remainder target modes` | 45 |
| `evaluated slices` | 4 |

## Score Definition

- Validation anchors: q25 `0.333`, q50 `0.538`, q75 `0.667`.
- Validation near-threshold mean: `0.581`; false-middle-transition mean: `0.405`.

## Slice Summary

| Slice | Label | Samples | Near | False | Mean Gap | Stability | Low False Capture | Low Near Capture | High Near Rate | High False Rate | High/Low Near Lift | High/Low False Ratio |
| --- | --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `all_remainder` | `all remainder target modes` | 45 | 30 | 15 | 0.191 | `stable` | 60.0% | 26.7% | 100.0% | 0.0% | 1.53x | 0.37x |
| `2022070605102497-38.4125-141.9545` | `event` | 34 | 25 | 9 | 0.213 | `directional_but_noisy` | 55.6% | 20.0% | 100.0% | 0.0% | 2.00x | 0.00x |
| `2022031700522985-37.7947-141.7145` | `event` | 4 | 3 | 1 | 0.000 | `sample_sparse` | 100.0% | 100.0% | 0.0% | 0.0% | 0.00x | 0.00x |
| `2022080409481868-37.6118-141.6195` | `event` | 4 | 2 | 2 | 0.085 | `sample_sparse` | 0.0% | 0.0% | 0.0% | 0.0% | 0.00x | 0.00x |

## `all_remainder`

- Label: `all remainder target modes`; stability: `stable`.
- Near count `30`, false count `15`, mean gap `0.191`.

### Validation-Anchored Band Transfer

| Band | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `low` | 17 | 8 | 9 | 47.1% | 52.9% | 26.7% | 60.0% |
| `mid_low` | 11 | 7 | 4 | 63.6% | 36.4% | 23.3% | 26.7% |
| `mid_high` | 14 | 12 | 2 | 85.7% | 14.3% | 40.0% | 13.3% |
| `high` | 3 | 3 | 0 | 100.0% | 0.0% | 10.0% | 0.0% |

### Quartiles

| Quartile | Score Min | Score Max | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.000 | 0.067 | 11 | 6 | 5 | 54.5% | 45.5% | 20.0% | 33.3% |
| 2 | 0.067 | 0.407 | 11 | 6 | 5 | 54.5% | 45.5% | 20.0% | 33.3% |
| 3 | 0.417 | 0.578 | 11 | 8 | 3 | 72.7% | 27.3% | 26.7% | 20.0% |
| 4 | 0.593 | 1.000 | 12 | 10 | 2 | 83.3% | 16.7% | 33.3% | 13.3% |

### Monotonicity

- High quartile near-positive rate: `83.3%`; low quartile near-positive rate: `54.5%`.
- High-to-low near-positive lift: `1.53x`.
- Low quartile false rate: `45.5%`; high quartile false rate: `16.7%`.
- High/low false-rate ratio: `0.37x`.

## `2022070605102497-38.4125-141.9545`

- Label: `event`; stability: `directional_but_noisy`.
- Near count `25`, false count `9`, mean gap `0.213`.

### Validation-Anchored Band Transfer

| Band | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `low` | 10 | 5 | 5 | 50.0% | 50.0% | 20.0% | 55.6% |
| `mid_low` | 8 | 6 | 2 | 75.0% | 25.0% | 24.0% | 22.2% |
| `mid_high` | 13 | 11 | 2 | 84.6% | 15.4% | 44.0% | 22.2% |
| `high` | 3 | 3 | 0 | 100.0% | 0.0% | 12.0% | 0.0% |

### Quartiles

| Quartile | Score Min | Score Max | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.000 | 0.133 | 8 | 4 | 4 | 50.0% | 50.0% | 16.0% | 44.4% |
| 2 | 0.133 | 0.451 | 9 | 7 | 2 | 77.8% | 22.2% | 28.0% | 22.2% |
| 3 | 0.451 | 0.593 | 8 | 5 | 3 | 62.5% | 37.5% | 20.0% | 33.3% |
| 4 | 0.594 | 1.000 | 9 | 9 | 0 | 100.0% | 0.0% | 36.0% | 0.0% |

### Monotonicity

- High quartile near-positive rate: `100.0%`; low quartile near-positive rate: `50.0%`.
- High-to-low near-positive lift: `2.00x`.
- Low quartile false rate: `50.0%`; high quartile false rate: `0.0%`.
- High/low false-rate ratio: `0.00x`.

## `2022031700522985-37.7947-141.7145`

- Label: `event`; stability: `sample_sparse`.
- Near count `3`, false count `1`, mean gap `0.000`.

### Validation-Anchored Band Transfer

| Band | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `low` | 4 | 3 | 1 | 75.0% | 25.0% | 100.0% | 100.0% |
| `mid_low` | 0 | 0 | 0 | 0.0% | 0.0% | 0.0% | 0.0% |
| `mid_high` | 0 | 0 | 0 | 0.0% | 0.0% | 0.0% | 0.0% |
| `high` | 0 | 0 | 0 | 0.0% | 0.0% | 0.0% | 0.0% |

### Quartiles

| Quartile | Score Min | Score Max | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.000 | 0.000 | 1 | 0 | 1 | 0.0% | 100.0% | 0.0% | 100.0% |
| 2 | 0.000 | 0.000 | 1 | 1 | 0 | 100.0% | 0.0% | 33.3% | 0.0% |
| 3 | 0.000 | 0.000 | 1 | 1 | 0 | 100.0% | 0.0% | 33.3% | 0.0% |
| 4 | 0.000 | 0.000 | 1 | 1 | 0 | 100.0% | 0.0% | 33.3% | 0.0% |

### Monotonicity

- High quartile near-positive rate: `100.0%`; low quartile near-positive rate: `0.0%`.
- High-to-low near-positive lift: `0.00x`.
- Low quartile false rate: `100.0%`; high quartile false rate: `0.0%`.
- High/low false-rate ratio: `0.00x`.

## `2022080409481868-37.6118-141.6195`

- Label: `event`; stability: `sample_sparse`.
- Near count `2`, false count `2`, mean gap `0.085`.

### Validation-Anchored Band Transfer

| Band | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `low` | 0 | 0 | 0 | 0.0% | 0.0% | 0.0% | 0.0% |
| `mid_low` | 3 | 1 | 2 | 33.3% | 66.7% | 50.0% | 100.0% |
| `mid_high` | 1 | 1 | 0 | 100.0% | 0.0% | 50.0% | 0.0% |
| `high` | 0 | 0 | 0 | 0.0% | 0.0% | 0.0% | 0.0% |

### Quartiles

| Quartile | Score Min | Score Max | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.407 | 0.407 | 1 | 0 | 1 | 0.0% | 100.0% | 0.0% | 50.0% |
| 2 | 0.417 | 0.417 | 1 | 1 | 0 | 100.0% | 0.0% | 50.0% | 0.0% |
| 3 | 0.506 | 0.506 | 1 | 0 | 1 | 0.0% | 100.0% | 0.0% | 50.0% |
| 4 | 0.667 | 0.667 | 1 | 1 | 0 | 100.0% | 0.0% | 50.0% | 0.0% |

### Monotonicity

- High quartile near-positive rate: `100.0%`; low quartile near-positive rate: `0.0%`.
- High-to-low near-positive lift: `0.00x`.
- Low quartile false rate: `100.0%`; high quartile false rate: `0.0%`.
- High/low false-rate ratio: `0.00x`.

## Decision

- This report remains diagnostic-only. It checks whether the family-local `supportGeometry-only` score keeps its ranking behavior across additional event slices rather than only on the pooled remainder.
- It does not tune PLUM, suppress predictions, or authorize production UI/wording/notification changes.
