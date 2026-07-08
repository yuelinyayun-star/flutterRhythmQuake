# PLUM Frozen-Test Evaluation

- Status: `pass`
- Split: `test`
- Frozen test evaluated: `true`
- Production ready: `false`
- Production UI connected: `false`
- Candidate: `plum_like_r30_d0_50`
- Outcome: `fail`

## Summary

| Metric | Value |
| --- | ---: |
| Cases | `2757` |
| Max-class MAE | `0.440` |
| Max-class underestimation | `17.2%` |
| Max-class within one | `95.4%` |

## Criteria Checks

| Check | Status | Actual | Required |
| --- | --- | ---: | ---: |
| `maxClassMae` | `pass` | `0.440` | `<= 0.500` |
| `maxClassUnderestimateRate` | `pass` | `17.2%` | `<= 25.0%` |
| `maxClassWithinOneAccuracy` | `pass` | `95.4%` | `>= 94.0%` |
| `shindo4Precision` | `fail` | `38.0%` | `>= 52.0%` |
| `shindo4Recall` | `fail` | `57.2%` | `>= 68.0%` |
| `shindo4F1` | `fail` | `45.7%` | `>= 60.0%` |
| `shindo5MinusPrecision` | `fail` | `26.5%` | `>= 52.0%` |
| `shindo5MinusRecall` | `fail` | `38.1%` | `>= 40.0%` |
| `shindo5MinusF1` | `fail` | `31.3%` | `>= 48.0%` |

## Decision

- Advance to production: `false`
- Next action: `diagnose_frozen_test_regression_before_any_production_gate`

This is the single frozen-test evaluation for the frozen diagnostic operating point. It does not authorize production UI, notifications or warning wording.

