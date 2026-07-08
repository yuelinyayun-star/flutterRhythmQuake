# PLUM Tohoku mismatch/one_sided/compact Minor-Event Pooled Signal Diagnostic

- Status: `pass`
- Method: `PLUM Tohoku mismatch/one_sided/compact minor-event pooled signal diagnostic`
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
| `validation target modes` | 278 |
| `minor-slice target modes` | 11 |
| `validation near-threshold positives` | 195 |
| `validation false middle-transition` | 83 |
| `minor-slice near-threshold positives` | 5 |
| `minor-slice false middle-transition` | 6 |
| `minor-slice events` | 3 |

## Scope

- Removed dominant event: `2022031623342701-37.6810-141.6062`
- Additional excluded event for minor slice: `2022070605102497-38.4125-141.9545`
- Estimated-source region: `tohoku`
- Fixed family: `mismatch/one_sided/compact`
- Minimum evidence count: `8`
- Maximum nearest evidence distance: `10.0 km`

## Minor Slice Events

| Event | Count |
| --- | ---: |
| `2022031700522985-37.7947-141.7145` | 4 |
| `2022080409481868-37.6118-141.6195` | 4 |
| `2022081814461047-37.6017-141.5853` | 3 |

## Mode Definitions

- `near_threshold_positive`: `family mismatch/one_sided/compact with actualGapBand=0.0_to_1.0 and evidenceGapBand=lt_1.0`
- `false_middle_transition`: `family mismatch/one_sided/compact with actualGapBand=-1.0_to_0.0 and evidenceGapBand=1.0_to_2.0`
- Feature boundary: `feature buckets use only runtime-visible source/support/evidence signals; truth-dependent labels stay offline diagnostic only`

## Variant Summary

| Variant | Val Mean Gap | Minor Mean Gap | Stability | Low False Capture | Low Near Capture | High Near Rate | High False Rate | High/Low Near Lift | High/Low False Ratio |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `support_geometry_only` | 0.159 | 0.007 | `not_stable` | 66.7% | 60.0% | 0.0% | 0.0% | 1.33x | 0.67x |
| `support_geometry_plus_proximity` | 0.134 | -0.061 | `not_stable` | 83.3% | 80.0% | 0.0% | 0.0% | 1.33x | 0.67x |
| `full_score` | 0.089 | -0.041 | `not_stable` | 83.3% | 80.0% | 0.0% | 0.0% | 1.33x | 0.67x |

## `support_geometry_only`

- Weights: `{"supportGeometry":1.0}`
- Validation anchors: q25 `0.333`, q50 `0.512`, q75 `0.667`.

### Mode Score Means

| Slice | Mode | Count | Score |
| --- | --- | ---: | ---: |
| `validation` | `nearThresholdPositive` | 195 | 0.564 |
| `validation` | `falseMiddleTransition` | 83 | 0.405 |
| `minorSlice` | `nearThresholdPositive` | 5 | 0.217 |
| `minorSlice` | `falseMiddleTransition` | 6 | 0.209 |

### Validation-Anchored Band Transfer

| Band | Val Count | Val Near | Val False | Minor Count | Minor Near | Minor False | Minor Near Rate | Minor False Rate | Minor Near Capture | Minor False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `low` | 76 | 36 | 40 | 7 | 3 | 4 | 42.9% | 57.1% | 60.0% | 66.7% |
| `mid_low` | 63 | 42 | 21 | 3 | 1 | 2 | 33.3% | 66.7% | 20.0% | 33.3% |
| `mid_high` | 95 | 80 | 15 | 1 | 1 | 0 | 100.0% | 0.0% | 20.0% | 0.0% |
| `high` | 44 | 37 | 7 | 0 | 0 | 0 | 0.0% | 0.0% | 0.0% | 0.0% |

### Minor Slice Quartiles

| Quartile | Score Min | Score Max | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.000 | 0.000 | 2 | 1 | 1 | 50.0% | 50.0% | 20.0% | 16.7% |
| 2 | 0.000 | 0.019 | 3 | 2 | 1 | 66.7% | 33.3% | 40.0% | 16.7% |
| 3 | 0.106 | 0.407 | 3 | 0 | 3 | 0.0% | 100.0% | 0.0% | 50.0% |
| 4 | 0.417 | 0.667 | 3 | 2 | 1 | 66.7% | 33.3% | 40.0% | 16.7% |

### Minor Slice Monotonicity

- High quartile near-positive rate: `66.7%`; low quartile near-positive rate: `50.0%`.
- High-to-low near-positive lift: `1.33x`.
- Low quartile false rate: `50.0%`; high quartile false rate: `33.3%`.
- High/low false-rate ratio: `0.67x`.

## `support_geometry_plus_proximity`

- Weights: `{"supportGeometry":0.7,"evidenceProximity":0.3}`
- Validation anchors: q25 `0.356`, q50 `0.577`, q75 `0.705`.

### Mode Score Means

| Slice | Mode | Count | Score |
| --- | --- | ---: | ---: |
| `validation` | `nearThresholdPositive` | 195 | 0.587 |
| `validation` | `falseMiddleTransition` | 83 | 0.453 |
| `minorSlice` | `nearThresholdPositive` | 5 | 0.176 |
| `minorSlice` | `falseMiddleTransition` | 6 | 0.237 |

### Validation-Anchored Band Transfer

| Band | Val Count | Val Near | Val False | Minor Count | Minor Near | Minor False | Minor Near Rate | Minor False Rate | Minor Near Capture | Minor False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `low` | 71 | 34 | 37 | 9 | 4 | 5 | 44.4% | 55.6% | 80.0% | 83.3% |
| `mid_low` | 68 | 52 | 16 | 0 | 0 | 0 | 0.0% | 0.0% | 0.0% | 0.0% |
| `mid_high` | 69 | 53 | 16 | 2 | 1 | 1 | 50.0% | 50.0% | 20.0% | 16.7% |
| `high` | 70 | 56 | 14 | 0 | 0 | 0 | 0.0% | 0.0% | 0.0% | 0.0% |

### Minor Slice Quartiles

| Quartile | Score Min | Score Max | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.000 | 0.000 | 2 | 1 | 1 | 50.0% | 50.0% | 20.0% | 16.7% |
| 2 | 0.000 | 0.136 | 3 | 2 | 1 | 66.7% | 33.3% | 40.0% | 16.7% |
| 3 | 0.153 | 0.285 | 3 | 0 | 3 | 0.0% | 100.0% | 0.0% | 50.0% |
| 4 | 0.292 | 0.654 | 3 | 2 | 1 | 66.7% | 33.3% | 40.0% | 16.7% |

### Minor Slice Monotonicity

- High quartile near-positive rate: `66.7%`; low quartile near-positive rate: `50.0%`.
- High-to-low near-positive lift: `1.33x`.
- Low quartile false rate: `50.0%`; high quartile false rate: `33.3%`.
- High/low false-rate ratio: `0.67x`.

## `full_score`

- Weights: `{"supportGeometry":0.45,"concentration":0.35,"evidenceProximity":0.2}`
- Validation anchors: q25 `0.231`, q50 `0.380`, q75 `0.460`.

### Mode Score Means

| Slice | Mode | Count | Score |
| --- | --- | ---: | ---: |
| `validation` | `nearThresholdPositive` | 195 | 0.384 |
| `validation` | `falseMiddleTransition` | 83 | 0.295 |
| `minorSlice` | `nearThresholdPositive` | 5 | 0.114 |
| `minorSlice` | `falseMiddleTransition` | 6 | 0.155 |

### Validation-Anchored Band Transfer

| Band | Val Count | Val Near | Val False | Minor Count | Minor Near | Minor False | Minor Near Rate | Minor False Rate | Minor Near Capture | Minor False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `low` | 70 | 35 | 35 | 9 | 4 | 5 | 44.4% | 55.6% | 80.0% | 83.3% |
| `mid_low` | 69 | 51 | 18 | 0 | 0 | 0 | 0.0% | 0.0% | 0.0% | 0.0% |
| `mid_high` | 71 | 55 | 16 | 2 | 1 | 1 | 50.0% | 50.0% | 20.0% | 16.7% |
| `high` | 68 | 54 | 14 | 0 | 0 | 0 | 0.0% | 0.0% | 0.0% | 0.0% |

### Minor Slice Quartiles

| Quartile | Score Min | Score Max | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.000 | 0.000 | 2 | 1 | 1 | 50.0% | 50.0% | 20.0% | 16.7% |
| 2 | 0.000 | 0.090 | 3 | 2 | 1 | 66.7% | 33.3% | 40.0% | 16.7% |
| 3 | 0.098 | 0.183 | 3 | 0 | 3 | 0.0% | 100.0% | 0.0% | 50.0% |
| 4 | 0.188 | 0.428 | 3 | 2 | 1 | 66.7% | 33.3% | 40.0% | 16.7% |

### Minor Slice Monotonicity

- High quartile near-positive rate: `66.7%`; low quartile near-positive rate: `50.0%`.
- High-to-low near-positive lift: `1.33x`.
- Low quartile false rate: `50.0%`; high quartile false rate: `33.3%`.
- High/low false-rate ratio: `0.67x`.

## Minor Slice Mode Feature Means

| Mode | Count | Local Mismatch | Evidence Count | Nearest Dist | Quadrants | Centroid Offset | Max Spread | Top1 Share | HHI | Mean Margin | Eff Support |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `minorNearThresholdPositive` | 5 | 0.833 | 13.400 | 6.144 | 1.000 | 9.424 | 0.000 | 1.000 | 1.000 | 0.069 | 1.000 |
| `minorFalseMiddleTransition` | 6 | 0.776 | 24.833 | 4.901 | 1.000 | 9.167 | 0.000 | 1.000 | 1.000 | 0.075 | 1.000 |

## Validation Mode Feature Means

| Mode | Count | Local Mismatch | Evidence Count | Nearest Dist | Quadrants | Centroid Offset | Max Spread | Top1 Share | HHI | Mean Margin | Eff Support |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `validationNearThresholdPositive` | 195 | 0.630 | 57.087 | 3.303 | 1.195 | 5.845 | 2.175 | 0.892 | 0.867 | 0.146 | 1.303 |
| `validationFalseMiddleTransition` | 83 | 0.686 | 39.807 | 3.681 | 1.096 | 8.684 | 1.230 | 0.958 | 0.943 | 0.184 | 1.111 |

## Ranked Separators

| Family | Bucket | Minor Near | Minor False | Near Share | False Share | Support | Dominant | Purity | Capture | Score |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: |
| `centroidOffsetBand` | `5_to_10` | 1 | 5 | 20.0% | 83.3% | 6 | `false_middle_transition` | 83.3% | 54.5% | 0.288 |
| `evidenceCountBand` | `gte_16` | 1 | 4 | 20.0% | 66.7% | 5 | `false_middle_transition` | 80.0% | 45.5% | 0.170 |
| `evidenceCountBand` | `12_to_15` | 3 | 1 | 60.0% | 16.7% | 4 | `near_threshold_positive` | 75.0% | 36.4% | 0.118 |
| `centroidOffsetBand` | `gte_10` | 3 | 1 | 60.0% | 16.7% | 4 | `near_threshold_positive` | 75.0% | 36.4% | 0.118 |
| `nearestEvidenceDistanceBand` | `5.0_to_10.0` | 4 | 3 | 80.0% | 50.0% | 7 | `near_threshold_positive` | 57.1% | 63.6% | 0.109 |
| `localMismatchBand` | `gte_0.85` | 3 | 2 | 60.0% | 33.3% | 5 | `near_threshold_positive` | 60.0% | 45.5% | 0.073 |
| `localMismatchBand|quadrantCoverageBand` | `gte_0.85|q1` | 3 | 2 | 60.0% | 33.3% | 5 | `near_threshold_positive` | 60.0% | 45.5% | 0.073 |
| `localMismatchBand` | `0.67_to_0.85` | 0 | 2 | 0.0% | 33.3% | 2 | `false_middle_transition` | 100.0% | 18.2% | 0.061 |
| `localMismatchBand|quadrantCoverageBand` | `0.67_to_0.85|q1` | 0 | 2 | 0.0% | 33.3% | 2 | `false_middle_transition` | 100.0% | 18.2% | 0.061 |
| `nearestEvidenceDistanceBand` | `2.5_to_5.0` | 1 | 2 | 20.0% | 33.3% | 3 | `false_middle_transition` | 66.7% | 27.3% | 0.024 |
| `localMismatchBand` | `0.50_to_0.67` | 2 | 2 | 40.0% | 33.3% | 4 | `tied` | 50.0% | 36.4% | 0.012 |
| `localMismatchBand|quadrantCoverageBand` | `0.50_to_0.67|q1` | 2 | 2 | 40.0% | 33.3% | 4 | `tied` | 50.0% | 36.4% | 0.012 |
| `evidenceCountBand` | `8_to_11` | 1 | 1 | 20.0% | 16.7% | 2 | `tied` | 50.0% | 18.2% | 0.003 |
| `sourceTriggerFamily` | `plum_only` | 5 | 6 | 100.0% | 100.0% | 11 | `false_middle_transition` | 54.5% | 100.0% | 0.000 |
| `sourceWinnerFamily` | `plum_higher` | 5 | 6 | 100.0% | 100.0% | 11 | `false_middle_transition` | 54.5% | 100.0% | 0.000 |
| `quadrantCoverageBand` | `q1` | 5 | 6 | 100.0% | 100.0% | 11 | `false_middle_transition` | 54.5% | 100.0% | 0.000 |
| `maxSpreadBand` | `lt_10` | 5 | 6 | 100.0% | 100.0% | 11 | `false_middle_transition` | 54.5% | 100.0% | 0.000 |
| `topContributionShareBand` | `gte_0.33` | 5 | 6 | 100.0% | 100.0% | 11 | `false_middle_transition` | 54.5% | 100.0% | 0.000 |
| `contributionHhiBand` | `gte_0.20` | 5 | 6 | 100.0% | 100.0% | 11 | `false_middle_transition` | 54.5% | 100.0% | 0.000 |
| `meanContributionMarginBand` | `lt_0.25` | 5 | 6 | 100.0% | 100.0% | 11 | `false_middle_transition` | 54.5% | 100.0% | 0.000 |

## `localMismatchBand`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `0.50_to_0.67` | 145 | 46 | 2 | 2 | +18.9pp | +6.7pp | 4 | `tied` | 0.012 |
| `0.67_to_0.85` | 43 | 22 | 0 | 2 | -4.5pp | -33.3pp | 2 | `false_middle_transition` | 0.061 |
| `gte_0.85` | 7 | 15 | 3 | 2 | -14.5pp | +26.7pp | 5 | `near_threshold_positive` | 0.073 |

## `sourceTriggerFamily`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `both` | 79 | 21 | 0 | 0 | +15.2pp | +0.0pp | 0 | `tied` | 0.000 |
| `plum_only` | 116 | 62 | 5 | 6 | -15.2pp | +0.0pp | 11 | `false_middle_transition` | 0.000 |

## `sourceWinnerFamily`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `jma_higher` | 54 | 13 | 0 | 0 | +12.0pp | +0.0pp | 0 | `tied` | 0.000 |
| `plum_higher` | 141 | 70 | 5 | 6 | -12.0pp | +0.0pp | 11 | `false_middle_transition` | 0.000 |

## `quadrantCoverageBand`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `q1` | 157 | 75 | 5 | 6 | -9.8pp | +0.0pp | 11 | `false_middle_transition` | 0.000 |
| `q2` | 38 | 8 | 0 | 0 | +9.8pp | +0.0pp | 0 | `tied` | 0.000 |

## `evidenceCountBand`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `12_to_15` | 18 | 13 | 3 | 1 | -6.4pp | +43.3pp | 4 | `near_threshold_positive` | 0.118 |
| `8_to_11` | 22 | 15 | 1 | 1 | -6.8pp | +3.3pp | 2 | `tied` | 0.003 |
| `gte_16` | 155 | 55 | 1 | 4 | +13.2pp | -46.7pp | 5 | `false_middle_transition` | 0.170 |

## `nearestEvidenceDistanceBand`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `2.5_to_5.0` | 53 | 26 | 1 | 2 | -4.1pp | -13.3pp | 3 | `false_middle_transition` | 0.024 |
| `5.0_to_10.0` | 41 | 22 | 4 | 3 | -5.5pp | +30.0pp | 7 | `near_threshold_positive` | 0.109 |
| `lt_2.5` | 101 | 35 | 0 | 1 | +9.6pp | -16.7pp | 1 | `false_middle_transition` | 0.015 |

## `centroidOffsetBand`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `5_to_10` | 70 | 34 | 1 | 5 | -5.1pp | -63.3pp | 6 | `false_middle_transition` | 0.288 |
| `gte_10` | 30 | 27 | 3 | 1 | -17.1pp | +43.3pp | 4 | `near_threshold_positive` | 0.118 |
| `lt_5` | 95 | 22 | 1 | 0 | +22.2pp | +20.0pp | 1 | `near_threshold_positive` | 0.018 |

## `maxSpreadBand`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `10_to_15` | 22 | 3 | 0 | 0 | +7.7pp | +0.0pp | 0 | `tied` | 0.000 |
| `15_to_20` | 1 | 2 | 0 | 0 | -1.9pp | +0.0pp | 0 | `tied` | 0.000 |
| `lt_10` | 172 | 78 | 5 | 6 | -5.8pp | +0.0pp | 11 | `false_middle_transition` | 0.000 |

## `topContributionShareBand`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `0.25_to_0.33` | 1 | 0 | 0 | 0 | +0.5pp | +0.0pp | 0 | `tied` | 0.000 |
| `gte_0.33` | 193 | 83 | 5 | 6 | -1.0pp | +0.0pp | 11 | `false_middle_transition` | 0.000 |
| `lt_0.20` | 1 | 0 | 0 | 0 | +0.5pp | +0.0pp | 0 | `tied` | 0.000 |

## `contributionHhiBand`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `0.10_to_0.14` | 1 | 0 | 0 | 0 | +0.5pp | +0.0pp | 0 | `tied` | 0.000 |
| `0.14_to_0.20` | 1 | 0 | 0 | 0 | +0.5pp | +0.0pp | 0 | `tied` | 0.000 |
| `gte_0.20` | 193 | 83 | 5 | 6 | -1.0pp | +0.0pp | 11 | `false_middle_transition` | 0.000 |

## `meanContributionMarginBand`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `0.25_to_0.40` | 17 | 14 | 0 | 0 | -8.1pp | +0.0pp | 0 | `tied` | 0.000 |
| `0.40_to_0.60` | 10 | 8 | 0 | 0 | -4.5pp | +0.0pp | 0 | `tied` | 0.000 |
| `gte_0.60` | 1 | 0 | 0 | 0 | +0.5pp | +0.0pp | 0 | `tied` | 0.000 |
| `lt_0.25` | 167 | 61 | 5 | 6 | +12.1pp | +0.0pp | 11 | `false_middle_transition` | 0.000 |

## `effectiveSupportCountBand`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `4_to_6` | 1 | 0 | 0 | 0 | +0.5pp | +0.0pp | 0 | `tied` | 0.000 |
| `6_to_8` | 1 | 0 | 0 | 0 | +0.5pp | +0.0pp | 0 | `tied` | 0.000 |
| `lt_4` | 193 | 83 | 5 | 6 | -1.0pp | +0.0pp | 11 | `false_middle_transition` | 0.000 |

## `localMismatchBand|quadrantCoverageBand`

| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `0.50_to_0.67|q1` | 114 | 40 | 2 | 2 | +10.3pp | +6.7pp | 4 | `tied` | 0.012 |
| `0.50_to_0.67|q2` | 31 | 6 | 0 | 0 | +8.7pp | +0.0pp | 0 | `tied` | 0.000 |
| `0.67_to_0.85|q1` | 37 | 21 | 0 | 2 | -6.3pp | -33.3pp | 2 | `false_middle_transition` | 0.061 |
| `0.67_to_0.85|q2` | 6 | 1 | 0 | 0 | +1.9pp | +0.0pp | 0 | `tied` | 0.000 |
| `gte_0.85|q1` | 6 | 14 | 3 | 2 | -13.8pp | +26.7pp | 5 | `near_threshold_positive` | 0.073 |
| `gte_0.85|q2` | 1 | 1 | 0 | 0 | -0.7pp | +0.0pp | 0 | `tied` | 0.000 |

## Sample Ledger

| Event | Mode | Actual | JMA | PLUM | Evidence | Nearest Dist | Local Mismatch | Quadrants | Centroid | SG Only | SG+Prox | Full |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `2022031700522985-37.7947-141.7145` | `false_middle_transition` | 3.000 | 2.410 | 3.507 | 22 | 5.749 | 1.000 | 1 | 13.859 | 0.000 | 0.000 | 0.000 |
| `2022031700522985-37.7947-141.7145` | `near_threshold_positive` | 3.700 | 2.843 | 3.602 | 10 | 5.750 | 1.000 | 1 | 11.957 | 0.000 | 0.000 | 0.000 |
| `2022031700522985-37.7947-141.7145` | `near_threshold_positive` | 3.500 | 1.952 | 3.506 | 18 | 6.154 | 1.000 | 1 | 11.880 | 0.000 | 0.000 | 0.000 |
| `2022031700522985-37.7947-141.7145` | `near_threshold_positive` | 3.500 | 2.238 | 3.506 | 12 | 7.413 | 1.000 | 1 | 11.880 | 0.000 | 0.000 | 0.000 |
| `2022080409481868-37.6118-141.6195` | `false_middle_transition` | 2.900 | 2.479 | 3.622 | 12 | 6.961 | 0.667 | 1 | 7.558 | 0.407 | 0.285 | 0.183 |
| `2022080409481868-37.6118-141.6195` | `false_middle_transition` | 2.600 | 2.434 | 3.629 | 10 | 1.853 | 0.500 | 1 | 7.413 | 0.506 | 0.654 | 0.428 |
| `2022080409481868-37.6118-141.6195` | `near_threshold_positive` | 3.800 | 2.724 | 3.701 | 15 | 3.988 | 0.500 | 1 | 3.988 | 0.667 | 0.588 | 0.381 |
| `2022080409481868-37.6118-141.6195` | `near_threshold_positive` | 3.500 | 2.488 | 3.529 | 12 | 7.413 | 0.667 | 1 | 7.413 | 0.417 | 0.292 | 0.188 |
| `2022081814461047-37.6017-141.5853` | `false_middle_transition` | 3.000 | 2.457 | 3.647 | 37 | 6.884 | 0.833 | 1 | 7.058 | 0.218 | 0.153 | 0.098 |
| `2022081814461047-37.6017-141.5853` | `false_middle_transition` | 2.600 | 1.926 | 3.515 | 34 | 3.979 | 0.857 | 1 | 9.708 | 0.019 | 0.136 | 0.090 |
| `2022081814461047-37.6017-141.5853` | `false_middle_transition` | 2.600 | 2.575 | 3.530 | 34 | 3.979 | 0.800 | 1 | 9.408 | 0.106 | 0.197 | 0.129 |

## Decision

- This report remains diagnostic-only. It inspects the minor-event pooled slice created by excluding the dominant residual event and the largest surviving residual event.
- It does not tune PLUM, suppress predictions, or authorize production UI/wording/notification changes.
