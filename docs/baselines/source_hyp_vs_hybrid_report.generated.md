# Source HYP vs hybrid diagnostic report

- Schema: `source_hyp_vs_hybrid_report_v1`
- Diagnostic only: `true`
- Cases: `10`
- HYP supported: `3`
- HYP depth supported: `3`
- HYP P-only timing fits: `0`
- HYP improved final error: `4`

| Case | Hybrid final | HYP final | Δ final | HYP supported | P-only | Depth | P/S/O | Residual | Pair | Unarrived | Finding |
|---|---:|---:|---:|---|---|---:|---|---:|---:|---:|---|
| `20260620_iwate_offshore_m34_ref` | 63.0 | 103.8 | 40.8 | false | false | 100 | 1/7/9 | 3.2 | 1.2 | 128.0 | hyp_regresses_final_error, large_unarrived_penalty |
| `20260621_fukushima_offshore_m32_eq6` | 172.0 | 240.6 | 68.6 | false | false | 10 | 3/0/8 | 24.6 | 1.1 | 11.7 | hyp_regresses_final_error, no_s_support |
| `20260622_iwate_east_offshore_m30_hinet` | 9.0 | 4.0 | -5.0 | true | false | 10 | 5/12/1 | 1.3 | 1.0 | 40.8 | hyp_near_hybrid_final_error, hyp_supported, hyp_depth_supported, large_unarrived_penalty |
| `20260622_iwate_offshore_m30_eq10` | 30.0 | 24.4 | -5.6 | false | false | 40 | 1/9/3 | 1.3 | 0.8 | 17.7 | hyp_near_hybrid_final_error |
| `20260622_kushiro_offshore_m30_jma` | 13.0 | 6.9 | -6.1 | true | false | 40 | 4/5/0 | 0.6 | 1.0 | 1.4 | hyp_near_hybrid_final_error, hyp_supported, hyp_depth_supported |
| `20260622_tomakomai_south_offshore_m35_hinet` | 7.0 | 97.0 | 90.0 | false | false | 100 | 11/2/1 | 1.2 | 0.9 | 116.0 | hyp_regresses_final_error, large_unarrived_penalty |
| `20260622_wakayama_south_m25_hinet` | 3.0 | 1.5 | -1.5 | true | false | 20 | 3/8/0 | 0.4 | 0.6 | 2.0 | hyp_near_hybrid_final_error, hyp_supported, hyp_depth_supported |
| `20260623_tokachi_southeast_offshore_m34_hinet` | 74.0 | 218.5 | 144.5 | false | false | 100 | 2/1/6 | 5.2 | 0.7 | 66.7 | hyp_regresses_final_error, large_unarrived_penalty |
| `20260624_fukushima_aizu_m32_jma_eq5` | 14.0 | 182.2 | 168.2 | false | false | 10 | 2/0/4 | 25.3 | 0.1 | 13.0 | hyp_regresses_final_error, no_s_support |
| `20260625_iwate_offshore_m32_jma` | 19.0 | 215.4 | 196.4 | false | false | 10 | 1/0/9 | 34.2 | 0.0 | 4.9 | hyp_regresses_final_error, no_s_support |

## Findings

- `p_only_cases_must_not_promote_location`
- `unarrived_penalty_needs_calibration`
- `some_reference_cases_have_two_phase_depth_support`
