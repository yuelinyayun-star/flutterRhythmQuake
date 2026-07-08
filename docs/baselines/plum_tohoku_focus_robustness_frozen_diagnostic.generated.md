# PLUM Tohoku Focus Robustness Frozen Diagnostic

- Status: `pass`
- Method: `PLUM Tohoku focus robustness frozen diagnostic`
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

### Joint Buckets

| branchAgreement | robustnessScore | Validation P+/P | Validation Band | Test P+/P | Delta |
| --- | --- | ---: | --- | ---: | ---: |
| `agree_2` | `score_6` | 2 / 100.0% | `insufficient` | 839 / 43.1% | -56.9pp |
| `agree_3` | `score_6` | 35 / 94.3% | `high` | 16 / 50.0% | -44.3pp |
| `agree_3` | `score_7` | 420 / 84.3% | `high` | 60 / 46.7% | -37.6pp |

### Band Transfer

| Band | Validation Buckets | Validation P+/P | Test P+/P | Delta |
| --- | ---: | ---: | ---: | ---: |
| `high` | 2 | 455 / 85.1% | 76 / 47.4% | -37.7pp |
| `medium` | 0 | 0 / 0.0% | 0 / 0.0% | +0.0pp |
| `low` | 0 | 0 / 0.0% | 0 / 0.0% | +0.0pp |
| `insufficient` | 1 | 2 / 100.0% | 839 / 43.1% | -56.9pp |

## `shindo5-`

### Focus Baseline

| Split | Focus samples | TP | FP | Precision |
| --- | ---: | ---: | ---: | ---: |
| validation | 28 | 26 | 2 | 92.9% |
| test | 40 | 10 | 30 | 25.0% |

### Joint Buckets

| branchAgreement | robustnessScore | Validation P+/P | Validation Band | Test P+/P | Delta |
| --- | --- | ---: | --- | ---: | ---: |
| `agree_2` | `score_6` | 21 / 100.0% | `high` | 40 / 25.0% | -75.0pp |
| `agree_3` | `score_7` | 7 / 71.4% | `insufficient` | 0 / 0.0% | -71.4pp |

### Band Transfer

| Band | Validation Buckets | Validation P+/P | Test P+/P | Delta |
| --- | ---: | ---: | ---: | ---: |
| `high` | 1 | 21 / 100.0% | 40 / 25.0% | -75.0pp |
| `medium` | 0 | 0 / 0.0% | 0 / 0.0% | +0.0pp |
| `low` | 0 | 0 / 0.0% | 0 / 0.0% | +0.0pp |
| `insufficient` | 1 | 7 / 71.4% | 0 / 0.0% | -71.4pp |

## Decision

- Diagnostic-only. This report checks whether the existing production-available robustness table transfers inside the `tohoku` focus hotspot before any calibration or wording decision is made.

