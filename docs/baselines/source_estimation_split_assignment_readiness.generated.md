# Source Estimation Split Assignment Readiness

- Status: `pass`
- Plan: `docs/data/source_estimation_split_assignment_plan.json`
- Hi-net decisions: `docs/data/hinet_truth_quality_review_decisions.json`
- Fixture directory: `test/fixtures/source_estimation`
- Cases: `19`
- Ready for frozen split: `7`
- Ready for manual split assignment: `0`
- Manual split assignment pending: `11`
- Dataset use tiers: `{metadata_only_or_incomplete: 4, diagnostic_ready: 8, strict_ready: 7}`

## Validation

- Errors: none
- Warnings: `recent_jma_final_catalog_links_pending:9`

## Cases

| Case | Tier | Planned use | Truth source | Capture | Catalog/review | Split | Manual-ready | Ready | Next action | Suggested split |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `20260620_iwate_offshore_m34_ref` | `metadata_only_or_incomplete` | `offshore_reference_pool` | `hinet_hypocenter_information` | `pending` | `hinet_preliminary_reference_requires_manual_review` | `unassigned_reference` | no | no | `review_hinet_preliminary_truth_quality` | `` |
| `20260621_fukushima_offshore_m32_eq6` | `diagnostic_ready` | `candidate_region_false_recovery_guard` | `user_provided_hinet_hypocenter` | `not_required` | `complete` | `unassigned_reference` | no | no | `keep_candidate_region_false_recovery_diagnostic_only` | `` |
| `20260621_iwate_offshore_m33_eq8` | `diagnostic_ready` | `offshore_reference_pool` | `user_provided_equake_final_report_reference` | `complete` | `final_catalog_or_hinet_revision_not_linked` | `unassigned_reference` | no | no | `link_final_catalog_or_hinet_revision` | `` |
| `20260622_fukushima_offshore_m22_eq4` | `strict_ready` | `small_offshore_reference_pool` | `equake_source_estimation_reference` | `complete` | `complete` | `validation_reference` | no | yes | `split_assignment_complete` | `validation` |
| `20260622_iwate_east_offshore_m30_hinet` | `strict_ready` | `offshore_reference_pool` | `user_provided_hinet_hypocenter` | `complete` | `complete` | `validation_reference` | no | yes | `split_assignment_complete` | `validation` |
| `20260622_iwate_offshore_m30_eq10` | `strict_ready` | `offshore_reference_pool` | `user_provided_hinet_hypocenter` | `complete` | `complete` | `validation_reference` | no | yes | `split_assignment_complete` | `validation` |
| `20260622_kushiro_offshore_m30_jma` | `diagnostic_ready` | `candidate_region_residual_positive_guard` | `jma_source_and_intensity_information` | `not_required` | `jma_final_catalog_missing_for_recent_event` | `unassigned_reference` | no | no | `review_jma_catalog_link` | `` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `strict_ready` | `candidate_region_residual_immediate_guard` | `user_provided_hinet_hypocenter` | `complete` | `complete` | `validation_reference` | no | yes | `split_assignment_complete` | `validation` |
| `20260622_wakayama_south_m25_hinet` | `strict_ready` | `inland_or_near_coast_reference_pool` | `user_provided_hinet_hypocenter` | `complete` | `complete` | `validation_reference` | no | yes | `split_assignment_complete` | `validation` |
| `20260623_tokachi_southeast_offshore_m34_hinet` | `strict_ready` | `candidate_region_hokkaido_control` | `user_provided_hinet_hypocenter` | `complete` | `complete` | `validation_reference` | no | yes | `split_assignment_complete` | `validation` |
| `20260624_fukushima_aizu_m32_jma_eq5` | `diagnostic_ready` | `inland_surrounded_control` | `jma_source_and_intensity_information` | `complete` | `jma_final_catalog_missing_for_recent_event` | `unassigned_reference` | no | no | `review_jma_catalog_link` | `` |
| `20260625_iwate_offshore_m32_jma` | `diagnostic_ready` | `candidate_region_local_support_positive_guard` | `jma_source_and_intensity_information` | `not_required` | `jma_final_catalog_missing_for_recent_event` | `unassigned_reference` | no | no | `review_jma_catalog_link` | `` |
| `20260626_yamanashi_east_fuji_five_lakes_m26_jma_p2p` | `metadata_only_or_incomplete` | `plum_like_replay_leadtime_moderate_reference` | `jma_source_and_intensity_information` | `pending` | `jma_final_catalog_missing_for_recent_event` | `unassigned_reference` | no | no | `keep_plum_like_diagnostic_only` | `` |
| `20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8` | `metadata_only_or_incomplete` | `plum_like_replay_leadtime_moderate_reference` | `jma_source_and_intensity_information` | `pending` | `jma_final_catalog_missing_for_recent_event` | `unassigned_reference` | no | no | `keep_plum_like_diagnostic_only` | `` |
| `20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21` | `diagnostic_ready` | `plum_like_replay_leadtime_strong_motion_reference` | `jma_source_and_intensity_information` | `complete` | `jma_final_catalog_missing_for_recent_event` | `unassigned_reference` | no | no | `keep_plum_like_diagnostic_only` | `` |
| `20260627_fukushima_aizu_m36_jma_equake17` | `diagnostic_ready` | `plum_like_replay_leadtime_moderate_reference` | `jma_source_and_intensity_information` | `complete` | `jma_final_catalog_missing_for_recent_event` | `unassigned_reference` | no | no | `keep_plum_like_diagnostic_only` | `` |
| `20260627_yamanashi_east_fuji_five_lakes_m24_jma_p2p` | `metadata_only_or_incomplete` | `plum_like_replay_leadtime_moderate_reference` | `jma_source_and_intensity_information` | `pending` | `jma_final_catalog_missing_for_recent_event` | `unassigned_reference` | no | no | `keep_plum_like_diagnostic_only` | `` |
| `20260628_iwate_offshore_m41_jma` | `diagnostic_ready` | `plum_like_replay_leadtime_moderate_reference` | `jma_source_and_intensity_information` | `complete` | `jma_final_catalog_missing_for_recent_event` | `unassigned_reference` | no | no | `keep_plum_like_diagnostic_only` | `` |
| `noto_m27_20260621_jma_eq5` | `strict_ready` | `multilayer_gain_probe` | `JMA` | `complete` | `complete` | `validation_reference` | no | yes | `split_assignment_complete` | `validation` |

## Condition Details

### 20260620_iwate_offshore_m34_ref
- `dataset_use_tier`: `metadata_only_or_incomplete` (local_capture_missing_or_has_failed_frames)
- `review_hinet_preliminary_truth_quality`: `pending` (hinet_preliminary_reference_requires_manual_review)
- `confirm_capture_provenance`: `pending` (capture_manifest_incomplete_or_has_failures)
- `assign_event_level_split`: `pending` (manual_event_level_split_assignment_required)

### 20260621_fukushima_offshore_m32_eq6
- `dataset_use_tier`: `diagnostic_ready` (local_fixture_or_capture_available_but_review_or_split_pending)
- `keep_candidate_region_diagnostic_only`: `complete` (isolated_from_frozen_metrics_and_coordinate_switch_guards)
- `review_hinet_truth_quality`: `complete` (hinet_constrained_reference_review_accepted)
- `keep_candidate_region_false_recovery_diagnostic_only`: `pending` (false_recovery_guard_requires_explicit_split_gate)

### 20260621_iwate_offshore_m33_eq8
- `dataset_use_tier`: `diagnostic_ready` (local_fixture_or_capture_available_but_review_or_split_pending)
- `link_final_catalog_or_hinet_revision`: `pending` (final_catalog_or_hinet_revision_not_linked)
- `confirm_capture_provenance`: `complete` (capture_manifest_complete_with_zero_failures)
- `assign_event_level_split`: `pending` (manual_event_level_split_assignment_required)

### 20260622_fukushima_offshore_m22_eq4
- `manual_split_recommendation`: `validation` (small_offshore_reference_only_validation_candidate)
- `manual_split_constraints`: `keep_include_in_detection_metrics_false`, `do_not_treat_as_catalog_truth`, `do_not_use_for_final_test_claims`
- `dataset_use_tier`: `strict_ready` (all_frozen_split_requirements_complete)
- `review_equake_reference_only_truth`: `complete` (equake_kept_reference_only_not_catalog_truth)
- `confirm_capture_provenance`: `complete` (capture_manifest_complete_with_zero_failures)
- `assign_event_level_split`: `complete` (already_assigned_to_frozen_split)

### 20260622_iwate_east_offshore_m30_hinet
- `manual_split_recommendation`: `validation` (hinet_constrained_offshore_reference_validation_candidate)
- `manual_split_constraints`: `hinet_constrained_reference_only`, `do_not_treat_as_catalog_truth`, `do_not_use_for_final_test_claims`
- `dataset_use_tier`: `strict_ready` (all_frozen_split_requirements_complete)
- `review_hinet_preliminary_truth_quality`: `complete` (hinet_constrained_reference_review_accepted)
- `confirm_capture_provenance`: `complete` (capture_manifest_complete_with_zero_failures)
- `assign_event_level_split`: `complete` (already_assigned_to_frozen_split)

### 20260622_iwate_offshore_m30_eq10
- `manual_split_recommendation`: `validation` (hinet_constrained_offshore_reference_validation_candidate)
- `manual_split_constraints`: `hinet_constrained_reference_only`, `do_not_treat_as_catalog_truth`, `do_not_use_for_final_test_claims`
- `dataset_use_tier`: `strict_ready` (all_frozen_split_requirements_complete)
- `review_hinet_preliminary_truth_quality`: `complete` (hinet_constrained_reference_review_accepted)
- `confirm_capture_provenance`: `complete` (capture_manifest_complete_with_zero_failures)
- `assign_event_level_split`: `complete` (already_assigned_to_frozen_split)

### 20260622_kushiro_offshore_m30_jma
- `dataset_use_tier`: `diagnostic_ready` (local_fixture_or_capture_available_but_review_or_split_pending)
- `keep_candidate_region_diagnostic_only`: `complete` (isolated_from_frozen_metrics_and_coordinate_switch_guards)
- `review_jma_catalog_link`: `pending` (jma_final_catalog_missing_for_recent_event)
- `assign_event_level_split`: `pending` (manual_event_level_split_assignment_required)

### 20260622_tomakomai_south_offshore_m35_hinet
- `manual_split_recommendation`: `validation` (hinet_constrained_residual_immediate_guard_validation_candidate)
- `manual_split_constraints`: `hinet_constrained_reference_only`, `do_not_treat_as_catalog_truth`, `do_not_use_for_final_test_claims`
- `dataset_use_tier`: `strict_ready` (all_frozen_split_requirements_complete)
- `review_hinet_preliminary_truth_quality`: `complete` (hinet_constrained_reference_review_accepted)
- `confirm_capture_provenance`: `complete` (capture_manifest_complete_with_zero_failures)
- `assign_event_level_split`: `complete` (already_assigned_to_frozen_split)

### 20260622_wakayama_south_m25_hinet
- `manual_split_recommendation`: `validation` (hinet_constrained_inland_or_near_coast_reference_validation_candidate)
- `manual_split_constraints`: `hinet_constrained_reference_only`, `do_not_treat_as_catalog_truth`, `do_not_use_for_final_test_claims`
- `dataset_use_tier`: `strict_ready` (all_frozen_split_requirements_complete)
- `review_hinet_preliminary_truth_quality`: `complete` (hinet_constrained_reference_review_accepted)
- `confirm_capture_provenance`: `complete` (capture_manifest_complete_with_zero_failures)
- `assign_event_level_split`: `complete` (already_assigned_to_frozen_split)

### 20260623_tokachi_southeast_offshore_m34_hinet
- `manual_split_recommendation`: `validation` (hinet_constrained_hokkaido_control_validation_candidate)
- `manual_split_constraints`: `hinet_constrained_reference_only`, `do_not_treat_as_catalog_truth`, `do_not_use_for_final_test_claims`
- `dataset_use_tier`: `strict_ready` (all_frozen_split_requirements_complete)
- `review_hinet_preliminary_truth_quality`: `complete` (hinet_constrained_reference_review_accepted)
- `confirm_capture_provenance`: `complete` (capture_manifest_complete_with_zero_failures)
- `assign_event_level_split`: `complete` (already_assigned_to_frozen_split)

### 20260624_fukushima_aizu_m32_jma_eq5
- `dataset_use_tier`: `diagnostic_ready` (local_fixture_or_capture_available_but_review_or_split_pending)
- `review_jma_catalog_link`: `pending` (jma_final_catalog_missing_for_recent_event)
- `confirm_capture_provenance`: `complete` (capture_manifest_complete_with_zero_failures)
- `assign_event_level_split`: `pending` (manual_event_level_split_assignment_required)

### 20260625_iwate_offshore_m32_jma
- `dataset_use_tier`: `diagnostic_ready` (local_fixture_or_capture_available_but_review_or_split_pending)
- `keep_candidate_region_diagnostic_only`: `complete` (isolated_from_frozen_metrics_and_coordinate_switch_guards)
- `review_jma_catalog_link`: `pending` (jma_final_catalog_missing_for_recent_event)
- `assign_event_level_split`: `pending` (manual_event_level_split_assignment_required)

### 20260626_yamanashi_east_fuji_five_lakes_m26_jma_p2p
- `dataset_use_tier`: `metadata_only_or_incomplete` (local_capture_missing_or_has_failed_frames)
- `keep_plum_like_diagnostic_only`: `pending` (unknown_requirement)
- `review_jma_catalog_link`: `pending` (jma_final_catalog_missing_for_recent_event)
- `confirm_capture_provenance`: `pending` (capture_manifest_incomplete_or_has_failures)
- `assign_event_level_split`: `pending` (manual_event_level_split_assignment_required)

### 20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8
- `dataset_use_tier`: `metadata_only_or_incomplete` (local_capture_missing_or_has_failed_frames)
- `keep_plum_like_diagnostic_only`: `pending` (unknown_requirement)
- `review_jma_catalog_link`: `pending` (jma_final_catalog_missing_for_recent_event)
- `confirm_capture_provenance`: `pending` (capture_manifest_incomplete_or_has_failures)
- `assign_event_level_split`: `pending` (manual_event_level_split_assignment_required)

### 20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21
- `dataset_use_tier`: `diagnostic_ready` (local_fixture_or_capture_available_but_review_or_split_pending)
- `keep_plum_like_diagnostic_only`: `pending` (unknown_requirement)
- `review_jma_catalog_link`: `pending` (jma_final_catalog_missing_for_recent_event)
- `confirm_capture_provenance`: `complete` (capture_manifest_complete_with_zero_failures)
- `assign_event_level_split`: `pending` (manual_event_level_split_assignment_required)

### 20260627_fukushima_aizu_m36_jma_equake17
- `dataset_use_tier`: `diagnostic_ready` (local_fixture_or_capture_available_but_review_or_split_pending)
- `keep_plum_like_diagnostic_only`: `pending` (unknown_requirement)
- `review_jma_catalog_link`: `pending` (jma_final_catalog_missing_for_recent_event)
- `confirm_capture_provenance`: `complete` (capture_manifest_complete_with_zero_failures)
- `assign_event_level_split`: `pending` (manual_event_level_split_assignment_required)

### 20260627_yamanashi_east_fuji_five_lakes_m24_jma_p2p
- `dataset_use_tier`: `metadata_only_or_incomplete` (local_capture_missing_or_has_failed_frames)
- `keep_plum_like_diagnostic_only`: `pending` (unknown_requirement)
- `review_jma_catalog_link`: `pending` (jma_final_catalog_missing_for_recent_event)
- `confirm_capture_provenance`: `pending` (capture_manifest_incomplete_or_has_failures)
- `assign_event_level_split`: `pending` (manual_event_level_split_assignment_required)

### 20260628_iwate_offshore_m41_jma
- `dataset_use_tier`: `diagnostic_ready` (local_fixture_or_capture_available_but_review_or_split_pending)
- `keep_plum_like_diagnostic_only`: `pending` (unknown_requirement)
- `review_jma_catalog_link`: `pending` (jma_final_catalog_missing_for_recent_event)
- `confirm_capture_provenance`: `complete` (capture_manifest_complete_with_zero_failures)
- `assign_event_level_split`: `pending` (manual_event_level_split_assignment_required)

### noto_m27_20260621_jma_eq5
- `manual_split_recommendation`: `validation` (noto_multilayer_gain_probe_reference_only_validation_candidate)
- `manual_split_constraints`: `keep_include_in_detection_metrics_false`, `do_not_treat_as_catalog_truth`, `do_not_use_for_final_test_claims`, `physical_fusion_diagnostic_only`, `preserve_historical_fetch_warning`
- `dataset_use_tier`: `strict_ready` (all_frozen_split_requirements_complete)
- `review_source_trigger_threshold_effect`: `complete` (source_trigger_threshold_review_cleared)
- `confirm_capture_provenance`: `complete` (capture_manifest_complete_with_zero_failures)
- `assign_event_level_split`: `complete` (already_assigned_to_frozen_split)

