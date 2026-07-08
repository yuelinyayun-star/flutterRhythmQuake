# Source Hi-net Reviewer-Decision Templates

- Status: `pass`
- Cases: `3`
- Reviewer-decision eligible: `0`
- Templates emitted: `0`
- Blocked: `3`
- Decision ledger writes allowed: `0`
- Truth-quality acceptance allowed: `0`

## Cases

| Case | Eligible | Ready evidence | Blockers | Template | Import dry-run |
| --- | --- | --- | --- | --- | --- |
| `20260622_iwate_east_offshore_m30_hinet` | `false` | `` | `evidence_not_ready`, `decision_not_pending_manual_review`, `already_accepted` | `null` | `null` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `false` | `` | `evidence_not_ready`, `decision_not_pending_manual_review`, `already_accepted` | `null` | `null` |
| `20260623_tokachi_southeast_offshore_m34_hinet` | `false` | `` | `evidence_not_ready`, `decision_not_pending_manual_review`, `already_accepted` | `null` | `null` |

## Decision

- Templates are emitted only after staging marks a case eligible.
- A filled template still must pass the reviewer-decision importer.
- This packet does not write the decision ledger, assign splits or change metric eligibility.

## Validation

- Status: `pass`.
- Violations: none.

