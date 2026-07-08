# PLUM Tohoku Upstream Source-Family Diagnostic

- Status: `pass`
- Method: `PLUM Tohoku upstream source-family diagnostic`
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

## Definitions

- `sourceTriggerFamily`
  - `jma_only`: JMA-style crosses threshold, PLUM r30/d0.50 does not
  - `plum_only`: PLUM r30/d0.50 crosses threshold, JMA-style does not
  - `both`: both JMA-style and PLUM r30/d0.50 cross threshold
- `sourceWinnerFamily`
  - `jma_higher`: JMA-style predicted intensity > PLUM r30/d0.50
  - `plum_higher`: PLUM r30/d0.50 predicted intensity > JMA-style
  - `tied`: JMA-style predicted intensity == PLUM r30/d0.50
- `eventFamily`
  - `localConsistency`: consistent if below-threshold share in 10km < 0.25, mixed if < 0.50, else mismatch
  - `geometry`: surrounded if supporting quadrants >= 3, else one_sided
  - `spread`: compact if max evidence spread < 20km, moderate if < 40km, else wide

## Split Summaries

| Split | Samples | TP | FP | Precision | Middle Transition | PLUM-only FP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| validation | 3250 | 1912 | 1338 | 58.8% | 93 (2.9%) | 342 |
| test | 3598 | 1455 | 2143 | 40.4% | 536 (14.9%) | 2085 |

## Source Trigger Family Transfer

| Family | Validation | Test | Delta Share | Delta Precision | Delta Middle Transition |
| --- | --- | --- | ---: | ---: | ---: |
| `jma_only` | 815 / 25.1%, P 25.0%, MT 0.0% | 10 / 0.3%, P 50.0%, MT 0.0% | -24.8pp | +25.0pp | 0.0pp |
| `plum_only` | 692 / 21.3%, P 50.6%, MT 9.0% | 3488 / 96.9%, P 40.2%, MT 14.7% | +75.7pp | -10.4pp | +5.8pp |
| `both` | 1743 / 53.6%, P 77.9%, MT 1.8% | 100 / 2.8%, P 47.0%, MT 22.0% | -50.9pp | -30.9pp | +20.2pp |

## Source Winner Family Transfer

| Family | Validation | Test | Delta Share | Delta Precision | Delta Middle Transition | Delta (PLUM-JMA) |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| `jma_higher` | 1310 / 40.3%, P 42.6%, MT 1.5% | 14 / 0.4%, P 50.0%, MT 0.0% | -39.9pp | +7.4pp | -1.5pp | +0.02 |
| `plum_higher` | 1940 / 59.7%, P 69.8%, MT 3.8% | 3584 / 99.6%, P 40.4%, MT 15.0% | +39.9pp | -29.4pp | +11.1pp | +0.94 |
| `tied` | 0 / 0.0%, P 0.0%, MT 0.0% | 0 / 0.0%, P 0.0%, MT 0.0% | 0.0pp | 0.0pp | 0.0pp | 0.00 |

## Source Winner x Transition Transfer

| Winner | Label | Validation | Test | Delta Share |
| --- | --- | --- | --- | ---: |
| `plum_higher` | `other_focus_samples` | 1866 / 57.4%, P 72.3%, MT 0.0% | 3048 / 84.7%, P 39.9%, MT 0.0% | +27.3pp |
| `plum_higher` | `middle_transition_zone` | 74 / 2.3%, P 5.4%, MT 100.0% | 536 / 14.9%, P 43.3%, MT 100.0% | +12.6pp |
| `jma_higher` | `other_focus_samples` | 1291 / 39.7%, P 42.8%, MT 0.0% | 14 / 0.4%, P 50.0%, MT 0.0% | -39.3pp |
| `jma_higher` | `middle_transition_zone` | 19 / 0.6%, P 26.3%, MT 100.0% | 0 / 0.0%, P 0.0%, MT 0.0% | -0.6pp |

## Source Winner x Event Family Transfer

| Winner | Event Family | Validation | Test | Delta Share |
| --- | --- | --- | --- | ---: |
| `plum_higher` | `mismatch/one_sided/compact` | 437 / 13.4%, P 33.9%, MT 16.2% | 2299 / 63.9%, P 38.7%, MT 11.5% | +50.5pp |
| `plum_higher` | `mismatch/one_sided/moderate` | 39 / 1.2%, P 64.1%, MT 2.6% | 463 / 12.9%, P 43.4%, MT 22.9% | +11.7pp |
| `plum_higher` | `mismatch/surrounded/moderate` | 79 / 2.4%, P 50.6%, MT 1.3% | 361 / 10.0%, P 42.9%, MT 24.7% | +7.6pp |
| `plum_higher` | `mismatch/surrounded/wide` | 22 / 0.7%, P 54.5%, MT 0.0% | 198 / 5.5%, P 43.4%, MT 25.3% | +4.8pp |
| `plum_higher` | `mismatch/surrounded/compact` | 12 / 0.4%, P 66.7%, MT 0.0% | 106 / 2.9%, P 40.6%, MT 12.3% | +2.6pp |
| `plum_higher` | `mismatch/one_sided/wide` | 4 / 0.1%, P 50.0%, MT 25.0% | 59 / 1.6%, P 47.5%, MT 23.7% | +1.5pp |
| `plum_higher` | `mixed/one_sided/moderate` | 29 / 0.9%, P 62.1%, MT 0.0% | 30 / 0.8%, P 43.3%, MT 0.0% | -0.1pp |
| `plum_higher` | `mixed/one_sided/compact` | 233 / 7.2%, P 57.9%, MT 0.0% | 23 / 0.6%, P 39.1%, MT 0.0% | -6.5pp |
| `plum_higher` | `mixed/surrounded/moderate` | 59 / 1.8%, P 64.4%, MT 0.0% | 16 / 0.4%, P 37.5%, MT 0.0% | -1.4pp |
| `plum_higher` | `mixed/surrounded/wide` | 55 / 1.7%, P 70.9%, MT 0.0% | 16 / 0.4%, P 37.5%, MT 0.0% | -1.2pp |
| `jma_higher` | `mismatch/one_sided/compact` | 817 / 25.1%, P 20.9%, MT 2.2% | 14 / 0.4%, P 50.0%, MT 0.0% | -24.7pp |
| `plum_higher` | `consistent/one_sided/compact` | 295 / 9.1%, P 85.4%, MT 0.0% | 13 / 0.4%, P 92.3%, MT 0.0% | -8.7pp |
| `plum_higher` | `consistent/surrounded/moderate` | 272 / 8.4%, P 96.7%, MT 0.0% | 0 / 0.0%, P 0.0%, MT 0.0% | -8.4pp |
| `plum_higher` | `consistent/surrounded/wide` | 237 / 7.3%, P 93.2%, MT 0.0% | 0 / 0.0%, P 0.0%, MT 0.0% | -7.3pp |
| `jma_higher` | `consistent/one_sided/compact` | 211 / 6.5%, P 87.7%, MT 0.0% | 0 / 0.0%, P 0.0%, MT 0.0% | -6.5pp |

## Dominant Test Events

| Event | Samples | TP | FP | Precision | Middle Transition | Dominant Winner | Dominant Event Family | Trigger Mix | Winner Mix |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- |
| `2022031623342701-37.6810-141.6062` | 3511 | 1410 | 2101 | 40.2% | 521 (14.8%) | `plum_higher` | `mismatch/one_sided/compact` | plum_only:3403, both:100, jma_only:8 | plum_higher:3499, jma_higher:12 |
| `2022070605102497-38.4125-141.9545` | 53 | 25 | 28 | 47.2% | 9 (17.0%) | `plum_higher` | `mismatch/one_sided/compact` | plum_only:53 | plum_higher:53 |
| `2022080409481868-37.6118-141.6195` | 23 | 15 | 8 | 65.2% | 2 (8.7%) | `plum_higher` | `consistent/one_sided/compact` | plum_only:21, jma_only:2 | plum_higher:21, jma_higher:2 |
| `2022031700522985-37.7947-141.7145` | 6 | 5 | 1 | 83.3% | 1 (16.7%) | `plum_higher` | `mismatch/one_sided/compact` | plum_only:6 | plum_higher:6 |
| `2022081814461047-37.6017-141.5853` | 5 | 0 | 5 | 0.0% | 3 (60.0%) | `plum_higher` | `mismatch/one_sided/compact` | plum_only:5 | plum_higher:5 |

## Decision

- This report stays diagnostic-only and does not tune PLUM, mutate raw predicted intensity, or connect anything to UI, wording, or notification.
- Its purpose is to identify whether the current frozen hotspot is primarily a PLUM-led source-family transfer problem before any future calibration or runtime change is considered.

