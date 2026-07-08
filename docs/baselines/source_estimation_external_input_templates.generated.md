# Source Estimation External Input Templates

- Status: `pass`
- Queue: `.dart_tool/source_estimation_external_input_queue/report.json`
- Fixture directory: `test/fixtures/source_estimation`
- Templates: `6`
- Manual-review required: `6`
- Automatic clearances: `0`
- Ledger mutations: `0`

## Input Type Counts

| Input type | Count |
| --- | ---: |
| `final_catalog_or_hinet_revision` | 1 |
| `local_jma_reference_capture_package` | 2 |
| `versioned_jma_final_catalog_record` | 3 |

## Validation

- Errors: none
- Warnings: none

## Templates

| Priority | Type | Case | Target | Action | Validation |
| ---: | --- | --- | --- | --- | --- |
| 20 | `local_jma_reference_capture_package` | `20260625_iwate_offshore_m46_jma_eqsc9` | `docs/data/jma_reference_event_candidates.json` | associate an existing local replay/capture package | `powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_jma_reference_capture_association.ps1` |
| 20 | `local_jma_reference_capture_package` | `20260626_yamanashi_central_west_m26_jma_equake5` | `docs/data/jma_reference_event_candidates.json` | associate an existing local replay/capture package | `powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_jma_reference_capture_association.ps1` |
| 30 | `versioned_jma_final_catalog_record` | `20260622_kushiro_offshore_m30_jma` | `test/fixtures/source_estimation/kushiro_offshore_m30_20260622_jma.json` | import a versioned JMA catalog and link the matching fixture | `powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_jma_catalog_availability.ps1` |
| 30 | `versioned_jma_final_catalog_record` | `20260624_fukushima_aizu_m32_jma_eq5` | `test/fixtures/source_estimation/fukushima_aizu_m32_20260624_jma_eq5.json` | import a versioned JMA catalog and link the matching fixture | `powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_jma_catalog_availability.ps1` |
| 30 | `versioned_jma_final_catalog_record` | `20260625_iwate_offshore_m32_jma` | `test/fixtures/source_estimation/iwate_offshore_m32_20260625_jma.json` | import a versioned JMA catalog and link the matching fixture | `powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_jma_catalog_availability.ps1` |
| 40 | `final_catalog_or_hinet_revision` | `20260621_iwate_offshore_m33_eq8` | `test/fixtures/source_estimation/iwate_offshore_m33_20260621_eq8.json` | link a final catalog row or revised Hi-net source | `powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_source_estimation_split_blocker_queue.ps1` |

## Decision

- These templates are instructions only. This report does not edit capture packages, ledgers, fixtures, split manifests or production source-estimation behavior.
- Filling a template only makes the corresponding downstream guard eligible to re-run. It never clears source truth or capture blockers by itself.
