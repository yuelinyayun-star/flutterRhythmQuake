# PLUM Tohoku Event-Concentration Diagnostic

- Status: `pass`
- Method: `PLUM Tohoku event-concentration diagnostic`
- Frozen test evaluated: `true`
- Production ready: `false`
- Production UI connected: `false`
- Diagnostic only: `true`
- Parameters tuned: `false`
- Suppression applied: `false`
- Raw predicted intensity mutated: `false`

## Coverage

- Validation variants: `2688`
- Test variants: `2757`
- Validation station forecasts: `69909`
- Test station forecasts: `60373`

## Focus Filter

- Estimated-source region: `tohoku`
- Minimum evidence count: `8`
- Maximum nearest evidence distance: `10.0 km`
- Baseline threshold crossing required: `true`
- PLUM margin gate applied: `false`

## Dominant Event

- Event: `2022031623342701-37.6810-141.6062`
- Test focus share: `97.6%` (3511 / 3598)
- Top 3 cumulative share: `99.7%`
- Top 5 cumulative share: `100.0%`

## Slice Summaries

| Slice | Samples | TP | FP | Precision | Middle Transition | PLUM-only FP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `validation` | 3250 | 1912 | 1338 | 58.8% | 93 (2.9%) | 342 |
| `testFull` | 3598 | 1455 | 2143 | 40.4% | 536 (14.9%) | 2085 |
| `dominantTestEventOnly` | 3511 | 1410 | 2101 | 40.2% | 521 (14.8%) | 2044 |
| `testWithoutDominantEvent` | 87 | 45 | 42 | 51.7% | 15 (17.2%) | 41 |

## Summary Delta

| Comparison | Sample Delta | Precision Delta | Middle Transition Delta | PLUM-only FP Delta |
| --- | ---: | ---: | ---: | ---: |
| `testFullVsLeaveTopEventOut` | -3511.0 | +11.3pp | +2.3pp | -2044.0 |
| `validationVsLeaveTopEventOut` | -3163.0 | -7.1pp | +14.4pp | -301.0 |

## Source Trigger Family Slices

| Family | Validation | Test Full | Dominant Event | Leave-Top-Event-Out |
| --- | --- | --- | --- | --- |
| `jma_only` | 815 / 25.1%, P 25.0%, MT 0.0% | 10 / 0.3%, P 50.0%, MT 0.0% | 8 / 0.2%, P 50.0%, MT 0.0% | 2 / 2.3%, P 50.0%, MT 0.0% |
| `plum_only` | 692 / 21.3%, P 50.6%, MT 9.0% | 3488 / 96.9%, P 40.2%, MT 14.7% | 3403 / 96.9%, P 39.9%, MT 14.7% | 85 / 97.7%, P 51.8%, MT 17.6% |
| `both` | 1743 / 53.6%, P 77.9%, MT 1.8% | 100 / 2.8%, P 47.0%, MT 22.0% | 100 / 2.8%, P 47.0%, MT 22.0% | 0 / 0.0%, P 0.0%, MT 0.0% |

## Source Winner Family Slices

| Family | Validation | Test Full | Dominant Event | Leave-Top-Event-Out |
| --- | --- | --- | --- | --- |
| `jma_higher` | 1310 / 40.3%, P 42.6%, MT 1.5% | 14 / 0.4%, P 50.0%, MT 0.0% | 12 / 0.3%, P 50.0%, MT 0.0% | 2 / 2.3%, P 50.0%, MT 0.0% |
| `plum_higher` | 1940 / 59.7%, P 69.8%, MT 3.8% | 3584 / 99.6%, P 40.4%, MT 15.0% | 3499 / 99.7%, P 40.1%, MT 14.9% | 85 / 97.7%, P 51.8%, MT 17.6% |
| `tied` | 0 / 0.0%, P 0.0%, MT 0.0% | 0 / 0.0%, P 0.0%, MT 0.0% | 0 / 0.0%, P 0.0%, MT 0.0% | 0 / 0.0%, P 0.0%, MT 0.0% |

## Source Winner x Transition Slices

| Winner | Label | Validation | Test Full | Dominant Event | Leave-Top-Event-Out |
| --- | --- | --- | --- | --- | --- |
| `plum_higher` | `other_focus_samples` | 1866 / 57.4%, P 72.3%, MT 0.0% | 3048 / 84.7%, P 39.9%, MT 0.0% | 2978 / 84.8%, P 39.4%, MT 0.0% | 70 / 80.5%, P 62.9%, MT 0.0% |
| `plum_higher` | `middle_transition_zone` | 74 / 2.3%, P 5.4%, MT 100.0% | 536 / 14.9%, P 43.3%, MT 100.0% | 521 / 14.8%, P 44.5%, MT 100.0% | 15 / 17.2%, P 0.0%, MT 100.0% |
| `jma_higher` | `other_focus_samples` | 1291 / 39.7%, P 42.8%, MT 0.0% | 14 / 0.4%, P 50.0%, MT 0.0% | 12 / 0.3%, P 50.0%, MT 0.0% | 2 / 2.3%, P 50.0%, MT 0.0% |
| `jma_higher` | `middle_transition_zone` | 19 / 0.6%, P 26.3%, MT 100.0% | 0 / 0.0%, P 0.0%, MT 0.0% | 0 / 0.0%, P 0.0%, MT 0.0% | 0 / 0.0%, P 0.0%, MT 0.0% |

## Test Event Concentration

| Event | Samples | TP | FP | Precision | Middle Transition | Winner | Family | Trigger Mix | Winner Mix |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- |
| `2022031623342701-37.6810-141.6062` | 3511 | 1410 | 2101 | 40.2% | 521 (14.8%) | `plum_higher` | `mismatch/one_sided/compact` | plum_only:3403, both:100, jma_only:8 | plum_higher:3499, jma_higher:12 |
| `2022070605102497-38.4125-141.9545` | 53 | 25 | 28 | 47.2% | 9 (17.0%) | `plum_higher` | `mismatch/one_sided/compact` | plum_only:53 | plum_higher:53 |
| `2022080409481868-37.6118-141.6195` | 23 | 15 | 8 | 65.2% | 2 (8.7%) | `plum_higher` | `consistent/one_sided/compact` | plum_only:21, jma_only:2 | plum_higher:21, jma_higher:2 |
| `2022031700522985-37.7947-141.7145` | 6 | 5 | 1 | 83.3% | 1 (16.7%) | `plum_higher` | `mismatch/one_sided/compact` | plum_only:6 | plum_higher:6 |
| `2022081814461047-37.6017-141.5853` | 5 | 0 | 5 | 0.0% | 3 (60.0%) | `plum_higher` | `mismatch/one_sided/compact` | plum_only:5 | plum_higher:5 |

## Decision

- This report stays diagnostic-only and is only meant to test whether the current PLUM-led hotspot is dominated by one test event.
- It does not tune PLUM, mutate raw predicted intensity, or connect any result to UI, wording, notification, or runtime policy.

