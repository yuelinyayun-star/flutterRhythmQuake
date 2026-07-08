# PLUM Specificity Frozen Diagnostic

- Status: `pass`
- Method: `PLUM r30/d0.50 frozen specificity diagnostic`
- Frozen test evaluated: `true`
- Production ready: `false`
- Production UI connected: `false`
- Diagnostic only: `true`
- Parameters tuned: `false`
- Raw predicted intensity mutated: `false`

## Coverage

| Split | Variants | Station forecasts |
| --- | ---: | ---: |
| validation | 2688 | 185694 |
| test | 2757 | 179844 |

## Method

- This report isolates `PLUM r30/d0.50` specificity on validation and frozen test. It does not tune radius/damping, suppress predictions, or connect to UI/wording/notifications.
- Buckets split PLUM station forecasts by estimated-source region and distance, mask rate, PLUM evidence count, nearest evidence distance, strongest evidence intensity, and prediction margin above threshold.
- `plumOnlyFalsePositive` counts negative stations where PLUM crosses the threshold while JMA-style stays below it, matching the raw source diagnostic trigger-source decomposition.

## `shindo4`

### Overall

| Split | TP | FP | FN | TN | Precision | Recall | Specificity | FPR | PLUM-only FP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| validation | 3314 | 1443 | 1963 | 178974 | 69.7% | 62.8% | 99.2% | 0.8% | 940 |
| test | 2268 | 3005 | 1905 | 172666 | 43.0% | 54.3% | 98.3% | 1.7% | 2886 |

### Delta (test - validation)

| Metric | Delta |
| --- | ---: |
| Precision | -26.7pp |
| Specificity | -0.9pp |
| FP count | 1562 |

### Region Buckets

| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Specificity | PLUM-only FP |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `hokkaido` | validation | 8375 | 0 | 2 | 12 | 0.0% | 0.0% | 100.0% | 2 |
| `hokkaido` | test | 7954 | 8 | 9 | 28 | 47.1% | 22.2% | 99.9% | 8 |
| `tohoku` | validation | 69909 | 2384 | 887 | 1445 | 72.9% | 62.3% | 98.7% | 412 |
| `tohoku` | test | 60373 | 1757 | 2565 | 1254 | 40.7% | 58.4% | 95.5% | 2496 |
| `kanto_chubu` | validation | 84634 | 894 | 480 | 318 | 65.1% | 73.8% | 99.4% | 456 |
| `kanto_chubu` | test | 88879 | 98 | 270 | 305 | 26.6% | 24.3% | 99.7% | 267 |
| `west_south` | validation | 22776 | 36 | 74 | 188 | 32.7% | 16.1% | 99.7% | 70 |
| `west_south` | test | 22638 | 405 | 161 | 318 | 71.6% | 56.0% | 99.3% | 115 |

### Estimated Source Distance Buckets

| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Specificity | PLUM-only FP |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `000_030km` | validation | 37220 | 884 | 400 | 269 | 68.8% | 76.7% | 98.9% | 274 |
| `000_030km` | test | 39832 | 341 | 333 | 296 | 50.6% | 53.5% | 99.2% | 284 |
| `030_060km` | validation | 43195 | 780 | 370 | 284 | 67.8% | 73.3% | 99.1% | 250 |
| `030_060km` | test | 45319 | 436 | 446 | 259 | 49.4% | 62.7% | 99.0% | 416 |
| `060_100km` | validation | 40160 | 578 | 159 | 323 | 78.4% | 64.2% | 99.6% | 80 |
| `060_100km` | test | 39718 | 474 | 560 | 238 | 45.8% | 66.6% | 98.6% | 537 |
| `100_200km` | validation | 39397 | 641 | 165 | 541 | 79.5% | 54.2% | 99.6% | 87 |
| `100_200km` | test | 37835 | 550 | 826 | 519 | 40.0% | 51.4% | 97.8% | 809 |
| `gt_200km` | validation | 25722 | 431 | 349 | 546 | 55.3% | 44.1% | 98.6% | 249 |
| `gt_200km` | test | 17140 | 467 | 840 | 593 | 35.7% | 44.1% | 94.8% | 840 |

### Mask Rate Buckets

| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Specificity | PLUM-only FP |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `20pct` | validation | 61898 | 1309 | 646 | 450 | 67.0% | 74.4% | 98.9% | 423 |
| `20pct` | test | 59948 | 969 | 1318 | 422 | 42.4% | 69.7% | 97.7% | 1281 |
| `50pct` | validation | 61898 | 1180 | 519 | 579 | 69.5% | 67.1% | 99.1% | 314 |
| `50pct` | test | 59948 | 842 | 1120 | 549 | 42.9% | 60.5% | 98.1% | 1079 |
| `80pct` | validation | 61898 | 825 | 278 | 934 | 74.8% | 46.9% | 99.5% | 203 |
| `80pct` | test | 59948 | 457 | 567 | 934 | 44.6% | 32.9% | 99.0% | 526 |

### Evidence Count Buckets

| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Specificity | PLUM-only FP |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `0` | validation | 9839 | 0 | 0 | 81 | 0.0% | 0.0% | 100.0% | 0 |
| `0` | test | 9455 | 0 | 0 | 87 | 0.0% | 0.0% | 100.0% | 0 |
| `1` | validation | 11672 | 35 | 5 | 83 | 87.5% | 29.7% | 100.0% | 1 |
| `1` | test | 11075 | 5 | 4 | 47 | 55.6% | 9.6% | 100.0% | 3 |
| `2_3` | validation | 25228 | 126 | 22 | 248 | 85.1% | 33.7% | 99.9% | 13 |
| `2_3` | test | 24120 | 38 | 34 | 136 | 52.8% | 21.8% | 99.9% | 33 |
| `4_7` | validation | 36352 | 323 | 93 | 402 | 77.6% | 44.6% | 99.7% | 55 |
| `4_7` | test | 34615 | 170 | 143 | 297 | 54.3% | 36.4% | 99.6% | 127 |
| `gte_8` | validation | 102603 | 2830 | 1323 | 1149 | 68.1% | 71.1% | 98.7% | 871 |
| `gte_8` | test | 100579 | 2055 | 2824 | 1338 | 42.1% | 60.6% | 97.1% | 2723 |

### Nearest Evidence Distance Buckets

| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Specificity | PLUM-only FP |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `no_evidence` | validation | 9839 | 0 | 0 | 81 | 0.0% | 0.0% | 100.0% | 0 |
| `no_evidence` | test | 9455 | 0 | 0 | 87 | 0.0% | 0.0% | 100.0% | 0 |
| `000_010km` | validation | 119298 | 2852 | 1314 | 1118 | 68.5% | 71.8% | 98.9% | 874 |
| `000_010km` | test | 115468 | 1904 | 2573 | 1086 | 42.5% | 63.7% | 97.7% | 2474 |
| `010_020km` | validation | 42966 | 416 | 123 | 552 | 77.2% | 43.0% | 99.7% | 66 |
| `010_020km` | test | 41642 | 339 | 406 | 549 | 45.5% | 38.2% | 99.0% | 391 |
| `020_030km` | validation | 13591 | 46 | 6 | 212 | 88.5% | 17.8% | 100.0% | 0 |
| `020_030km` | test | 13279 | 25 | 26 | 183 | 49.0% | 12.0% | 99.8% | 21 |

### Strongest Evidence Intensity Buckets

| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Specificity | PLUM-only FP |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `no_evidence` | validation | 9839 | 0 | 0 | 81 | 0.0% | 0.0% | 100.0% | 0 |
| `no_evidence` | test | 9455 | 0 | 0 | 87 | 0.0% | 0.0% | 100.0% | 0 |
| `lt_1_5` | validation | 64899 | 0 | 0 | 26 | 0.0% | 0.0% | 100.0% | 0 |
| `lt_1_5` | test | 65231 | 0 | 0 | 23 | 0.0% | 0.0% | 100.0% | 0 |
| `1_5_2_5` | validation | 71080 | 0 | 0 | 41 | 0.0% | 0.0% | 100.0% | 0 |
| `1_5_2_5` | test | 66706 | 0 | 0 | 64 | 0.0% | 0.0% | 100.0% | 0 |
| `2_5_3_5` | validation | 29104 | 0 | 0 | 537 | 0.0% | 0.0% | 100.0% | 0 |
| `2_5_3_5` | test | 26435 | 0 | 0 | 466 | 0.0% | 0.0% | 100.0% | 0 |
| `gte_3_5` | validation | 10772 | 3314 | 1443 | 1278 | 69.7% | 72.2% | 76.7% | 940 |
| `gte_3_5` | test | 12017 | 2268 | 3005 | 1265 | 43.0% | 64.2% | 64.6% | 2886 |

### Prediction Margin Buckets

| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Specificity | PLUM-only FP |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `negative` | validation | 180937 | 0 | 0 | 1963 | 0.0% | 0.0% | 100.0% | 0 |
| `negative` | test | 174571 | 0 | 0 | 1905 | 0.0% | 0.0% | 100.0% | 0 |
| `000_025` | validation | 1543 | 756 | 787 | 0 | 49.0% | 100.0% | 0.0% | 610 |
| `000_025` | test | 1774 | 647 | 1127 | 0 | 36.5% | 100.0% | 0.0% | 1099 |
| `025_050` | validation | 1074 | 753 | 321 | 0 | 70.1% | 100.0% | 0.0% | 212 |
| `025_050` | test | 1090 | 488 | 602 | 0 | 44.8% | 100.0% | 0.0% | 578 |
| `050_100` | validation | 1374 | 1131 | 243 | 0 | 82.3% | 100.0% | 0.0% | 109 |
| `050_100` | test | 1166 | 553 | 613 | 0 | 47.4% | 100.0% | 0.0% | 601 |
| `gte_100` | validation | 766 | 674 | 92 | 0 | 88.0% | 100.0% | 0.0% | 9 |
| `gte_100` | test | 1243 | 580 | 663 | 0 | 46.7% | 100.0% | 0.0% | 608 |

## `shindo5-`

### Overall

| Split | TP | FP | FN | TN | Precision | Recall | Specificity | FPR | PLUM-only FP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| validation | 445 | 321 | 533 | 184395 | 58.1% | 45.5% | 99.8% | 0.2% | 311 |
| test | 330 | 913 | 537 | 178064 | 26.5% | 38.1% | 99.5% | 0.5% | 913 |

### Delta (test - validation)

| Metric | Delta |
| --- | ---: |
| Precision | -31.5pp |
| Specificity | -0.3pp |
| FP count | 592 |

### Region Buckets

| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Specificity | PLUM-only FP |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `hokkaido` | validation | 8375 | 0 | 0 | 0 | 0.0% | 0.0% | 100.0% | 0 |
| `hokkaido` | test | 7954 | 0 | 0 | 6 | 0.0% | 0.0% | 100.0% | 0 |
| `tohoku` | validation | 69909 | 408 | 151 | 456 | 73.0% | 47.2% | 99.8% | 141 |
| `tohoku` | test | 60373 | 289 | 863 | 440 | 25.1% | 39.6% | 98.6% | 863 |
| `kanto_chubu` | validation | 84634 | 37 | 168 | 68 | 18.0% | 35.2% | 99.8% | 168 |
| `kanto_chubu` | test | 88879 | 4 | 21 | 23 | 16.0% | 14.8% | 100.0% | 21 |
| `west_south` | validation | 22776 | 0 | 2 | 9 | 0.0% | 0.0% | 100.0% | 2 |
| `west_south` | test | 22638 | 37 | 29 | 68 | 56.1% | 35.2% | 99.9% | 29 |

### Estimated Source Distance Buckets

| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Specificity | PLUM-only FP |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `000_030km` | validation | 37220 | 146 | 176 | 136 | 45.3% | 51.8% | 99.5% | 168 |
| `000_030km` | test | 39832 | 63 | 167 | 59 | 27.4% | 51.6% | 99.6% | 167 |
| `030_060km` | validation | 43195 | 115 | 97 | 159 | 54.2% | 42.0% | 99.8% | 95 |
| `030_060km` | test | 45319 | 117 | 282 | 122 | 29.3% | 49.0% | 99.4% | 282 |
| `060_100km` | validation | 40160 | 147 | 32 | 139 | 82.1% | 51.4% | 99.9% | 32 |
| `060_100km` | test | 39718 | 105 | 330 | 119 | 24.1% | 46.9% | 99.2% | 330 |
| `100_200km` | validation | 39397 | 37 | 16 | 91 | 69.8% | 28.9% | 100.0% | 16 |
| `100_200km` | test | 37835 | 44 | 133 | 209 | 24.9% | 17.4% | 99.6% | 133 |
| `gt_200km` | validation | 25722 | 0 | 0 | 8 | 0.0% | 0.0% | 100.0% | 0 |
| `gt_200km` | test | 17140 | 1 | 1 | 28 | 50.0% | 3.4% | 100.0% | 1 |

### Mask Rate Buckets

| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Specificity | PLUM-only FP |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `20pct` | validation | 61898 | 207 | 153 | 119 | 57.5% | 63.5% | 99.8% | 150 |
| `20pct` | test | 59948 | 171 | 481 | 118 | 26.2% | 59.2% | 99.2% | 481 |
| `50pct` | validation | 61898 | 168 | 122 | 158 | 57.9% | 51.5% | 99.8% | 119 |
| `50pct` | test | 59948 | 125 | 353 | 164 | 26.2% | 43.3% | 99.4% | 353 |
| `80pct` | validation | 61898 | 70 | 46 | 256 | 60.3% | 21.5% | 99.9% | 42 |
| `80pct` | test | 59948 | 34 | 79 | 255 | 30.1% | 11.8% | 99.9% | 79 |

### Evidence Count Buckets

| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Specificity | PLUM-only FP |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `0` | validation | 9839 | 0 | 0 | 8 | 0.0% | 0.0% | 100.0% | 0 |
| `0` | test | 9455 | 0 | 0 | 28 | 0.0% | 0.0% | 100.0% | 0 |
| `1` | validation | 11672 | 2 | 1 | 22 | 66.7% | 8.3% | 100.0% | 1 |
| `1` | test | 11075 | 0 | 0 | 6 | 0.0% | 0.0% | 100.0% | 0 |
| `2_3` | validation | 25228 | 14 | 10 | 70 | 58.3% | 16.7% | 100.0% | 10 |
| `2_3` | test | 24120 | 0 | 5 | 27 | 0.0% | 0.0% | 100.0% | 5 |
| `4_7` | validation | 36352 | 25 | 12 | 86 | 67.6% | 22.5% | 100.0% | 8 |
| `4_7` | test | 34615 | 14 | 21 | 74 | 40.0% | 15.9% | 99.9% | 21 |
| `gte_8` | validation | 102603 | 404 | 298 | 347 | 57.5% | 53.8% | 99.7% | 292 |
| `gte_8` | test | 100579 | 316 | 887 | 402 | 26.3% | 44.0% | 99.1% | 887 |

### Nearest Evidence Distance Buckets

| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Specificity | PLUM-only FP |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `no_evidence` | validation | 9839 | 0 | 0 | 8 | 0.0% | 0.0% | 100.0% | 0 |
| `no_evidence` | test | 9455 | 0 | 0 | 28 | 0.0% | 0.0% | 100.0% | 0 |
| `000_010km` | validation | 119298 | 409 | 308 | 297 | 57.0% | 57.9% | 99.7% | 300 |
| `000_010km` | test | 115468 | 304 | 842 | 261 | 26.5% | 53.8% | 99.3% | 842 |
| `010_020km` | validation | 42966 | 36 | 13 | 173 | 73.5% | 17.2% | 100.0% | 11 |
| `010_020km` | test | 41642 | 25 | 68 | 179 | 26.9% | 12.3% | 99.8% | 68 |
| `020_030km` | validation | 13591 | 0 | 0 | 55 | 0.0% | 0.0% | 100.0% | 0 |
| `020_030km` | test | 13279 | 1 | 3 | 69 | 25.0% | 1.4% | 100.0% | 3 |

### Strongest Evidence Intensity Buckets

| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Specificity | PLUM-only FP |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `no_evidence` | validation | 9839 | 0 | 0 | 8 | 0.0% | 0.0% | 100.0% | 0 |
| `no_evidence` | test | 9455 | 0 | 0 | 28 | 0.0% | 0.0% | 100.0% | 0 |
| `lt_1_5` | validation | 64899 | 0 | 0 | 5 | 0.0% | 0.0% | 100.0% | 0 |
| `lt_1_5` | test | 65231 | 0 | 0 | 3 | 0.0% | 0.0% | 100.0% | 0 |
| `1_5_2_5` | validation | 71080 | 0 | 0 | 2 | 0.0% | 0.0% | 100.0% | 0 |
| `1_5_2_5` | test | 66706 | 0 | 0 | 18 | 0.0% | 0.0% | 100.0% | 0 |
| `2_5_3_5` | validation | 29104 | 0 | 0 | 7 | 0.0% | 0.0% | 100.0% | 0 |
| `2_5_3_5` | test | 26435 | 0 | 0 | 13 | 0.0% | 0.0% | 100.0% | 0 |
| `gte_3_5` | validation | 10772 | 445 | 321 | 511 | 58.1% | 46.5% | 96.7% | 311 |
| `gte_3_5` | test | 12017 | 330 | 913 | 475 | 26.5% | 41.0% | 91.9% | 913 |

### Prediction Margin Buckets

| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Specificity | PLUM-only FP |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `negative` | validation | 184928 | 0 | 0 | 533 | 0.0% | 0.0% | 100.0% | 0 |
| `negative` | test | 178601 | 0 | 0 | 537 | 0.0% | 0.0% | 100.0% | 0 |
| `000_025` | validation | 371 | 136 | 235 | 0 | 36.7% | 100.0% | 0.0% | 233 |
| `000_025` | test | 530 | 125 | 405 | 0 | 23.6% | 100.0% | 0.0% | 405 |
| `025_050` | validation | 200 | 140 | 60 | 0 | 70.0% | 100.0% | 0.0% | 58 |
| `025_050` | test | 315 | 98 | 217 | 0 | 31.1% | 100.0% | 0.0% | 217 |
| `050_100` | validation | 167 | 143 | 24 | 0 | 85.6% | 100.0% | 0.0% | 20 |
| `050_100` | test | 358 | 97 | 261 | 0 | 27.1% | 100.0% | 0.0% | 261 |
| `gte_100` | validation | 28 | 26 | 2 | 0 | 92.9% | 100.0% | 0.0% | 0 |
| `gte_100` | test | 40 | 10 | 30 | 0 | 25.0% | 100.0% | 0.0% | 30 |

## Decision

- Diagnostic-only. Results here identify PLUM r30/d0.50 specificity failure modes and do not authorize production intensity, UI, wording, notification, or parameter changes.

