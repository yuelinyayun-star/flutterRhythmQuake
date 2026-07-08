# Source Metric-Readiness Triage

- Status: `pass`
- Cases: `19`
- Metric-bearing ready: `0`
- Reference-validation only: `7`
- Diagnostic-ready blocked: `8`
- Metadata-only/incomplete: `4`
- Ready for manual split assignment: `0`
- Reference labels available: `19`
- JMA reference labels available: `10`

## Triage

| Case | Triage | Label | Planned use | Split | Next action | Metric blocker |
| --- | --- | --- | --- | --- | --- | --- |
| `20260620_iwate_offshore_m34_ref` | `metadata_only_or_incomplete` | `hinet_reference_label_available` | `offshore_reference_pool` | `unassigned_reference` | `review_hinet_preliminary_truth_quality` | `local_capture_missing_or_has_failed_frames` |
| `20260621_fukushima_offshore_m32_eq6` | `diagnostic_ready_blocked` | `hinet_reference_label_available` | `candidate_region_false_recovery_guard` | `unassigned_reference` | `keep_candidate_region_false_recovery_diagnostic_only` | `keep_candidate_region_false_recovery_diagnostic_only` |
| `20260621_iwate_offshore_m33_eq8` | `diagnostic_ready_blocked` | `equake_reference_label_available` | `offshore_reference_pool` | `unassigned_reference` | `link_final_catalog_or_hinet_revision` | `link_final_catalog_or_hinet_revision` |
| `20260622_fukushima_offshore_m22_eq4` | `reference_validation_only` | `equake_reference_label_available` | `small_offshore_reference_pool` | `validation_reference` | `split_assignment_complete` | `reference_only_validation_not_for_final_metric_claims` |
| `20260622_iwate_east_offshore_m30_hinet` | `reference_validation_only` | `hinet_reference_label_available` | `offshore_reference_pool` | `validation_reference` | `split_assignment_complete` | `reference_only_validation_not_for_final_metric_claims` |
| `20260622_iwate_offshore_m30_eq10` | `reference_validation_only` | `hinet_reference_label_available` | `offshore_reference_pool` | `validation_reference` | `split_assignment_complete` | `reference_only_validation_not_for_final_metric_claims` |
| `20260622_kushiro_offshore_m30_jma` | `diagnostic_ready_blocked` | `jma_reference_label_available` | `candidate_region_residual_positive_guard` | `unassigned_reference` | `review_jma_catalog_link` | `jma_reference_label_available_final_catalog_link_pending` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `reference_validation_only` | `hinet_reference_label_available` | `candidate_region_residual_immediate_guard` | `validation_reference` | `split_assignment_complete` | `reference_only_validation_not_for_final_metric_claims` |
| `20260622_wakayama_south_m25_hinet` | `reference_validation_only` | `hinet_reference_label_available` | `inland_or_near_coast_reference_pool` | `validation_reference` | `split_assignment_complete` | `reference_only_validation_not_for_final_metric_claims` |
| `20260623_tokachi_southeast_offshore_m34_hinet` | `reference_validation_only` | `hinet_reference_label_available` | `candidate_region_hokkaido_control` | `validation_reference` | `split_assignment_complete` | `reference_only_validation_not_for_final_metric_claims` |
| `20260624_fukushima_aizu_m32_jma_eq5` | `diagnostic_ready_blocked` | `jma_reference_label_available` | `inland_surrounded_control` | `unassigned_reference` | `review_jma_catalog_link` | `jma_reference_label_available_final_catalog_link_pending` |
| `20260625_iwate_offshore_m32_jma` | `diagnostic_ready_blocked` | `jma_reference_label_available` | `candidate_region_local_support_positive_guard` | `unassigned_reference` | `review_jma_catalog_link` | `jma_reference_label_available_final_catalog_link_pending` |
| `20260626_yamanashi_east_fuji_five_lakes_m26_jma_p2p` | `metadata_only_or_incomplete` | `jma_reference_label_available` | `plum_like_replay_leadtime_moderate_reference` | `unassigned_reference` | `keep_plum_like_diagnostic_only` | `local_capture_missing_or_has_failed_frames` |
| `20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8` | `metadata_only_or_incomplete` | `jma_reference_label_available` | `plum_like_replay_leadtime_moderate_reference` | `unassigned_reference` | `keep_plum_like_diagnostic_only` | `local_capture_missing_or_has_failed_frames` |
| `20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21` | `diagnostic_ready_blocked` | `jma_reference_label_available` | `plum_like_replay_leadtime_strong_motion_reference` | `unassigned_reference` | `keep_plum_like_diagnostic_only` | `keep_plum_like_diagnostic_only` |
| `20260627_fukushima_aizu_m36_jma_equake17` | `diagnostic_ready_blocked` | `jma_reference_label_available` | `plum_like_replay_leadtime_moderate_reference` | `unassigned_reference` | `keep_plum_like_diagnostic_only` | `keep_plum_like_diagnostic_only` |
| `20260627_yamanashi_east_fuji_five_lakes_m24_jma_p2p` | `metadata_only_or_incomplete` | `jma_reference_label_available` | `plum_like_replay_leadtime_moderate_reference` | `unassigned_reference` | `keep_plum_like_diagnostic_only` | `local_capture_missing_or_has_failed_frames` |
| `20260628_iwate_offshore_m41_jma` | `diagnostic_ready_blocked` | `jma_reference_label_available` | `plum_like_replay_leadtime_moderate_reference` | `unassigned_reference` | `keep_plum_like_diagnostic_only` | `keep_plum_like_diagnostic_only` |
| `noto_m27_20260621_jma_eq5` | `reference_validation_only` | `jma_reference_label_available` | `multilayer_gain_probe` | `validation_reference` | `split_assignment_complete` | `reference_only_validation_not_for_final_metric_claims` |

## Decision

- No current case is ready for metric-bearing validation or final accuracy claims.
- The `7` strict-ready cases remain reference-validation only because their constraints forbid final test claims and catalog-truth use.
- The `8` diagnostic-ready cases remain useful for algorithm diagnostics but are blocked by JMA catalog, Hi-net review, final-catalog/revision evidence, or diagnostic-only PLUM replay scope.
- PLUM-like replay lead-time cases marked `keep_plum_like_diagnostic_only` must not be promoted into metric-bearing source-estimation split assignment from this report.
- JMA source-and-intensity labels count as reference labels for diagnostic use; the pending final-catalog link only blocks metric-bearing truth claims.
- Manual-ready constrained references still require explicit event-level split assignment before they can leave the blocker queue.
- The `4` metadata-only/incomplete cases remain blocked by capture provenance or incomplete local replay packages.

## Validation

- Status: `pass`.
- Violations: none.

