# HYP JMA2001 experiment report

- Schema: `source_hyp_jma2001_experiment_report_v1`
- Status: `pass`
- Diagnostic only: `true`
- Cases: `5`
- JMA2001 diagnostic present: `5`
- JQ scoring diagnostic present: `5`
- Baseline/JMA/JQ supported: `2` / `2` / `2`
- Median baseline/JMA/JQ HYP error: `6.9` / `6.9` / `36.7` km

| Case | Hybrid | HYP fixed | HYP JMA2001 | HYP JQ | JMA-fixed | JQ-fixed | Fixed supported | JMA supported | JQ supported | Fixed P/S/O | JMA P/S/O | JQ P/S/O | Fixed residual | JMA residual | JQ residual | Finding |
|---|---:|---:|---:|---:|---:|---:|---|---|---|---|---|---|---:|---:|---:|---|
| `20260622_iwate_east_offshore_m30_hinet` | 16.0 | 6.2 | 4.7 | 4.6 | -1.5 | -1.6 | false | false | true | 3/9/2 | 3/10/1 | 3/11/0 | 1.0 | 0.8 | 0.7 | jma2001_near_baseline_hyp, jma2001_low_error_candidate, jq_scoring_near_baseline_hyp, jq_scoring_gains_supported_case, jq_scoring_low_error_candidate |
| `20260622_kushiro_offshore_m30_jma` | 13.0 | 6.9 | 6.9 | 23.5 | 0.0 | 16.6 | true | true | false | 4/5/0 | 4/5/0 | 8/0/1 | 0.6 | 0.7 | 1.9 | jma2001_near_baseline_hyp, jma2001_low_error_candidate, jq_scoring_regresses_hyp_by_10km, jq_scoring_loses_supported_case |
| `20260622_tomakomai_south_offshore_m35_hinet` | 33.0 | 79.1 | 79.1 | 79.1 | 0.0 | 0.0 | false | false | true | 8/2/0 | 8/2/0 | 8/2/0 | 0.8 | 0.8 | 0.5 | jma2001_near_baseline_hyp, jq_scoring_near_baseline_hyp, jq_scoring_gains_supported_case, jq_scoring_supported_large_error |
| `20260622_wakayama_south_m25_hinet` | 3.0 | 1.5 | 1.5 | 36.7 | 0.0 | 35.1 | true | true | false | 3/8/0 | 3/8/0 | 9/0/2 | 0.4 | 0.4 | 1.6 | jma2001_near_baseline_hyp, jma2001_low_error_candidate, jq_scoring_regresses_hyp_by_10km, jq_scoring_loses_supported_case |
| `20260630_fukushima_hamadori_m35_hinet_equake10` | 61.0 | 118.1 | 118.1 | 136.9 | 0.0 | 18.8 | false | false | false | 9/0/3 | 9/0/3 | 12/0/0 | 1.1 | 1.1 | 0.4 | low_decoded_frame_coverage, jma2001_near_baseline_hyp, jq_scoring_regresses_hyp_by_10km |

## Findings

- `jq_scoring_regresses_some_hyp_candidates`
- `some_reports_have_low_decoded_frame_coverage`
- `jq_scoring_support_gate_allows_large_error_case`
- `diagnostic_only_do_not_promote`
