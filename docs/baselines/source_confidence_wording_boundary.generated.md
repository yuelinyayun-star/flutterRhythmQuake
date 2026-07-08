# Source Confidence Wording Boundary

- Status: `pass`
- Diagnostic only: `true`
- Boundaries: `6` (6 pass)
- Source-card visible boundaries: `4`
- Official alert wording allowed: `0`
- Production coordinate switches allowed: `0`

## Boundary Matrix

| Signal | Status | Source card | Reports/debug | Official alert wording | Coordinate switch | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| `production_estimate_quality` | `pass` | `show_quality_line` | `show_full_metrics` | `hide` | `forbid` | `delayed_same_region_recovery`, `false_recovery_reject`, `immediate_accept`, `local_support_delayed_confirmation`, `no_candidate_region_control` |
| `candidate_region_pending` | `pass` | `show_as_uncertainty_only` | `show_full_metrics` | `hide` | `forbid` | `delayed_same_region_recovery` |
| `candidate_region_residual_confirmed` | `pass` | `show_as_diagnostic_confirmation` | `show_full_metrics` | `hide` | `forbid` | `immediate_accept`, `delayed_same_region_recovery` |
| `candidate_region_local_support_confirmed` | `pass` | `show_as_diagnostic_confirmation` | `show_full_metrics` | `hide` | `forbid` | `local_support_delayed_confirmation` |
| `candidate_region_rejected_or_expired` | `pass` | `hide_or_show_debug_only` | `show_full_metrics` | `hide` | `forbid` | `false_recovery_reject`, `no_candidate_region_control` |
| `event_level_metrics_and_split` | `pass` | `not_ready` | `show_blocker_state` | `hide` | `forbid` | -- |

## Allowed Copy

### production_estimate_quality

- Allowed: quality grade and confidence percentage; RMS residual, azimuthal gap and P90 uncertainty; estimated shindo badge colored by estimated shindo; trigger and support station counts.
- Forbidden: final hypocenter wording; JMA or EEW replacement wording; coordinate correction wording.

### candidate_region_pending

- Allowed: candidate region pending; awaiting same-region residual or local member support.
- Forbidden: confirmed epicenter; replace production hypocenter; voice or push alert wording.

### candidate_region_residual_confirmed

- Allowed: candidate region confirmed; candidate region delayed-confirmed; same-region residual support.
- Forbidden: official source update; production coordinate switch; final report language.

### candidate_region_local_support_confirmed

- Allowed: candidate region delayed-confirmed; local member support station count and growth; estimate-member centroid distance and convergence.
- Forbidden: local-support truth claim; replace production hypocenter; official alert wording.

### candidate_region_rejected_or_expired

- Allowed: rejected in debug/report surfaces; expired in debug/report surfaces; dual residual regression reason.
- Forbidden: uncertain epicenter warning in alert copy; candidate region map recenter; coordinate correction wording.

### event_level_metrics_and_split

- Allowed: diagnostic-ready only; split or metric gate not complete.
- Forbidden: validated production accuracy wording; calibrated probability wording; test-set performance wording.

## Decision

- Source-estimation card may show production estimate quality and explicitly diagnostic candidate-region state.
- Generated reports and debug surfaces may show full candidate-region residual/local-support details.
- Official alert wording, voice/push wording and production coordinate replacement remain disallowed.
- Event-level split and metric gates must be completed before any calibrated production accuracy wording is introduced.

## Validation

- Status: `pass`.
- Violations: none.

