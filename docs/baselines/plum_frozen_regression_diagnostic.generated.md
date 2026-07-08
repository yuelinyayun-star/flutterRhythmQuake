# PLUM Frozen Regression Diagnostic

- Status: `pass`
- Frozen test evaluated: `true`
- Production ready: `false`
- Method: `max_jma_style_plum_like_r30_d0_50`

## Overall Thresholds

| Threshold | Validation P/R/F1 | Test P/R/F1 | Delta P/R/F1 |
| --- | ---: | ---: | ---: |
| `shindo4` | 55.9% / 72.5% / 63.1% | 38.0% / 57.2% / 45.7% | -17.9% / -15.2% / -17.4% |
| `shindo5-` | 58.8% / 46.9% / 52.2% | 26.5% / 38.1% / 31.3% | -32.3% / -8.9% / -20.9% |

## Worst Shindo4 F1 Drops

| Group | Bucket | Test positives | Validation F1 | Test F1 | Delta F1 |
| --- | --- | ---: | ---: | ---: | ---: |
| `eventLatitudeBand` | `kanto_chubu` | 336 | 69.5% | 23.5% | -46.0% |
| `stationDistance` | `030_060km` | 372 | 71.2% | 45.6% | -25.6% |
| `maskRate` | `80pct` | 1391 | 59.4% | 37.2% | -22.2% |
| `stationDistance` | `060_100km` | 855 | 75.4% | 56.7% | -18.7% |
| `eventLatitudeBand` | `tohoku` | 3069 | 66.4% | 48.0% | -18.4% |
| `actualMaxClass` | `max_5plus` | 3774 | 68.8% | 50.6% | -18.1% |
| `stationDistance` | `100_200km` | 1347 | 69.6% | 51.6% | -18.1% |
| `overall` | `all` | 4173 | 63.1% | 45.7% | -17.4% |

## Bucket Comparisons

### Shindo4 F1 by Mask Rate

| Bucket | Validation | Test | Delta |
| --- | ---: | ---: | ---: |
| `20pct` | 64.9% | 49.9% | -15.0% |
| `50pct` | 64.5% | 47.7% | -16.9% |
| `80pct` | 59.4% | 37.2% | -22.2% |

### Shindo4 F1 by Station Distance

| Bucket | Validation | Test | Delta |
| --- | ---: | ---: | ---: |
| `000_030km` | 57.4% | 41.1% | -16.3% |
| `030_060km` | 71.2% | 45.6% | -25.6% |
| `060_100km` | 75.4% | 56.7% | -18.7% |
| `100_200km` | 69.6% | 51.6% | -18.1% |
| `gt_200km` | 45.9% | 33.6% | -12.3% |

### Shindo4 F1 by Actual Max Class

| Bucket | Validation | Test | Delta |
| --- | ---: | ---: | ---: |
| `max_3` | 0.0% | 0.0% | 0.0% |
| `max_4` | 26.5% | 13.5% | -13.0% |
| `max_5plus` | 68.8% | 50.6% | -18.1% |
| `max_le_2` | 0.0% | 0.0% | 0.0% |

## Decision

- Do not tune from this frozen report.
- Use the bucket failures to decide whether the model family or validation gates were insufficient.
- Production remains blocked.

