# PLUM Tohoku Propagation-Shape Diagnostic

- Status: `pass`
- Method: `PLUM Tohoku strong-nearby-evidence propagation-shape diagnostic`
- Frozen test evaluated: `true`
- Production ready: `false`
- Production UI connected: `false`
- Diagnostic only: `true`
- Parameters tuned: `false`
- Suppression applied: `false`
- Raw predicted intensity mutated: `false`

## Coverage

| Split | Variants | Station forecasts |
| --- | ---: | ---: |
| validation | 2688 | 185694 |
| test | 2757 | 179844 |

## Focus Filter

- Estimated-source region: `tohoku`
- Minimum evidence count: `8`
- Maximum nearest evidence distance: `10.0 km`
- Minimum prediction margin: `1.0 shindo`
- Neighbor windows: `[10.0, 20.0]`
- Supporting evidence definition: observed station within 30 km whose propagated contribution alone crosses the target threshold

## `shindo4`

### Focus Summary

| Split | Focus samples | TP | FP | Precision | PLUM-only FP |
| --- | ---: | ---: | ---: | ---: | ---: |
| validation | 457 | 389 | 68 | 85.1% | 0 |
| test | 1051 | 458 | 593 | 43.6% | 549 |

### Feature Aggregates

| Split | Outcome | Samples | Strongest Evidence | Actual | Gap | Below@10km | Below@20km | Support Count | Quadrants | Centroid Offset | Mean Dist | Max Spread |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| validation | truePositive | 389 | 5.35 | 4.98 | 0.36 | 10.2% | 11.7% | 13.93 | 3.40 | 7.77 | 16.35 | 42.55 |
| validation | falsePositive | 68 | 5.27 | 1.11 | 4.17 | 34.0% | 33.9% | 13.09 | 3.13 | 7.93 | 15.55 | 37.29 |
| test | truePositive | 458 | 5.52 | 4.67 | 0.85 | 55.3% | 55.6% | 12.88 | 2.28 | 10.53 | 16.55 | 28.15 |
| test | falsePositive | 593 | 5.50 | 1.66 | 3.84 | 56.0% | 56.6% | 12.83 | 2.31 | 10.24 | 16.36 | 28.43 |

### False-Positive Examples

| Split | Event | Variant | Station | PLUM | Actual | Gap | Below@10km | Support Count | Quadrants | Max Spread | PLUM-only |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| validation | `2021021323075051-37.7288-141.6985` | `2021021323075051-37.7288-141.6985_mask_50pct` | `2210820` | 5.17 | 0.50 | 5.50 | 20.0% | 12.00 | 4.00 | 50.73 | false |
| validation | `2021021323075051-37.7288-141.6985` | `2021021323075051-37.7288-141.6985_mask_20pct` | `2210820` | 5.17 | 0.50 | 5.50 | 20.0% | 17.00 | 4.00 | 50.73 | false |
| validation | `2021021323075051-37.7288-141.6985` | `2021021323075051-37.7288-141.6985_mask_20pct` | `2504932` | 5.23 | 0.60 | 5.30 | 0.0% | 19.00 | 4.00 | 55.72 | false |
| validation | `2021021323075051-37.7288-141.6985` | `2021021323075051-37.7288-141.6985_mask_20pct` | `2511132` | 5.54 | 0.70 | 5.30 | 33.3% | 18.00 | 4.00 | 55.77 | false |
| validation | `2021021323075051-37.7288-141.6985` | `2021021323075051-37.7288-141.6985_mask_50pct` | `2511132` | 5.54 | 0.70 | 5.30 | 33.3% | 9.00 | 4.00 | 48.67 | false |
| validation | `2021021323075051-37.7288-141.6985` | `2021021323075051-37.7288-141.6985_mask_50pct` | `2511535` | 4.65 | 0.70 | 5.30 | 25.0% | 3.00 | 2.00 | 48.39 | false |
| validation | `2021021323075051-37.7288-141.6985` | `2021021323075051-37.7288-141.6985_mask_20pct` | `2510900` | 5.40 | 0.50 | 5.10 | 50.0% | 14.00 | 4.00 | 54.72 | false |
| validation | `2021021323075051-37.7288-141.6985` | `2021021323075051-37.7288-141.6985_mask_20pct` | `2504734` | 4.94 | 0.50 | 5.00 | 33.3% | 16.00 | 4.00 | 56.98 | false |
| test | `2022031623342701-37.6810-141.6062` | `2022031623342701-37.6810-141.6062_mask_50pct` | `2205631` | 4.97 | 0.60 | 5.40 | 52.2% | 4.00 | 1.00 | 0.00 | false |
| test | `2022031623342701-37.6810-141.6062` | `2022031623342701-37.6810-141.6062_mask_50pct` | `2205731` | 4.69 | 0.60 | 5.40 | 51.9% | 6.00 | 2.00 | 49.99 | true |
| test | `2022031623342701-37.6810-141.6062` | `2022031623342701-37.6810-141.6062_mask_50pct` | `2205731` | 4.69 | 0.60 | 5.40 | 51.9% | 6.00 | 2.00 | 49.99 | true |
| test | `2022031623342701-37.6810-141.6062` | `2022031623342701-37.6810-141.6062_mask_50pct` | `2205730` | 5.06 | 0.70 | 5.30 | 58.3% | 8.00 | 1.00 | 11.94 | true |
| test | `2022031623342701-37.6810-141.6062` | `2022031623342701-37.6810-141.6062_mask_20pct` | `2205730` | 5.06 | 0.70 | 5.30 | 58.3% | 12.00 | 2.00 | 19.41 | true |
| test | `2022031623342701-37.6810-141.6062` | `2022031623342701-37.6810-141.6062_mask_50pct` | `2205700` | 4.91 | 0.70 | 5.30 | 55.6% | 8.00 | 1.00 | 11.94 | true |
| test | `2022031623342701-37.6810-141.6062` | `2022031623342701-37.6810-141.6062_mask_50pct` | `2200730` | 4.52 | 0.70 | 5.30 | 52.4% | 4.00 | 1.00 | 0.00 | true |
| test | `2022031623342701-37.6810-141.6062` | `2022031623342701-37.6810-141.6062_mask_20pct` | `2205338` | 5.36 | 0.70 | 5.30 | 45.5% | 16.00 | 3.00 | 45.59 | true |

## `shindo5-`

### Focus Summary

| Split | Focus samples | TP | FP | Precision | PLUM-only FP |
| --- | ---: | ---: | ---: | ---: | ---: |
| validation | 28 | 26 | 2 | 92.9% | 0 |
| test | 40 | 10 | 30 | 25.0% | 30 |

### Feature Aggregates

| Split | Outcome | Samples | Strongest Evidence | Actual | Gap | Below@10km | Below@20km | Support Count | Quadrants | Centroid Offset | Mean Dist | Max Spread |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| validation | truePositive | 26 | 5.80 | 5.37 | 0.43 | 6.7% | 12.6% | 5.04 | 2.50 | 6.56 | 9.41 | 17.17 |
| validation | falsePositive | 2 | 6.00 | 0.70 | 5.30 | 33.3% | 22.2% | 4.50 | 2.00 | 10.42 | 14.33 | 25.82 |
| test | truePositive | 10 | 6.00 | 5.54 | 0.46 | 73.2% | 73.6% | 9.20 | 1.80 | 6.85 | 9.89 | 16.80 |
| test | falsePositive | 30 | 6.00 | 2.21 | 3.79 | 73.2% | 73.6% | 9.20 | 1.80 | 6.85 | 9.89 | 16.80 |

### False-Positive Examples

| Split | Event | Variant | Station | PLUM | Actual | Gap | Below@10km | Support Count | Quadrants | Max Spread | PLUM-only |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| validation | `2021021323075051-37.7288-141.6985` | `2021021323075051-37.7288-141.6985_mask_20pct` | `2511132` | 5.54 | 0.70 | 5.30 | 33.3% | 5.00 | 2.00 | 28.14 | false |
| validation | `2021021323075051-37.7288-141.6985` | `2021021323075051-37.7288-141.6985_mask_50pct` | `2511132` | 5.54 | 0.70 | 5.30 | 33.3% | 4.00 | 2.00 | 23.50 | false |
| test | `2022031623342701-37.6810-141.6062` | `2022031623342701-37.6810-141.6062_mask_20pct` | `2205337` | 5.53 | 0.90 | 5.10 | 75.0% | 8.00 | 2.00 | 11.94 | true |
| test | `2022031623342701-37.6810-141.6062` | `2022031623342701-37.6810-141.6062_mask_50pct` | `2205337` | 5.53 | 0.90 | 5.10 | 75.0% | 8.00 | 2.00 | 11.94 | true |
| test | `2022031623342701-37.6810-141.6062` | `2022031623342701-37.6810-141.6062_mask_20pct` | `2205239` | 5.56 | 1.10 | 4.90 | 75.0% | 12.00 | 2.00 | 28.14 | true |
| test | `2022031623342701-37.6810-141.6062` | `2022031623342701-37.6810-141.6062_mask_50pct` | `2205239` | 5.56 | 1.10 | 4.90 | 75.0% | 8.00 | 1.00 | 11.94 | true |
| test | `2022031623342701-37.6810-141.6062` | `2022031623342701-37.6810-141.6062_mask_20pct` | `2205336` | 5.88 | 1.30 | 4.70 | 73.7% | 12.00 | 2.00 | 28.14 | true |
| test | `2022031623342701-37.6810-141.6062` | `2022031623342701-37.6810-141.6062_mask_50pct` | `2205336` | 5.88 | 1.30 | 4.70 | 73.7% | 8.00 | 2.00 | 11.94 | true |
| test | `2022031623342701-37.6810-141.6062` | `2022031623342701-37.6810-141.6062_mask_20pct` | `2205300` | 5.60 | 1.30 | 4.70 | 73.7% | 8.00 | 2.00 | 11.94 | true |
| test | `2022031623342701-37.6810-141.6062` | `2022031623342701-37.6810-141.6062_mask_50pct` | `2205300` | 5.60 | 1.30 | 4.70 | 73.7% | 8.00 | 2.00 | 11.94 | true |

## Decision

- This report stays diagnostic-only. It does not tune PLUM, suppress predictions, or authorize production UI/wording/notification changes.
- Use this drilldown to decide whether the next step should be non-suppressive robustness scoring or a region-specific calibration, not a hard gate.

