# PLUM Tohoku mismatch/one_sided/compact Mode Signal Separation Diagnostic

- Status: `pass`
- Method: `PLUM Tohoku mismatch/one_sided/compact mode signal separation diagnostic`
- Frozen test evaluated: `true`
- Production ready: `false`
- Production UI connected: `false`
- Diagnostic only: `true`
- Parameters tuned: `false`
- Suppression applied: `false`
- Raw predicted intensity mutated: `false`

## Coverage

| Slice | Count |
| --- | ---: |
| `validation family samples` | 1254 |
| `remainder family samples` | 67 |
| `validation near-threshold positives` | 195 |
| `validation false middle-transition` | 83 |
| `remainder near-threshold positives` | 30 |
| `remainder false middle-transition` | 15 |

## Scope

- Removed dominant event: `2022031623342701-37.6810-141.6062`
- Estimated-source region: `tohoku`
- Fixed family: `mismatch/one_sided/compact`
- Minimum evidence count: `8`
- Maximum nearest evidence distance: `10.0 km`

## Mode Definitions

- `near_threshold_positive`: `family mismatch/one_sided/compact with actualGapBand=0.0_to_1.0 and evidenceGapBand=lt_1.0`
- `false_middle_transition`: `family mismatch/one_sided/compact with actualGapBand=-1.0_to_0.0 and evidenceGapBand=1.0_to_2.0`
- Feature boundary: `feature buckets use only runtime-visible source/support/evidence signals; truth-dependent labels stay offline diagnostic only`

## Remainder Mode Feature Means

| Mode | Count | Local Mismatch | Evidence Count | Nearest Dist | Quadrants | Centroid Offset | Max Spread | Top1 Share | HHI | Mean Margin | Eff Support |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `remainderNearThresholdPositive` | 30 | 0.717 | 23.167 | 4.824 | 1.167 | 6.929 | 1.933 | 0.939 | 0.911 | 0.180 | 1.158 |
| `remainderFalseMiddleTransition` | 15 | 0.756 | 20.600 | 5.277 | 1.000 | 9.346 | 0.000 | 1.000 | 1.000 | 0.166 | 1.000 |

## Validation Mode Feature Means

| Mode | Count | Local Mismatch | Evidence Count | Nearest Dist | Quadrants | Centroid Offset | Max Spread | Top1 Share | HHI | Mean Margin | Eff Support |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `validationNearThresholdPositive` | 195 | 0.630 | 57.087 | 3.303 | 1.195 | 5.845 | 2.175 | 0.892 | 0.867 | 0.146 | 1.303 |
| `validationFalseMiddleTransition` | 83 | 0.686 | 39.807 | 3.681 | 1.096 | 8.684 | 1.230 | 0.958 | 0.943 | 0.184 | 1.111 |

## Ranked Separators

| Family | Bucket | Remainder Near | Remainder False | Near Share | False Share | Support | Dominant | Purity | Capture | Score |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: |
| `quadrantCoverageBand` | `q1` | 25 | 15 | 83.3% | 100.0% | 40 | `near_threshold_positive` | 62.5% | 88.9% | 0.093 |
| `localMismatchBand` | `0.50_to_0.67` | 18 | 6 | 60.0% | 40.0% | 24 | `near_threshold_positive` | 75.0% | 53.3% | 0.080 |
| `centroidOffsetBand` | `lt_5` | 9 | 0 | 30.0% | 0.0% | 9 | `near_threshold_positive` | 100.0% | 20.0% | 0.060 |
| `centroidOffsetBand` | `5_to_10` | 13 | 9 | 43.3% | 60.0% | 22 | `near_threshold_positive` | 59.1% | 48.9% | 0.048 |
| `nearestEvidenceDistanceBand` | `5.0_to_10.0` | 16 | 10 | 53.3% | 66.7% | 26 | `near_threshold_positive` | 61.5% | 57.8% | 0.047 |
| `centroidOffsetBand` | `gte_10` | 8 | 6 | 26.7% | 40.0% | 14 | `near_threshold_positive` | 57.1% | 31.1% | 0.024 |
| `maxSpreadBand` | `lt_10` | 29 | 15 | 96.7% | 100.0% | 44 | `near_threshold_positive` | 65.9% | 97.8% | 0.021 |
| `quadrantCoverageBand` | `q2` | 5 | 0 | 16.7% | 0.0% | 5 | `near_threshold_positive` | 100.0% | 11.1% | 0.019 |
| `localMismatchBand|quadrantCoverageBand` | `0.50_to_0.67|q2` | 5 | 0 | 16.7% | 0.0% | 5 | `near_threshold_positive` | 100.0% | 11.1% | 0.019 |
| `nearestEvidenceDistanceBand` | `lt_2.5` | 6 | 1 | 20.0% | 6.7% | 7 | `near_threshold_positive` | 85.7% | 15.6% | 0.018 |
| `localMismatchBand` | `0.67_to_0.85` | 6 | 5 | 20.0% | 33.3% | 11 | `near_threshold_positive` | 54.5% | 24.4% | 0.018 |
| `localMismatchBand|quadrantCoverageBand` | `0.67_to_0.85|q1` | 6 | 5 | 20.0% | 33.3% | 11 | `near_threshold_positive` | 54.5% | 24.4% | 0.018 |
| `meanContributionMarginBand` | `lt_0.25` | 23 | 11 | 76.7% | 73.3% | 34 | `near_threshold_positive` | 67.6% | 75.6% | 0.017 |
| `evidenceCountBand` | `gte_16` | 19 | 10 | 63.3% | 66.7% | 29 | `near_threshold_positive` | 65.5% | 64.4% | 0.014 |
| `meanContributionMarginBand` | `0.25_to_0.40` | 5 | 4 | 16.7% | 26.7% | 9 | `near_threshold_positive` | 55.6% | 20.0% | 0.011 |
| `localMismatchBand|quadrantCoverageBand` | `0.50_to_0.67|q1` | 13 | 6 | 43.3% | 40.0% | 19 | `near_threshold_positive` | 68.4% | 42.2% | 0.010 |
| `localMismatchBand` | `gte_0.85` | 6 | 4 | 20.0% | 26.7% | 10 | `near_threshold_positive` | 60.0% | 22.2% | 0.009 |
| `localMismatchBand|quadrantCoverageBand` | `gte_0.85|q1` | 6 | 4 | 20.0% | 26.7% | 10 | `near_threshold_positive` | 60.0% | 22.2% | 0.009 |
| `evidenceCountBand` | `8_to_11` | 7 | 3 | 23.3% | 20.0% | 10 | `near_threshold_positive` | 70.0% | 22.2% | 0.005 |
| `sourceTriggerFamily` | `plum_only` | 30 | 15 | 100.0% | 100.0% | 45 | `near_threshold_positive` | 66.7% | 100.0% | 0.000 |

## `localMismatchBand`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `0.50_to_0.67` | 145 | 46 | 18 | 6 | +18.9pp | +20.0pp | 24 | `near_threshold_positive` | 0.080 |
| `0.67_to_0.85` | 43 | 22 | 6 | 5 | -4.5pp | -13.3pp | 11 | `near_threshold_positive` | 0.018 |
| `gte_0.85` | 7 | 15 | 6 | 4 | -14.5pp | -6.7pp | 10 | `near_threshold_positive` | 0.009 |

## `sourceTriggerFamily`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `both` | 79 | 21 | 0 | 0 | +15.2pp | +0.0pp | 0 | `tied` | 0.000 |
| `plum_only` | 116 | 62 | 30 | 15 | -15.2pp | +0.0pp | 45 | `near_threshold_positive` | 0.000 |

## `sourceWinnerFamily`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `jma_higher` | 54 | 13 | 0 | 0 | +12.0pp | +0.0pp | 0 | `tied` | 0.000 |
| `plum_higher` | 141 | 70 | 30 | 15 | -12.0pp | +0.0pp | 45 | `near_threshold_positive` | 0.000 |

## `quadrantCoverageBand`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `q1` | 157 | 75 | 25 | 15 | -9.8pp | -16.7pp | 40 | `near_threshold_positive` | 0.093 |
| `q2` | 38 | 8 | 5 | 0 | +9.8pp | +16.7pp | 5 | `near_threshold_positive` | 0.019 |

## `evidenceCountBand`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `12_to_15` | 18 | 13 | 4 | 2 | -6.4pp | +0.0pp | 6 | `near_threshold_positive` | 0.000 |
| `8_to_11` | 22 | 15 | 7 | 3 | -6.8pp | +3.3pp | 10 | `near_threshold_positive` | 0.005 |
| `gte_16` | 155 | 55 | 19 | 10 | +13.2pp | -3.3pp | 29 | `near_threshold_positive` | 0.014 |

## `nearestEvidenceDistanceBand`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `2.5_to_5.0` | 53 | 26 | 8 | 4 | -4.1pp | +0.0pp | 12 | `near_threshold_positive` | 0.000 |
| `5.0_to_10.0` | 41 | 22 | 16 | 10 | -5.5pp | -13.3pp | 26 | `near_threshold_positive` | 0.047 |
| `lt_2.5` | 101 | 35 | 6 | 1 | +9.6pp | +13.3pp | 7 | `near_threshold_positive` | 0.018 |

## `centroidOffsetBand`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `5_to_10` | 70 | 34 | 13 | 9 | -5.1pp | -16.7pp | 22 | `near_threshold_positive` | 0.048 |
| `gte_10` | 30 | 27 | 8 | 6 | -17.1pp | -13.3pp | 14 | `near_threshold_positive` | 0.024 |
| `lt_5` | 95 | 22 | 9 | 0 | +22.2pp | +30.0pp | 9 | `near_threshold_positive` | 0.060 |

## `maxSpreadBand`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `10_to_15` | 22 | 3 | 1 | 0 | +7.7pp | +3.3pp | 1 | `near_threshold_positive` | 0.001 |
| `15_to_20` | 1 | 2 | 0 | 0 | -1.9pp | +0.0pp | 0 | `tied` | 0.000 |
| `lt_10` | 172 | 78 | 29 | 15 | -5.8pp | -3.3pp | 44 | `near_threshold_positive` | 0.021 |

## `topContributionShareBand`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `0.25_to_0.33` | 1 | 0 | 0 | 0 | +0.5pp | +0.0pp | 0 | `tied` | 0.000 |
| `gte_0.33` | 193 | 83 | 30 | 15 | -1.0pp | +0.0pp | 45 | `near_threshold_positive` | 0.000 |
| `lt_0.20` | 1 | 0 | 0 | 0 | +0.5pp | +0.0pp | 0 | `tied` | 0.000 |

## `contributionHhiBand`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `0.10_to_0.14` | 1 | 0 | 0 | 0 | +0.5pp | +0.0pp | 0 | `tied` | 0.000 |
| `0.14_to_0.20` | 1 | 0 | 0 | 0 | +0.5pp | +0.0pp | 0 | `tied` | 0.000 |
| `gte_0.20` | 193 | 83 | 30 | 15 | -1.0pp | +0.0pp | 45 | `near_threshold_positive` | 0.000 |

## `meanContributionMarginBand`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `0.25_to_0.40` | 17 | 14 | 5 | 4 | -8.1pp | -10.0pp | 9 | `near_threshold_positive` | 0.011 |
| `0.40_to_0.60` | 10 | 8 | 2 | 0 | -4.5pp | +6.7pp | 2 | `near_threshold_positive` | 0.003 |
| `gte_0.60` | 1 | 0 | 0 | 0 | +0.5pp | +0.0pp | 0 | `tied` | 0.000 |
| `lt_0.25` | 167 | 61 | 23 | 11 | +12.1pp | +3.3pp | 34 | `near_threshold_positive` | 0.017 |

## `effectiveSupportCountBand`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `4_to_6` | 1 | 0 | 0 | 0 | +0.5pp | +0.0pp | 0 | `tied` | 0.000 |
| `6_to_8` | 1 | 0 | 0 | 0 | +0.5pp | +0.0pp | 0 | `tied` | 0.000 |
| `lt_4` | 193 | 83 | 30 | 15 | -1.0pp | +0.0pp | 45 | `near_threshold_positive` | 0.000 |

## `localMismatchBand|quadrantCoverageBand`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `0.50_to_0.67|q1` | 114 | 40 | 13 | 6 | +10.3pp | +3.3pp | 19 | `near_threshold_positive` | 0.010 |
| `0.50_to_0.67|q2` | 31 | 6 | 5 | 0 | +8.7pp | +16.7pp | 5 | `near_threshold_positive` | 0.019 |
| `0.67_to_0.85|q1` | 37 | 21 | 6 | 5 | -6.3pp | -13.3pp | 11 | `near_threshold_positive` | 0.018 |
| `0.67_to_0.85|q2` | 6 | 1 | 0 | 0 | +1.9pp | +0.0pp | 0 | `tied` | 0.000 |
| `gte_0.85|q1` | 6 | 14 | 6 | 4 | -13.8pp | -6.7pp | 10 | `near_threshold_positive` | 0.009 |
| `gte_0.85|q2` | 1 | 1 | 0 | 0 | -0.7pp | +0.0pp | 0 | `tied` | 0.000 |
