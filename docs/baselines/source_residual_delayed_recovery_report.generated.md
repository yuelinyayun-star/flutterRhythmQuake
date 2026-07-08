# Source Residual Delayed-Recovery Report

- Status: `pass`
- Delayed recovered positive frames: `3`
- False-recovery guard delayed recovered frames: `0`
- Positive guard delayed recovered frames: `3`
- Immediate positive guard accepted frames: `3`
- Production coordinate switches: `0`

## Case Summary

| Case | Role | Diagnosis | Rejected positive | Delayed recovered | Dual-reg rejected | Accepted positive | Immediate | Residual delayed | Switch |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `20260621_fukushima_offshore_m32_eq6` | `false_recovery_guard` | `dual_regression_blocks_false_recovery` | 7 | 0 | 7 | 0 | 0 | 0 | 0 |
| `20260622_kushiro_offshore_m30_jma` | `residual_delayed_positive_guard` | `same_region_residual_recovery_after_initial_no_support` | 3 | 3 | 0 | 5 | 4 | 1 | 0 |
| `20260622_tomakomai_south_offshore_m35_hinet` | `residual_immediate_positive_guard` | `immediate_acceptance_by_dual_residual_support` | 0 | 0 | 0 | 3 | 3 | 0 | 0 |

## Delayed Recovered Frames

| Case | Time | Delay | Base err | Cand err | Gain | Reject rank d | Reject atten r | Confirm time | Confirm rank d | Confirm atten d |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: |
| `20260622_kushiro_offshore_m30_jma` | `2026-06-22T16:38:23.000` | 4 | 101.6 | 10.6 | 91.0 | 0.067 | 1.41 | `2026-06-22T16:38:27.000` | -0.267 | -0.138 |
| `20260622_kushiro_offshore_m30_jma` | `2026-06-22T16:38:24.000` | 3 | 101.6 | 10.6 | 91.0 | 0.067 | 1.41 | `2026-06-22T16:38:27.000` | -0.267 | -0.138 |
| `20260622_kushiro_offshore_m30_jma` | `2026-06-22T16:38:25.000` | 2 | 101.6 | 10.6 | 91.0 | 0.067 | 1.41 | `2026-06-22T16:38:27.000` | -0.267 | -0.138 |

## Immediate Accepted Positive Frames

| Case | Time | Base err | Cand err | Gain | Rank d | Atten d | Atten r | Travel r |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `20260622_tomakomai_south_offshore_m35_hinet` | `2026-06-22T20:38:18.000` | 136.8 | 27.8 | 109.0 | -0.462 | -0.253 | 0.43 | 2.25 |
| `20260622_tomakomai_south_offshore_m35_hinet` | `2026-06-22T20:38:19.000` | 136.8 | 27.8 | 108.9 | -0.462 | -0.251 | 0.44 | 2.27 |
| `20260622_tomakomai_south_offshore_m35_hinet` | `2026-06-22T20:38:20.000` | 136.8 | 27.3 | 109.5 | -0.462 | -0.176 | 0.60 | 2.60 |

## False-Recovery Guard Rejected Positives

| Case | Time | Base err | Cand err | Gain | Rank d | Atten r | Travel r | Dual regression | Reasons |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:41:51.000` | 306.8 | 136.7 | 170.1 | 0.143 | 2.63 | 2.26 | yes | `no_rank_or_attenuation_support`, `rank_and_attenuation_regress_together` |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:41:52.000` | 310.5 | 132.3 | 178.2 | 0.286 | 2.71 | 2.44 | yes | `no_rank_or_attenuation_support`, `rank_and_attenuation_regress_together` |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:41:53.000` | 310.5 | 132.3 | 178.2 | 0.286 | 2.71 | 2.44 | yes | `no_rank_or_attenuation_support`, `rank_and_attenuation_regress_together` |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:41:54.000` | 310.5 | 132.3 | 178.2 | 0.286 | 2.71 | 2.44 | yes | `no_rank_or_attenuation_support`, `rank_and_attenuation_regress_together` |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:41:55.000` | 312.7 | 131.1 | 181.6 | 0.214 | 2.56 | 2.53 | yes | `no_rank_or_attenuation_support`, `rank_and_attenuation_regress_together` |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:41:56.000` | 312.7 | 131.1 | 181.6 | 0.214 | 2.69 | 2.53 | yes | `no_rank_or_attenuation_support`, `rank_and_attenuation_regress_together` |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:41:57.000` | 312.7 | 131.3 | 181.4 | 0.214 | 2.63 | 2.53 | yes | `no_rank_or_attenuation_support`, `rank_and_attenuation_regress_together` |

## Validation

- Status: `pass`.
- Violations: none.

