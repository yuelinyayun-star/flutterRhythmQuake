# Source Estimation Split Blocker Queue

- Status: `pass`
- Readiness report: `.dart_tool/source_estimation_split_assignment_readiness/report.json`
- Readiness status: `pass`
- Blocked cases: `12`
- Completed split assignments: `7`
- Manual-ready blocked cases: `0`

## Validation

- Errors: none
- Warnings: none

## Next Action Counts

| Next action | Count | Guidance |
| --- | ---: | --- |
| `keep_candidate_region_false_recovery_diagnostic_only` | 1 | Keep the false-recovery guard diagnostic-only until an explicit split gate approves promotion. |
| `keep_plum_like_diagnostic_only` | 6 | Inspect the readiness report for the required evidence. |
| `link_final_catalog_or_hinet_revision` | 1 | Link a final catalog or revised Hi-net source before assignment. |
| `review_hinet_preliminary_truth_quality` | 1 | Manually review Hi-net preliminary truth quality before assignment. |
| `review_jma_catalog_link` | 3 | Link a versioned JMA final catalog record before split assignment. |

## Blocked Cases

| Case | Planned use | Split | Next action | Pending conditions | Guidance |
| --- | --- | --- | --- | --- | --- |
| `20260622_kushiro_offshore_m30_jma` | `candidate_region_residual_positive_guard` | `unassigned_reference` | `review_jma_catalog_link` | `review_jma_catalog_link`, `assign_event_level_split` | Link a versioned JMA final catalog record before split assignment. |
| `20260624_fukushima_aizu_m32_jma_eq5` | `inland_surrounded_control` | `unassigned_reference` | `review_jma_catalog_link` | `review_jma_catalog_link`, `assign_event_level_split` | Link a versioned JMA final catalog record before split assignment. |
| `20260625_iwate_offshore_m32_jma` | `candidate_region_local_support_positive_guard` | `unassigned_reference` | `review_jma_catalog_link` | `review_jma_catalog_link`, `assign_event_level_split` | Link a versioned JMA final catalog record before split assignment. |
| `20260620_iwate_offshore_m34_ref` | `offshore_reference_pool` | `unassigned_reference` | `review_hinet_preliminary_truth_quality` | `review_hinet_preliminary_truth_quality`, `confirm_capture_provenance`, `assign_event_level_split` | Manually review Hi-net preliminary truth quality before assignment. |
| `20260621_iwate_offshore_m33_eq8` | `offshore_reference_pool` | `unassigned_reference` | `link_final_catalog_or_hinet_revision` | `link_final_catalog_or_hinet_revision`, `assign_event_level_split` | Link a final catalog or revised Hi-net source before assignment. |
| `20260621_fukushima_offshore_m32_eq6` | `candidate_region_false_recovery_guard` | `unassigned_reference` | `keep_candidate_region_false_recovery_diagnostic_only` | `keep_candidate_region_false_recovery_diagnostic_only` | Keep the false-recovery guard diagnostic-only until an explicit split gate approves promotion. |
| `20260626_yamanashi_east_fuji_five_lakes_m26_jma_p2p` | `plum_like_replay_leadtime_moderate_reference` | `unassigned_reference` | `keep_plum_like_diagnostic_only` | `keep_plum_like_diagnostic_only`, `review_jma_catalog_link`, `confirm_capture_provenance`, `assign_event_level_split` | Inspect the readiness report for the required evidence. |
| `20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8` | `plum_like_replay_leadtime_moderate_reference` | `unassigned_reference` | `keep_plum_like_diagnostic_only` | `keep_plum_like_diagnostic_only`, `review_jma_catalog_link`, `confirm_capture_provenance`, `assign_event_level_split` | Inspect the readiness report for the required evidence. |
| `20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21` | `plum_like_replay_leadtime_strong_motion_reference` | `unassigned_reference` | `keep_plum_like_diagnostic_only` | `keep_plum_like_diagnostic_only`, `review_jma_catalog_link`, `assign_event_level_split` | Inspect the readiness report for the required evidence. |
| `20260627_fukushima_aizu_m36_jma_equake17` | `plum_like_replay_leadtime_moderate_reference` | `unassigned_reference` | `keep_plum_like_diagnostic_only` | `keep_plum_like_diagnostic_only`, `review_jma_catalog_link`, `assign_event_level_split` | Inspect the readiness report for the required evidence. |
| `20260627_yamanashi_east_fuji_five_lakes_m24_jma_p2p` | `plum_like_replay_leadtime_moderate_reference` | `unassigned_reference` | `keep_plum_like_diagnostic_only` | `keep_plum_like_diagnostic_only`, `review_jma_catalog_link`, `confirm_capture_provenance`, `assign_event_level_split` | Inspect the readiness report for the required evidence. |
| `20260628_iwate_offshore_m41_jma` | `plum_like_replay_leadtime_moderate_reference` | `unassigned_reference` | `keep_plum_like_diagnostic_only` | `keep_plum_like_diagnostic_only`, `review_jma_catalog_link`, `assign_event_level_split` | Inspect the readiness report for the required evidence. |

## Completed Split Assignments

| Case | Split | Constraints |
| --- | --- | --- |
| `20260622_fukushima_offshore_m22_eq4` | `validation_reference` | `keep_include_in_detection_metrics_false`, `do_not_treat_as_catalog_truth`, `do_not_use_for_final_test_claims` |
| `20260622_iwate_east_offshore_m30_hinet` | `validation_reference` | `hinet_constrained_reference_only`, `do_not_treat_as_catalog_truth`, `do_not_use_for_final_test_claims` |
| `20260622_iwate_offshore_m30_eq10` | `validation_reference` | `hinet_constrained_reference_only`, `do_not_treat_as_catalog_truth`, `do_not_use_for_final_test_claims` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `validation_reference` | `hinet_constrained_reference_only`, `do_not_treat_as_catalog_truth`, `do_not_use_for_final_test_claims` |
| `20260622_wakayama_south_m25_hinet` | `validation_reference` | `hinet_constrained_reference_only`, `do_not_treat_as_catalog_truth`, `do_not_use_for_final_test_claims` |
| `20260623_tokachi_southeast_offshore_m34_hinet` | `validation_reference` | `hinet_constrained_reference_only`, `do_not_treat_as_catalog_truth`, `do_not_use_for_final_test_claims` |
| `noto_m27_20260621_jma_eq5` | `validation_reference` | `keep_include_in_detection_metrics_false`, `do_not_treat_as_catalog_truth`, `do_not_use_for_final_test_claims`, `physical_fusion_diagnostic_only`, `preserve_historical_fetch_warning` |
