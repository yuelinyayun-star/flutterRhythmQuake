# Source Estimation External Input Delta

- Status: `pass`
- Queue: `.dart_tool/source_estimation_external_input_queue/report.json`
- Templates: `.dart_tool/source_estimation_external_input_templates/report.json`
- Matched templates: `6`
- Missing templates: `0`
- Stale templates: `0`
- Coverage complete: `true`
- Safe template semantics: `true`

## Validation

- Errors: none
- Warnings: none

## Delta

| Priority | Type | Case | Status | Priority match | Manual review | Auto clearance |
| ---: | --- | --- | --- | --- | --- | --- |
| 20 | `local_jma_reference_capture_package` | `20260625_iwate_offshore_m46_jma_eqsc9` | `matched` | `true` | `true` | `false` |
| 20 | `local_jma_reference_capture_package` | `20260626_yamanashi_central_west_m26_jma_equake5` | `matched` | `true` | `true` | `false` |
| 30 | `versioned_jma_final_catalog_record` | `20260622_kushiro_offshore_m30_jma` | `matched` | `true` | `true` | `false` |
| 30 | `versioned_jma_final_catalog_record` | `20260624_fukushima_aizu_m32_jma_eq5` | `matched` | `true` | `true` | `false` |
| 30 | `versioned_jma_final_catalog_record` | `20260625_iwate_offshore_m32_jma` | `matched` | `true` | `true` | `false` |
| 40 | `final_catalog_or_hinet_revision` | `20260621_iwate_offshore_m33_eq8` | `matched` | `true` | `true` | `false` |

## Decision

- This delta only verifies that the intake queue and generated templates agree one-for-one.
- A matched template is still operational documentation only; it does not clear capture, catalog, truth-quality or split blockers.
