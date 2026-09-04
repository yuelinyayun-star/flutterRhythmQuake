# Combined Intensity Prediction Diagnostic

- Status: `pass`
- Split: `validation`
- Frozen test evaluated: `false`
- Production ready: `false`
- Production UI connected: `false`

## Method

- This compares four validation-only station prediction branches on the same synthetic-reveal validation variants.
- `p3_static_raw` is the existing static intensity inversion forecast.
- `jma_style_p3_source` applies the JMA-style PGV path using the P3-estimated source.
- `plum_like` propagates observed shaking from retained stations and does not use source latitude, longitude, depth or magnitude.
- `plum_like_r20_d0_50` and `plum_like_r30_d0_50` are replay-grid false-positive-control candidates. They are not production-selected.
- `max_jma_style_plum_like` takes the station-level maximum of the traditional and PLUM-like branches. It is diagnostic-only.

## Coverage

- Station forecasts: `185694`
- No-PLUM-prediction station rate (baseline): `5.3%`

## Summary

| Method | Cases | Max class MAE | Station MAE | Underestimate rate | Within 1 class |
| --- | ---: | ---: | ---: | ---: | ---: |
| `p3_static_raw` | 2688 | 0.61 | 0.67 | 52.8% | 92.7% |
| `jma_style_p3_source` | 2688 | 0.60 | 0.62 | 30.4% | 92.6% |
| `plum_like` | 2688 | 0.37 | 0.64 | 34.3% | 97.6% |
| `plum_like_r20_d0_50` | 2688 | 0.52 | 0.90 | 46.8% | 95.9% |
| `plum_like_r30_d0_50` | 2688 | 0.51 | 0.66 | 46.8% | 96.5% |
| `max_jma_style_plum_like` | 2688 | 0.42 | 0.63 | 16.5% | 96.0% |
| `max_jma_style_plum_like_r20_d0_50` | 2688 | 0.46 | 0.59 | 19.8% | 95.9% |
| `max_jma_style_plum_like_r30_d0_50` | 2688 | 0.46 | 0.59 | 19.8% | 95.9% |

## Threshold Comparison

| Threshold | P3 raw | P3 probability gate | JMA-style | PLUM baseline | PLUM r20/d0.50 | PLUM r30/d0.50 | max baseline | max r20/d0.50 | max r30/d0.50 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `shindo3` | 36.7% / 86.5% / 51.5% | 41.6% / 84.6% / 55.8% | 46.6% / 64.4% / 54.1% | 59.4% / 82.3% / 69.0% | 74.3% / 66.7% / 70.3% | 73.8% / 69.1% / 71.4% | 43.0% / 87.8% / 57.7% | 47.2% / 80.3% / 59.5% | 47.1% / 80.9% / 59.5% |
| `shindo4` | 28.3% / 88.6% / 42.9% | 55.1% / 63.6% / 59.0% | 56.7% / 51.2% / 53.8% | 57.4% / 78.9% / 66.5% | 69.6% / 60.7% / 64.8% | 69.7% / 62.8% / 66.1% | 49.8% / 83.1% / 62.3% | 56.0% / 72.1% / 63.1% | 56.0% / 72.6% / 63.2% |
| `shindo5-` | 17.2% / 74.9% / 27.9% | 33.3% / 71.1% / 45.3% | 83.8% / 8.5% / 15.4% | 43.8% / 67.4% / 53.1% | 58.0% / 44.1% / 50.1% | 58.1% / 45.5% / 51.0% | 44.0% / 68.0% / 53.4% | 58.6% / 45.6% / 51.3% | 58.7% / 47.0% / 52.2% |

## Decision

- Do not connect this report to production UI, notifications or warning wording.
- The `max(JMA-style, PLUM-like)` branch recovers high-shindo recall by construction, so it must be judged against false positives before any frozen-test decision.
- Next step: choose a diagnostic operating point by comparing the synthetic-reveal combined result with the real replay lead-time grid.

