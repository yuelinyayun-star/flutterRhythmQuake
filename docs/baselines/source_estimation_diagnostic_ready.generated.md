# Source Estimation Diagnostic-Ready Report

- Status: `pass`
- Diagnostic-ready cases: `12`
- Strict metric eligible in this report: `0`
- Production coordinate switch allowed: `0`
- Candidate frames: `22`
- Offline missed positive frames: `13`
- Delayed recovered missed positives: `3`

## Policy

- These cases are diagnostic-only. They may guide algorithm work, but must not be used for final metric claims or frozen split reporting.

## Cases

| Case | Role | Action | Planned use | Promotion | Timeline | Catalog/review |
| --- | --- | --- | --- | --- | --- | --- |
| `20260621_fukushima_offshore_m32_eq6` | `false_recovery_guard` | `inspect_candidate_rejection_residuals` | `candidate_region_false_recovery_guard` | cand `8`, accept `0`, miss `7` | imm `0`, delayed `0`, local `0` | `hinet_preliminary_reference_requires_manual_review` |
| `20260621_iwate_offshore_m33_eq8` | `no_candidate_control` | `keep_as_no_candidate_control` | `offshore_reference_pool` | cand `n/a`, accept `n/a`, miss `n/a` | imm `n/a`, delayed `n/a`, local `n/a` | `final_catalog_or_hinet_revision_not_linked` |
| `20260622_iwate_east_offshore_m30_hinet` | `no_candidate_control` | `keep_as_no_candidate_control` | `offshore_reference_pool` | cand `0`, accept `0`, miss `0` | imm `n/a`, delayed `n/a`, local `n/a` | `complete` |
| `20260622_iwate_offshore_m30_eq10` | `no_candidate_control` | `keep_as_no_candidate_control` | `offshore_reference_pool` | cand `0`, accept `0`, miss `0` | imm `n/a`, delayed `n/a`, local `n/a` | `hinet_preliminary_reference_requires_manual_review` |
| `20260622_kushiro_offshore_m30_jma` | `residual_candidate_region_guard` | `study_delayed_confirmation_recovery` | `candidate_region_residual_positive_guard` | cand `8`, accept `5`, miss `3` | imm `4`, delayed `1`, local `0` | `jma_final_catalog_missing_for_recent_event` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `residual_candidate_region_guard` | `keep_as_positive_residual_guard` | `candidate_region_residual_immediate_guard` | cand `3`, accept `3`, miss `0` | imm `3`, delayed `0`, local `0` | `complete` |
| `20260622_wakayama_south_m25_hinet` | `no_candidate_control` | `keep_as_no_candidate_control` | `inland_or_near_coast_reference_pool` | cand `0`, accept `0`, miss `0` | imm `n/a`, delayed `n/a`, local `n/a` | `hinet_preliminary_reference_requires_manual_review` |
| `20260623_tokachi_southeast_offshore_m34_hinet` | `no_candidate_control` | `keep_as_no_candidate_control` | `candidate_region_hokkaido_control` | cand `0`, accept `0`, miss `0` | imm `0`, delayed `0`, local `0` | `complete` |
| `20260624_fukushima_aizu_m32_jma_eq5` | `no_candidate_control` | `keep_as_no_candidate_control` | `inland_surrounded_control` | cand `0`, accept `0`, miss `0` | imm `0`, delayed `0`, local `0` | `jma_final_catalog_missing_for_recent_event` |
| `20260625_iwate_offshore_m32_jma` | `local_support_positive_guard` | `inspect_candidate_rejection_residuals` | `candidate_region_local_support_positive_guard` | cand `3`, accept `0`, miss `3` | imm `0`, delayed `1`, local `1` | `jma_final_catalog_missing_for_recent_event` |
| `20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21` | `no_candidate_control` | `keep_as_no_candidate_control` | `plum_like_replay_leadtime_strong_motion_reference` | cand `n/a`, accept `n/a`, miss `n/a` | imm `n/a`, delayed `n/a`, local `n/a` | `jma_final_catalog_missing_for_recent_event` |
| `20260627_fukushima_aizu_m36_jma_equake17` | `no_candidate_control` | `keep_as_no_candidate_control` | `plum_like_replay_leadtime_moderate_reference` | cand `n/a`, accept `n/a`, miss `n/a` | imm `n/a`, delayed `n/a`, local `n/a` | `jma_final_catalog_missing_for_recent_event` |
