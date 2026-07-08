# PLUM Tohoku Residual Remainder Family Audit

- Status: `pass`
- Method: `PLUM Tohoku residual remainder family audit`
- Frozen test evaluated: `true`
- Production ready: `false`
- Production UI connected: `false`
- Diagnostic only: `true`
- Parameters tuned: `false`
- Suppression applied: `false`
- Raw predicted intensity mutated: `false`

## Scope

- Removed dominant event: `2022031623342701-37.6810-141.6062`
- Estimated-source region: `tohoku`
- Minimum evidence count: `8`
- Maximum nearest evidence distance: `10.0 km`
- Remainder focus samples: `87`
- Remainder false positives: `42`
- Remainder PLUM-only false positives: `41`
- Remainder PLUM-higher false positives: `41`

## Slice Summaries

| Slice | Samples | TP | FP | Precision | Middle Transition | PLUM-only FP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `validation` | 3250 | 1912 | 1338 | 58.8% | 93 (2.9%) | 342 |
| `remainder` | 87 | 45 | 42 | 51.7% | 15 (17.2%) | 41 |
| `remainderFalsePositives` | 42 | 0 | 42 | 0.0% | 15 (35.7%) | 41 |
| `remainderPlumOnlyFalsePositives` | 41 | 0 | 41 | 0.0% | 15 (36.6%) | 41 |
| `remainderPlumHigherFalsePositives` | 41 | 0 | 41 | 0.0% | 15 (36.6%) | 41 |

## Dominance Summary

| Slice | Top Family | Top Share | Top-2 | Top-3 | Family Count |
| --- | --- | ---: | ---: | ---: | ---: |
| `remainderAll` | `mismatch/one_sided/compact` | 77.0% | 92.0% | 100.0% | 3 |
| `remainderFalsePositives` | `mismatch/one_sided/compact` | 85.7% | 97.6% | 100.0% | 3 |
| `remainderPlumOnlyFalsePositives` | `mismatch/one_sided/compact` | 85.4% | 97.6% | 100.0% | 3 |
| `remainderPlumHigherFalsePositives` | `mismatch/one_sided/compact` | 85.4% | 97.6% | 100.0% | 3 |

## Validation Families

| Family | Count | TP | FP | Precision | Middle Transition | PLUM-only FP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `mismatch/one_sided/compact` | 1254 | 319 | 935 | 25.4% | 89 (7.1%) | 243 |
| `consistent/one_sided/compact` | 506 | 437 | 69 | 86.4% | 0 (0.0%) | 26 |
| `mixed/one_sided/compact` | 384 | 230 | 154 | 59.9% | 0 (0.0%) | 63 |
| `consistent/surrounded/moderate` | 300 | 290 | 10 | 96.7% | 0 (0.0%) | 4 |
| `consistent/surrounded/wide` | 245 | 228 | 17 | 93.1% | 0 (0.0%) | 0 |
| `consistent/one_sided/moderate` | 125 | 118 | 7 | 94.4% | 0 (0.0%) | 0 |
| `mismatch/surrounded/moderate` | 79 | 40 | 39 | 50.6% | 1 (1.3%) | 1 |
| `mixed/surrounded/moderate` | 72 | 47 | 25 | 65.3% | 0 (0.0%) | 0 |
| `consistent/surrounded/compact` | 66 | 64 | 2 | 97.0% | 0 (0.0%) | 1 |
| `mixed/surrounded/wide` | 55 | 39 | 16 | 70.9% | 0 (0.0%) | 0 |
| `mismatch/one_sided/moderate` | 50 | 32 | 18 | 64.0% | 1 (2.0%) | 0 |
| `mixed/one_sided/moderate` | 49 | 30 | 19 | 61.2% | 0 (0.0%) | 2 |

## Remainder Families

| Family | Count | TP | FP | Precision | Middle Transition | PLUM-only FP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `mismatch/one_sided/compact` | 67 | 31 | 36 | 46.3% | 15 (22.4%) | 35 |
| `consistent/one_sided/compact` | 13 | 12 | 1 | 92.3% | 0 (0.0%) | 1 |
| `mixed/one_sided/compact` | 7 | 2 | 5 | 28.6% | 0 (0.0%) | 5 |

## Remainder False-Positive Families

| Family | Count | TP | FP | Precision | Middle Transition | PLUM-only FP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `mismatch/one_sided/compact` | 36 | 0 | 36 | 0.0% | 15 (41.7%) | 35 |
| `mixed/one_sided/compact` | 5 | 0 | 5 | 0.0% | 0 (0.0%) | 5 |
| `consistent/one_sided/compact` | 1 | 0 | 1 | 0.0% | 0 (0.0%) | 1 |

## Remainder PLUM-Only False-Positive Families

| Family | Count | TP | FP | Precision | Middle Transition | PLUM-only FP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `mismatch/one_sided/compact` | 35 | 0 | 35 | 0.0% | 15 (42.9%) | 35 |
| `mixed/one_sided/compact` | 5 | 0 | 5 | 0.0% | 0 (0.0%) | 5 |
| `consistent/one_sided/compact` | 1 | 0 | 1 | 0.0% | 0 (0.0%) | 1 |

## Remainder PLUM-Higher False-Positive Families

| Family | Count | TP | FP | Precision | Middle Transition | PLUM-only FP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `mismatch/one_sided/compact` | 35 | 0 | 35 | 0.0% | 15 (42.9%) | 35 |
| `mixed/one_sided/compact` | 5 | 0 | 5 | 0.0% | 0 (0.0%) | 5 |
| `consistent/one_sided/compact` | 1 | 0 | 1 | 0.0% | 0 (0.0%) | 1 |

## Remainder Events

| Event | Samples | TP | FP | Precision | Middle Transition | Winner | Family | Trigger Mix | Winner Mix |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- |
| `2022070605102497-38.4125-141.9545` | 53 | 25 | 28 | 47.2% | 9 (17.0%) | `plum_higher` | `mismatch/one_sided/compact` | plum_only:53 | plum_higher:53 |
| `2022080409481868-37.6118-141.6195` | 23 | 15 | 8 | 65.2% | 2 (8.7%) | `plum_higher` | `consistent/one_sided/compact` | plum_only:21, jma_only:2 | plum_higher:21, jma_higher:2 |
| `2022031700522985-37.7947-141.7145` | 6 | 5 | 1 | 83.3% | 1 (16.7%) | `plum_higher` | `mismatch/one_sided/compact` | plum_only:6 | plum_higher:6 |
| `2022081814461047-37.6017-141.5853` | 5 | 0 | 5 | 0.0% | 3 (60.0%) | `plum_higher` | `mismatch/one_sided/compact` | plum_only:5 | plum_higher:5 |

## Decision

- This report stays diagnostic-only and only audits whether the leave-top-event-out remainder forms a stable transferable family.
- It does not tune PLUM, mutate raw predicted intensity, or connect results to UI, wording, notification, or runtime policy.

