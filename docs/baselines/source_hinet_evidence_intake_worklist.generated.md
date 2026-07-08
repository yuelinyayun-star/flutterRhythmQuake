# Source Hi-net Evidence Intake Worklist

- Status: `pass`
- Cases: `3`
- Authenticated-row templates ready: `0`
- No-row-found templates ready: `0`
- Authenticated evidence ready: `0`
- No-row evidence ready: `0`
- Reviewer-decision templates emitted: `0`
- Accepted constrained references: `3`
- Next-action counts: `{accepted_constrained_reference_waiting_split_gate: 3}`

## Worklist

| Case | Next action | Decision status | Accepted constrained | Window JST | Auth template | No-row template |
| --- | --- | --- | --- | --- | --- | --- |
| `20260622_iwate_east_offshore_m30_hinet` | `accepted_constrained_reference_waiting_split_gate` | `accepted_constrained_reference` | `true` | `null` | `` | `` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `accepted_constrained_reference_waiting_split_gate` | `accepted_constrained_reference` | `true` | `null` | `` | `` |
| `20260623_tokachi_southeast_offshore_m34_hinet` | `accepted_constrained_reference_waiting_split_gate` | `accepted_constrained_reference` | `true` | `null` | `` | `` |

## Commands

### 20260622_iwate_east_offshore_m30_hinet
- Auth dry-run: `null`
- Auth import: `null`
- No-row dry-run: `null`
- No-row import: `null`
- Reviewer dry-run: `null`
- Reviewer import: `null`

### 20260622_tomakomai_south_offshore_m35_hinet
- Auth dry-run: `null`
- Auth import: `null`
- No-row dry-run: `null`
- No-row import: `null`
- Reviewer dry-run: `null`
- Reviewer import: `null`

### 20260623_tokachi_southeast_offshore_m34_hinet
- Auth dry-run: `null`
- Auth import: `null`
- No-row dry-run: `null`
- No-row import: `null`
- Reviewer dry-run: `null`
- Reviewer import: `null`

## Decision

- Fill an authenticated-row template first when a matching event row exists.
- Fill a no-row-found template only after an authenticated search finds no matching row.
- After any evidence import, rerun reviewer-decision staging/templates before importing a truth-quality decision.
- Accepted constrained references skip evidence intake and wait for the separate constrained split gate.
- This worklist does not submit evidence, accept truth quality, assign splits or change metric eligibility.

## Validation

- Status: `pass`.
- Violations: none.

