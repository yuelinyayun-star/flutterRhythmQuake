# HYP scoring calibration report

- Schema: `source_hyp_scoring_calibration_report_v1`
- Status: `pass`
- Diagnostic only: `true`
- Historical GIF redownload: `false`

| Variant | Cases | Supported | Depth | Improved | Regressed | Median HYP | Median supported HYP | Median Δ | P-only final rows |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `baseline` | 4 | 3 | 3 | 3 | 1 | 5.4 | 4.0 | -3.2 | 0 |
| `unarrived_x2` | 4 | 2 | 2 | 2 | 1 | 12.1 | 4.2 | 3.4 | 0 |
| `unarrived_x4` | 4 | 2 | 2 | 2 | 1 | 12.1 | 4.2 | 3.4 | 0 |
| `shallow_bias` | 4 | 3 | 3 | 3 | 1 | 5.4 | 4.0 | -3.2 | 0 |

## Variant rows

### `baseline`

| Case | Hybrid final | HYP final | Δ | Supported | Depth | P/S/O | Residual | Pair | Unarrived | HYP depth | |
|---|---:|---:|---:|---|---|---|---:|---:|---:|---:|
| `20260622_iwate_east_offshore_m30_hinet` | 9.0 | 4.0 | -5.0 | true | true | 5/12/1 | 1.3 | 1.0 | 40.8 | 10 |
| `20260622_kushiro_offshore_m30_jma` | 13.0 | 6.9 | -6.1 | true | true | 4/5/0 | 0.6 | 1.0 | 1.4 | 40 |
| `20260622_tomakomai_south_offshore_m35_hinet` | 7.0 | 97.0 | 90.0 | false | false | 11/2/1 | 1.2 | 0.9 | 116.0 | 100 |
| `20260622_wakayama_south_m25_hinet` | 3.0 | 1.5 | -1.5 | true | true | 3/8/0 | 0.4 | 0.6 | 2.0 | 20 |

### `unarrived_x2`

| Case | Hybrid final | HYP final | Δ | Supported | Depth | P/S/O | Residual | Pair | Unarrived | HYP depth | |
|---|---:|---:|---:|---|---|---|---:|---:|---:|---:|
| `20260622_iwate_east_offshore_m30_hinet` | 9.0 | 17.3 | 8.3 | false | false | 2/7/9 | 2.9 | 1.0 | 21.2 | 10 |
| `20260622_kushiro_offshore_m30_jma` | 13.0 | 6.9 | -6.1 | true | true | 4/5/0 | 0.7 | 1.0 | 1.3 | 40 |
| `20260622_tomakomai_south_offshore_m35_hinet` | 7.0 | 184.6 | 177.6 | false | false | 0/2/12 | 23.1 | 0.5 | 4.7 | 10 |
| `20260622_wakayama_south_m25_hinet` | 3.0 | 1.5 | -1.5 | true | true | 3/8/0 | 0.4 | 0.6 | 2.0 | 20 |

### `unarrived_x4`

| Case | Hybrid final | HYP final | Δ | Supported | Depth | P/S/O | Residual | Pair | Unarrived | HYP depth | |
|---|---:|---:|---:|---|---|---|---:|---:|---:|---:|
| `20260622_iwate_east_offshore_m30_hinet` | 9.0 | 17.3 | 8.3 | false | false | 2/7/9 | 2.9 | 1.0 | 21.2 | 10 |
| `20260622_kushiro_offshore_m30_jma` | 13.0 | 6.9 | -6.1 | true | true | 4/5/0 | 0.7 | 1.0 | 1.3 | 40 |
| `20260622_tomakomai_south_offshore_m35_hinet` | 7.0 | 184.6 | 177.6 | false | false | 0/2/12 | 23.1 | 0.5 | 4.7 | 10 |
| `20260622_wakayama_south_m25_hinet` | 3.0 | 1.5 | -1.5 | true | true | 3/8/0 | 0.4 | 0.6 | 2.0 | 20 |

### `shallow_bias`

| Case | Hybrid final | HYP final | Δ | Supported | Depth | P/S/O | Residual | Pair | Unarrived | HYP depth | |
|---|---:|---:|---:|---|---|---|---:|---:|---:|---:|
| `20260622_iwate_east_offshore_m30_hinet` | 9.0 | 4.0 | -5.0 | true | true | 5/12/1 | 1.3 | 1.0 | 40.8 | 10 |
| `20260622_kushiro_offshore_m30_jma` | 13.0 | 6.9 | -6.1 | true | true | 4/5/0 | 0.6 | 1.0 | 1.4 | 40 |
| `20260622_tomakomai_south_offshore_m35_hinet` | 7.0 | 97.0 | 90.0 | false | false | 11/2/1 | 1.2 | 0.9 | 116.0 | 100 |
| `20260622_wakayama_south_m25_hinet` | 3.0 | 1.5 | -1.5 | true | true | 3/8/0 | 0.4 | 0.6 | 2.0 | 20 |

## Findings

- `best_non_regressing_variant_shallow_bias`
- `baseline_supported_count_3`
- `candidate_search_calibration_only`
- `keep_hyp_diagnostic_until_variant_beats_hybrid_reliably`
