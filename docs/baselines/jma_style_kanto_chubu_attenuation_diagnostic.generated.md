# JMA-Style Kanto/Chubu Attenuation Diagnostic

- Status: `pass`
- Target region: `kanto_chubu`
- Frozen test evaluated: `true`
- Production ready: `false`
- Production UI connected: `false`
- Diagnostic only: `true`
- Parameters tuned: `false`
- Raw predicted intensity mutated: `false`

## Coverage

| Split | Variants | Station forecasts |
| --- | ---: | ---: |
| validation | 1067 | 84634 |
| test | 978 | 88879 |

## Method

- This is a diagnostic-only drilldown for the JMA-style attenuation branch. It does not tune parameters, does not modify raw predicted intensity, and does not connect to UI/notifications/wording.
- The target sample is synthetic-reveal variants whose estimated-source latitude falls in `kanto_chubu` (34.5 <= lat < 37.5).
- `estimatedSourceJma` uses the same estimated source produced by `StaticIntensityLocator`; `oracleSourceJma` uses the catalog source with the same JMA-style PGV attenuation formula. Bucket tables below use `estimatedSourceJma`.

## `shindo4`

### Estimated vs Oracle Source

| Split | Branch | TP | FP | FN | Precision | Recall | F1 | Mean error | MAE |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| validation | `estimatedSourceJma` | 311 | 324 | 901 | 49.0% | 25.7% | 33.7% | 0.37 | 0.63 |
| validation | `oracleSourceJma` | 144 | 12 | 1068 | 92.3% | 11.9% | 21.1% | 0.19 | 0.50 |
| test | `estimatedSourceJma` | 19 | 508 | 384 | 3.6% | 4.7% | 4.1% | 0.34 | 0.57 |
| test | `oracleSourceJma` | 12 | 30 | 391 | 28.6% | 3.0% | 5.4% | 0.22 | 0.54 |

### Precision Delta (test - validation)

| Branch | Delta |
| --- | ---: |
| `estimatedSourceJma` | -45.4pp |
| `oracleSourceJma` | -63.7pp |

### Source Error Buckets

| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Mean error | MAE |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `000_025km` | validation | 37708 | 0 | 0 | 208 | 0.0% | 0.0% | 0.17 | 0.48 |
| `000_025km` | test | 36972 | 13 | 2 | 152 | 86.7% | 7.9% | 0.27 | 0.51 |
| `025_050km` | validation | 19676 | 311 | 28 | 677 | 91.7% | 31.5% | 0.20 | 0.48 |
| `025_050km` | test | 26656 | 0 | 1 | 142 | 0.0% | 0.0% | 0.20 | 0.48 |
| `050_100km` | validation | 11948 | 0 | 0 | 16 | 0.0% | 0.0% | 0.40 | 0.61 |
| `050_100km` | test | 19079 | 3 | 2 | 84 | 60.0% | 3.4% | 0.46 | 0.62 |
| `100_200km` | validation | 9307 | 0 | 0 | 0 | 0.0% | 0.0% | 0.82 | 0.95 |
| `100_200km` | test | 1048 | 0 | 1 | 0 | 0.0% | 0.0% | 0.70 | 0.76 |
| `gt_200km` | validation | 5995 | 0 | 296 | 0 | 0.0% | 0.0% | 1.51 | 1.55 |
| `gt_200km` | test | 5124 | 3 | 502 | 6 | 0.6% | 33.3% | 0.99 | 1.25 |

### Estimated Source Distance Buckets

| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Mean error | MAE |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `000_030km` | validation | 19875 | 234 | 83 | 369 | 73.8% | 38.8% | 0.13 | 0.55 |
| `000_030km` | test | 22272 | 13 | 43 | 206 | 23.2% | 5.9% | 0.18 | 0.54 |
| `030_060km` | validation | 24239 | 77 | 153 | 371 | 33.5% | 17.2% | 0.31 | 0.59 |
| `030_060km` | test | 26081 | 4 | 145 | 140 | 2.7% | 2.8% | 0.29 | 0.54 |
| `060_100km` | validation | 21525 | 0 | 77 | 155 | 0.0% | 0.0% | 0.49 | 0.67 |
| `060_100km` | test | 20935 | 2 | 287 | 29 | 0.7% | 6.5% | 0.39 | 0.58 |
| `100_200km` | validation | 16688 | 0 | 11 | 6 | 0.0% | 0.0% | 0.59 | 0.72 |
| `100_200km` | test | 17645 | 0 | 33 | 9 | 0.0% | 0.0% | 0.50 | 0.63 |
| `gt_200km` | validation | 2307 | 0 | 0 | 0 | 0.0% | 0.0% | 0.46 | 0.67 |
| `gt_200km` | test | 1946 | 0 | 0 | 0 | 0.0% | 0.0% | 0.67 | 0.81 |

### Estimated Depth Buckets

| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Mean error | MAE |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `000_020km` | validation | 9703 | 0 | 0 | 16 | 0.0% | 0.0% | 0.38 | 0.58 |
| `000_020km` | test | 15781 | 13 | 3 | 73 | 81.3% | 15.1% | 0.36 | 0.55 |
| `020_050km` | validation | 0 | 0 | 0 | 0 | 0.0% | 0.0% | 0.00 | 0.00 |
| `020_050km` | test | 0 | 0 | 0 | 0 | 0.0% | 0.0% | 0.00 | 0.00 |
| `050_100km` | validation | 25703 | 302 | 28 | 456 | 91.5% | 39.8% | 0.19 | 0.47 |
| `050_100km` | test | 31213 | 3 | 3 | 113 | 50.0% | 2.6% | 0.29 | 0.55 |
| `gt_100km` | validation | 49228 | 9 | 296 | 429 | 3.0% | 2.1% | 0.47 | 0.72 |
| `gt_100km` | test | 41885 | 3 | 502 | 198 | 0.6% | 1.5% | 0.36 | 0.60 |

### Magnitude Buckets

| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Mean error | MAE |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `lt_m3` | validation | 651 | 0 | 0 | 0 | 0.0% | 0.0% | -0.40 | 0.65 |
| `lt_m3` | test | 354 | 0 | 0 | 0 | 0.0% | 0.0% | 0.11 | 0.43 |
| `m3_m4` | validation | 13511 | 0 | 0 | 5 | 0.0% | 0.0% | 0.08 | 0.43 |
| `m3_m4` | test | 16504 | 0 | 0 | 0 | 0.0% | 0.0% | 0.10 | 0.47 |
| `m4_m5` | validation | 42559 | 0 | 0 | 49 | 0.0% | 0.0% | 0.24 | 0.50 |
| `m4_m5` | test | 53176 | 0 | 0 | 164 | 0.0% | 0.0% | 0.28 | 0.51 |
| `gte_m5` | validation | 27913 | 311 | 324 | 847 | 49.0% | 26.9% | 0.74 | 0.92 |
| `gte_m5` | test | 18845 | 19 | 508 | 220 | 3.6% | 7.9% | 0.71 | 0.84 |

### Amplification Buckets

| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Mean error | MAE |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `default_arv` | validation | 27 | 0 | 0 | 0 | 0.0% | 0.0% | 0.53 | 0.63 |
| `default_arv` | test | 3 | 0 | 0 | 0 | 0.0% | 0.0% | 0.36 | 0.36 |
| `lt_0_8` | validation | 7238 | 0 | 0 | 27 | 0.0% | 0.0% | -0.10 | 0.53 |
| `lt_0_8` | test | 6317 | 0 | 0 | 46 | 0.0% | 0.0% | -0.13 | 0.52 |
| `0_8_1_2` | validation | 27189 | 0 | 0 | 181 | 0.0% | 0.0% | 0.22 | 0.53 |
| `0_8_1_2` | test | 27872 | 3 | 0 | 151 | 100.0% | 1.9% | 0.18 | 0.49 |
| `gte_1_2` | validation | 50180 | 311 | 324 | 693 | 49.0% | 31.0% | 0.52 | 0.69 |
| `gte_1_2` | test | 54687 | 16 | 508 | 187 | 3.1% | 7.9% | 0.47 | 0.62 |

## `shindo5-`

### Estimated vs Oracle Source

| Split | Branch | TP | FP | FN | Precision | Recall | F1 | Mean error | MAE |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| validation | `estimatedSourceJma` | 0 | 0 | 105 | 0.0% | 0.0% | 0.0% | 0.37 | 0.63 |
| validation | `oracleSourceJma` | 0 | 0 | 105 | 0.0% | 0.0% | 0.0% | 0.19 | 0.50 |
| test | `estimatedSourceJma` | 0 | 0 | 27 | 0.0% | 0.0% | 0.0% | 0.34 | 0.57 |
| test | `oracleSourceJma` | 0 | 0 | 27 | 0.0% | 0.0% | 0.0% | 0.22 | 0.54 |

### Precision Delta (test - validation)

| Branch | Delta |
| --- | ---: |
| `estimatedSourceJma` | +0.0pp |
| `oracleSourceJma` | +0.0pp |

### Source Error Buckets

| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Mean error | MAE |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `000_025km` | validation | 37708 | 0 | 0 | 2 | 0.0% | 0.0% | 0.17 | 0.48 |
| `000_025km` | test | 36972 | 0 | 0 | 9 | 0.0% | 0.0% | 0.27 | 0.51 |
| `025_050km` | validation | 19676 | 0 | 0 | 100 | 0.0% | 0.0% | 0.20 | 0.48 |
| `025_050km` | test | 26656 | 0 | 0 | 8 | 0.0% | 0.0% | 0.20 | 0.48 |
| `050_100km` | validation | 11948 | 0 | 0 | 3 | 0.0% | 0.0% | 0.40 | 0.61 |
| `050_100km` | test | 19079 | 0 | 0 | 10 | 0.0% | 0.0% | 0.46 | 0.62 |
| `100_200km` | validation | 9307 | 0 | 0 | 0 | 0.0% | 0.0% | 0.82 | 0.95 |
| `100_200km` | test | 1048 | 0 | 0 | 0 | 0.0% | 0.0% | 0.70 | 0.76 |
| `gt_200km` | validation | 5995 | 0 | 0 | 0 | 0.0% | 0.0% | 1.51 | 1.55 |
| `gt_200km` | test | 5124 | 0 | 0 | 0 | 0.0% | 0.0% | 0.99 | 1.25 |

### Estimated Source Distance Buckets

| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Mean error | MAE |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `000_030km` | validation | 19875 | 0 | 0 | 68 | 0.0% | 0.0% | 0.13 | 0.55 |
| `000_030km` | test | 22272 | 0 | 0 | 14 | 0.0% | 0.0% | 0.18 | 0.54 |
| `030_060km` | validation | 24239 | 0 | 0 | 35 | 0.0% | 0.0% | 0.31 | 0.59 |
| `030_060km` | test | 26081 | 0 | 0 | 12 | 0.0% | 0.0% | 0.29 | 0.54 |
| `060_100km` | validation | 21525 | 0 | 0 | 2 | 0.0% | 0.0% | 0.49 | 0.67 |
| `060_100km` | test | 20935 | 0 | 0 | 1 | 0.0% | 0.0% | 0.39 | 0.58 |
| `100_200km` | validation | 16688 | 0 | 0 | 0 | 0.0% | 0.0% | 0.59 | 0.72 |
| `100_200km` | test | 17645 | 0 | 0 | 0 | 0.0% | 0.0% | 0.50 | 0.63 |
| `gt_200km` | validation | 2307 | 0 | 0 | 0 | 0.0% | 0.0% | 0.46 | 0.67 |
| `gt_200km` | test | 1946 | 0 | 0 | 0 | 0.0% | 0.0% | 0.67 | 0.81 |

### Estimated Depth Buckets

| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Mean error | MAE |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `000_020km` | validation | 9703 | 0 | 0 | 1 | 0.0% | 0.0% | 0.38 | 0.58 |
| `000_020km` | test | 15781 | 0 | 0 | 11 | 0.0% | 0.0% | 0.36 | 0.55 |
| `020_050km` | validation | 0 | 0 | 0 | 0 | 0.0% | 0.0% | 0.00 | 0.00 |
| `020_050km` | test | 0 | 0 | 0 | 0 | 0.0% | 0.0% | 0.00 | 0.00 |
| `050_100km` | validation | 25703 | 0 | 0 | 67 | 0.0% | 0.0% | 0.19 | 0.47 |
| `050_100km` | test | 31213 | 0 | 0 | 8 | 0.0% | 0.0% | 0.29 | 0.55 |
| `gt_100km` | validation | 49228 | 0 | 0 | 37 | 0.0% | 0.0% | 0.47 | 0.72 |
| `gt_100km` | test | 41885 | 0 | 0 | 8 | 0.0% | 0.0% | 0.36 | 0.60 |

### Magnitude Buckets

| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Mean error | MAE |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `lt_m3` | validation | 651 | 0 | 0 | 0 | 0.0% | 0.0% | -0.40 | 0.65 |
| `lt_m3` | test | 354 | 0 | 0 | 0 | 0.0% | 0.0% | 0.11 | 0.43 |
| `m3_m4` | validation | 13511 | 0 | 0 | 0 | 0.0% | 0.0% | 0.08 | 0.43 |
| `m3_m4` | test | 16504 | 0 | 0 | 0 | 0.0% | 0.0% | 0.10 | 0.47 |
| `m4_m5` | validation | 42559 | 0 | 0 | 3 | 0.0% | 0.0% | 0.24 | 0.50 |
| `m4_m5` | test | 53176 | 0 | 0 | 3 | 0.0% | 0.0% | 0.28 | 0.51 |
| `gte_m5` | validation | 27913 | 0 | 0 | 102 | 0.0% | 0.0% | 0.74 | 0.92 |
| `gte_m5` | test | 18845 | 0 | 0 | 24 | 0.0% | 0.0% | 0.71 | 0.84 |

### Amplification Buckets

| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Mean error | MAE |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `default_arv` | validation | 27 | 0 | 0 | 0 | 0.0% | 0.0% | 0.53 | 0.63 |
| `default_arv` | test | 3 | 0 | 0 | 0 | 0.0% | 0.0% | 0.36 | 0.36 |
| `lt_0_8` | validation | 7238 | 0 | 0 | 3 | 0.0% | 0.0% | -0.10 | 0.53 |
| `lt_0_8` | test | 6317 | 0 | 0 | 6 | 0.0% | 0.0% | -0.13 | 0.52 |
| `0_8_1_2` | validation | 27189 | 0 | 0 | 3 | 0.0% | 0.0% | 0.22 | 0.53 |
| `0_8_1_2` | test | 27872 | 0 | 0 | 6 | 0.0% | 0.0% | 0.18 | 0.49 |
| `gte_1_2` | validation | 50180 | 0 | 0 | 99 | 0.0% | 0.0% | 0.52 | 0.69 |
| `gte_1_2` | test | 54687 | 0 | 0 | 15 | 0.0% | 0.0% | 0.47 | 0.62 |

## Decision

- Diagnostic-only. This report identifies where JMA-style attenuation migration fails in `kanto_chubu`; it does not authorize production coordinate, intensity, UI, wording, or notification changes.

