# PLUM Evidence Robustness Calibration Diagnostic

- Status: `pass`
- Split: `validation`
- Frozen test evaluated: `false`
- Production ready: `false`
- Raw predicted intensity mutated: `false`
- Station forecasts: `185694`

## Method

- This report does not suppress, cap, replace, or hide predicted intensity.
- It builds a joint calibration table over `branchAgreement` x `robustnessScore` for high-threshold predictions, and maps each non-empty bucket to an empirical confidence band.
- Confidence bands are diagnostic labels only; they do not change the raw predicted intensity field and must not feed notifications or UI wording until explicit wording-only acceptance criteria exist.

## Band Definitions

| Band | Min empirical precision |
| --- | ---: |
| `high` | `75.0%` |
| `medium` | `55.0%` |
| `low` | `0.0%` |
- Min sample for band assignment: `20`

## `shindo4`

- Baseline P/R/F1: `55.9% / 72.5% / 63.1%`

### Joint Calibration Table

| branchAgreement | robustnessScore | Pred+ | TP | FP | Precision | Band |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `agree_0` | `score_1` | 1 | 1 | 0 | 100.0% | `insufficient` |
| `agree_0` | `score_2` | 1 | 1 | 0 | 100.0% | `insufficient` |
| `agree_0` | `score_3` | 13 | 7 | 6 | 53.8% | `insufficient` |
| `agree_0` | `score_4` | 36 | 17 | 19 | 47.2% | `low` |
| `agree_1` | `score_1` | 14 | 1 | 13 | 7.1% | `insufficient` |
| `agree_1` | `score_2` | 90 | 49 | 41 | 54.4% | `low` |
| `agree_1` | `score_3` | 175 | 87 | 88 | 49.7% | `low` |
| `agree_1` | `score_4` | 820 | 278 | 542 | 33.9% | `low` |
| `agree_1` | `score_5` | 1872 | 473 | 1399 | 25.3% | `low` |
| `agree_2` | `score_4` | 12 | 12 | 0 | 100.0% | `insufficient` |
| `agree_2` | `score_5` | 502 | 389 | 113 | 77.5% | `high` |
| `agree_2` | `score_6` | 1156 | 722 | 434 | 62.5% | `medium` |
| `agree_3` | `score_5` | 14 | 11 | 3 | 78.6% | `insufficient` |
| `agree_3` | `score_6` | 300 | 262 | 38 | 87.3% | `high` |
| `agree_3` | `score_7` | 1833 | 1514 | 319 | 82.6% | `high` |

### Band Summary

| Band | Buckets | Pred+ | TP | FP | Precision |
| --- | ---: | ---: | ---: | ---: | ---: |
| `high` | 3 | 2635 | 2165 | 470 | 82.2% |
| `medium` | 1 | 1156 | 722 | 434 | 62.5% |
| `low` | 5 | 2993 | 904 | 2089 | 30.2% |
| `insufficient` | 6 | 55 | 33 | 22 | 60.0% |

## `shindo5-`

- Baseline P/R/F1: `58.8% / 46.9% / 52.2%`

### Joint Calibration Table

| branchAgreement | robustnessScore | Pred+ | TP | FP | Precision | Band |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `agree_0` | `score_4` | 23 | 14 | 9 | 60.9% | `medium` |
| `agree_1` | `score_1` | 1 | 0 | 1 | 0.0% | `insufficient` |
| `agree_1` | `score_2` | 1 | 1 | 0 | 100.0% | `insufficient` |
| `agree_1` | `score_3` | 3 | 3 | 0 | 100.0% | `insufficient` |
| `agree_1` | `score_4` | 45 | 22 | 23 | 48.9% | `low` |
| `agree_1` | `score_5` | 222 | 81 | 141 | 36.5% | `low` |
| `agree_2` | `score_4` | 2 | 1 | 1 | 50.0% | `insufficient` |
| `agree_2` | `score_5` | 58 | 38 | 20 | 65.5% | `medium` |
| `agree_2` | `score_6` | 364 | 245 | 119 | 67.3% | `medium` |
| `agree_3` | `score_6` | 18 | 16 | 2 | 88.9% | `insufficient` |
| `agree_3` | `score_7` | 44 | 38 | 6 | 86.4% | `high` |

### Band Summary

| Band | Buckets | Pred+ | TP | FP | Precision |
| --- | ---: | ---: | ---: | ---: | ---: |
| `high` | 1 | 44 | 38 | 6 | 86.4% |
| `medium` | 3 | 445 | 297 | 148 | 66.7% |
| `low` | 2 | 267 | 103 | 164 | 38.6% |
| `insufficient` | 5 | 25 | 21 | 4 | 84.0% |

## Decision

- Production remains blocked.
- Frozen test remains closed.
- Use the joint calibration table to design a future wording-only confidence layer; do not replace, cap, or hide predicted intensity.

