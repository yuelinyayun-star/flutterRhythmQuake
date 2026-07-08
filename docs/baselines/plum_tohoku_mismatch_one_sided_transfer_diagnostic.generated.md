# PLUM Tohoku Mismatch One-Sided Transfer Diagnostic

- Status: `pass`
- Method: `PLUM Tohoku mismatch one-sided transfer diagnostic`
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

## Regime Definitions

- `localConsistencyBand`
  - `consistent`: belowThresholdShare10Km < 0.25
  - `mixed`: 0.25 <= belowThresholdShare10Km < 0.50
  - `mismatch`: belowThresholdShare10Km >= 0.50
- `geometryBand`
  - `surrounded`: quadrant coverage >= 3
  - `one_sided`: quadrant coverage < 3
- `spreadBand`
  - `compact`: max spread < 20 km
  - `moderate`: 20 <= max spread < 40 km
  - `wide`: max spread >= 40 km

## `shindo4`

### Focus Summary

| Split | Samples | TP | FP | Precision |
| --- | ---: | ---: | ---: | ---: |
| validation | 457 | 389 | 68 | 85.1% |
| test | 1051 | 458 | 593 | 43.6% |

### Regime Aggregates

| Split | Regime | Samples | TP | FP | Precision |
| --- | --- | ---: | ---: | ---: | ---: |
| validation | `consistent/surrounded/wide` | 217 | 202 | 15 | 93.1% |
| validation | `consistent/surrounded/moderate` | 85 | 84 | 1 | 98.8% |
| validation | `mixed/surrounded/wide` | 36 | 27 | 9 | 75.0% |
| validation | `mismatch/surrounded/moderate` | 30 | 15 | 15 | 50.0% |
| validation | `mixed/surrounded/moderate` | 20 | 13 | 7 | 65.0% |
| validation | `consistent/one_sided/moderate` | 14 | 12 | 2 | 85.7% |
| validation | `mismatch/one_sided/moderate` | 13 | 7 | 6 | 53.8% |
| validation | `mismatch/surrounded/wide` | 8 | 4 | 4 | 50.0% |
| validation | `mismatch/one_sided/compact` | 8 | 4 | 4 | 50.0% |
| validation | `consistent/surrounded/compact` | 5 | 5 | 0 | 100.0% |
| validation | `mixed/one_sided/wide` | 4 | 2 | 2 | 50.0% |
| validation | `mixed/one_sided/moderate` | 4 | 3 | 1 | 75.0% |
| validation | `mixed/one_sided/compact` | 4 | 3 | 1 | 75.0% |
| validation | `consistent/one_sided/wide` | 4 | 4 | 0 | 100.0% |
| validation | `consistent/one_sided/compact` | 3 | 3 | 0 | 100.0% |
| validation | `mismatch/surrounded/compact` | 2 | 1 | 1 | 50.0% |
| test | `mismatch/one_sided/moderate` | 253 | 110 | 143 | 43.5% |
| test | `mismatch/one_sided/compact` | 249 | 112 | 137 | 45.0% |
| test | `mismatch/surrounded/moderate` | 224 | 97 | 127 | 43.3% |
| test | `mismatch/surrounded/wide` | 170 | 72 | 98 | 42.4% |
| test | `mismatch/one_sided/wide` | 55 | 26 | 29 | 47.3% |
| test | `mixed/one_sided/moderate` | 28 | 12 | 16 | 42.9% |
| test | `mismatch/surrounded/compact` | 24 | 10 | 14 | 41.7% |
| test | `mixed/surrounded/moderate` | 16 | 6 | 10 | 37.5% |
| test | `mixed/surrounded/wide` | 16 | 6 | 10 | 37.5% |
| test | `mixed/one_sided/compact` | 16 | 7 | 9 | 43.8% |

### Mismatch Transfer

| Regime | Val Samples | Val TP | Val FP | Val Precision | Test Samples | Test TP | Test FP | Test Precision | Delta |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `mismatch/one_sided/compact` | 8 | 4 | 4 | 50.0% | 249 | 112 | 137 | 45.0% | -5.0pp |
| `mismatch/one_sided/moderate` | 13 | 7 | 6 | 53.8% | 253 | 110 | 143 | 43.5% | -10.4pp |
| `mismatch/one_sided/wide` | 0 | 0 | 0 | 0.0% | 55 | 26 | 29 | 47.3% | +47.3pp |
| `mismatch/surrounded/compact` | 2 | 1 | 1 | 50.0% | 24 | 10 | 14 | 41.7% | -8.3pp |
| `mismatch/surrounded/moderate` | 30 | 15 | 15 | 50.0% | 224 | 97 | 127 | 43.3% | -6.7pp |
| `mismatch/surrounded/wide` | 8 | 4 | 4 | 50.0% | 170 | 72 | 98 | 42.4% | -7.6pp |

## `shindo5-`

### Focus Summary

| Split | Samples | TP | FP | Precision |
| --- | ---: | ---: | ---: | ---: |
| validation | 28 | 26 | 2 | 92.9% |
| test | 40 | 10 | 30 | 25.0% |

### Regime Aggregates

| Split | Regime | Samples | TP | FP | Precision |
| --- | --- | ---: | ---: | ---: | ---: |
| validation | `consistent/one_sided/compact` | 10 | 10 | 0 | 100.0% |
| validation | `consistent/surrounded/moderate` | 7 | 7 | 0 | 100.0% |
| validation | `consistent/surrounded/compact` | 6 | 6 | 0 | 100.0% |
| validation | `mixed/one_sided/moderate` | 4 | 2 | 2 | 50.0% |
| validation | `mixed/one_sided/compact` | 1 | 1 | 0 | 100.0% |
| test | `mismatch/one_sided/compact` | 28 | 7 | 21 | 25.0% |
| test | `mismatch/one_sided/moderate` | 12 | 3 | 9 | 25.0% |

### Mismatch Transfer

| Regime | Val Samples | Val TP | Val FP | Val Precision | Test Samples | Test TP | Test FP | Test Precision | Delta |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `mismatch/one_sided/compact` | 0 | 0 | 0 | 0.0% | 28 | 7 | 21 | 25.0% | +25.0pp |
| `mismatch/one_sided/moderate` | 0 | 0 | 0 | 0.0% | 12 | 3 | 9 | 25.0% | +25.0pp |

## Decision

- This report is diagnostic-only. It checks whether one-sidedness is the transfer-breaking dimension inside mismatch regimes.
- It does not tune PLUM, suppress predictions, or authorize production UI/wording/notification changes.

