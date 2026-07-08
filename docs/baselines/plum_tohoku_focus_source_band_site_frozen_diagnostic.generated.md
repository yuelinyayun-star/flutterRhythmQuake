# PLUM Tohoku Focus Source-Band/Site Frozen Diagnostic

- Status: `pass`
- Method: `PLUM Tohoku focus source-band/site frozen diagnostic`
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

### Source-Band/Site Buckets

| Source Band | Site | Validation P+/P | Validation Band | Test P+/P | Delta |
| --- | --- | ---: | --- | ---: | ---: |
| `mid_tohoku` | `tohoku` | 22 / 100.0% | `high` | 0 / 0.0% | -100.0pp |
| `south_tohoku` | `kanto_chubu` | 89 / 92.1% | `high` | 268 / 42.9% | -49.2pp |
| `south_tohoku` | `tohoku` | 346 / 82.4% | `high` | 783 / 43.8% | -38.6pp |

### Band Transfer

| Band | Validation Buckets | Validation P+/P | Test P+/P | Delta |
| --- | ---: | ---: | ---: | ---: |
| `high` | 3 | 457 / 85.1% | 1051 / 43.6% | -41.5pp |
| `medium` | 0 | 0 / 0.0% | 0 / 0.0% | +0.0pp |
| `low` | 0 | 0 / 0.0% | 0 / 0.0% | +0.0pp |
| `insufficient` | 0 | 0 / 0.0% | 0 / 0.0% | +0.0pp |

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

### Source-Band/Site Buckets

| Source Band | Site | Validation P+/P | Validation Band | Test P+/P | Delta |
| --- | --- | ---: | --- | ---: | ---: |
| `south_tohoku` | `kanto_chubu` | 8 / 100.0% | `insufficient` | 0 / 0.0% | -100.0pp |
| `south_tohoku` | `tohoku` | 20 / 90.0% | `high` | 40 / 25.0% | -65.0pp |

### Band Transfer

| Band | Validation Buckets | Validation P+/P | Test P+/P | Delta |
| --- | ---: | ---: | ---: | ---: |
| `high` | 1 | 20 / 90.0% | 40 / 25.0% | -65.0pp |
| `medium` | 0 | 0 / 0.0% | 0 / 0.0% | +0.0pp |
| `low` | 0 | 0 / 0.0% | 0 / 0.0% | +0.0pp |
| `insufficient` | 1 | 8 / 100.0% | 0 / 0.0% | -100.0pp |

## Decision

- Diagnostic-only. This report checks whether finer Tohoku source sub-bands transfer inside the hotspot before adding new calibration logic.

