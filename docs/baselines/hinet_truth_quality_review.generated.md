# Hi-net Truth-Quality Review

- Status: `pass`
- Readiness report: `.dart_tool/source_estimation_split_assignment_readiness/report.json`
- Decision file: `docs/data/hinet_truth_quality_review_decisions.json`
- Readiness status: `pass`
- Hi-net review cases: `7`
- Decision cases: `7`
- Pending decisions: `1`
- Accepted constrained references: `6`
- Blocking-evidence cases: `1`
- Blocking-evidence entries: `1`
- Capture directories present: `7`
- Capture manifests present: `7`
- Capture provenance complete: `6`
- Capture manifest failures: `1`
- Reference-isolated cases: `2`
- Catalog truth flag mismatches: `0`
- Manual review ready cases: `2`

## Validation

- Errors: none
- Warnings: none

## Review Flag Counts

| Flag | Count |
| --- | ---: |
| `capture_manifest_has_failed_gifs` | 1 |
| `capture_manifest_has_missing_frames` | 1 |
| `capture_provenance_incomplete` | 1 |
| `hinet_information_without_user_provided_marker` | 1 |
| `not_isolated_from_frozen_metrics` | 5 |
| `preliminary` | 4 |
| `review_decision_pending` | 1 |
| `user_provided_not_preliminary` | 3 |

## Blocking Evidence Counts

| Type | Count |
| --- | ---: |
| `capture_repair_attempt` | 1 |

## Cases

| Case | Requirement | Decision | Accepted | Blocking evidence | Truth source | Truth quality | Catalog flag | Capture | Capture complete | Isolated | Flags |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `20260620_iwate_offshore_m34_ref` | `review_hinet_preliminary_truth_quality` | `pending_manual_review` | no | `capture_repair_attempt` | `hinet_hypocenter_information` | `hinet_preliminary_reference` | false | yes (307 files, 301/302 GIFs, 1 failed) | no | yes | `review_decision_pending`, `capture_manifest_has_failed_gifs`, `capture_manifest_has_missing_frames`, `capture_provenance_incomplete`, `hinet_information_without_user_provided_marker`, `preliminary` |
| `20260621_fukushima_offshore_m32_eq6` | `review_hinet_truth_quality` | `accepted_constrained_reference` | yes | `` | `user_provided_hinet_hypocenter` | `hinet_user_provided` | false | yes (1211 files, 1208/1208 GIFs, 0 failed) | yes | yes | `user_provided_not_preliminary` |
| `20260622_iwate_east_offshore_m30_hinet` | `review_hinet_preliminary_truth_quality` | `accepted_constrained_reference` | yes | `` | `user_provided_hinet_hypocenter` | `hinet_user_provided_preliminary` | false | yes (1211 files, 1208/1208 GIFs, 0 failed) | yes | no | `not_isolated_from_frozen_metrics`, `preliminary` |
| `20260622_iwate_offshore_m30_eq10` | `review_hinet_preliminary_truth_quality` | `accepted_constrained_reference` | yes | `` | `user_provided_hinet_hypocenter` | `hinet_user_provided` | false | yes (1211 files, 1208/1208 GIFs, 0 failed) | yes | no | `not_isolated_from_frozen_metrics`, `user_provided_not_preliminary` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `review_hinet_preliminary_truth_quality` | `accepted_constrained_reference` | yes | `` | `user_provided_hinet_hypocenter` | `hinet_user_provided_preliminary` | false | yes (1210 files, 1208/1208 GIFs, 0 failed) | yes | no | `not_isolated_from_frozen_metrics`, `preliminary` |
| `20260622_wakayama_south_m25_hinet` | `review_hinet_preliminary_truth_quality` | `accepted_constrained_reference` | yes | `` | `user_provided_hinet_hypocenter` | `hinet_user_provided` | false | yes (1211 files, 1208/1208 GIFs, 0 failed) | yes | no | `not_isolated_from_frozen_metrics`, `user_provided_not_preliminary` |
| `20260623_tokachi_southeast_offshore_m34_hinet` | `review_hinet_preliminary_truth_quality` | `accepted_constrained_reference` | yes | `` | `user_provided_hinet_hypocenter` | `hinet_user_provided_preliminary` | false | yes (1215 files, 1208/1208 GIFs, 0 failed) | yes | no | `not_isolated_from_frozen_metrics`, `preliminary` |

## Decision

- Hi-net user-provided or automatic hypocenter labels stay reference-only until a manual truth-quality review links a revised Hi-net/JMA source or explicitly accepts the case for a constrained reference split.
- `catalogTruthVerified=true` on a Hi-net preliminary/user-provided source is treated as a review flag, not as final catalog evidence.
- Pending decisions in `docs/data/hinet_truth_quality_review_decisions.json` do not clear blockers. A case can clear Hi-net review only after an explicit accepted decision records reviewer/evidence metadata.
