# PLUM Tohoku Middle-Transition Runtime-Score Diagnostic

- Status: `pass`
- Method: `PLUM Tohoku middle-transition runtime-score diagnostic`
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

## Score Definition

- Weights: concentration `0.400`, spreadVariance `0.350`, plumMargin `0.250`.
- Validation anchors: q25 `0.576`, q50 `0.748`, q75 `0.839`.

## Test Outcome Score Means

| Outcome | Concentration | Spread Variance | PLUM Margin | Runtime Score |
| --- | ---: | ---: | ---: | ---: |
| `middleTransitionZone` | 0.822 | 0.385 | 0.673 | 0.631 |
| `otherFocusSamples` | 0.807 | 0.371 | 0.652 | 0.616 |

## Validation-Anchored Band Transfer

| Band | Val Samples | Val Share | Test Samples | Test Share | Test Middle | Test Rate | Lift | Capture Share |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `low` | 116 | 25.4% | 424 | 40.3% | 95 | 22.4% | 0.96x | 38.6% |
| `mid_low` | 113 | 24.7% | 304 | 28.9% | 66 | 21.7% | 0.93x | 26.8% |
| `mid_high` | 114 | 24.9% | 129 | 12.3% | 34 | 26.4% | 1.13x | 13.8% |
| `high` | 114 | 24.9% | 194 | 18.5% | 51 | 26.3% | 1.12x | 20.7% |

## Test Deciles

| Decile | Score Min | Score Max | Samples | Middle | Rate | Capture Share |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.161 | 0.335 | 105 | 24 | 22.9% | 9.8% |
| 2 | 0.335 | 0.422 | 105 | 24 | 22.9% | 9.8% |
| 3 | 0.426 | 0.482 | 105 | 21 | 20.0% | 8.5% |
| 4 | 0.482 | 0.573 | 105 | 25 | 23.8% | 10.2% |
| 5 | 0.575 | 0.604 | 105 | 21 | 20.0% | 8.5% |
| 6 | 0.604 | 0.690 | 105 | 25 | 23.8% | 10.2% |
| 7 | 0.690 | 0.751 | 105 | 24 | 22.9% | 9.8% |
| 8 | 0.753 | 0.829 | 105 | 27 | 25.7% | 11.0% |
| 9 | 0.829 | 0.902 | 105 | 27 | 25.7% | 11.0% |
| 10 | 0.910 | 0.980 | 106 | 28 | 26.4% | 11.4% |

## Monotonicity

- Top decile rate: `26.4%`; bottom decile rate: `22.9%`.
- Top-to-bottom lift: `1.16x`.
- Non-decreasing adjacent pairs: `6`; decreasing pairs: `3`.

## Decision

- This report remains diagnostic-only. It checks whether a small continuous runtime score is more useful than the prior discrete buckets for the `shindo4` middle-transition regime.
- It does not tune PLUM, suppress predictions, or authorize production UI/wording/notification changes.

