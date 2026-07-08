# PLUM Tohoku Middle-Transition Local-Mismatch-Ramp Diagnostic

- Status: `pass`
- Method: `PLUM Tohoku middle-transition local-mismatch-ramp diagnostic`
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

- Base weights: concentration `0.400`, spreadVariance `0.350`, plumMargin `0.250`.
- Local mismatch ramp: `clamp((localBelowThresholdShare10Km - 0.25) / 0.25, 0, 1)`.
- Adjusted score: `runtimeScore * localMismatchRamp`.

## Test Outcome Means

| Variant | Outcome | Local Ramp | Score |
| --- | --- | ---: | ---: |
| `base` | `middleTransitionZone` | 1.000 | 0.631 |
| `base` | `otherFocusSamples` | 0.986 | 0.616 |
| `adjusted` | `middleTransitionZone` | 1.000 | 0.631 |
| `adjusted` | `otherFocusSamples` | 0.986 | 0.607 |

## Comparison Summary

- Base top-to-bottom lift: `1.16x`; adjusted: `1.26x`.
- Lift delta: `+0.105`.
- Base decreasing pairs: `3`; adjusted: `3`.
- Decreasing-pair improvement: `+0.000`.

## `base` Validation-Anchored Band Transfer

| Band | Val Samples | Val Share | Test Samples | Test Share | Test Middle | Test Rate | Lift | Capture Share |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `low` | 116 | 25.4% | 424 | 40.3% | 95 | 22.4% | 0.96x | 38.6% |
| `mid_low` | 113 | 24.7% | 304 | 28.9% | 66 | 21.7% | 0.93x | 26.8% |
| `mid_high` | 114 | 24.9% | 129 | 12.3% | 34 | 26.4% | 1.13x | 13.8% |
| `high` | 114 | 24.9% | 194 | 18.5% | 51 | 26.3% | 1.12x | 20.7% |

## `base` Test Deciles

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

## `base` Monotonicity

- Top decile rate: `26.4%`; bottom decile rate: `22.9%`.
- Top-to-bottom lift: `1.16x`.
- Non-decreasing adjacent pairs: `6`; decreasing pairs: `3`.

## `adjusted` Validation-Anchored Band Transfer

| Band | Val Samples | Val Share | Test Samples | Test Share | Test Middle | Test Rate | Lift | Capture Share |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `low` | 339 | 74.2% | 0 | 0.0% | 0 | 0.0% | 0.00x | 0.0% |
| `mid_low` | 0 | 0.0% | 0 | 0.0% | 0 | 0.0% | 0.00x | 0.0% |
| `mid_high` | 4 | 0.9% | 0 | 0.0% | 0 | 0.0% | 0.00x | 0.0% |
| `high` | 114 | 24.9% | 1051 | 100.0% | 246 | 23.4% | 1.00x | 100.0% |

## `adjusted` Test Deciles

| Decile | Score Min | Score Max | Samples | Middle | Rate | Capture Share |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.161 | 0.325 | 105 | 22 | 21.0% | 8.9% |
| 2 | 0.325 | 0.419 | 105 | 24 | 22.9% | 9.8% |
| 3 | 0.419 | 0.467 | 105 | 19 | 18.1% | 7.7% |
| 4 | 0.467 | 0.545 | 105 | 21 | 20.0% | 8.5% |
| 5 | 0.546 | 0.594 | 105 | 24 | 22.9% | 9.8% |
| 6 | 0.594 | 0.684 | 105 | 29 | 27.6% | 11.8% |
| 7 | 0.684 | 0.751 | 105 | 23 | 21.9% | 9.3% |
| 8 | 0.751 | 0.829 | 105 | 29 | 27.6% | 11.8% |
| 9 | 0.829 | 0.902 | 105 | 27 | 25.7% | 11.0% |
| 10 | 0.910 | 0.980 | 106 | 28 | 26.4% | 11.4% |

## `adjusted` Monotonicity

- Top decile rate: `26.4%`; bottom decile rate: `21.0%`.
- Top-to-bottom lift: `1.26x`.
- Non-decreasing adjacent pairs: `6`; decreasing pairs: `3`.

## Decision

- This report remains diagnostic-only. It checks whether multiplying the runtime score by a local-mismatch ramp materially improves ordering of the `shindo4` middle-transition regime.
- It does not tune PLUM, suppress predictions, or authorize production UI/wording/notification changes.

