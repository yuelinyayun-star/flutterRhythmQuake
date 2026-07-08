# Hi-net Truth-Quality Review Queue

- Status: `pass`
- Review report: `.dart_tool/hinet_truth_quality_review/report.json`
- Cases: `7`
- Priority external-evidence reviews: `6`
- Capture-repair blocked: `1`
- Catalog-flag-mismatch blocked: `0`
- External evidence missing: `1`
- Accepted constrained references: `6`

## Next Action Counts

| Action | Count |
| --- | ---: |
| `collect_external_hinet_or_jma_revised_evidence` | 6 |
| `repair_capture_before_review` | 1 |

## Cases

| Case | Priority | Next action | Truth quality | Capture complete | Catalog mismatch | Required evidence |
| --- | ---: | --- | --- | --- | --- | --- |
| `20260621_fukushima_offshore_m32_eq6` | 1 | `collect_external_hinet_or_jma_revised_evidence` | `hinet_user_provided` | yes | no | `external_hinet_or_jma_source_quality_evidence`, `reviewer_and_review_timestamp` |
| `20260622_iwate_east_offshore_m30_hinet` | 1 | `collect_external_hinet_or_jma_revised_evidence` | `hinet_user_provided_preliminary` | yes | no | `revised_hinet_or_jma_final_catalog_link`, `reviewer_and_review_timestamp` |
| `20260622_iwate_offshore_m30_eq10` | 1 | `collect_external_hinet_or_jma_revised_evidence` | `hinet_user_provided` | yes | no | `external_hinet_or_jma_source_quality_evidence`, `reviewer_and_review_timestamp` |
| `20260622_tomakomai_south_offshore_m35_hinet` | 1 | `collect_external_hinet_or_jma_revised_evidence` | `hinet_user_provided_preliminary` | yes | no | `revised_hinet_or_jma_final_catalog_link`, `reviewer_and_review_timestamp` |
| `20260622_wakayama_south_m25_hinet` | 1 | `collect_external_hinet_or_jma_revised_evidence` | `hinet_user_provided` | yes | no | `external_hinet_or_jma_source_quality_evidence`, `reviewer_and_review_timestamp` |
| `20260623_tokachi_southeast_offshore_m34_hinet` | 1 | `collect_external_hinet_or_jma_revised_evidence` | `hinet_user_provided_preliminary` | yes | no | `revised_hinet_or_jma_final_catalog_link`, `reviewer_and_review_timestamp` |
| `20260620_iwate_offshore_m34_ref` | 3 | `repair_capture_before_review` | `hinet_preliminary_reference` | no | no | `complete_or_exclude_local_capture_package`, `revised_hinet_or_jma_final_catalog_link`, `reviewer_and_review_timestamp` |

## Decision

- This queue does not accept or split any Hi-net case. It only orders the current pending review cases by the evidence needed next.
- Cases in `collect_external_hinet_or_jma_revised_evidence` are the first practical review targets because their local capture packages are complete and they do not carry the catalog-truth flag mismatch.
- Cases with catalog-truth flag mismatch must first remove or justify that mismatch; Hi-net/user-provided labels are not JMA final catalog truth.
