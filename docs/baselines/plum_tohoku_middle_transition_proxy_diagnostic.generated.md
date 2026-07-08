# PLUM Tohoku Middle-Transition Proxy Diagnostic

- Status: `pass`
- Method: `PLUM Tohoku middle-transition proxy diagnostic`
- Frozen test evaluated: `true`
- Production ready: `false`
- Production UI connected: `false`
- Diagnostic only: `true`
- Parameters tuned: `false`
- Suppression applied: `false`
- Raw predicted intensity mutated: `false`

## Coverage

| Split | Variants | Station forecasts | Focus samples | Middle-transition samples | Rate |
| --- | ---: | ---: | ---: | ---: | ---: |
| validation | 2688 | 185694 | 457 | 0 | 0.0% |
| test | 2757 | 179844 | 1051 | 246 | 23.4% |

## Focus Filter

- Estimated-source region: `tohoku`
- Minimum evidence count: `8`
- Maximum nearest evidence distance: `10.0 km`
- Minimum prediction margin: `1.0 shindo`
- Baseline threshold crossing required: `true`

## Ranked Proxy Candidates

| Family | Bucket | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score | Share Delta |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `evidenceCountBand` | `gte_16` | 1029 | 241 | 23.4% | 1.00x | 98.0% | 37.8% | +26.6pp |
| `branchAgreement` | `agree_2` | 885 | 208 | 23.5% | 1.00x | 84.6% | 36.8% | +83.8pp |
| `robustnessScore` | `score_6` | 885 | 208 | 23.5% | 1.00x | 84.6% | 36.8% | +83.8pp |
| `plumMarginBand` | `1.0_to_1.5` | 691 | 167 | 24.2% | 1.03x | 67.9% | 35.6% | +5.4pp |
| `supportGeometry` | `one_sided` | 601 | 139 | 23.1% | 0.99x | 56.5% | 32.8% | +45.4pp |
| `supportSpreadBand` | `moderate` | 521 | 123 | 23.6% | 1.01x | 50.0% | 32.1% | +13.2pp |
| `supportGeometry` | `surrounded` | 450 | 107 | 23.8% | 1.02x | 43.5% | 30.7% | -45.4pp |
| `quadrantCoverageBand` | `q3_plus` | 450 | 107 | 23.8% | 1.02x | 43.5% | 30.7% | -45.4pp |
| `centroidOffsetBand` | `lt_8` | 417 | 99 | 23.7% | 1.01x | 40.2% | 29.9% | -16.1pp |
| `quadrantCoverageBand` | `q2` | 362 | 89 | 24.6% | 1.05x | 36.2% | 29.3% | +23.7pp |
| `centroidOffsetBand` | `gte_12` | 340 | 77 | 22.6% | 0.97x | 31.3% | 26.3% | +18.1pp |
| `centroidOffsetBand` | `8_to_12` | 294 | 70 | 23.8% | 1.02x | 28.5% | 25.9% | -2.0pp |
| `supportSpreadBand` | `compact` | 289 | 68 | 23.5% | 1.01x | 27.6% | 25.4% | +22.7pp |
| `plumMarginBand` | `1.5_to_2.0` | 320 | 71 | 22.2% | 0.95x | 28.9% | 25.1% | -3.0pp |
| `geometrySpread` | `surrounded/moderate` | 240 | 60 | 25.0% | 1.07x | 24.4% | 24.7% | -6.7pp |

## `branchAgreement`

| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `agree_1` | 0 | 0.0% | 90 | 19 | 21.1% | 0.90x | 7.7% | 11.3% |
| `agree_2` | 2 | 0.0% | 885 | 208 | 23.5% | 1.00x | 84.6% | 36.8% |
| `agree_3` | 455 | 0.0% | 76 | 19 | 25.0% | 1.07x | 7.7% | 11.8% |

## `robustnessScore`

| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `score_5` | 0 | 0.0% | 90 | 19 | 21.1% | 0.90x | 7.7% | 11.3% |
| `score_6` | 2 | 0.0% | 885 | 208 | 23.5% | 1.00x | 84.6% | 36.8% |
| `score_7` | 455 | 0.0% | 76 | 19 | 25.0% | 1.07x | 7.7% | 11.8% |

## `supportGeometry`

| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `one_sided` | 54 | 0.0% | 601 | 139 | 23.1% | 0.99x | 56.5% | 32.8% |
| `surrounded` | 403 | 0.0% | 450 | 107 | 23.8% | 1.02x | 43.5% | 30.7% |

## `supportSpreadBand`

| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `compact` | 22 | 0.0% | 289 | 68 | 23.5% | 1.01x | 27.6% | 25.4% |
| `moderate` | 166 | 0.0% | 521 | 123 | 23.6% | 1.01x | 50.0% | 32.1% |
| `wide` | 269 | 0.0% | 241 | 55 | 22.8% | 0.98x | 22.4% | 22.6% |

## `geometrySpread`

| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `one_sided/compact` | 15 | 0.0% | 265 | 63 | 23.8% | 1.02x | 25.6% | 24.7% |
| `one_sided/moderate` | 31 | 0.0% | 281 | 63 | 22.4% | 0.96x | 25.6% | 23.9% |
| `one_sided/wide` | 8 | 0.0% | 55 | 13 | 23.6% | 1.01x | 5.3% | 8.6% |
| `surrounded/compact` | 7 | 0.0% | 24 | 5 | 20.8% | 0.89x | 2.0% | 3.7% |
| `surrounded/moderate` | 135 | 0.0% | 240 | 60 | 25.0% | 1.07x | 24.4% | 24.7% |
| `surrounded/wide` | 261 | 0.0% | 186 | 42 | 22.6% | 0.96x | 17.1% | 19.4% |

## `quadrantCoverageBand`

| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `q1` | 5 | 0.0% | 239 | 50 | 20.9% | 0.89x | 20.3% | 20.6% |
| `q2` | 49 | 0.0% | 362 | 89 | 24.6% | 1.05x | 36.2% | 29.3% |
| `q3_plus` | 403 | 0.0% | 450 | 107 | 23.8% | 1.02x | 43.5% | 30.7% |

## `plumMarginBand`

| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `1.0_to_1.5` | 276 | 0.0% | 691 | 167 | 24.2% | 1.03x | 67.9% | 35.6% |
| `1.5_to_2.0` | 153 | 0.0% | 320 | 71 | 22.2% | 0.95x | 28.9% | 25.1% |
| `2.0_to_3.0` | 28 | 0.0% | 40 | 8 | 20.0% | 0.85x | 3.3% | 5.6% |

## `evidenceCountBand`

| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `10_12` | 65 | 0.0% | 10 | 3 | 30.0% | 1.28x | 1.2% | 2.3% |
| `13_15` | 38 | 0.0% | 12 | 2 | 16.7% | 0.71x | 0.8% | 1.6% |
| `8_9` | 28 | 0.0% | 0 | 0 | 0.0% | 0.00x | 0.0% | 0.0% |
| `gte_16` | 326 | 0.0% | 1029 | 241 | 23.4% | 1.00x | 98.0% | 37.8% |

## `centroidOffsetBand`

| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `8_to_12` | 137 | 0.0% | 294 | 70 | 23.8% | 1.02x | 28.5% | 25.9% |
| `gte_12` | 65 | 0.0% | 340 | 77 | 22.6% | 0.97x | 31.3% | 26.3% |
| `lt_8` | 255 | 0.0% | 417 | 99 | 23.7% | 1.01x | 40.2% | 29.9% |

## `branchAgreement|geometrySpread`

| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `agree_1|one_sided/compact` | 0 | 0.0% | 54 | 12 | 22.2% | 0.95x | 4.9% | 8.0% |
| `agree_1|one_sided/moderate` | 0 | 0.0% | 28 | 5 | 17.9% | 0.76x | 2.0% | 3.6% |
| `agree_1|one_sided/wide` | 0 | 0.0% | 8 | 2 | 25.0% | 1.07x | 0.8% | 1.6% |
| `agree_2|one_sided/compact` | 0 | 0.0% | 195 | 47 | 24.1% | 1.03x | 19.1% | 21.3% |
| `agree_2|one_sided/moderate` | 0 | 0.0% | 225 | 51 | 22.7% | 0.97x | 20.7% | 21.7% |
| `agree_2|one_sided/wide` | 0 | 0.0% | 39 | 9 | 23.1% | 0.99x | 3.7% | 6.3% |
| `agree_2|surrounded/compact` | 0 | 0.0% | 24 | 5 | 20.8% | 0.89x | 2.0% | 3.7% |
| `agree_2|surrounded/moderate` | 1 | 0.0% | 232 | 58 | 25.0% | 1.07x | 23.6% | 24.3% |
| `agree_2|surrounded/wide` | 1 | 0.0% | 170 | 38 | 22.4% | 0.95x | 15.4% | 18.3% |
| `agree_3|one_sided/compact` | 15 | 0.0% | 16 | 4 | 25.0% | 1.07x | 1.6% | 3.1% |
| `agree_3|one_sided/moderate` | 31 | 0.0% | 28 | 7 | 25.0% | 1.07x | 2.8% | 5.1% |
| `agree_3|one_sided/wide` | 8 | 0.0% | 8 | 2 | 25.0% | 1.07x | 0.8% | 1.6% |
| `agree_3|surrounded/compact` | 7 | 0.0% | 0 | 0 | 0.0% | 0.00x | 0.0% | 0.0% |
| `agree_3|surrounded/moderate` | 134 | 0.0% | 8 | 2 | 25.0% | 1.07x | 0.8% | 1.6% |
| `agree_3|surrounded/wide` | 260 | 0.0% | 16 | 4 | 25.0% | 1.07x | 1.6% | 3.1% |

## `robustnessScore|geometrySpread`

| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `score_5|one_sided/compact` | 0 | 0.0% | 54 | 12 | 22.2% | 0.95x | 4.9% | 8.0% |
| `score_5|one_sided/moderate` | 0 | 0.0% | 28 | 5 | 17.9% | 0.76x | 2.0% | 3.6% |
| `score_5|one_sided/wide` | 0 | 0.0% | 8 | 2 | 25.0% | 1.07x | 0.8% | 1.6% |
| `score_6|one_sided/compact` | 0 | 0.0% | 195 | 47 | 24.1% | 1.03x | 19.1% | 21.3% |
| `score_6|one_sided/moderate` | 0 | 0.0% | 225 | 51 | 22.7% | 0.97x | 20.7% | 21.7% |
| `score_6|one_sided/wide` | 0 | 0.0% | 39 | 9 | 23.1% | 0.99x | 3.7% | 6.3% |
| `score_6|surrounded/compact` | 0 | 0.0% | 24 | 5 | 20.8% | 0.89x | 2.0% | 3.7% |
| `score_6|surrounded/moderate` | 1 | 0.0% | 232 | 58 | 25.0% | 1.07x | 23.6% | 24.3% |
| `score_6|surrounded/wide` | 1 | 0.0% | 170 | 38 | 22.4% | 0.95x | 15.4% | 18.3% |
| `score_7|one_sided/compact` | 15 | 0.0% | 16 | 4 | 25.0% | 1.07x | 1.6% | 3.1% |
| `score_7|one_sided/moderate` | 31 | 0.0% | 28 | 7 | 25.0% | 1.07x | 2.8% | 5.1% |
| `score_7|one_sided/wide` | 8 | 0.0% | 8 | 2 | 25.0% | 1.07x | 0.8% | 1.6% |
| `score_7|surrounded/compact` | 7 | 0.0% | 0 | 0 | 0.0% | 0.00x | 0.0% | 0.0% |
| `score_7|surrounded/moderate` | 134 | 0.0% | 8 | 2 | 25.0% | 1.07x | 0.8% | 1.6% |
| `score_7|surrounded/wide` | 260 | 0.0% | 16 | 4 | 25.0% | 1.07x | 1.6% | 3.1% |

## `plumMarginBand|geometrySpread`

| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `1.0_to_1.5|one_sided/compact` | 15 | 0.0% | 163 | 41 | 25.2% | 1.07x | 16.7% | 20.0% |
| `1.0_to_1.5|one_sided/moderate` | 28 | 0.0% | 213 | 47 | 22.1% | 0.94x | 19.1% | 20.5% |
| `1.0_to_1.5|one_sided/wide` | 6 | 0.0% | 32 | 7 | 21.9% | 0.93x | 2.8% | 5.0% |
| `1.0_to_1.5|surrounded/compact` | 7 | 0.0% | 16 | 3 | 18.8% | 0.80x | 1.2% | 2.3% |
| `1.0_to_1.5|surrounded/moderate` | 107 | 0.0% | 140 | 39 | 27.9% | 1.19x | 15.9% | 20.2% |
| `1.0_to_1.5|surrounded/wide` | 113 | 0.0% | 127 | 30 | 23.6% | 1.01x | 12.2% | 16.1% |
| `1.5_to_2.0|one_sided/compact` | 0 | 0.0% | 90 | 20 | 22.2% | 0.95x | 8.1% | 11.9% |
| `1.5_to_2.0|one_sided/moderate` | 3 | 0.0% | 60 | 15 | 25.0% | 1.07x | 6.1% | 9.8% |
| `1.5_to_2.0|one_sided/wide` | 2 | 0.0% | 23 | 6 | 26.1% | 1.11x | 2.4% | 4.5% |
| `1.5_to_2.0|surrounded/moderate` | 24 | 0.0% | 88 | 18 | 20.5% | 0.87x | 7.3% | 10.8% |
| `1.5_to_2.0|surrounded/wide` | 124 | 0.0% | 59 | 12 | 20.3% | 0.87x | 4.9% | 7.9% |
| `2.0_to_3.0|one_sided/compact` | 0 | 0.0% | 12 | 2 | 16.7% | 0.71x | 0.8% | 1.6% |
| `2.0_to_3.0|one_sided/moderate` | 0 | 0.0% | 8 | 1 | 12.5% | 0.53x | 0.4% | 0.8% |
| `2.0_to_3.0|surrounded/compact` | 0 | 0.0% | 8 | 2 | 25.0% | 1.07x | 0.8% | 1.6% |
| `2.0_to_3.0|surrounded/moderate` | 4 | 0.0% | 12 | 3 | 25.0% | 1.07x | 1.2% | 2.3% |
| `2.0_to_3.0|surrounded/wide` | 24 | 0.0% | 0 | 0 | 0.0% | 0.00x | 0.0% | 0.0% |

## Decision

- This report remains diagnostic-only. It uses truth-defined labels only to score proxy candidates; the candidate features themselves are limited to production-available evidence and support-shape signals.
- It does not tune PLUM, suppress predictions, or authorize production UI/wording/notification changes.

