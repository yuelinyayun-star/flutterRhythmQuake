# PLUM Tohoku Validation Event/Propagation-Family Diagnostic

- Status: `pass`
- Method: `PLUM Tohoku validation event/propagation-family diagnostic`
- Frozen test evaluated: `false`
- Validation only: `true`
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

## Focus Filter

- Estimated-source region: `tohoku`
- Minimum evidence count: `8`
- Maximum nearest evidence distance: `10.0 km`
- Minimum prediction margin: `1.0 shindo`
- Baseline threshold crossing required: `true`
- Neighbor windows: `[10.0, 20.0]`

## Family Definitions

- `localConsistencyBand`
  - `consistent`: median belowThresholdShare10Km < 0.25
  - `mixed`: 0.25 <= median belowThresholdShare10Km < 0.50
  - `mismatch`: median belowThresholdShare10Km >= 0.50
- `geometryBand`
  - `surrounded`: median quadrant coverage >= 3.0
  - `one_sided`: median quadrant coverage < 3.0
- `spreadBand`
  - `compact`: median max spread < 20 km
  - `moderate`: 20 <= median max spread < 40 km
  - `wide`: median max spread >= 40 km

## `shindo4`

### Validation Focus Summary

| Samples | TP | FP | Precision | PLUM-only FP |
| ---: | ---: | ---: | ---: | ---: |
| 457 | 389 | 68 | 85.1% | 0 |

### Family Aggregates

| Family | Events | Samples | TP | FP | Precision | PLUM-only FP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `consistent/surrounded/wide` | 1 | 345 | 317 | 28 | 91.9% | 0 |
| `mismatch/surrounded/moderate` | 1 | 90 | 50 | 40 | 55.6% | 0 |
| `consistent/surrounded/moderate` | 1 | 22 | 22 | 0 | 100.0% | 0 |

### Event Signatures

| Event | Family | Samples | TP | FP | Precision | PLUM-only FP | Below@10km | Quadrants | Max Spread | Strongest Evidence | Actual |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `2021021323075051-37.7288-141.6985` | `consistent/surrounded/wide` | 345 | 317 | 28 | 91.9% | 0 | 0.0% | 4.00 | 47.14 | 5.40 | 5.10 |
| `2021032018094483-38.4680-141.6277` | `mismatch/surrounded/moderate` | 90 | 50 | 40 | 55.6% | 0 | 50.0% | 3.00 | 30.52 | 5.00 | 4.20 |
| `2021050110272690-38.1740-141.7400` | `consistent/surrounded/moderate` | 22 | 22 | 0 | 100.0% | 0 | 0.0% | 3.00 | 32.46 | 5.00 | 4.60 |

## `shindo5-`

### Validation Focus Summary

| Samples | TP | FP | Precision | PLUM-only FP |
| ---: | ---: | ---: | ---: | ---: |
| 28 | 26 | 2 | 92.9% | 0 |

### Family Aggregates

| Family | Events | Samples | TP | FP | Precision | PLUM-only FP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `consistent/one_sided/compact` | 1 | 28 | 26 | 2 | 92.9% | 0 |

### Event Signatures

| Event | Family | Samples | TP | FP | Precision | PLUM-only FP | Below@10km | Quadrants | Max Spread | Strongest Evidence | Actual |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `2021021323075051-37.7288-141.6985` | `consistent/one_sided/compact` | 28 | 26 | 2 | 92.9% | 0 | 0.0% | 2.00 | 18.59 | 5.80 | 5.30 |

## Decision

- This report is validation-only. It identifies candidate event-level propagation families before any further frozen-transfer verification.
- It does not tune PLUM, suppress predictions, or authorize production UI/wording/notification changes.

