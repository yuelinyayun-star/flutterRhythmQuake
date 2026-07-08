# Source Candidate Rejection Residual Report

- Status: `pass`
- Core cases: `4`
- Inspect rejection cases: `2`
- Inspect rejected offline-positive frames: `10`
- Core rejected offline-positive frames: `13`
- Offline false accepts: `0`
- Production coordinate switches: `0`

## Policy

- Diagnostic-only. Candidate coordinates remain blocked from production switching.
- Truth-error columns are offline labels used only to inspect gate behavior.

## Case Summary

| Case | Action | Diagnosis | Cand | Accept | Miss | Delayed | Local delayed | Switch |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `20260621_fukushima_offshore_m32_eq6` | `inspect_candidate_rejection_residuals` | `residual_gate_rejects_offline_positive_candidates` | 8 | 0 | 7 | 0 | 0 | 0 |
| `20260622_kushiro_offshore_m30_jma` | `study_delayed_confirmation_recovery` | `residual_delayed_recovery_positive_guard` | 8 | 5 | 3 | 3 | 0 | 0 |
| `20260622_tomakomai_south_offshore_m35_hinet` | `keep_as_positive_residual_guard` | `residual_immediate_positive_guard` | 3 | 3 | 0 | 0 | 0 | 0 |
| `20260625_iwate_offshore_m32_jma` | `inspect_candidate_rejection_residuals` | `local_support_recovers_residual_rejection` | 3 | 0 | 3 | 0 | 1 | 0 |

## Rejected Offline-Positive Frames

### 20260621_fukushima_offshore_m32_eq6

| Time | Diagnosis | Base err | Cand err | Gain | Rank d | Atten d | Atten r | Travel r | Local support | Reject reason |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `2026-06-21T23:41:51.000` | `rejected_offline_positive` | 306.8 | 136.7 | 170.1 | 0.143 | 0.344 | 2.63 | 2.26 | `pending`, m=10, d=173.7, conv=-40.6, `one_sided` | `no_rank_or_attenuation_support`, `rank_and_attenuation_regress_together` |
| `2026-06-21T23:41:52.000` | `rejected_offline_positive` | 310.5 | 132.3 | 178.2 | 0.286 | 0.362 | 2.71 | 2.44 | `pending`, m=14, d=183.0, conv=-49.9, `one_sided` | `no_rank_or_attenuation_support`, `rank_and_attenuation_regress_together` |
| `2026-06-21T23:41:53.000` | `rejected_offline_positive` | 310.5 | 132.3 | 178.2 | 0.286 | 0.362 | 2.71 | 2.44 | `pending`, m=14, d=183.0, conv=-49.9, `one_sided` | `no_rank_or_attenuation_support`, `rank_and_attenuation_regress_together` |
| `2026-06-21T23:41:54.000` | `rejected_offline_positive` | 310.5 | 132.3 | 178.2 | 0.286 | 0.362 | 2.71 | 2.44 | `pending`, m=14, d=183.0, conv=-49.9, `one_sided` | `no_rank_or_attenuation_support`, `rank_and_attenuation_regress_together` |
| `2026-06-21T23:41:55.000` | `rejected_offline_positive` | 312.7 | 131.1 | 181.6 | 0.214 | 0.330 | 2.56 | 2.53 | `pending`, m=16, d=187.9, conv=-54.7, `one_sided` | `no_rank_or_attenuation_support`, `rank_and_attenuation_regress_together` |
| `2026-06-21T23:41:56.000` | `rejected_offline_positive` | 312.7 | 131.1 | 181.6 | 0.214 | 0.337 | 2.69 | 2.53 | `expired`, m=16, d=187.9, conv=-54.7, `one_sided` | `no_rank_or_attenuation_support`, `rank_and_attenuation_regress_together` |
| `2026-06-21T23:41:57.000` | `rejected_offline_positive` | 312.7 | 131.3 | 181.4 | 0.214 | 0.327 | 2.63 | 2.53 | `pending`, m=16, d=187.9, conv=0.0, `one_sided` | `no_rank_or_attenuation_support`, `rank_and_attenuation_regress_together` |

### 20260622_kushiro_offshore_m30_jma

| Time | Diagnosis | Base err | Cand err | Gain | Rank d | Atten d | Atten r | Travel r | Local support | Reject reason |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `2026-06-22T16:38:23.000` | `residual_delayed_recovered_positive` | 101.6 | 10.6 | 91.0 | 0.067 | 0.285 | 1.41 | 1.72 | `pending`, m=6, d=107.8, conv=--, `one_sided` | `no_rank_or_attenuation_support` |
| `2026-06-22T16:38:24.000` | `residual_delayed_recovered_positive` | 101.6 | 10.6 | 91.0 | 0.067 | 0.285 | 1.41 | 1.72 | `pending`, m=6, d=107.8, conv=0.0, `one_sided` | `no_rank_or_attenuation_support` |
| `2026-06-22T16:38:25.000` | `residual_delayed_recovered_positive` | 101.6 | 10.6 | 91.0 | 0.067 | 0.285 | 1.41 | 1.72 | `pending`, m=6, d=107.8, conv=0.0, `one_sided` | `no_rank_or_attenuation_support` |

### 20260625_iwate_offshore_m32_jma

| Time | Diagnosis | Base err | Cand err | Gain | Rank d | Atten d | Atten r | Travel r | Local support | Reject reason |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `2026-06-25T19:21:57.000` | `rejected_offline_positive` | 143.9 | 23.8 | 120.1 | 0.357 | 0.061 | 1.06 | 2.23 | `pending`, m=6, d=156.5, conv=--, `one_sided` | `no_rank_or_attenuation_support` |
| `2026-06-25T19:21:58.000` | `rejected_offline_positive` | 122.9 | 29.1 | 93.8 | 0.333 | 0.088 | 1.09 | 2.02 | `pending`, m=10, d=139.7, conv=16.8, `one_sided` | `no_rank_or_attenuation_support` |
| `2026-06-25T19:21:59.000` | `rejected_offline_positive` | 122.9 | 30.0 | 92.9 | 0.000 | 0.053 | 1.05 | 2.05 | `pending`, m=10, d=139.7, conv=16.8, `one_sided` | `no_rank_or_attenuation_support` |

## Candidate-Region Timeline Diagnostics

| Case | Time | Status | Reason | Residual | Local support | Members | Est-member | Converge | Geometry | Switch |
| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | --- | --- |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:41:50.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 5 | 133.1 | -- | `one_sided` | no |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:41:51.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 10 | 173.7 | -40.6 | `one_sided` | no |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:41:52.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 14 | 183.0 | -49.9 | `one_sided` | no |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:41:53.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 14 | 183.0 | -49.9 | `one_sided` | no |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:41:54.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 14 | 183.0 | -49.9 | `one_sided` | no |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:41:55.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 16 | 187.9 | -54.7 | `one_sided` | no |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:41:56.000` | `expired` | `pending_candidate_expired` | no | no | 16 | 187.9 | -54.7 | `one_sided` | no |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:41:57.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 16 | 187.9 | 0.0 | `one_sided` | no |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:41:58.000` | `pending` | `awaiting_local_member_support` | no | no | 17 | 36.6 | 151.2 | `one_sided` | no |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:41:59.000` | `pending` | `awaiting_local_member_support` | no | no | 17 | 36.6 | 151.2 | `one_sided` | no |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:42:00.000` | `pending` | `awaiting_local_member_support` | no | no | 17 | 5.7 | 182.2 | `surrounded` | no |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:42:01.000` | `pending` | `awaiting_local_member_support` | no | no | 17 | 5.7 | 182.2 | `surrounded` | no |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:42:02.000` | `expired` | `pending_candidate_expired` | no | no | 18 | 2.8 | 185.1 | `surrounded` | no |
| `20260622_kushiro_offshore_m30_jma` | `2026-06-22T16:38:23.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 6 | 107.8 | -- | `one_sided` | no |
| `20260622_kushiro_offshore_m30_jma` | `2026-06-22T16:38:24.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 6 | 107.8 | 0.0 | `one_sided` | no |
| `20260622_kushiro_offshore_m30_jma` | `2026-06-22T16:38:25.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 6 | 107.8 | 0.0 | `one_sided` | no |
| `20260622_kushiro_offshore_m30_jma` | `2026-06-22T16:38:26.000` | `pending` | `awaiting_local_member_support` | no | no | 8 | 44.1 | 63.6 | `one_sided` | no |
| `20260622_kushiro_offshore_m30_jma` | `2026-06-22T16:38:27.000` | `confirmedDelayed` | `same_region_residual_confirmation` | yes | no | 9 | 120.2 | -12.4 | `one_sided` | no |
| `20260622_kushiro_offshore_m30_jma` | `2026-06-22T16:38:28.000` | `confirmedImmediate` | `residual_supported_candidate` | yes | no | 10 | 153.2 | -- | `one_sided` | no |
| `20260622_kushiro_offshore_m30_jma` | `2026-06-22T16:38:29.000` | `confirmedImmediate` | `residual_supported_candidate` | yes | no | 10 | 153.2 | -- | `one_sided` | no |
| `20260622_kushiro_offshore_m30_jma` | `2026-06-22T16:38:30.000` | `confirmedImmediate` | `residual_supported_candidate` | yes | no | 13 | 162.7 | -- | `one_sided` | no |
| `20260622_kushiro_offshore_m30_jma` | `2026-06-22T16:38:31.000` | `confirmedImmediate` | `residual_supported_candidate` | yes | no | 13 | 162.7 | -- | `one_sided` | no |
| `20260622_tomakomai_south_offshore_m35_hinet` | `2026-06-22T20:38:18.000` | `confirmedImmediate` | `residual_supported_candidate` | yes | no | 7 | 110.0 | -- | `one_sided` | no |
| `20260622_tomakomai_south_offshore_m35_hinet` | `2026-06-22T20:38:19.000` | `confirmedImmediate` | `residual_supported_candidate` | yes | no | 7 | 110.0 | -- | `one_sided` | no |
| `20260622_tomakomai_south_offshore_m35_hinet` | `2026-06-22T20:38:20.000` | `confirmedImmediate` | `residual_supported_candidate` | yes | no | 8 | 115.5 | -- | `one_sided` | no |
| `20260625_iwate_offshore_m32_jma` | `2026-06-25T19:21:57.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 6 | 156.5 | -- | `one_sided` | no |
| `20260625_iwate_offshore_m32_jma` | `2026-06-25T19:21:58.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 10 | 139.7 | 16.8 | `one_sided` | no |
| `20260625_iwate_offshore_m32_jma` | `2026-06-25T19:21:59.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 10 | 139.7 | 16.8 | `one_sided` | no |
| `20260625_iwate_offshore_m32_jma` | `2026-06-25T19:22:00.000` | `confirmedDelayed` | `same_region_local_support_confirmation` | no | yes | 11 | 19.1 | 137.4 | `surrounded` | no |

## Validation

- Status: `pass`.
- Violations: none.

