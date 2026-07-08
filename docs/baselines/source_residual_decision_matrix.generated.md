# Source Residual Decision Matrix

- Status: `pass`
- Diagnostic only: `true`
- Production coordinate switches: `0`
- Manifest cases: `6` (4 with candidate-region frames)
- Unexpected local-support confirmations: `0`

## Matrix

| Signature | Status | Cases | Decision | Evidence |
| --- | --- | --- | --- | --- |
| `immediate_accept` | `pass` | `20260622_tomakomai_south_offshore_m35_hinet` | candidate-region can be confirmed immediately when rank and attenuation both support the candidate and there is no dual residual regression | `acceptedPositiveFrameCount=3`, `confirmedImmediateCount=3`, `rejectedPositiveFrameCount=0`, `dualRegressionRejectedPositiveFrameCount=0`, `coordinateSwitchAllowedCount=0` |
| `delayed_same_region_recovery` | `pass` | `20260622_kushiro_offshore_m30_jma` | early no-support candidate frames may be recovered by a later same-region residual-supported frame | `delayedRecoveredPositiveFrameCount=3`, `residualConfirmedDelayedCount=1`, `dualRegressionRejectedPositiveFrameCount=0`, `noSupportRejectedPositiveFrameCount=3`, `coordinateSwitchAllowedCount=0` |
| `false_recovery_reject` | `pass` | `20260621_fukushima_offshore_m32_eq6` | candidate frames that improve truth offline but regress rank and attenuation together remain rejected | `rejectedPositiveFrameCount=7`, `delayedRecoveredPositiveFrameCount=0`, `dualRegressionRejectedPositiveFrameCount=7`, `coordinateSwitchAllowedCount=0` |
| `local_support_delayed_confirmation` | `pass` | `20260625_iwate_offshore_m32_jma` | local member growth may confirm a pending candidate-region as diagnostic metadata only | `localSupportConfirmedCount=1`, `confirmedDelayedCount=1`, `expectedResidualConfirmedDelayedCount=0`, `unexpectedLocalSupportConfirmationCount=0`, `coordinateSwitchAllowedCount=0` |
| `no_candidate_region_control` | `pass` | `20260623_tokachi_southeast_offshore_m34_hinet`, `20260624_fukushima_aizu_m32_jma_eq5` | manifest controls without candidate-region evidence must stay empty and must not create delayed confirmations | `controlCaseCount=2`, `productionCoordinateSwitchAllowedCount=0`, `cases=2` |

## Interpretation

- `immediate_accept`: Tomakomai remains the positive guard for direct residual-supported confirmation.
- `delayed_same_region_recovery`: Kushiro keeps the delayed recovery path for early no-support frames.
- `false_recovery_reject`: Fukushima remains blocked because rank and attenuation regress together.
- `local_support_delayed_confirmation`: Iwate is confirmed by local member growth only as metadata.
- `no_candidate_region_control`: Tokachi and Fukushima Aizu stay empty controls.

## Validation

- Status: `pass`.
- Violations: none.

