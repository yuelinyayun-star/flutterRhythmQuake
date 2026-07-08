# PLUM Tohoku mismatch/one_sided/compact Sub-Regime Audit

- Status: `pass`
- Method: `PLUM Tohoku mismatch/one_sided/compact sub-regime audit`
- Frozen test evaluated: `true`
- Production ready: `false`
- Production UI connected: `false`
- Diagnostic only: `true`
- Parameters tuned: `false`
- Suppression applied: `false`
- Raw predicted intensity mutated: `false`

## Scope

- Family: `mismatch/one_sided/compact`
- Removed dominant event: `2022031623342701-37.6810-141.6062`
- Validation family samples: `1254`
- Remainder family samples: `67`
- Remainder family false positives: `36`

## Family Summaries

| Slice | Samples | TP | FP | Precision | Middle Transition | PLUM-only FP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `validationFamily` | 1254 | 319 | 935 | 25.4% | 89 (7.1%) | 243 |
| `remainderFamily` | 67 | 31 | 36 | 46.3% | 15 (22.4%) | 35 |
| `remainderFamilyFalsePositives` | 36 | 0 | 36 | 0.0% | 15 (41.7%) | 35 |

## Transition Rows

| Label | Validation | Remainder | Delta Share | Delta Middle Transition | Delta Local Mismatch |
| --- | --- | --- | ---: | ---: | ---: |
| `middle_transition_zone` | 89 / 7.1%, P 6.7%, MT 100.0%, LM 0.68 | 15 / 22.4%, P 0.0%, MT 100.0%, LM 0.76 | +15.3pp | 0.0pp | +0.08 |
| `other_family_samples` | 1165 / 92.9%, P 26.9%, MT 0.0%, LM 0.79 | 52 / 77.6%, P 59.6%, MT 0.0%, LM 0.68 | -15.3pp | 0.0pp | -0.11 |

## Local Mismatch Rows

| Label | Validation | Remainder | Delta Share | Delta Middle Transition | Delta Local Mismatch |
| --- | --- | --- | ---: | ---: | ---: |
| `0.50_to_0.67` | 465 / 37.1%, P 44.1%, MT 11.2%, LM 0.57 | 42 / 62.7%, P 42.9%, MT 14.3%, LM 0.58 | +25.6pp | +3.1pp | +0.01 |
| `0.67_to_0.85` | 280 / 22.3%, P 22.9%, MT 7.9%, LM 0.77 | 12 / 17.9%, P 50.0%, MT 41.7%, LM 0.79 | -4.4pp | +33.8pp | +0.02 |
| `gte_0.85` | 509 / 40.6%, P 9.8%, MT 2.9%, LM 0.99 | 13 / 19.4%, P 53.8%, MT 30.8%, LM 0.99 | -21.2pp | +27.8pp | -0.00 |

## Gap Cells

| Actual Gap | Evidence Gap | Validation | Remainder | Delta Share |
| --- | --- | --- | --- | ---: |
| `0.0_to_1.0` | `lt_1.0` | 195 / 15.6%, P 100.0%, MT 0.0%, LM 0.63 | 30 / 44.8%, P 100.0%, MT 0.0%, LM 0.72 | +29.2pp |
| `-1.0_to_0.0` | `lt_1.0` | 241 / 19.2%, P 0.0%, MT 0.0%, LM 0.68 | 15 / 22.4%, P 0.0%, MT 0.0%, LM 0.60 | +3.2pp |
| `-1.0_to_0.0` | `1.0_to_2.0` | 83 / 6.6%, P 0.0%, MT 100.0%, LM 0.69 | 15 / 22.4%, P 0.0%, MT 100.0%, LM 0.76 | +15.8pp |
| `-2.0_to_-1.0` | `1.0_to_2.0` | 6 / 0.5%, P 0.0%, MT 0.0%, LM 0.74 | 4 / 6.0%, P 0.0%, MT 0.0%, LM 0.59 | +5.5pp |
| `-2.0_to_-1.0` | `2.0_to_3.0` | 5 / 0.4%, P 0.0%, MT 0.0%, LM 0.60 | 1 / 1.5%, P 0.0%, MT 0.0%, LM 0.67 | +1.1pp |
| `lt_-2.0` | `gte_3.0` | 15 / 1.2%, P 0.0%, MT 0.0%, LM 0.50 | 0 / 0.0%, P 0.0%, MT 0.0%, LM 0.00 | -1.2pp |
| `gte_1.0` | `lt_1.0` | 12 / 1.0%, P 100.0%, MT 0.0%, LM 0.54 | 0 / 0.0%, P 0.0%, MT 0.0%, LM 0.00 | -1.0pp |
| `0.0_to_1.0` | `1.0_to_2.0` | 6 / 0.5%, P 100.0%, MT 100.0%, LM 0.61 | 0 / 0.0%, P 0.0%, MT 0.0%, LM 0.00 | -0.5pp |
| `lt_-2.0` | `2.0_to_3.0` | 1 / 0.1%, P 0.0%, MT 0.0%, LM 0.50 | 0 / 0.0%, P 0.0%, MT 0.0%, LM 0.00 | -0.1pp |
| `-2.0_to_-1.0` | `gte_3.0` | 1 / 0.1%, P 0.0%, MT 0.0%, LM 0.50 | 0 / 0.0%, P 0.0%, MT 0.0%, LM 0.00 | -0.1pp |

## Joint Sub-Regime Rows

| Label | Validation | Remainder | Delta Share | Delta Middle Transition | Delta Local Mismatch |
| --- | --- | --- | ---: | ---: | ---: |
| `other_family_samples|0.50_to_0.67|0.0_to_1.0|lt_1.0` | 145 / 11.6%, P 100.0%, MT 0.0%, LM 0.57 | 18 / 26.9%, P 100.0%, MT 0.0%, LM 0.60 | +15.3pp | 0.0pp | +0.03 |
| `other_family_samples|0.50_to_0.67|-1.0_to_0.0|lt_1.0` | 131 / 10.4%, P 0.0%, MT 0.0%, LM 0.60 | 13 / 19.4%, P 0.0%, MT 0.0%, LM 0.55 | +9.0pp | 0.0pp | -0.05 |
| `middle_transition_zone|0.50_to_0.67|-1.0_to_0.0|1.0_to_2.0` | 46 / 3.7%, P 0.0%, MT 100.0%, LM 0.55 | 6 / 9.0%, P 0.0%, MT 100.0%, LM 0.58 | +5.3pp | 0.0pp | +0.03 |
| `other_family_samples|0.67_to_0.85|0.0_to_1.0|lt_1.0` | 43 / 3.4%, P 100.0%, MT 0.0%, LM 0.76 | 6 / 9.0%, P 100.0%, MT 0.0%, LM 0.78 | +5.5pp | 0.0pp | +0.02 |
| `other_family_samples|gte_0.85|0.0_to_1.0|lt_1.0` | 7 / 0.6%, P 100.0%, MT 0.0%, LM 1.00 | 6 / 9.0%, P 100.0%, MT 0.0%, LM 1.00 | +8.4pp | 0.0pp | 0.00 |
| `middle_transition_zone|0.67_to_0.85|-1.0_to_0.0|1.0_to_2.0` | 22 / 1.8%, P 0.0%, MT 100.0%, LM 0.77 | 5 / 7.5%, P 0.0%, MT 100.0%, LM 0.80 | +5.7pp | 0.0pp | +0.03 |
| `middle_transition_zone|gte_0.85|-1.0_to_0.0|1.0_to_2.0` | 15 / 1.2%, P 0.0%, MT 100.0%, LM 0.97 | 4 / 6.0%, P 0.0%, MT 100.0%, LM 0.96 | +4.8pp | 0.0pp | -0.01 |
| `other_family_samples|0.50_to_0.67|-2.0_to_-1.0|1.0_to_2.0` | 2 / 0.2%, P 0.0%, MT 0.0%, LM 0.58 | 4 / 6.0%, P 0.0%, MT 0.0%, LM 0.59 | +5.8pp | 0.0pp | +0.00 |
| `other_family_samples|gte_0.85|-1.0_to_0.0|missing` | 299 / 23.8%, P 0.0%, MT 0.0%, LM 0.99 | 1 / 1.5%, P 0.0%, MT 0.0%, LM 1.00 | -22.4pp | 0.0pp | +0.01 |
| `other_family_samples|0.67_to_0.85|-1.0_to_0.0|lt_1.0` | 97 / 7.7%, P 0.0%, MT 0.0%, LM 0.76 | 1 / 1.5%, P 0.0%, MT 0.0%, LM 0.80 | -6.2pp | 0.0pp | +0.04 |
| `other_family_samples|gte_0.85|0.0_to_1.0|missing` | 42 / 3.3%, P 100.0%, MT 0.0%, LM 0.99 | 1 / 1.5%, P 100.0%, MT 0.0%, LM 1.00 | -1.9pp | 0.0pp | +0.01 |
| `other_family_samples|gte_0.85|-1.0_to_0.0|lt_1.0` | 13 / 1.0%, P 0.0%, MT 0.0%, LM 0.88 | 1 / 1.5%, P 0.0%, MT 0.0%, LM 1.00 | +0.5pp | 0.0pp | +0.12 |

## Remainder Events

| Event | Samples | TP | FP | Precision | Middle Transition | Winner | Trigger Mix |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `2022070605102497-38.4125-141.9545` | 48 | 25 | 23 | 52.1% | 9 (18.8%) | `plum_higher` | plum_only:48 |
| `2022080409481868-37.6118-141.6195` | 10 | 3 | 7 | 30.0% | 2 (20.0%) | `plum_higher` | plum_only:8, jma_only:2 |
| `2022081814461047-37.6017-141.5853` | 5 | 0 | 5 | 0.0% | 3 (60.0%) | `plum_higher` | plum_only:5 |
| `2022031700522985-37.7947-141.7145` | 4 | 3 | 1 | 75.0% | 1 (25.0%) | `plum_higher` | plum_only:4 |

## Decision

- This report stays diagnostic-only and only tests whether a narrower frozen-only slice exists inside `mismatch/one_sided/compact`.
- It does not tune PLUM, mutate raw predicted intensity, or connect results to UI, wording, notification, or runtime policy.

