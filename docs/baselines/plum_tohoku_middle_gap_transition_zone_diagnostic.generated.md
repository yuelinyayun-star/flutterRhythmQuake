# PLUM Tohoku Middle-Gap Transition-Zone Diagnostic

- Status: `pass`
- Method: `PLUM Tohoku middle-gap transition-zone diagnostic`
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

## Zone Definitions

- `middle_transition_zone`: actual gap in [-1.0, +1.0) and evidence gap in [1.0, 3.0)
- `extreme_false_zone`: actual gap < -1.0 and evidence gap >= 3.0
- `extreme_true_zone`: actual gap >= 0.0 and evidence gap < 1.0
- `other_mismatch_zone`: all remaining mismatch cells outside the three comparison zones

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

### Zone Comparison

| Zone | Val Count | Val Share | Val Precision | Test Count | Test Share | Test Precision | Share Delta | Precision Delta |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `middle_transition_zone` | 0 | 0.0% | 0.0% | 246 | 25.2% | 66.7% | +25.2pp | +66.7pp |
| `extreme_false_zone` | 30 | 49.2% | 0.0% | 436 | 44.7% | 0.0% | -4.5pp | +0.0pp |
| `extreme_true_zone` | 31 | 50.8% | 100.0% | 247 | 25.3% | 100.0% | -25.5pp | +0.0pp |
| `other_mismatch_zone` | 0 | 0.0% | 0.0% | 46 | 4.7% | 34.8% | +4.7pp | +34.8pp |

### Signature Assessment

- Dominant share-delta zone: `middle_transition_zone` (+25.2pp)
- Middle-transition share: `0.0% -> 25.2%`
- Middle-transition precision delta: `+66.7pp`
- Middle-transition likely frozen-only signature: `true`

## `shindo5-`

### Mismatch Summary

| Split | Mismatch Samples | Mismatch Precision |
| --- | ---: | ---: |
| validation | 0 | 0.0% |
| test | 40 | 25.0% |

### Zone Comparison

| Zone | Val Count | Val Share | Val Precision | Test Count | Test Share | Test Precision | Share Delta | Precision Delta |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `middle_transition_zone` | 0 | 0.0% | 0.0% | 10 | 25.0% | 20.0% | +25.0pp | +20.0pp |
| `extreme_false_zone` | 0 | 0.0% | 0.0% | 20 | 50.0% | 0.0% | +50.0pp | +0.0pp |
| `extreme_true_zone` | 0 | 0.0% | 0.0% | 8 | 20.0% | 100.0% | +20.0pp | +100.0pp |
| `other_mismatch_zone` | 0 | 0.0% | 0.0% | 2 | 5.0% | 0.0% | +5.0pp | +0.0pp |

### Signature Assessment

- Dominant share-delta zone: `extreme_false_zone` (+50.0pp)
- Middle-transition share: `0.0% -> 25.0%`
- Middle-transition precision delta: `+20.0pp`
- Middle-transition likely frozen-only signature: `false`

## Decision

- This report is diagnostic-only. It tests whether the frozen hotspot is best explained by a narrow middle transition zone rather than by broad mismatch labeling.
- It does not tune PLUM, suppress predictions, or authorize production UI/wording/notification changes.

