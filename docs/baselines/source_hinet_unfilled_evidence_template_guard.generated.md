# Source Hi-net Unfilled Evidence Template Guard

- Status: `pass`
- Cases: `3`
- Auth templates rejected: `3`
- No-row templates rejected: `3`
- Credential fields present: `0`
- Accidental importable templates: `0`

## Cases

| Case | Auth rejected | Auth errors | No-row rejected | No-row errors |
| --- | --- | --- | --- | --- |
| `20260622_iwate_east_offshore_m30_hinet` | `true` | `unresolved_placeholder:sourceVersionOrPageDate`, `unresolved_placeholder:checkedAtUtc`, `unresolved_placeholder:reviewer`, `unresolved_placeholder:originTimeJst`, `missing_required_field:latitude`, `missing_required_field:longitude`, `missing_required_field:depthKm`, `missing_required_field:magnitude`, `unresolved_placeholder:region`, `unresolved_placeholder:rawRowText`, `checked_at_not_parseable`, `origin_time_not_parseable`, `numeric_field_required:latitude`, `numeric_field_required:longitude`, `numeric_field_required:depthKm`, `numeric_field_required:magnitude` | `true` | `unresolved_placeholder:checkedAtUtc`, `unresolved_placeholder:reviewer`, `unresolved_placeholder:searchedOriginTimeJst`, `missing_required_field:searchedLatitude`, `missing_required_field:searchedLongitude`, `missing_required_field:searchedMagnitude`, `unresolved_placeholder:notes`, `checked_at_not_parseable`, `numeric_field_required:searchedLatitude`, `numeric_field_required:searchedLongitude`, `numeric_field_required:searchedMagnitude` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `true` | `unresolved_placeholder:sourceVersionOrPageDate`, `unresolved_placeholder:checkedAtUtc`, `unresolved_placeholder:reviewer`, `unresolved_placeholder:originTimeJst`, `missing_required_field:latitude`, `missing_required_field:longitude`, `missing_required_field:depthKm`, `missing_required_field:magnitude`, `unresolved_placeholder:region`, `unresolved_placeholder:rawRowText`, `checked_at_not_parseable`, `origin_time_not_parseable`, `numeric_field_required:latitude`, `numeric_field_required:longitude`, `numeric_field_required:depthKm`, `numeric_field_required:magnitude` | `true` | `unresolved_placeholder:checkedAtUtc`, `unresolved_placeholder:reviewer`, `unresolved_placeholder:searchedOriginTimeJst`, `missing_required_field:searchedLatitude`, `missing_required_field:searchedLongitude`, `missing_required_field:searchedMagnitude`, `unresolved_placeholder:notes`, `checked_at_not_parseable`, `numeric_field_required:searchedLatitude`, `numeric_field_required:searchedLongitude`, `numeric_field_required:searchedMagnitude` |
| `20260623_tokachi_southeast_offshore_m34_hinet` | `true` | `unresolved_placeholder:sourceVersionOrPageDate`, `unresolved_placeholder:checkedAtUtc`, `unresolved_placeholder:reviewer`, `unresolved_placeholder:originTimeJst`, `missing_required_field:latitude`, `missing_required_field:longitude`, `missing_required_field:depthKm`, `missing_required_field:magnitude`, `unresolved_placeholder:region`, `unresolved_placeholder:rawRowText`, `checked_at_not_parseable`, `origin_time_not_parseable`, `numeric_field_required:latitude`, `numeric_field_required:longitude`, `numeric_field_required:depthKm`, `numeric_field_required:magnitude` | `true` | `unresolved_placeholder:checkedAtUtc`, `unresolved_placeholder:reviewer`, `unresolved_placeholder:searchedOriginTimeJst`, `missing_required_field:searchedLatitude`, `missing_required_field:searchedLongitude`, `missing_required_field:searchedMagnitude`, `unresolved_placeholder:notes`, `checked_at_not_parseable`, `numeric_field_required:searchedLatitude`, `numeric_field_required:searchedLongitude`, `numeric_field_required:searchedMagnitude` |

## Decision

- Generated templates are intentionally not importable until a reviewer fills real evidence.
- This guard calls validators directly; it does not execute import commands or write ledgers.
- Evidence, truth quality, split assignment and metric eligibility remain unchanged.

## Validation

- Status: `pass`.
- Violations: none.

