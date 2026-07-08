# Source Estimation External Input Worklist

- Status: `pass`
- Queue: `.dart_tool/source_estimation_external_input_queue/report.json`
- Templates: `.dart_tool/source_estimation_external_input_templates/report.json`
- Attempts: `.dart_tool/source_estimation_external_input_attempts/report.json`
- Repair probe: `.dart_tool/hinet_capture_repair_probe/report.json`
- Authenticated export packet: `.dart_tool/hinet_authenticated_export_review_packet/report.json`
- JMA reference capture packet: `.dart_tool/jma_reference_capture_review_packet/report.json`
- JMA final catalog packet: `.dart_tool/jma_final_catalog_review_packet/report.json`
- Final catalog or Hi-net revision packet: `.dart_tool/final_catalog_or_hinet_revision_review_packet/report.json`
- Open inputs: `6`
- Inputs with recorded attempts: `6`
- Inputs without attempts: `0`
- Automatic clearances: `0`
- Operation artifacts: `6`
- Next input: `local_jma_reference_capture_package::20260625_iwate_offshore_m46_jma_eqsc9`

## Input Type Counts

| Input type | Open | With attempts |
| --- | ---: | ---: |
| `final_catalog_or_hinet_revision` | 1 | 1 |
| `local_jma_reference_capture_package` | 2 | 2 |
| `versioned_jma_final_catalog_record` | 3 | 3 |

## Worklist

| Priority | Type | Case | Attempts | Last result | Action | Operation artifact | Validation |
| ---: | --- | --- | ---: | --- | --- | --- | --- |
| 20 | `local_jma_reference_capture_package` | `20260625_iwate_offshore_m46_jma_eqsc9` | 1 | `not_found` | associate an existing local replay/capture package | `pending_capture_association` | `powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_jma_reference_capture_association.ps1` |
| 20 | `local_jma_reference_capture_package` | `20260626_yamanashi_central_west_m26_jma_equake5` | 1 | `not_found` | associate an existing local replay/capture package | `pending_capture_association` | `powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_jma_reference_capture_association.ps1` |
| 30 | `versioned_jma_final_catalog_record` | `20260622_kushiro_offshore_m30_jma` | 1 | `event_year_not_in_latest_final_catalog` | import a versioned JMA catalog and link the matching fixture | `external_catalog_not_yet_available` | `powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_jma_catalog_availability.ps1` |
| 30 | `versioned_jma_final_catalog_record` | `20260624_fukushima_aizu_m32_jma_eq5` | 1 | `event_year_not_in_latest_final_catalog` | import a versioned JMA catalog and link the matching fixture | `external_catalog_not_yet_available` | `powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_jma_catalog_availability.ps1` |
| 30 | `versioned_jma_final_catalog_record` | `20260625_iwate_offshore_m32_jma` | 1 | `event_year_not_in_latest_final_catalog` | import a versioned JMA catalog and link the matching fixture | `external_catalog_not_yet_available` | `powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_jma_catalog_availability.ps1` |
| 40 | `final_catalog_or_hinet_revision` | `20260621_iwate_offshore_m33_eq8` | 1 | `no_versioned_catalog_or_authenticated_revision_available` | link a final catalog row or revised Hi-net source | `reference_only` | `powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_source_estimation_split_blocker_queue.ps1` |

## Validation

- Errors: none
- Warnings: none

## Decision

- This worklist is operational only. It does not clear capture, catalog, truth-quality or split blockers.
- Recorded negative attempts remain non-evidence and only prevent repeating untracked searches.
