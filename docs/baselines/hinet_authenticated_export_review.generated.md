# Hi-net Authenticated Export Review

- Status: `pass`
- Request file: `docs/data/hinet_authenticated_export_request.json`
- Rows file: `docs/data/hinet_authenticated_export_rows.json`
- Decision file: `docs/data/hinet_truth_quality_review_decisions.json`
- Rows: `6`
- Pending exports: `0`
- Submitted for review: `6`
- Rejected: `0`
- Valid submitted rows: `6`
- Decision-evidence ready: `0`
- Pending decisions: `0`
- Accepted decisions: `6`

## Validation

- Errors: none
- Warnings: none

## Cases

| Case | Row status | Submitted valid | Evidence ready | Decision | Errors |
| --- | --- | --- | --- | --- | --- |
| `20260621_fukushima_offshore_m32_eq6` | `submitted_for_review` | yes | no | `accepted_constrained_reference` | `` |
| `20260622_iwate_east_offshore_m30_hinet` | `submitted_for_review` | yes | no | `accepted_constrained_reference` | `` |
| `20260622_iwate_offshore_m30_eq10` | `submitted_for_review` | yes | no | `accepted_constrained_reference` | `` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `submitted_for_review` | yes | no | `accepted_constrained_reference` | `` |
| `20260622_wakayama_south_m25_hinet` | `submitted_for_review` | yes | no | `accepted_constrained_reference` | `` |
| `20260623_tokachi_southeast_offshore_m34_hinet` | `submitted_for_review` | yes | no | `accepted_constrained_reference` | `` |

## Decision

- This report does not modify `docs/data/hinet_truth_quality_review_decisions.json`.
- A valid submitted row only becomes `decisionEvidenceReady=true`; a reviewer still has to explicitly copy it into the decision ledger.
