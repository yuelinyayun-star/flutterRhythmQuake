# Raw Intensity Frozen Source Diagnostic

- Status: `pass`
- Splits: `[validation, test]`
- Method: `max_jma_style_plum_like_r30_d0_50`
- Frozen test evaluated (diagnostic only): `true`
- Production ready: `false`
- Production UI connected: `false`
- Diagnostic only: `true`
- Parameters tuned: `false`
- Raw predicted intensity mutated: `false`

## Coverage

- Validation station forecasts: `185694`
- Test station forecasts: `179844`
- Skipped missing-magnitude events: `0`
- Skipped no-source-estimate variants: `0`

## Method

- This is a non-suppressive diagnostic: it does not modify raw predicted intensity, does not connect to UI/wording, and does not tune any parameter.
- It reuses `SyntheticRevealDatasetBuilder` to build validation and test synthetic reveal datasets, and reuses `StaticIntensityLocator`, `JmaStyleIntensityPredictor`, `PlumLikeIntensityPredictor(r=30km, d=0.50/km)` exactly as the frozen evaluation tool does.
- baseline = `max(JMA-style, PLUM r30/d0.50)`. Region bucket uses estimated-source latitude (production-available); distance bucket uses estimated-source → station haversine distance.
- FP trigger source decomposes each baseline FP into `jma_only`, `plum_only`, or `both` based on which component crossed the threshold.
- One-shot compliance: this diagnostic does not touch the confidence band wording layer, does not tune parameters, and does not re-run the confidence band frozen evaluation. It only decomposes raw intensity performance on the frozen test split.

## `shindo4`

### Three-Component P/R/F1 (validation vs test)

| Component | Split | TP | FP | FN | TN | Precision | Recall | F1 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `jmaStyle` | validation | 2693 | 2075 | 2584 | 178342 | 56.5% | 51.0% | 53.6% |
| `plumR30D050` | validation | 3314 | 1443 | 1963 | 178974 | 69.7% | 62.8% | 66.1% |
| `baselineMax` | validation | 3824 | 3015 | 1453 | 177402 | 55.9% | 72.5% | 63.1% |
| `jmaStyle` | test | 389 | 1013 | 3784 | 174658 | 27.7% | 9.3% | 14.0% |
| `plumR30D050` | test | 2268 | 3005 | 1905 | 172666 | 43.0% | 54.3% | 48.0% |
| `baselineMax` | test | 2389 | 3899 | 1784 | 171772 | 38.0% | 57.2% | 45.7% |

### Precision Delta (test − validation)

| Component | Validation P | Test P | Delta |
| --- | ---: | ---: | ---: |
| `jmaStyle` | 56.5% | 27.7% | -28.7% **(largest drop)** |
| `plumR30D050` | 69.7% | 43.0% | -26.7% |
| `baselineMax` | 55.9% | 38.0% | -17.9% |

### Region Buckets (precision by estimated-source latitude)

| Region | Split | jmaStyle P | plumR30D050 P | baselineMax P |
| --- | --- | ---: | ---: | ---: |
| `hokkaido` | validation | 2.2% | 0.0% | 2.1% |
| `hokkaido` | test | 40.0% | 47.1% | 46.2% |
| `tohoku` | validation | 59.3% | 72.9% | 58.6% |
| `tohoku` | test | 47.4% | 40.7% | 40.7% |
| `kanto_chubu` | validation | 49.0% | 65.1% | 53.5% |
| `kanto_chubu` | test | 3.6% | 26.6% | 11.8% |
| `west_south` | validation | 10.0% | 32.7% | 21.8% |
| `west_south` | test | 41.2% | 71.6% | 48.7% |

### Distance Buckets (precision by estimated-source → station)

| Distance | Split | jmaStyle P | plumR30D050 P | baselineMax P |
| --- | --- | ---: | ---: | ---: |
| `000_030km` | validation | 66.5% | 68.8% | 61.9% |
| `000_030km` | test | 27.6% | 50.6% | 39.3% |
| `030_060km` | validation | 58.9% | 67.8% | 58.5% |
| `030_060km` | test | 32.0% | 49.4% | 40.9% |
| `060_100km` | validation | 63.0% | 78.4% | 61.5% |
| `060_100km` | test | 22.1% | 45.8% | 36.8% |
| `100_200km` | validation | 46.0% | 79.5% | 49.4% |
| `100_200km` | test | 33.3% | 40.0% | 38.2% |
| `gt_200km` | validation | 55.4% | 55.3% | 49.4% |
| `gt_200km` | test | 0.0% | 35.7% | 35.7% |

### FP Trigger Source (baseline FP decomposition)

| Split | jma_only | plum_only | both |
| --- | ---: | ---: | ---: |
| validation | 1572 | 940 | 503 |
| test | 894 | 2886 | 119 |

## `shindo5-`

### Three-Component P/R/F1 (validation vs test)

| Component | Split | TP | FP | FN | TN | Precision | Recall | F1 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `jmaStyle` | validation | 79 | 11 | 899 | 184705 | 87.8% | 8.1% | 14.8% |
| `plumR30D050` | validation | 445 | 321 | 533 | 184395 | 58.1% | 45.5% | 51.0% |
| `baselineMax` | validation | 459 | 322 | 519 | 184394 | 58.8% | 46.9% | 52.2% |
| `jmaStyle` | test | 0 | 2 | 867 | 178975 | 0.0% | 0.0% | 0.0% |
| `plumR30D050` | test | 330 | 913 | 537 | 178064 | 26.5% | 38.1% | 31.3% |
| `baselineMax` | test | 330 | 915 | 537 | 178062 | 26.5% | 38.1% | 31.3% |

### Precision Delta (test − validation)

| Component | Validation P | Test P | Delta |
| --- | ---: | ---: | ---: |
| `jmaStyle` | 87.8% | 0.0% | -87.8% **(largest drop)** |
| `plumR30D050` | 58.1% | 26.5% | -31.5% |
| `baselineMax` | 58.8% | 26.5% | -32.3% |

### Region Buckets (precision by estimated-source latitude)

| Region | Split | jmaStyle P | plumR30D050 P | baselineMax P |
| --- | --- | ---: | ---: | ---: |
| `hokkaido` | validation | 0.0% | 0.0% | 0.0% |
| `hokkaido` | test | 0.0% | 0.0% | 0.0% |
| `tohoku` | validation | 88.8% | 73.0% | 73.6% |
| `tohoku` | test | 0.0% | 25.1% | 25.1% |
| `kanto_chubu` | validation | 0.0% | 18.0% | 18.0% |
| `kanto_chubu` | test | 0.0% | 16.0% | 16.0% |
| `west_south` | validation | 0.0% | 0.0% | 0.0% |
| `west_south` | test | 0.0% | 56.1% | 54.4% |

### Distance Buckets (precision by estimated-source → station)

| Distance | Split | jmaStyle P | plumR30D050 P | baselineMax P |
| --- | --- | ---: | ---: | ---: |
| `000_030km` | validation | 76.9% | 45.3% | 45.4% |
| `000_030km` | test | 0.0% | 27.4% | 27.4% |
| `030_060km` | validation | 90.0% | 54.2% | 55.3% |
| `030_060km` | test | 0.0% | 29.3% | 29.3% |
| `060_100km` | validation | 100.0% | 82.1% | 82.9% |
| `060_100km` | test | 0.0% | 24.1% | 24.0% |
| `100_200km` | validation | 0.0% | 69.8% | 69.8% |
| `100_200km` | test | 0.0% | 24.9% | 24.9% |
| `gt_200km` | validation | 0.0% | 0.0% | 0.0% |
| `gt_200km` | test | 0.0% | 50.0% | 50.0% |

### FP Trigger Source (baseline FP decomposition)

| Split | jma_only | plum_only | both |
| --- | ---: | ---: | ---: |
| validation | 1 | 311 | 10 |
| test | 2 | 913 | 0 |

## Decision

- Non-suppressive: this diagnostic does not modify raw predicted intensity, does not connect to UI/notifications/wording, and does not tune any parameter.
- One-shot compliance: it does not re-run the confidence band wording layer frozen evaluation and therefore does not spend the one-shot budget for that layer.
- This is a prerequisite diagnostic for improving raw intensity frozen migration; results here do not authorize production UI.

