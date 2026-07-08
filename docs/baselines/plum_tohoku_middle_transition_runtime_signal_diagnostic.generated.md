# PLUM Tohoku Middle-Transition Runtime-Signal Diagnostic

- Status: `pass`
- Method: `PLUM Tohoku middle-transition runtime-signal diagnostic`
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

## Test Outcome Feature Means

| Outcome | Top1 Share | Top2 Share | HHI | Dominance Share Gap | Dominance Margin Gap | Margin StdDev | Margin Range | Mean Margin | Effective Support Count |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `middleTransitionZone` | 0.144 | 0.287 | 0.123 | 0.000 | 0.000 | 0.379 | 0.938 | 0.941 | 10.288 |
| `otherFocusSamples` | 0.148 | 0.295 | 0.127 | 0.000 | 0.000 | 0.376 | 0.926 | 0.970 | 9.898 |

## Ranked Runtime-Signal Candidates

| Family | Bucket | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score | Share Delta |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `dominanceShareGapBand` | `lt_0.05` | 1051 | 246 | 23.4% | 1.00x | 100.0% | 37.9% | +23.2pp |
| `dominanceMarginGapBand` | `lt_0.10` | 1051 | 246 | 23.4% | 1.00x | 100.0% | 37.9% | +59.1pp |
| `topContributionShareBand` | `lt_0.20` | 831 | 197 | 23.7% | 1.01x | 80.1% | 36.6% | +9.0pp |
| `meanContributionMarginBand` | `gte_0.60` | 946 | 218 | 23.0% | 0.98x | 88.6% | 36.6% | +23.5pp |
| `top2ContributionShareBand` | `lt_0.35` | 793 | 188 | 23.7% | 1.01x | 76.4% | 36.2% | +7.6pp |
| `effectiveSupportCountBand` | `gte_8` | 625 | 153 | 24.5% | 1.05x | 62.2% | 35.1% | -7.9pp |
| `contributionHhiBand` | `lt_0.10` | 450 | 112 | 24.9% | 1.06x | 45.5% | 32.2% | -7.1pp |
| `marginRangeBand` | `gte_1.00` | 500 | 119 | 23.8% | 1.02x | 48.4% | 31.9% | -35.4pp |
| `marginStdDevBand` | `0.30_to_0.50` | 399 | 100 | 25.1% | 1.07x | 40.7% | 31.0% | -37.3pp |
| `marginStdDevBand|plumMarginBand` | `0.30_to_0.50|1.0_to_1.5` | 325 | 86 | 26.5% | 1.13x | 35.0% | 30.1% | -17.0pp |
| `contributionHhiBand|plumMarginBand` | `lt_0.10|1.0_to_1.5` | 308 | 82 | 26.6% | 1.14x | 33.3% | 29.6% | +2.6pp |
| `contributionHhiBand` | `0.10_to_0.14` | 344 | 76 | 22.1% | 0.94x | 30.9% | 25.8% | +7.6pp |
| `marginStdDevBand` | `gte_0.50` | 306 | 69 | 22.5% | 0.96x | 28.0% | 25.0% | +16.4pp |
| `topContributionShareBand|geometrySpread` | `lt_0.20|surrounded/moderate` | 240 | 60 | 25.0% | 1.07x | 24.4% | 24.7% | +3.8pp |
| `marginRangeBand` | `0.60_to_1.00` | 275 | 64 | 23.3% | 0.99x | 26.0% | 24.6% | +11.3pp |
| `effectiveSupportCountBand` | `4_to_6` | 216 | 47 | 21.8% | 0.93x | 19.1% | 20.3% | +9.2pp |
| `marginStdDevBand|plumMarginBand` | `gte_0.50|1.5_to_2.0` | 198 | 45 | 22.7% | 0.97x | 18.3% | 20.3% | +10.7pp |
| `topContributionShareBand|geometrySpread` | `lt_0.20|one_sided/moderate` | 186 | 43 | 23.1% | 0.99x | 17.5% | 19.9% | +16.8pp |
| `effectiveSupportCountBand` | `6_to_8` | 198 | 44 | 22.2% | 0.95x | 17.9% | 19.8% | +5.5pp |
| `contributionHhiBand` | `gte_0.20` | 181 | 42 | 23.2% | 0.99x | 17.1% | 19.7% | +5.0pp |

## `topContributionShareBand`

| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `0.20_to_0.25` | 48 | 0.0% | 77 | 19 | 24.7% | 1.05x | 7.7% | 11.8% |
| `0.25_to_0.33` | 39 | 0.0% | 135 | 28 | 20.7% | 0.89x | 11.4% | 14.7% |
| `gte_0.33` | 50 | 0.0% | 8 | 2 | 25.0% | 1.07x | 0.8% | 1.6% |
| `lt_0.20` | 320 | 0.0% | 831 | 197 | 23.7% | 1.01x | 80.1% | 36.6% |

## `top2ContributionShareBand`

| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `0.35_to_0.45` | 63 | 0.0% | 69 | 16 | 23.2% | 0.99x | 6.5% | 10.2% |
| `0.45_to_0.60` | 45 | 0.0% | 169 | 38 | 22.5% | 0.96x | 15.4% | 18.3% |
| `gte_0.60` | 39 | 0.0% | 20 | 4 | 20.0% | 0.85x | 1.6% | 3.0% |
| `lt_0.35` | 310 | 0.0% | 793 | 188 | 23.7% | 1.01x | 76.4% | 36.2% |

## `contributionHhiBand`

| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `0.10_to_0.14` | 115 | 0.0% | 344 | 76 | 22.1% | 0.94x | 30.9% | 25.8% |
| `0.14_to_0.20` | 58 | 0.0% | 76 | 16 | 21.1% | 0.90x | 6.5% | 9.9% |
| `gte_0.20` | 56 | 0.0% | 181 | 42 | 23.2% | 0.99x | 17.1% | 19.7% |
| `lt_0.10` | 228 | 0.0% | 450 | 112 | 24.9% | 1.06x | 45.5% | 32.2% |

## `dominanceShareGapBand`

| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `0.05_to_0.10` | 56 | 0.0% | 0 | 0 | 0.0% | 0.00x | 0.0% | 0.0% |
| `0.10_to_0.20` | 32 | 0.0% | 0 | 0 | 0.0% | 0.00x | 0.0% | 0.0% |
| `gte_0.20` | 18 | 0.0% | 0 | 0 | 0.0% | 0.00x | 0.0% | 0.0% |
| `lt_0.05` | 351 | 0.0% | 1051 | 246 | 23.4% | 1.00x | 100.0% | 37.9% |

## `dominanceMarginGapBand`

| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `0.10_to_0.20` | 91 | 0.0% | 0 | 0 | 0.0% | 0.00x | 0.0% | 0.0% |
| `0.20_to_0.40` | 89 | 0.0% | 0 | 0 | 0.0% | 0.00x | 0.0% | 0.0% |
| `gte_0.40` | 90 | 0.0% | 0 | 0 | 0.0% | 0.00x | 0.0% | 0.0% |
| `lt_0.10` | 187 | 0.0% | 1051 | 246 | 23.4% | 1.00x | 100.0% | 37.9% |

## `marginStdDevBand`

| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `0.15_to_0.30` | 55 | 0.0% | 150 | 36 | 24.0% | 1.03x | 14.6% | 18.2% |
| `0.30_to_0.50` | 344 | 0.0% | 399 | 100 | 25.1% | 1.07x | 40.7% | 31.0% |
| `gte_0.50` | 58 | 0.0% | 306 | 69 | 22.5% | 0.96x | 28.0% | 25.0% |
| `lt_0.15` | 0 | 0.0% | 196 | 41 | 20.9% | 0.89x | 16.7% | 18.6% |

## `marginRangeBand`

| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `0.30_to_0.60` | 10 | 0.0% | 96 | 26 | 27.1% | 1.16x | 10.6% | 15.2% |
| `0.60_to_1.00` | 68 | 0.0% | 275 | 64 | 23.3% | 0.99x | 26.0% | 24.6% |
| `gte_1.00` | 379 | 0.0% | 500 | 119 | 23.8% | 1.02x | 48.4% | 31.9% |
| `lt_0.30` | 0 | 0.0% | 180 | 37 | 20.6% | 0.88x | 15.0% | 17.4% |

## `meanContributionMarginBand`

| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `0.25_to_0.40` | 26 | 0.0% | 10 | 2 | 20.0% | 0.85x | 0.8% | 1.6% |
| `0.40_to_0.60` | 127 | 0.0% | 95 | 26 | 27.4% | 1.17x | 10.6% | 15.2% |
| `gte_0.60` | 304 | 0.0% | 946 | 218 | 23.0% | 0.98x | 88.6% | 36.6% |

## `effectiveSupportCountBand`

| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `4_to_6` | 52 | 0.0% | 216 | 47 | 21.8% | 0.93x | 19.1% | 20.3% |
| `6_to_8` | 61 | 0.0% | 198 | 44 | 22.2% | 0.95x | 17.9% | 19.8% |
| `gte_8` | 308 | 0.0% | 625 | 153 | 24.5% | 1.05x | 62.2% | 35.1% |
| `lt_4` | 36 | 0.0% | 12 | 2 | 16.7% | 0.71x | 0.8% | 1.6% |

## `topContributionShareBand|geometrySpread`

| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `0.20_to_0.25|one_sided/compact` | 0 | 0.0% | 10 | 3 | 30.0% | 1.28x | 1.2% | 2.3% |
| `0.20_to_0.25|one_sided/moderate` | 5 | 0.0% | 55 | 13 | 23.6% | 1.01x | 5.3% | 8.6% |
| `0.20_to_0.25|one_sided/wide` | 2 | 0.0% | 12 | 3 | 25.0% | 1.07x | 1.2% | 2.3% |
| `0.20_to_0.25|surrounded/moderate` | 21 | 0.0% | 0 | 0 | 0.0% | 0.00x | 0.0% | 0.0% |
| `0.20_to_0.25|surrounded/wide` | 20 | 0.0% | 0 | 0 | 0.0% | 0.00x | 0.0% | 0.0% |
| `0.25_to_0.33|one_sided/compact` | 3 | 0.0% | 103 | 23 | 22.3% | 0.95x | 9.3% | 13.2% |
| `0.25_to_0.33|one_sided/moderate` | 9 | 0.0% | 32 | 5 | 15.6% | 0.67x | 2.0% | 3.6% |
| `0.25_to_0.33|one_sided/wide` | 1 | 0.0% | 0 | 0 | 0.0% | 0.00x | 0.0% | 0.0% |
| `0.25_to_0.33|surrounded/moderate` | 9 | 0.0% | 0 | 0 | 0.0% | 0.00x | 0.0% | 0.0% |
| `0.25_to_0.33|surrounded/wide` | 17 | 0.0% | 0 | 0 | 0.0% | 0.00x | 0.0% | 0.0% |
| `gte_0.33|one_sided/compact` | 6 | 0.0% | 0 | 0 | 0.0% | 0.00x | 0.0% | 0.0% |
| `gte_0.33|one_sided/moderate` | 13 | 0.0% | 8 | 2 | 25.0% | 1.07x | 0.8% | 1.6% |
| `gte_0.33|one_sided/wide` | 2 | 0.0% | 0 | 0 | 0.0% | 0.00x | 0.0% | 0.0% |
| `gte_0.33|surrounded/compact` | 5 | 0.0% | 0 | 0 | 0.0% | 0.00x | 0.0% | 0.0% |
| `gte_0.33|surrounded/moderate` | 18 | 0.0% | 0 | 0 | 0.0% | 0.00x | 0.0% | 0.0% |
| `gte_0.33|surrounded/wide` | 6 | 0.0% | 0 | 0 | 0.0% | 0.00x | 0.0% | 0.0% |
| `lt_0.20|one_sided/compact` | 6 | 0.0% | 152 | 37 | 24.3% | 1.04x | 15.0% | 18.6% |
| `lt_0.20|one_sided/moderate` | 4 | 0.0% | 186 | 43 | 23.1% | 0.99x | 17.5% | 19.9% |
| `lt_0.20|one_sided/wide` | 3 | 0.0% | 43 | 10 | 23.3% | 0.99x | 4.1% | 6.9% |
| `lt_0.20|surrounded/compact` | 2 | 0.0% | 24 | 5 | 20.8% | 0.89x | 2.0% | 3.7% |
| `lt_0.20|surrounded/moderate` | 87 | 0.0% | 240 | 60 | 25.0% | 1.07x | 24.4% | 24.7% |
| `lt_0.20|surrounded/wide` | 218 | 0.0% | 186 | 42 | 22.6% | 0.96x | 17.1% | 19.4% |

## `contributionHhiBand|plumMarginBand`

| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `0.10_to_0.14|1.0_to_1.5` | 61 | 0.0% | 181 | 41 | 22.7% | 0.97x | 16.7% | 19.2% |
| `0.10_to_0.14|1.5_to_2.0` | 46 | 0.0% | 143 | 31 | 21.7% | 0.93x | 12.6% | 15.9% |
| `0.10_to_0.14|2.0_to_3.0` | 8 | 0.0% | 20 | 4 | 20.0% | 0.85x | 1.6% | 3.0% |
| `0.14_to_0.20|1.0_to_1.5` | 40 | 0.0% | 65 | 13 | 20.0% | 0.85x | 5.3% | 8.4% |
| `0.14_to_0.20|1.5_to_2.0` | 14 | 0.0% | 11 | 3 | 27.3% | 1.17x | 1.2% | 2.3% |
| `0.14_to_0.20|2.0_to_3.0` | 4 | 0.0% | 0 | 0 | 0.0% | 0.00x | 0.0% | 0.0% |
| `gte_0.20|1.0_to_1.5` | 53 | 0.0% | 137 | 31 | 22.6% | 0.97x | 12.6% | 16.2% |
| `gte_0.20|1.5_to_2.0` | 2 | 0.0% | 44 | 11 | 25.0% | 1.07x | 4.5% | 7.6% |
| `gte_0.20|2.0_to_3.0` | 1 | 0.0% | 0 | 0 | 0.0% | 0.00x | 0.0% | 0.0% |
| `lt_0.10|1.0_to_1.5` | 122 | 0.0% | 308 | 82 | 26.6% | 1.14x | 33.3% | 29.6% |
| `lt_0.10|1.5_to_2.0` | 91 | 0.0% | 122 | 26 | 21.3% | 0.91x | 10.6% | 14.1% |
| `lt_0.10|2.0_to_3.0` | 15 | 0.0% | 20 | 4 | 20.0% | 0.85x | 1.6% | 3.0% |

## `marginStdDevBand|plumMarginBand`

| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `0.15_to_0.30|1.0_to_1.5` | 55 | 0.0% | 122 | 30 | 24.6% | 1.05x | 12.2% | 16.3% |
| `0.15_to_0.30|1.5_to_2.0` | 0 | 0.0% | 20 | 4 | 20.0% | 0.85x | 1.6% | 3.0% |
| `0.15_to_0.30|2.0_to_3.0` | 0 | 0.0% | 8 | 2 | 25.0% | 1.07x | 0.8% | 1.6% |
| `0.30_to_0.50|1.0_to_1.5` | 219 | 0.0% | 325 | 86 | 26.5% | 1.13x | 35.0% | 30.1% |
| `0.30_to_0.50|1.5_to_2.0` | 116 | 0.0% | 70 | 14 | 20.0% | 0.85x | 5.7% | 8.9% |
| `0.30_to_0.50|2.0_to_3.0` | 9 | 0.0% | 4 | 0 | 0.0% | 0.00x | 0.0% | 0.0% |
| `gte_0.50|1.0_to_1.5` | 2 | 0.0% | 80 | 18 | 22.5% | 0.96x | 7.3% | 11.0% |
| `gte_0.50|1.5_to_2.0` | 37 | 0.0% | 198 | 45 | 22.7% | 0.97x | 18.3% | 20.3% |
| `gte_0.50|2.0_to_3.0` | 19 | 0.0% | 28 | 6 | 21.4% | 0.92x | 2.4% | 4.4% |
| `lt_0.15|1.0_to_1.5` | 0 | 0.0% | 164 | 33 | 20.1% | 0.86x | 13.4% | 16.1% |
| `lt_0.15|1.5_to_2.0` | 0 | 0.0% | 32 | 8 | 25.0% | 1.07x | 3.3% | 5.8% |

## Decision

- This report remains diagnostic-only. It scores runtime-visible support-contribution signals against a truth-defined middle-transition label without changing PLUM or any production behavior.
- It does not tune PLUM, suppress predictions, or authorize production UI/wording/notification changes.

