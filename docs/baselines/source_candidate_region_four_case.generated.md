# Source Candidate-Region Four-Case Report

- Status: `pass`
- Cases: `4`
- False-recovery guards blocked: `1`
- Residual delayed positives: `1`
- Residual immediate positives: `1`
- Local-support delayed positives: `1`
- Production coordinate switches: `0`

## Case Summary

| Case | Role | Outcome | Residual diagnosis | Local-support diagnosis | Switch |
| --- | --- | --- | --- | --- | ---: |
| `20260621_fukushima_offshore_m32_eq6` | `false_recovery_guard` | `blocked_by_dual_residual_and_local_growth` | `dual_regression_blocks_false_recovery` | `blocked_false_recovery_by_member_growth` | 0 |
| `20260622_kushiro_offshore_m30_jma` | `residual_delayed_positive_guard` | `same_region_residual_delayed_confirmation` | `same_region_residual_recovery_after_initial_no_support` | `--` | 0 |
| `20260622_tomakomai_south_offshore_m35_hinet` | `residual_immediate_positive_guard` | `dual_residual_immediate_confirmation` | `immediate_acceptance_by_dual_residual_support` | `--` | 0 |
| `20260625_iwate_offshore_m32_jma` | `local_support_positive_guard` | `local_support_delayed_confirmation` | `--` | `confirmed_positive_by_full_local_support` | 0 |

## Validation

- Status: `pass`.
- Violations: none.

