# HYP vs EQuake reference comparison

- Schema: `source_hyp_equake_reference_comparison_v1`
- Status: `pass`
- Reference-only / not truth: `true` / `true`
- Cases: `3`
- HYP benchmark matched: `2`
- Current capture matched: `1`

| Case | EQ final | Catalog error | EQ P/S/O | HYP case | JQ-EQ | JQ P/S/O | Current case | Current-EQ | Findings |
|---|---|---:|---|---|---:|---|---|---:|---|
| `equake_20260630_iwate_offshore_m38_report17` | 40.30, 142.53 / 13km | 11.4 | 58/37/18 | -- | -- | -- | -- | -- | missing_hyp_benchmark, equake_progression_p_only_to_mixed |
| `equake_20260630_fukushima_hamadori_m36_report10` | 37.35, 140.97 / 67km | 3.0 | 33/75/21 | `20260630_fukushima_hamadori_m35_hinet_equake10` | 134.7 | 12/0/0 | `20260630_fukushima_hamadori_m34` | 59.3 | matched_hyp_benchmark, matched_current_capture, jq_scoring_far_from_equake_40km, hyp_benchmark_low_decoded_frame_coverage, equake_s_rich_final, current_capture_far_from_equake_40km, equake_progression_p_only_to_mixed |
| `equake_20260622_tomakomai_south_offshore_m29_report10` | 42.14, 141.22 / 118km | 13.5 | 10/33/6 | `20260622_tomakomai_south_offshore_m35_hinet` | 4.4 | 0/13/1 | -- | -- | matched_hyp_benchmark, jq_scoring_near_equake_10km, jq_scoring_zero_p_against_equake_p_support, equake_s_rich_final |

## Findings

- `some_equake_references_need_hyp_benchmark_replay`
- `phase_origin_assignment_needs_p_support_recovery`
- `current_capture_production_estimate_has_large_reference_gap`
- `some_hyp_benchmarks_have_low_decoded_frame_coverage`
- `reference_only_do_not_promote_to_truth`
- `diagnostic_only_do_not_promote_to_production_coordinates`
