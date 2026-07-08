# PLUM Tohoku Mismatch Gap-Transition Diagnostic

- Status: `pass`
- Method: `PLUM Tohoku mismatch gap-transition diagnostic`
- Frozen test evaluated: `true`
- Production ready: `false`
- Production UI connected: `false`
- Diagnostic only: `true`
- Parameters tuned: `false`
- Suppression applied: `false`
- Raw predicted intensity mutated: `false`

## Coverage

| Split | Variants | Station forecasts |
| --- | ---: | ---: |
| validation | 2688 | 185694 |
| test | 2757 | 179844 |

## Focus Filter

- Estimated-source region: `tohoku`
- Minimum evidence count: `8`
- Maximum nearest evidence distance: `10.0 km`
- Minimum prediction margin: `1.0 shindo`
- Baseline threshold crossing required: `true`
- Neighbor windows: `[10.0, 20.0]`

## Gap Definitions

- `actualGapBand`
  - `lt_-2.0`: actual - threshold < -2.0
  - `-2.0_to_-1.0`: -2.0 <= actual - threshold < -1.0
  - `-1.0_to_0.0`: -1.0 <= actual - threshold < 0.0
  - `0.0_to_1.0`: 0.0 <= actual - threshold < 1.0
  - `gte_1.0`: actual - threshold >= 1.0
- `evidenceGapBand`
  - `lt_1.0`: strongestEvidence - actual < 1.0
  - `1.0_to_2.0`: 1.0 <= strongestEvidence - actual < 2.0
  - `2.0_to_3.0`: 2.0 <= strongestEvidence - actual < 3.0
  - `gte_3.0`: strongestEvidence - actual >= 3.0
  - `missing`: no supporting evidence intensity available

## `shindo4`

### Mismatch Summary

| Split | Mismatch Samples | Mismatch Precision |
| --- | ---: | ---: |
| validation | 61 | 50.8% |
| test | 975 | 43.8% |

### Gap Transition Matrix

| Actual Gap | Evidence Gap | Val Count | Val Share | Val Precision | Test Count | Test Share | Test Precision | Share Delta | Precision Delta |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `lt_-2.0` | `gte_3.0` | 18 | 29.5% | 0.0% | 274 | 28.1% | 0.0% | -1.4pp | +0.0pp |
| `-2.0_to_-1.0` | `2.0_to_3.0` | 0 | 0.0% | 0.0% | 19 | 1.9% | 0.0% | +1.9pp | +0.0pp |
| `-2.0_to_-1.0` | `gte_3.0` | 12 | 19.7% | 0.0% | 162 | 16.6% | 0.0% | -3.1pp | +0.0pp |
| `-1.0_to_0.0` | `1.0_to_2.0` | 0 | 0.0% | 0.0% | 27 | 2.8% | 0.0% | +2.8pp | +0.0pp |
| `-1.0_to_0.0` | `2.0_to_3.0` | 0 | 0.0% | 0.0% | 55 | 5.6% | 0.0% | +5.6pp | +0.0pp |
| `-1.0_to_0.0` | `gte_3.0` | 0 | 0.0% | 0.0% | 11 | 1.1% | 0.0% | +1.1pp | +0.0pp |
| `0.0_to_1.0` | `lt_1.0` | 5 | 8.2% | 100.0% | 22 | 2.3% | 100.0% | -5.9pp | +0.0pp |
| `0.0_to_1.0` | `1.0_to_2.0` | 0 | 0.0% | 0.0% | 117 | 12.0% | 100.0% | +12.0pp | +100.0pp |
| `0.0_to_1.0` | `2.0_to_3.0` | 0 | 0.0% | 0.0% | 47 | 4.8% | 100.0% | +4.8pp | +100.0pp |
| `gte_1.0` | `lt_1.0` | 26 | 42.6% | 100.0% | 225 | 23.1% | 100.0% | -19.5pp | +0.0pp |
| `gte_1.0` | `1.0_to_2.0` | 0 | 0.0% | 0.0% | 16 | 1.6% | 100.0% | +1.6pp | +100.0pp |

## `shindo5-`

### Mismatch Summary

| Split | Mismatch Samples | Mismatch Precision |
| --- | ---: | ---: |
| validation | 0 | 0.0% |
| test | 40 | 25.0% |

### Gap Transition Matrix

| Actual Gap | Evidence Gap | Val Count | Val Share | Val Precision | Test Count | Test Share | Test Precision | Share Delta | Precision Delta |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `lt_-2.0` | `gte_3.0` | 0 | 0.0% | 0.0% | 20 | 50.0% | 0.0% | +50.0pp | +0.0pp |
| `-2.0_to_-1.0` | `2.0_to_3.0` | 0 | 0.0% | 0.0% | 2 | 5.0% | 0.0% | +5.0pp | +0.0pp |
| `-1.0_to_0.0` | `1.0_to_2.0` | 0 | 0.0% | 0.0% | 2 | 5.0% | 0.0% | +5.0pp | +0.0pp |
| `-1.0_to_0.0` | `2.0_to_3.0` | 0 | 0.0% | 0.0% | 6 | 15.0% | 0.0% | +15.0pp | +0.0pp |
| `0.0_to_1.0` | `lt_1.0` | 0 | 0.0% | 0.0% | 4 | 10.0% | 100.0% | +10.0pp | +100.0pp |
| `0.0_to_1.0` | `1.0_to_2.0` | 0 | 0.0% | 0.0% | 2 | 5.0% | 100.0% | +5.0pp | +100.0pp |
| `gte_1.0` | `lt_1.0` | 0 | 0.0% | 0.0% | 4 | 10.0% | 100.0% | +10.0pp | +100.0pp |

## Decision

- This report is diagnostic-only. It checks whether frozen test creates new mismatch gap-transition cells that validation did not cover.
- It does not tune PLUM, suppress predictions, or authorize production UI/wording/notification changes.

