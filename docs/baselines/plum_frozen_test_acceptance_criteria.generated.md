# PLUM Frozen-Test Acceptance Criteria

- Status: `pass`
- Scope: `criteria_only_before_frozen_test`
- Frozen test evaluated: `false`
- Production ready: `false`
- Production UI connected: `false`

## Selected Operating Point

| Field | Value |
| --- | ---: |
| Candidate | `plum_like_r30_d0_50` |
| Combined method | `max_jma_style_plum_like_r30_d0_50` |
| Replay key | `r30_d0.50` |
| Radius | `30.0 km` |
| Damping | `0.5 shindo / 10 km` |
| Minimum evidence | `1` |

## Synthetic-Reveal Frozen Criteria

| Metric | Required |
| --- | ---: |
| Max-class MAE | <= `0.5` |
| Max-class underestimation | <= `25.0%` |
| Max-class within one | >= `94.0%` |
| Shindo4 precision | >= `52.0%` |
| Shindo4 recall | >= `68.0%` |
| Shindo4 F1 | >= `60.0%` |
| Shindo5- precision | >= `52.0%` |
| Shindo5- recall | >= `40.0%` |
| Shindo5- F1 | >= `48.0%` |

## Real-Replay Frozen Criteria

| Metric | Required |
| --- | ---: |
| Minimum cases | `7` |
| Minimum decoded frames | `1000` |
| Minimum shindo4 actual stations | `20` |
| Shindo4 recall | >= `55.0%` |
| Shindo4 false-alarm reduction | >= `25.0%` |
| Shindo4 false-alarm ratio | <= `50.0%` |
| Median lead | >= `0.0 s` |
| Shindo5- | `watch_metric_until_actual_station_count_reaches_10` |

## Decision

- Ready to run frozen evaluation: `true`
- Advance to production: `false`
- Next action: `run_plum_frozen_test_evaluation_once`

These criteria freeze the diagnostic operating point before frozen-test evaluation. They do not authorize production UI, notifications or warning wording.

