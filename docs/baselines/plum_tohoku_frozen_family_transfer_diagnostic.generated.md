# PLUM Tohoku Frozen Family Transfer Diagnostic

- Status: `pass`
- Method: `PLUM Tohoku frozen family transfer diagnostic`
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

### Focus Summary

| Split | Samples | TP | FP | Precision | PLUM-only FP |
| --- | ---: | ---: | ---: | ---: | ---: |
| validation | 457 | 389 | 68 | 85.1% | 0 |
| test | 1051 | 458 | 593 | 43.6% | 549 |

### Family Transfer

| Family | Val Events | Val Samples | Val TP | Val FP | Val Precision | Test Events | Test Samples | Test TP | Test FP | Test Precision | Delta |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `consistent/surrounded/moderate` | 1 | 22 | 22 | 0 | 100.0% | 0 | 0 | 0 | 0 | 0.0% | -100.0pp |
| `consistent/surrounded/wide` | 1 | 345 | 317 | 28 | 91.9% | 0 | 0 | 0 | 0 | 0.0% | -91.9pp |
| `mismatch/one_sided/moderate` | 0 | 0 | 0 | 0 | 0.0% | 1 | 1051 | 458 | 593 | 43.6% | +43.6pp |
| `mismatch/surrounded/moderate` | 1 | 90 | 50 | 40 | 55.6% | 0 | 0 | 0 | 0 | 0.0% | -55.6pp |

### Event Signatures

| Split | Event | Family | Samples | TP | FP | Precision | PLUM-only FP | Below@10km | Quadrants | Max Spread | Strongest Evidence | Actual |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| validation | `2021021323075051-37.7288-141.6985` | `consistent/surrounded/wide` | 345 | 317 | 28 | 91.9% | 0 | 0.0% | 4.00 | 47.14 | 5.40 | 5.10 |
| validation | `2021032018094483-38.4680-141.6277` | `mismatch/surrounded/moderate` | 90 | 50 | 40 | 55.6% | 0 | 50.0% | 3.00 | 30.52 | 5.00 | 4.20 |
| validation | `2021050110272690-38.1740-141.7400` | `consistent/surrounded/moderate` | 22 | 22 | 0 | 100.0% | 0 | 0.0% | 3.00 | 32.46 | 5.00 | 4.60 |
| test | `2022031623342701-37.6810-141.6062` | `mismatch/one_sided/moderate` | 1051 | 458 | 593 | 43.6% | 549 | 54.2% | 2.00 | 31.36 | 5.60 | 2.90 |

## `shindo5-`

### Focus Summary

| Split | Samples | TP | FP | Precision | PLUM-only FP |
| --- | ---: | ---: | ---: | ---: | ---: |
| validation | 28 | 26 | 2 | 92.9% | 0 |
| test | 40 | 10 | 30 | 25.0% | 30 |

### Family Transfer

| Family | Val Events | Val Samples | Val TP | Val FP | Val Precision | Test Events | Test Samples | Test TP | Test FP | Test Precision | Delta |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `consistent/one_sided/compact` | 1 | 28 | 26 | 2 | 92.9% | 0 | 0 | 0 | 0 | 0.0% | -92.9pp |
| `mismatch/one_sided/compact` | 0 | 0 | 0 | 0 | 0.0% | 1 | 40 | 10 | 30 | 25.0% | +25.0pp |

### Event Signatures

| Split | Event | Family | Samples | TP | FP | Precision | PLUM-only FP | Below@10km | Quadrants | Max Spread | Strongest Evidence | Actual |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| validation | `2021021323075051-37.7288-141.6985` | `consistent/one_sided/compact` | 28 | 26 | 2 | 92.9% | 0 | 0.0% | 2.00 | 18.59 | 5.80 | 5.30 |
| test | `2022031623342701-37.6810-141.6062` | `mismatch/one_sided/compact` | 40 | 10 | 30 | 25.0% | 30 | 73.7% | 2.00 | 11.94 | 6.00 | 2.60 |

## Decision

- This report is diagnostic-only. It freezes the validation-defined family labels and checks whether they transfer to the Tohoku frozen hotspot.
- It does not tune PLUM, suppress predictions, or authorize production UI/wording/notification changes.

