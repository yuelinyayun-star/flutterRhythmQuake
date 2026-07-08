# Source Estimation External Input Queue

- Status: `pass`
- Blocker queue: `.dart_tool/source_estimation_split_blocker_queue/report.json`
- JMA capture association: `.dart_tool/jma_reference_capture_association/report.json`
- Hi-net repair probe: `.dart_tool/hinet_capture_repair_probe/report.json`
- Hi-net authenticated export review: `.dart_tool/hinet_authenticated_export_review/report.json`
- Input items: `6`
- Automatic clearances: `0`

## Input Type Counts

| Input type | Count |
| --- | ---: |
| `final_catalog_or_hinet_revision` | 1 |
| `local_jma_reference_capture_package` | 2 |
| `versioned_jma_final_catalog_record` | 3 |

## Validation

- Errors: none
- Warnings: none

## Queue

| Priority | Type | Case | Required input | Source report | Details |
| ---: | --- | --- | --- | --- | --- |
| 20 | `local_jma_reference_capture_package` | `20260625_iwate_offshore_m46_jma_eqsc9` | Associate a local replay/capture package in the JMA reference manifest. | `jma_reference_capture_association` | status=pending_capture_association; originJst=2026-06-26T01:11:51+09:00 |
| 20 | `local_jma_reference_capture_package` | `20260626_yamanashi_central_west_m26_jma_equake5` | Associate a local replay/capture package in the JMA reference manifest. | `jma_reference_capture_association` | status=pending_capture_association; originJst=2026-06-26T15:41:13+09:00 |
| 30 | `versioned_jma_final_catalog_record` | `20260622_kushiro_offshore_m30_jma` | Link a versioned JMA final catalog record for this recent event. | `source_estimation_split_blocker_queue` | plannedUse=candidate_region_residual_positive_guard |
| 30 | `versioned_jma_final_catalog_record` | `20260624_fukushima_aizu_m32_jma_eq5` | Link a versioned JMA final catalog record for this recent event. | `source_estimation_split_blocker_queue` | plannedUse=inland_surrounded_control |
| 30 | `versioned_jma_final_catalog_record` | `20260625_iwate_offshore_m32_jma` | Link a versioned JMA final catalog record for this recent event. | `source_estimation_split_blocker_queue` | plannedUse=candidate_region_local_support_positive_guard |
| 40 | `final_catalog_or_hinet_revision` | `20260621_iwate_offshore_m33_eq8` | Link a final catalog row or revised Hi-net source before split assignment. | `source_estimation_split_blocker_queue` | plannedUse=offshore_reference_pool |

## Decision

- This queue does not edit split manifests, review ledgers or capture packages.
- Providing one of these inputs only makes a downstream guard eligible to re-evaluate; it never clears source truth or capture blockers by itself.
