# PLUM Tohoku Focus Source-Band Distance/Site Frozen Diagnostic

- Status: `pass`
- Method: `PLUM Tohoku focus source-band distance/site frozen diagnostic`
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

### Marginal Source-Band Precision

| Source Band | Validation P+/P | Test P+/P | Delta |
| --- | ---: | ---: | ---: |
| `south_tohoku` | 435 / 84.4% | 1051 / 43.6% | -40.8pp |
| `mid_tohoku` | 22 / 100.0% | 0 / 0.0% | -100.0pp |
| `north_tohoku` | 0 / 0.0% | 0 / 0.0% | +0.0pp |

### Source-Band Distance/Site Buckets

| Source Band | Distance | Site | Validation P+/P | Validation Band | Test P+/P | Delta |
| --- | --- | --- | ---: | --- | ---: | ---: |
| `mid_tohoku` | `000_030km` | `tohoku` | 20 / 100.0% | `high` | 0 / 0.0% | -100.0pp |
| `mid_tohoku` | `030_060km` | `tohoku` | 2 / 100.0% | `insufficient` | 0 / 0.0% | -100.0pp |
| `south_tohoku` | `000_030km` | `tohoku` | 132 / 70.5% | `medium` | 150 / 48.0% | -22.5pp |
| `south_tohoku` | `030_060km` | `kanto_chubu` | 25 / 76.0% | `high` | 4 / 50.0% | -26.0pp |
| `south_tohoku` | `030_060km` | `tohoku` | 84 / 79.8% | `high` | 317 / 45.4% | -34.3pp |
| `south_tohoku` | `060_100km` | `kanto_chubu` | 57 / 98.2% | `high` | 120 / 47.5% | -50.7pp |
| `south_tohoku` | `060_100km` | `tohoku` | 89 / 94.4% | `high` | 293 / 41.0% | -53.4pp |
| `south_tohoku` | `100_200km` | `kanto_chubu` | 7 / 100.0% | `insufficient` | 142 / 38.7% | -61.3pp |
| `south_tohoku` | `100_200km` | `tohoku` | 41 / 100.0% | `high` | 23 / 30.4% | -69.6pp |

### Band Transfer

| Band | Validation Buckets | Validation P+/P | Test P+/P | Delta |
| --- | ---: | ---: | ---: | ---: |
| `high` | 6 | 316 / 90.8% | 757 / 43.6% | -47.2pp |
| `medium` | 1 | 132 / 70.5% | 150 / 48.0% | -22.5pp |
| `low` | 0 | 0 / 0.0% | 0 / 0.0% | +0.0pp |
| `insufficient` | 2 | 9 / 100.0% | 142 / 38.7% | -61.3pp |

## `shindo5-`

### Focus Baseline

| Split | Focus samples | TP | FP | Precision |
| --- | ---: | ---: | ---: | ---: |
| validation | 28 | 26 | 2 | 92.9% |
| test | 40 | 10 | 30 | 25.0% |

### Marginal Source-Band Precision

| Source Band | Validation P+/P | Test P+/P | Delta |
| --- | ---: | ---: | ---: |
| `south_tohoku` | 28 / 92.9% | 40 / 25.0% | -67.9pp |
| `mid_tohoku` | 0 / 0.0% | 0 / 0.0% | +0.0pp |
| `north_tohoku` | 0 / 0.0% | 0 / 0.0% | +0.0pp |

### Source-Band Distance/Site Buckets

| Source Band | Distance | Site | Validation P+/P | Validation Band | Test P+/P | Delta |
| --- | --- | --- | ---: | --- | ---: | ---: |
| `south_tohoku` | `000_030km` | `tohoku` | 10 / 80.0% | `insufficient` | 0 / 0.0% | -80.0pp |
| `south_tohoku` | `030_060km` | `kanto_chubu` | 3 / 100.0% | `insufficient` | 0 / 0.0% | -100.0pp |
| `south_tohoku` | `030_060km` | `tohoku` | 4 / 100.0% | `insufficient` | 8 / 25.0% | -75.0pp |
| `south_tohoku` | `060_100km` | `kanto_chubu` | 5 / 100.0% | `insufficient` | 0 / 0.0% | -100.0pp |
| `south_tohoku` | `060_100km` | `tohoku` | 2 / 100.0% | `insufficient` | 32 / 25.0% | -75.0pp |
| `south_tohoku` | `100_200km` | `tohoku` | 4 / 100.0% | `insufficient` | 0 / 0.0% | -100.0pp |

### Band Transfer

| Band | Validation Buckets | Validation P+/P | Test P+/P | Delta |
| --- | ---: | ---: | ---: | ---: |
| `high` | 0 | 0 / 0.0% | 0 / 0.0% | +0.0pp |
| `medium` | 0 | 0 / 0.0% | 0 / 0.0% | +0.0pp |
| `low` | 0 | 0 / 0.0% | 0 / 0.0% | +0.0pp |
| `insufficient` | 6 | 28 / 92.9% | 40 / 25.0% | -67.9pp |

## Decision

- Diagnostic-only. This report checks whether combining Tohoku source sub-bands with offshore-distance/site geography transfers inside the `tohoku` hotspot before adding new calibration logic.

