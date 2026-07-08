# Source Local-Support Separation Report

- Status: `pass`
- Cases: `2`
- False-recovery guard confirmations: `0`
- Positive guard confirmations: `1`
- Near-complete frames blocked only by growth: `3`
- Production coordinate switches: `0`

## Thresholds

| Member count | Member growth | Est-member distance | Convergence | Window |
| ---: | ---: | ---: | ---: | ---: |
| `8` | `4` | `50.0km` | `80.0km` | `5.0s` |

## Case Summary

| Case | Role | Diagnosis | Frames | Confirmed | Expired | Growth-blocked near-complete | Switch |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| `20260621_fukushima_offshore_m32_eq6` | `false_recovery_guard` | `blocked_false_recovery_by_member_growth` | 13 | 0 | 2 | 3 | 0 |
| `20260625_iwate_offshore_m32_jma` | `local_support_positive_guard` | `confirmed_positive_by_full_local_support` | 4 | 1 | 0 | 0 | 0 |

## Local-Support Frames

| Case | Time | Status | Age | Confirm | Count | Growth | Distance | Converge | Geometry | Blockers |
| --- | --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:41:56.000` | `expired` | 6 | no | 16 | 11 | 187.9 | -54.7 | `one_sided` | `estimateMemberDistance`, `convergence`, `geometry`, `confirmationWindow` |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:42:00.000` | `pending` | 4 | no | 17 | 1 | 5.7 | 182.2 | `surrounded` | `memberGrowth` |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:42:01.000` | `pending` | 5 | no | 17 | 1 | 5.7 | 182.2 | `surrounded` | `memberGrowth` |
| `20260621_fukushima_offshore_m32_eq6` | `2026-06-21T23:42:02.000` | `expired` | 6 | no | 18 | 2 | 2.8 | 185.1 | `surrounded` | `memberGrowth`, `confirmationWindow` |
| `20260625_iwate_offshore_m32_jma` | `2026-06-25T19:22:00.000` | `confirmedDelayed` | 3 | yes | 11 | 5 | 19.1 | 137.4 | `surrounded` | -- |

## Validation

- Status: `pass`.
- Violations: none.

