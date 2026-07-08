# PLUM Tohoku Focus Distance/Site Frozen Diagnostic

- Status: `pass`
- Method: `PLUM Tohoku focus distance/site frozen diagnostic`
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
- Minimum PLUM prediction margin: `1.0 shindo`
- Baseline threshold crossing required: `true`

## `shindo4`

### Focus Baseline

| Split | Focus samples | TP | FP | Precision |
| --- | ---: | ---: | ---: | ---: |
| validation | 457 | 389 | 68 | 85.1% |
| test | 1051 | 458 | 593 | 43.6% |

### Marginal Distance Precision

| Distance | Validation P+/P | Test P+/P | Delta |
| --- | ---: | ---: | ---: |
| `000_030km` | 152 / 74.3% | 150 / 48.0% | -26.3pp |
| `030_060km` | 111 / 79.3% | 321 / 45.5% | -33.8pp |
| `060_100km` | 146 / 95.9% | 413 / 42.9% | -53.0pp |
| `100_200km` | 48 / 100.0% | 165 / 37.6% | -62.4pp |
| `gt_200km` | 0 / 0.0% | 2 / 50.0% | +50.0pp |

### Distance-Site Buckets

| Distance | Site | Validation P+/P | Validation Band | Test P+/P | Delta |
| --- | --- | ---: | --- | ---: | ---: |
| `000_030km` | `tohoku` | 152 / 74.3% | `medium` | 150 / 48.0% | -26.3pp |
| `030_060km` | `kanto_chubu` | 25 / 76.0% | `high` | 4 / 50.0% | -26.0pp |
| `030_060km` | `tohoku` | 86 / 80.2% | `high` | 317 / 45.4% | -34.8pp |
| `060_100km` | `kanto_chubu` | 57 / 98.2% | `high` | 120 / 47.5% | -50.7pp |
| `060_100km` | `tohoku` | 89 / 94.4% | `high` | 293 / 41.0% | -53.4pp |
| `100_200km` | `kanto_chubu` | 7 / 100.0% | `insufficient` | 142 / 38.7% | -61.3pp |
| `100_200km` | `tohoku` | 41 / 100.0% | `high` | 23 / 30.4% | -69.6pp |

### Band Transfer

| Band | Validation Buckets | Validation P+/P | Test P+/P | Delta |
| --- | ---: | ---: | ---: | ---: |
| `high` | 5 | 298 / 90.3% | 757 / 43.6% | -46.7pp |
| `medium` | 1 | 152 / 74.3% | 150 / 48.0% | -26.3pp |
| `low` | 0 | 0 / 0.0% | 0 / 0.0% | +0.0pp |
| `insufficient` | 1 | 7 / 100.0% | 142 / 38.7% | -61.3pp |

## `shindo5-`

### Focus Baseline

| Split | Focus samples | TP | FP | Precision |
| --- | ---: | ---: | ---: | ---: |
| validation | 28 | 26 | 2 | 92.9% |
| test | 40 | 10 | 30 | 25.0% |

### Marginal Distance Precision

| Distance | Validation P+/P | Test P+/P | Delta |
| --- | ---: | ---: | ---: |
| `000_030km` | 10 / 80.0% | 0 / 0.0% | -80.0pp |
| `030_060km` | 7 / 100.0% | 8 / 25.0% | -75.0pp |
| `060_100km` | 7 / 100.0% | 32 / 25.0% | -75.0pp |
| `100_200km` | 4 / 100.0% | 0 / 0.0% | -100.0pp |
| `gt_200km` | 0 / 0.0% | 0 / 0.0% | +0.0pp |

### Distance-Site Buckets

| Distance | Site | Validation P+/P | Validation Band | Test P+/P | Delta |
| --- | --- | ---: | --- | ---: | ---: |
| `000_030km` | `tohoku` | 10 / 80.0% | `insufficient` | 0 / 0.0% | -80.0pp |
| `030_060km` | `kanto_chubu` | 3 / 100.0% | `insufficient` | 0 / 0.0% | -100.0pp |
| `030_060km` | `tohoku` | 4 / 100.0% | `insufficient` | 8 / 25.0% | -75.0pp |
| `060_100km` | `kanto_chubu` | 5 / 100.0% | `insufficient` | 0 / 0.0% | -100.0pp |
| `060_100km` | `tohoku` | 2 / 100.0% | `insufficient` | 32 / 25.0% | -75.0pp |
| `100_200km` | `tohoku` | 4 / 100.0% | `insufficient` | 0 / 0.0% | -100.0pp |

### Band Transfer

| Band | Validation Buckets | Validation P+/P | Test P+/P | Delta |
| --- | ---: | ---: | ---: | ---: |
| `high` | 0 | 0 / 0.0% | 0 / 0.0% | +0.0pp |
| `medium` | 0 | 0 / 0.0% | 0 / 0.0% | +0.0pp |
| `low` | 0 | 0 / 0.0% | 0 / 0.0% | +0.0pp |
| `insufficient` | 6 | 28 / 92.9% | 40 / 25.0% | -67.9pp |

## Decision

- Diagnostic-only. This report checks whether finer offshore-distance/site geography transfers inside the `tohoku` hotspot.

