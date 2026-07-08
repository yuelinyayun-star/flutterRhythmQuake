# PLUM Evidence Robustness Diagnostic

- Status: `pass`
- Split: `validation`
- Frozen test evaluated: `false`
- Production ready: `false`
- Raw predicted intensity mutated: `false`
- Station forecasts: `185694`

## Method

- This report does not suppress, cap, replace, or hide predicted intensity.
- It stratifies baseline high-threshold predictions by evidence robustness features: mask rate, retained station count, PLUM evidence count, nearest evidence distance, and branch agreement.

## `shindo4`

- Baseline P/R/F1: `55.9% / 72.5% / 63.1%`

| Feature | Bucket | Pred+ | Precision | TP | FP |
| --- | --- | ---: | ---: | ---: | ---: |
| `maskRate` | `20pct` | 2592 | 54.4% | 1411 | 1181 |
| `maskRate` | `50pct` | 2387 | 56.1% | 1338 | 1049 |
| `maskRate` | `80pct` | 1860 | 57.8% | 1075 | 785 |
| `retainedCount` | `08_15` | 40 | 5.0% | 2 | 38 |
| `retainedCount` | `ge_16` | 6747 | 56.6% | 3821 | 2926 |
| `retainedCount` | `lt_8` | 52 | 1.9% | 1 | 51 |
| `plumEvidenceCount` | `0` | 66 | 39.4% | 26 | 40 |
| `plumEvidenceCount` | `1` | 110 | 53.6% | 59 | 51 |
| `plumEvidenceCount` | `2` | 207 | 55.1% | 114 | 93 |
| `plumEvidenceCount` | `ge_3` | 6456 | 56.1% | 3625 | 2831 |
| `nearestEvidenceDistance` | `000_010km` | 5531 | 56.3% | 3116 | 2415 |
| `nearestEvidenceDistance` | `010_020km` | 1028 | 54.2% | 557 | 471 |
| `nearestEvidenceDistance` | `020_030km` | 214 | 58.4% | 125 | 89 |
| `nearestEvidenceDistance` | `none` | 66 | 39.4% | 26 | 40 |
| `branchAgreement` | `agree_0` | 51 | 51.0% | 26 | 25 |
| `branchAgreement` | `agree_1` | 2971 | 29.9% | 888 | 2083 |
| `branchAgreement` | `agree_2` | 1670 | 67.2% | 1123 | 547 |
| `branchAgreement` | `agree_3` | 2147 | 83.2% | 1787 | 360 |
| `robustnessScore` | `score_1` | 15 | 13.3% | 2 | 13 |
| `robustnessScore` | `score_2` | 91 | 54.9% | 50 | 41 |
| `robustnessScore` | `score_3` | 188 | 50.0% | 94 | 94 |
| `robustnessScore` | `score_4` | 868 | 35.4% | 307 | 561 |
| `robustnessScore` | `score_5` | 2388 | 36.6% | 873 | 1515 |
| `robustnessScore` | `score_6` | 1456 | 67.6% | 984 | 472 |
| `robustnessScore` | `score_7` | 1833 | 82.6% | 1514 | 319 |

## `shindo5-`

- Baseline P/R/F1: `58.8% / 46.9% / 52.2%`

| Feature | Bucket | Pred+ | Precision | TP | FP |
| --- | --- | ---: | ---: | ---: | ---: |
| `maskRate` | `20pct` | 361 | 57.6% | 208 | 153 |
| `maskRate` | `50pct` | 292 | 58.2% | 170 | 122 |
| `maskRate` | `80pct` | 128 | 63.3% | 81 | 47 |
| `retainedCount` | `ge_16` | 780 | 58.8% | 459 | 321 |
| `retainedCount` | `lt_8` | 1 | 0.0% | 0 | 1 |
| `plumEvidenceCount` | `0` | 2 | 50.0% | 1 | 1 |
| `plumEvidenceCount` | `1` | 3 | 66.7% | 2 | 1 |
| `plumEvidenceCount` | `2` | 11 | 54.5% | 6 | 5 |
| `plumEvidenceCount` | `ge_3` | 765 | 58.8% | 450 | 315 |
| `nearestEvidenceDistance` | `000_010km` | 720 | 57.2% | 412 | 308 |
| `nearestEvidenceDistance` | `010_020km` | 57 | 77.2% | 44 | 13 |
| `nearestEvidenceDistance` | `020_030km` | 2 | 100.0% | 2 | 0 |
| `nearestEvidenceDistance` | `none` | 2 | 50.0% | 1 | 1 |
| `branchAgreement` | `agree_0` | 23 | 60.9% | 14 | 9 |
| `branchAgreement` | `agree_1` | 272 | 39.3% | 107 | 165 |
| `branchAgreement` | `agree_2` | 424 | 67.0% | 284 | 140 |
| `branchAgreement` | `agree_3` | 62 | 87.1% | 54 | 8 |
| `robustnessScore` | `score_1` | 1 | 0.0% | 0 | 1 |
| `robustnessScore` | `score_2` | 1 | 100.0% | 1 | 0 |
| `robustnessScore` | `score_3` | 3 | 100.0% | 3 | 0 |
| `robustnessScore` | `score_4` | 70 | 52.9% | 37 | 33 |
| `robustnessScore` | `score_5` | 280 | 42.5% | 119 | 161 |
| `robustnessScore` | `score_6` | 382 | 68.3% | 261 | 121 |
| `robustnessScore` | `score_7` | 44 | 86.4% | 38 | 6 |

## Decision

- Production remains blocked.
- Frozen test remains closed.
- Use these buckets to design non-suppressive confidence or calibration features; do not replace predicted intensity.

