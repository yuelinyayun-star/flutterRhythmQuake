# Source Candidate-Region Timeline

Generated from benchmark reports. This is metadata-only validation; source estimate coordinates are not switched.

- Manifest: `docs/data/source_candidate_region_validation_manifest.json`

## Summary

| Case | Frames | Pending | Confirmed delayed | Confirmed immediate | Expired | Local support | Coordinate switches |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `20260621_fukushima_offshore_m32_eq6` | 13 | 11 | 0 (0 residual / 0 local) | 0 | 2 | 0 | 0 |
| `20260622_kushiro_offshore_m30_jma` | 9 | 4 | 1 (1 residual / 0 local) | 4 | 0 | 0 | 0 |
| `20260622_tomakomai_south_offshore_m35_hinet` | 3 | 0 | 0 (0 residual / 0 local) | 3 | 0 | 0 | 0 |
| `20260623_tokachi_southeast_offshore_m34_hinet` | 0 | 0 | 0 (0 residual / 0 local) | 0 | 0 | 0 | 0 |
| `20260624_fukushima_aizu_m32_jma_eq5` | 0 | 0 | 0 (0 residual / 0 local) | 0 | 0 | 0 | 0 |
| `20260625_iwate_offshore_m32_jma` | 4 | 3 | 1 (0 residual / 1 local) | 0 | 0 | 1 | 0 |

## Coverage Manifest

| Case | Role | Expectations |
| --- | --- | --- |
| `20260621_fukushima_offshore_m32_eq6` | `offshore_false_recovery_guard` | `localSupportConfirmedCount=0`, `confirmedDelayedCount=0`, `confirmedImmediateCount=0`, `coordinateSwitchAllowedCount=0` |
| `20260622_kushiro_offshore_m30_jma` | `residual_delayed_positive_guard` | `localSupportConfirmedCount=0`, `confirmedDelayedCount=1`, `residualConfirmedDelayedCount=1`, `localSupportConfirmedDelayedCount=0`, `confirmedImmediateCount=4`, `coordinateSwitchAllowedCount=0` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `residual_immediate_positive_guard` | `localSupportConfirmedCount=0`, `confirmedImmediateCount=3`, `coordinateSwitchAllowedCount=0` |
| `20260623_tokachi_southeast_offshore_m34_hinet` | `hokkaido_no_candidate_region_control` | `frameCount=0`, `coordinateSwitchAllowedCount=0` |
| `20260624_fukushima_aizu_m32_jma_eq5` | `inland_surrounded_control` | `frameCount=0`, `coordinateSwitchAllowedCount=0` |
| `20260625_iwate_offshore_m32_jma` | `local_support_delayed_positive_guard` | `pendingCount=3`, `localSupportConfirmedCount=1`, `confirmedDelayedCount=1`, `residualConfirmedDelayedCount=0`, `localSupportConfirmedDelayedCount=1`, `coordinateSwitchAllowedCount=0` |

## Timelines

### 20260621_fukushima_offshore_m32_eq6

| Time | Status | Reason | Residual | Local support | Region | Estimate | Delay | Cluster | Rank delta | Atten delta | Members | Est-member | Converge | Geometry | Switch |
| --- | --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `2026-06-21T23:41:50.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 38.406, 141.062 | 37.205, 141.021 | -- | 0.0km | 0.000 | 0.088 | 5 | 133.1km | -- | `one_sided` | no |
| `2026-06-21T23:41:51.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 38.406, 141.062 | 39.466, 139.661 | -- | 2.6km | 0.143 | 0.344 | 10 (+5) | 173.7km | -40.6km | `one_sided` | no |
| `2026-06-21T23:41:52.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 38.406, 141.062 | 39.516, 139.661 | -- | 6.7km | 0.286 | 0.362 | 14 (+9) | 183.0km | -49.9km | `one_sided` | no |
| `2026-06-21T23:41:53.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 38.406, 141.062 | 39.516, 139.661 | -- | 6.7km | 0.286 | 0.362 | 14 (+9) | 183.0km | -49.9km | `one_sided` | no |
| `2026-06-21T23:41:54.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 38.406, 141.062 | 39.516, 139.661 | -- | 6.7km | 0.286 | 0.362 | 14 (+9) | 183.0km | -49.9km | `one_sided` | no |
| `2026-06-21T23:41:55.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 38.406, 141.062 | 39.545, 139.661 | -- | 11.3km | 0.214 | 0.330 | 16 (+11) | 187.9km | -54.7km | `one_sided` | no |
| `2026-06-21T23:41:56.000` | `expired` | `pending_candidate_expired` | no | no | 38.406, 141.062 | 39.545, 139.661 | -- | 11.3km | 0.214 | 0.337 | 16 (+11) | 187.9km | -54.7km | `one_sided` | no |
| `2026-06-21T23:41:57.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 38.304, 141.064 | 39.545, 139.661 | -- | 0.3km | 0.214 | 0.327 | 16 (+0) | 187.9km | 0.0km | `one_sided` | no |
| `2026-06-21T23:41:58.000` | `pending` | `awaiting_local_member_support` | no | no | 38.304, 141.064 | 38.325, 140.626 | -- | -- | -- | -- | 17 (+1) | 36.6km | 151.2km | `one_sided` | no |
| `2026-06-21T23:41:59.000` | `pending` | `awaiting_local_member_support` | no | no | 38.304, 141.064 | 38.325, 140.626 | -- | -- | -- | -- | 17 (+1) | 36.6km | 151.2km | `one_sided` | no |
| `2026-06-21T23:42:00.000` | `pending` | `awaiting_local_member_support` | no | no | 38.304, 141.064 | 38.175, 141.006 | -- | -- | -- | -- | 17 (+1) | 5.7km | 182.2km | `surrounded` | no |
| `2026-06-21T23:42:01.000` | `pending` | `awaiting_local_member_support` | no | no | 38.304, 141.064 | 38.175, 141.006 | -- | -- | -- | -- | 17 (+1) | 5.7km | 182.2km | `surrounded` | no |
| `2026-06-21T23:42:02.000` | `expired` | `pending_candidate_expired` | no | no | 38.304, 141.064 | 38.195, 141.023 | -- | -- | -- | -- | 18 (+2) | 2.8km | 185.1km | `surrounded` | no |

### 20260622_kushiro_offshore_m30_jma

| Time | Status | Reason | Residual | Local support | Region | Estimate | Delay | Cluster | Rank delta | Atten delta | Members | Est-member | Converge | Geometry | Switch |
| --- | --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `2026-06-22T16:38:23.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 42.993, 144.029 | 42.224, 144.834 | -- | 0.0km | 0.067 | 0.285 | 6 | 107.8km | -- | `one_sided` | no |
| `2026-06-22T16:38:24.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 42.993, 144.029 | 42.224, 144.834 | -- | 0.0km | 0.067 | 0.285 | 6 (+0) | 107.8km | 0.0km | `one_sided` | no |
| `2026-06-22T16:38:25.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 42.993, 144.029 | 42.224, 144.834 | -- | 0.0km | 0.067 | 0.285 | 6 (+0) | 107.8km | 0.0km | `one_sided` | no |
| `2026-06-22T16:38:26.000` | `pending` | `awaiting_local_member_support` | no | no | 42.993, 144.029 | 42.634, 144.144 | -- | -- | -- | -- | 8 (+2) | 44.1km | 63.6km | `one_sided` | no |
| `2026-06-22T16:38:27.000` | `confirmedDelayed` | `same_region_residual_confirmation` | yes | no | 43.071, 144.163 | 43.604, 142.884 | 4.0s | 13.9km | -0.267 | -0.138 | 9 (+3) | 120.2km | -12.4km | `one_sided` | no |
| `2026-06-22T16:38:28.000` | `confirmedImmediate` | `residual_supported_candidate` | yes | no | 43.085, 144.113 | 41.834, 144.819 | 0.0s | 0.0km | -0.267 | -0.104 | 10 | 153.2km | -- | `one_sided` | no |
| `2026-06-22T16:38:29.000` | `confirmedImmediate` | `residual_supported_candidate` | yes | no | 43.085, 144.113 | 41.834, 144.819 | 0.0s | 0.0km | -0.267 | -0.104 | 10 | 153.2km | -- | `one_sided` | no |
| `2026-06-22T16:38:30.000` | `confirmedImmediate` | `residual_supported_candidate` | yes | no | 43.115, 144.034 | 41.834, 144.889 | 0.0s | 0.0km | -0.267 | -0.080 | 13 | 162.7km | -- | `one_sided` | no |
| `2026-06-22T16:38:31.000` | `confirmedImmediate` | `residual_supported_candidate` | yes | no | 43.115, 144.032 | 41.834, 144.889 | 0.0s | 0.0km | -0.267 | -0.078 | 13 | 162.7km | -- | `one_sided` | no |

### 20260622_tomakomai_south_offshore_m35_hinet

| Time | Status | Reason | Residual | Local support | Region | Estimate | Delay | Cluster | Rank delta | Atten delta | Members | Est-member | Converge | Geometry | Switch |
| --- | --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `2026-06-22T20:38:18.000` | `confirmedImmediate` | `residual_supported_candidate` | yes | no | 41.996, 141.023 | 42.089, 139.690 | 0.0s | 0.0km | -0.462 | -0.253 | 7 | 110.0km | -- | `one_sided` | no |
| `2026-06-22T20:38:19.000` | `confirmedImmediate` | `residual_supported_candidate` | yes | no | 41.994, 141.023 | 42.089, 139.690 | 0.0s | 0.0km | -0.462 | -0.251 | 7 | 110.0km | -- | `one_sided` | no |
| `2026-06-22T20:38:20.000` | `confirmedImmediate` | `residual_supported_candidate` | yes | no | 41.929, 141.070 | 42.089, 139.690 | 0.0s | 0.0km | -0.462 | -0.176 | 8 | 115.5km | -- | `one_sided` | no |

### 20260623_tokachi_southeast_offshore_m34_hinet

| Time | Status | Reason | Residual | Local support | Region | Estimate | Delay | Cluster | Rank delta | Atten delta | Members | Est-member | Converge | Geometry | Switch |
| --- | --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |

### 20260624_fukushima_aizu_m32_jma_eq5

| Time | Status | Reason | Residual | Local support | Region | Estimate | Delay | Cluster | Rank delta | Atten delta | Members | Est-member | Converge | Geometry | Switch |
| --- | --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |

### 20260625_iwate_offshore_m32_jma

| Time | Status | Reason | Residual | Local support | Region | Estimate | Delay | Cluster | Rank delta | Atten delta | Members | Est-member | Converge | Geometry | Switch |
| --- | --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `2026-06-25T19:21:57.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 39.718, 141.822 | 40.838, 142.907 | -- | 0.0km | 0.357 | 0.061 | 6 | 156.5km | -- | `one_sided` | no |
| `2026-06-25T19:21:58.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 39.718, 141.822 | 40.708, 142.695 | -- | 5.7km | 0.333 | 0.088 | 10 (+4) | 139.7km | 16.8km | `one_sided` | no |
| `2026-06-25T19:21:59.000` | `pending` | `awaiting_same_region_residual_support` | no | no | 39.718, 141.822 | 40.708, 142.695 | -- | 6.8km | 0.000 | 0.053 | 10 (+4) | 139.7km | 16.8km | `one_sided` | no |
| `2026-06-25T19:22:00.000` | `confirmedDelayed` | `same_region_local_support_confirmation` | no | yes | 39.718, 141.822 | 39.898, 141.705 | 3.0s | -- | -- | -- | 11 (+5) | 19.1km | 137.4km | `surrounded` | no |

## Validation

- Status: `pass`.
- Violations: none.

## Decision

- Delayed-confirmed candidate-region cases: `20260622_kushiro_offshore_m30_jma`, `20260625_iwate_offshore_m32_jma`.
- Residual delayed-confirmed cases: `20260622_kushiro_offshore_m30_jma`.
- Local-support delayed-confirmed cases: `20260625_iwate_offshore_m32_jma`.
- Immediate-confirmed candidate-region cases: `20260622_kushiro_offshore_m30_jma`, `20260622_tomakomai_south_offshore_m35_hinet`.
- Pending-only candidate-region cases: `20260621_fukushima_offshore_m32_eq6`.
- Local-support recovered cases: `20260625_iwate_offshore_m32_jma`.
- Production coordinate switch cases: none.
- Candidate-region metadata remains diagnostic-only. Pending-only cases must be treated as uncertainty evidence, not coordinate replacements.
