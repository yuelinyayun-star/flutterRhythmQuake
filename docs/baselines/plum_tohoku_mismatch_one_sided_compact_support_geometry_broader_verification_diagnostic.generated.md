# PLUM Tohoku mismatch/one_sided/compact Support-Geometry Broader Verification Diagnostic

- Status: `pass`
- Method: `PLUM Tohoku mismatch/one_sided/compact support-geometry broader verification diagnostic`
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
| `remainder events` | 4 |
| `evaluated slices` | 8 |
| `leave-event-out pooled slices` | 4 |
| `event-only slices` | 3 |

## Score Definition

- Validation anchors: q25 `0.333`, q50 `0.538`, q75 `0.667`.
- Validation near-threshold mean: `0.581`; false-middle-transition mean: `0.405`.

## Slice Category Summary

| Category | Total | Stable | Directional But Noisy | Sample Sparse | Not Stable |
| --- | ---: | ---: | ---: | ---: | ---: |
| `pooled_remainder` | 1 | 1 | 0 | 0 | 0 |
| `leave_event_out_pool` | 4 | 0 | 3 | 0 | 1 |
| `event_only` | 3 | 0 | 1 | 2 | 0 |

## Slice Summary

| Slice | Category | Label | Samples | Near | False | Mean Gap | Stability | Low False Capture | Low Near Capture | High Near Rate | High False Rate | High/Low Near Lift | High/Low False Ratio |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `all_remainder` | `pooled_remainder` | `all remainder target modes` | 45 | 30 | 15 | 0.191 | `stable` | 60.0% | 26.7% | 100.0% | 0.0% | 1.53x | 0.37x |
| `leave_event_out::2022070605102497-38.4125-141.9545` | `leave_event_out_pool` | `leave-event-out pooled remainder` | 11 | 5 | 6 | 0.007 | `not_stable` | 66.7% | 60.0% | 0.0% | 0.0% | 1.33x | 0.67x |
| `event_only::2022070605102497-38.4125-141.9545` | `event_only` | `event-only slice` | 34 | 25 | 9 | 0.213 | `directional_but_noisy` | 55.6% | 20.0% | 100.0% | 0.0% | 2.00x | 0.00x |
| `leave_event_out::2022031700522985-37.7947-141.7145` | `leave_event_out_pool` | `leave-event-out pooled remainder` | 41 | 27 | 14 | 0.221 | `directional_but_noisy` | 57.1% | 18.5% | 100.0% | 0.0% | 2.27x | 0.15x |
| `event_only::2022031700522985-37.7947-141.7145` | `event_only` | `event-only slice` | 4 | 3 | 1 | 0.000 | `sample_sparse` | 100.0% | 100.0% | 0.0% | 0.0% | 0.00x | 0.00x |
| `leave_event_out::2022080409481868-37.6118-141.6195` | `leave_event_out_pool` | `leave-event-out pooled remainder` | 41 | 28 | 13 | 0.216 | `directional_but_noisy` | 69.2% | 28.6% | 100.0% | 0.0% | 1.36x | 0.45x |
| `event_only::2022080409481868-37.6118-141.6195` | `event_only` | `event-only slice` | 4 | 2 | 2 | 0.085 | `sample_sparse` | 0.0% | 0.0% | 0.0% | 0.0% | 0.00x | 0.00x |
| `leave_event_out::2022081814461047-37.6017-141.5853` | `leave_event_out_pool` | `leave-event-out pooled remainder` | 42 | 30 | 12 | 0.159 | `directional_but_noisy` | 50.0% | 26.7% | 100.0% | 0.0% | 1.52x | 0.23x |

## `all_remainder`

- Category: `pooled_remainder`; label: `all remainder target modes`; stability: `stable`.
- Included events: `2022070605102497-38.4125-141.9545, 2022031700522985-37.7947-141.7145, 2022080409481868-37.6118-141.6195, 2022081814461047-37.6017-141.5853`; excluded events: `none`.
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

## `leave_event_out::2022070605102497-38.4125-141.9545`

- Category: `leave_event_out_pool`; label: `leave-event-out pooled remainder`; stability: `not_stable`.
- Included events: `2022031700522985-37.7947-141.7145, 2022080409481868-37.6118-141.6195, 2022081814461047-37.6017-141.5853`; excluded events: `2022070605102497-38.4125-141.9545`.
- Near count `5`, false count `6`, mean gap `0.007`.

### Validation-Anchored Band Transfer

| Band | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `low` | 7 | 3 | 4 | 42.9% | 57.1% | 60.0% | 66.7% |
| `mid_low` | 3 | 1 | 2 | 33.3% | 66.7% | 20.0% | 33.3% |
| `mid_high` | 1 | 1 | 0 | 100.0% | 0.0% | 20.0% | 0.0% |
| `high` | 0 | 0 | 0 | 0.0% | 0.0% | 0.0% | 0.0% |

### Quartiles

| Quartile | Score Min | Score Max | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.000 | 0.000 | 2 | 1 | 1 | 50.0% | 50.0% | 20.0% | 16.7% |
| 2 | 0.000 | 0.019 | 3 | 2 | 1 | 66.7% | 33.3% | 40.0% | 16.7% |
| 3 | 0.106 | 0.407 | 3 | 0 | 3 | 0.0% | 100.0% | 0.0% | 50.0% |
| 4 | 0.417 | 0.667 | 3 | 2 | 1 | 66.7% | 33.3% | 40.0% | 16.7% |

### Monotonicity

- High quartile near-positive rate: `66.7%`; low quartile near-positive rate: `50.0%`.
- High-to-low near-positive lift: `1.33x`.
- Low quartile false rate: `50.0%`; high quartile false rate: `33.3%`.
- High/low false-rate ratio: `0.67x`.

## `event_only::2022070605102497-38.4125-141.9545`

- Category: `event_only`; label: `event-only slice`; stability: `directional_but_noisy`.
- Included events: `2022070605102497-38.4125-141.9545`; excluded events: `none`.
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

## `leave_event_out::2022031700522985-37.7947-141.7145`

- Category: `leave_event_out_pool`; label: `leave-event-out pooled remainder`; stability: `directional_but_noisy`.
- Included events: `2022070605102497-38.4125-141.9545, 2022080409481868-37.6118-141.6195, 2022081814461047-37.6017-141.5853`; excluded events: `2022031700522985-37.7947-141.7145`.
- Near count `27`, false count `14`, mean gap `0.221`.

### Validation-Anchored Band Transfer

| Band | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `low` | 13 | 5 | 8 | 38.5% | 61.5% | 18.5% | 57.1% |
| `mid_low` | 11 | 7 | 4 | 63.6% | 36.4% | 25.9% | 28.6% |
| `mid_high` | 14 | 12 | 2 | 85.7% | 14.3% | 44.4% | 14.3% |
| `high` | 3 | 3 | 0 | 100.0% | 0.0% | 11.1% | 0.0% |

### Quartiles

| Quartile | Score Min | Score Max | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.000 | 0.133 | 10 | 4 | 6 | 40.0% | 60.0% | 14.8% | 42.9% |
| 2 | 0.133 | 0.417 | 10 | 7 | 3 | 70.0% | 30.0% | 25.9% | 21.4% |
| 3 | 0.417 | 0.593 | 10 | 6 | 4 | 60.0% | 40.0% | 22.2% | 28.6% |
| 4 | 0.593 | 1.000 | 11 | 10 | 1 | 90.9% | 9.1% | 37.0% | 7.1% |

### Monotonicity

- High quartile near-positive rate: `90.9%`; low quartile near-positive rate: `40.0%`.
- High-to-low near-positive lift: `2.27x`.
- Low quartile false rate: `60.0%`; high quartile false rate: `9.1%`.
- High/low false-rate ratio: `0.15x`.

## `event_only::2022031700522985-37.7947-141.7145`

- Category: `event_only`; label: `event-only slice`; stability: `sample_sparse`.
- Included events: `2022031700522985-37.7947-141.7145`; excluded events: `none`.
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

## `leave_event_out::2022080409481868-37.6118-141.6195`

- Category: `leave_event_out_pool`; label: `leave-event-out pooled remainder`; stability: `directional_but_noisy`.
- Included events: `2022070605102497-38.4125-141.9545, 2022031700522985-37.7947-141.7145, 2022081814461047-37.6017-141.5853`; excluded events: `2022080409481868-37.6118-141.6195`.
- Near count `28`, false count `13`, mean gap `0.216`.

### Validation-Anchored Band Transfer

| Band | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `low` | 17 | 8 | 9 | 47.1% | 52.9% | 28.6% | 69.2% |
| `mid_low` | 8 | 6 | 2 | 75.0% | 25.0% | 21.4% | 15.4% |
| `mid_high` | 13 | 11 | 2 | 84.6% | 15.4% | 39.3% | 15.4% |
| `high` | 3 | 3 | 0 | 100.0% | 0.0% | 10.7% | 0.0% |

### Quartiles

| Quartile | Score Min | Score Max | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.000 | 0.019 | 10 | 6 | 4 | 60.0% | 40.0% | 21.4% | 30.8% |
| 2 | 0.067 | 0.356 | 10 | 5 | 5 | 50.0% | 50.0% | 17.9% | 38.5% |
| 3 | 0.356 | 0.578 | 10 | 8 | 2 | 80.0% | 20.0% | 28.6% | 15.4% |
| 4 | 0.593 | 1.000 | 11 | 9 | 2 | 81.8% | 18.2% | 32.1% | 15.4% |

### Monotonicity

- High quartile near-positive rate: `81.8%`; low quartile near-positive rate: `60.0%`.
- High-to-low near-positive lift: `1.36x`.
- Low quartile false rate: `40.0%`; high quartile false rate: `18.2%`.
- High/low false-rate ratio: `0.45x`.

## `event_only::2022080409481868-37.6118-141.6195`

- Category: `event_only`; label: `event-only slice`; stability: `sample_sparse`.
- Included events: `2022080409481868-37.6118-141.6195`; excluded events: `none`.
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

## `leave_event_out::2022081814461047-37.6017-141.5853`

- Category: `leave_event_out_pool`; label: `leave-event-out pooled remainder`; stability: `directional_but_noisy`.
- Included events: `2022070605102497-38.4125-141.9545, 2022031700522985-37.7947-141.7145, 2022080409481868-37.6118-141.6195`; excluded events: `2022081814461047-37.6017-141.5853`.
- Near count `30`, false count `12`, mean gap `0.159`.

### Validation-Anchored Band Transfer

| Band | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `low` | 14 | 8 | 6 | 57.1% | 42.9% | 26.7% | 50.0% |
| `mid_low` | 11 | 7 | 4 | 63.6% | 36.4% | 23.3% | 33.3% |
| `mid_high` | 14 | 12 | 2 | 85.7% | 14.3% | 40.0% | 16.7% |
| `high` | 3 | 3 | 0 | 100.0% | 0.0% | 10.0% | 0.0% |

### Quartiles

| Quartile | Score Min | Score Max | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.000 | 0.067 | 10 | 6 | 4 | 60.0% | 40.0% | 20.0% | 33.3% |
| 2 | 0.067 | 0.417 | 11 | 8 | 3 | 72.7% | 27.3% | 26.7% | 25.0% |
| 3 | 0.417 | 0.593 | 10 | 6 | 4 | 60.0% | 40.0% | 20.0% | 33.3% |
| 4 | 0.593 | 1.000 | 11 | 10 | 1 | 90.9% | 9.1% | 33.3% | 8.3% |

### Monotonicity

- High quartile near-positive rate: `90.9%`; low quartile near-positive rate: `60.0%`.
- High-to-low near-positive lift: `1.52x`.
- Low quartile false rate: `40.0%`; high quartile false rate: `9.1%`.
- High/low false-rate ratio: `0.23x`.

## Decision

- This report remains diagnostic-only. It extends the family-local `supportGeometry-only` check beyond the original pooled remainder by adding leave-event-out pooled slices and event-only slices.
- The leave-event-out pooled slices are the main broader-verification signal: if those collapse when one event is removed, the ranking is still event-mix dependent rather than broadly transferable.
- It does not tune PLUM, suppress predictions, or authorize production UI/wording/notification changes.
