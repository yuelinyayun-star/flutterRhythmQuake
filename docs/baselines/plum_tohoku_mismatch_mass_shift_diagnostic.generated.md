# PLUM Tohoku Mismatch Regime Mass-Shift Diagnostic

- Status: `pass`
- Method: `PLUM Tohoku mismatch regime mass-shift diagnostic`
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

## Definitions

- `localConsistencyBand`
  - `consistent`: belowThresholdShare10Km < 0.25
  - `mixed`: 0.25 <= belowThresholdShare10Km < 0.50
  - `mismatch`: belowThresholdShare10Km >= 0.50
- `geometrySpread`
  - `one_sided/compact`: quadrants < 3 and maxSpread < 20 km
  - `one_sided/moderate`: quadrants < 3 and 20 <= maxSpread < 40 km
  - `one_sided/wide`: quadrants < 3 and maxSpread >= 40 km
  - `surrounded/compact`: quadrants >= 3 and maxSpread < 20 km
  - `surrounded/moderate`: quadrants >= 3 and 20 <= maxSpread < 40 km
  - `surrounded/wide`: quadrants >= 3 and maxSpread >= 40 km
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

### Focus Summary

| Split | Samples | TP | FP | Precision | Mismatch Share |
| --- | ---: | ---: | ---: | ---: | ---: |
| validation | 457 | 389 | 68 | 85.1% | 13.3% |
| test | 1051 | 458 | 593 | 43.6% | 92.8% |

### Local-Consistency Mass Shift

| Bucket | Val Count | Val Share | Val Precision | Test Count | Test Share | Test Precision | Share Delta | Precision Delta |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `consistent` | 328 | 71.8% | 94.5% | 0 | 0.0% | 0.0% | -71.8pp | -94.5pp |
| `mixed` | 68 | 14.9% | 70.6% | 76 | 7.2% | 40.8% | -7.6pp | -29.8pp |
| `mismatch` | 61 | 13.3% | 50.8% | 975 | 92.8% | 43.8% | +79.4pp | -7.0pp |

### Mismatch Geometry/Spread Mass Shift

| Bucket | Val Count | Val Share | Val Precision | Test Count | Test Share | Test Precision | Share Delta | Precision Delta |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `one_sided/compact` | 8 | 13.1% | 50.0% | 249 | 25.5% | 45.0% | +12.4pp | -5.0pp |
| `one_sided/moderate` | 13 | 21.3% | 53.8% | 253 | 25.9% | 43.5% | +4.6pp | -10.4pp |
| `one_sided/wide` | 0 | 0.0% | 0.0% | 55 | 5.6% | 47.3% | +5.6pp | +47.3pp |
| `surrounded/compact` | 2 | 3.3% | 50.0% | 24 | 2.5% | 41.7% | -0.8pp | -8.3pp |
| `surrounded/moderate` | 30 | 49.2% | 50.0% | 224 | 23.0% | 43.3% | -26.2pp | -6.7pp |
| `surrounded/wide` | 8 | 13.1% | 50.0% | 170 | 17.4% | 42.4% | +4.3pp | -7.6pp |

### Mismatch Actual-Gap Mass Shift

| Bucket | Val Count | Val Share | Val Precision | Test Count | Test Share | Test Precision | Share Delta | Precision Delta |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `lt_-2.0` | 18 | 29.5% | 0.0% | 274 | 28.1% | 0.0% | -1.4pp | +0.0pp |
| `-2.0_to_-1.0` | 12 | 19.7% | 0.0% | 181 | 18.6% | 0.0% | -1.1pp | +0.0pp |
| `-1.0_to_0.0` | 0 | 0.0% | 0.0% | 93 | 9.5% | 0.0% | +9.5pp | +0.0pp |
| `0.0_to_1.0` | 5 | 8.2% | 100.0% | 186 | 19.1% | 100.0% | +10.9pp | +0.0pp |
| `gte_1.0` | 26 | 42.6% | 100.0% | 241 | 24.7% | 100.0% | -17.9pp | +0.0pp |

### Mismatch Evidence-Gap Mass Shift

| Bucket | Val Count | Val Share | Val Precision | Test Count | Test Share | Test Precision | Share Delta | Precision Delta |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `lt_1.0` | 31 | 50.8% | 100.0% | 247 | 25.3% | 100.0% | -25.5pp | +0.0pp |
| `1.0_to_2.0` | 0 | 0.0% | 0.0% | 160 | 16.4% | 83.1% | +16.4pp | +83.1pp |
| `2.0_to_3.0` | 0 | 0.0% | 0.0% | 121 | 12.4% | 38.8% | +12.4pp | +38.8pp |
| `gte_3.0` | 30 | 49.2% | 0.0% | 447 | 45.8% | 0.0% | -3.3pp | +0.0pp |
| `missing` | 0 | 0.0% | 0.0% | 0 | 0.0% | 0.0% | +0.0pp | +0.0pp |
## `shindo5-`

### Focus Summary

| Split | Samples | TP | FP | Precision | Mismatch Share |
| --- | ---: | ---: | ---: | ---: | ---: |
| validation | 28 | 26 | 2 | 92.9% | 0.0% |
| test | 40 | 10 | 30 | 25.0% | 100.0% |

### Local-Consistency Mass Shift

| Bucket | Val Count | Val Share | Val Precision | Test Count | Test Share | Test Precision | Share Delta | Precision Delta |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `consistent` | 23 | 82.1% | 100.0% | 0 | 0.0% | 0.0% | -82.1pp | -100.0pp |
| `mixed` | 5 | 17.9% | 60.0% | 0 | 0.0% | 0.0% | -17.9pp | -60.0pp |
| `mismatch` | 0 | 0.0% | 0.0% | 40 | 100.0% | 25.0% | +100.0pp | +25.0pp |

### Mismatch Geometry/Spread Mass Shift

| Bucket | Val Count | Val Share | Val Precision | Test Count | Test Share | Test Precision | Share Delta | Precision Delta |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `one_sided/compact` | 0 | 0.0% | 0.0% | 28 | 70.0% | 25.0% | +70.0pp | +25.0pp |
| `one_sided/moderate` | 0 | 0.0% | 0.0% | 12 | 30.0% | 25.0% | +30.0pp | +25.0pp |
| `one_sided/wide` | 0 | 0.0% | 0.0% | 0 | 0.0% | 0.0% | +0.0pp | +0.0pp |
| `surrounded/compact` | 0 | 0.0% | 0.0% | 0 | 0.0% | 0.0% | +0.0pp | +0.0pp |
| `surrounded/moderate` | 0 | 0.0% | 0.0% | 0 | 0.0% | 0.0% | +0.0pp | +0.0pp |
| `surrounded/wide` | 0 | 0.0% | 0.0% | 0 | 0.0% | 0.0% | +0.0pp | +0.0pp |

### Mismatch Actual-Gap Mass Shift

| Bucket | Val Count | Val Share | Val Precision | Test Count | Test Share | Test Precision | Share Delta | Precision Delta |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `lt_-2.0` | 0 | 0.0% | 0.0% | 20 | 50.0% | 0.0% | +50.0pp | +0.0pp |
| `-2.0_to_-1.0` | 0 | 0.0% | 0.0% | 2 | 5.0% | 0.0% | +5.0pp | +0.0pp |
| `-1.0_to_0.0` | 0 | 0.0% | 0.0% | 8 | 20.0% | 0.0% | +20.0pp | +0.0pp |
| `0.0_to_1.0` | 0 | 0.0% | 0.0% | 6 | 15.0% | 100.0% | +15.0pp | +100.0pp |
| `gte_1.0` | 0 | 0.0% | 0.0% | 4 | 10.0% | 100.0% | +10.0pp | +100.0pp |

### Mismatch Evidence-Gap Mass Shift

| Bucket | Val Count | Val Share | Val Precision | Test Count | Test Share | Test Precision | Share Delta | Precision Delta |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `lt_1.0` | 0 | 0.0% | 0.0% | 8 | 20.0% | 100.0% | +20.0pp | +100.0pp |
| `1.0_to_2.0` | 0 | 0.0% | 0.0% | 4 | 10.0% | 50.0% | +10.0pp | +50.0pp |
| `2.0_to_3.0` | 0 | 0.0% | 0.0% | 8 | 20.0% | 0.0% | +20.0pp | +0.0pp |
| `gte_3.0` | 0 | 0.0% | 0.0% | 20 | 50.0% | 0.0% | +50.0pp | +0.0pp |
| `missing` | 0 | 0.0% | 0.0% | 0 | 0.0% | 0.0% | +0.0pp | +0.0pp |
## Decision

- This report is diagnostic-only. It decomposes why frozen test shifts so much focus mass into already-weak mismatch regimes.
- It does not tune PLUM, suppress predictions, or authorize production UI/wording/notification changes.

