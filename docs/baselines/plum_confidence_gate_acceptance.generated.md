# PLUM Confidence Gate Acceptance Triage

- Status: `pass`
- Frozen test evaluated: `false`
- Production ready: `false`
- Raw intensity field mutated: `false`
- Recommended gate: `plum_r20_d0_50_only`
- Replay grid label: `r20_d0.50`
- Decision status: `fail`
- Ready for frozen criteria: `false`
- Requires manual decision: `true`

## Validation

| Metric | Value |
| --- | ---: |
| Shindo4 precision gain | 13.7% |
| Shindo4 recall loss | 11.8% |
| Shindo4 F1 gain | 1.7% |

## Replay

| Metric | Value |
| --- | ---: |
| Baseline shindo4 recall | 62.5% |
| Gate shindo4 recall | 56.3% |
| Baseline false alarms | 17 |
| Gate false alarms | 14 |
| False-alarm reduction | 17.6% |

## Notes

| Note |
| --- |
| `replay_recall_below_preferred_manual_decision_required` |
| `replay_coverage_below_minimum` |

## Decision

- This gate can only affect confidence/wording experiments; raw predicted intensity remains unchanged.
- Do not open frozen test or production wiring from this triage report.

