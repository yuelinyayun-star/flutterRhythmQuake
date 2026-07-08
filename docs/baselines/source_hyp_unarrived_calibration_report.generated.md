# HYP unarrived-penalty calibration report

- Schema: `source_hyp_unarrived_calibration_report_v1`
- Status: `pass`
- Diagnostic only: `true`
- Recommended max unarrived penalty: `60.0`
- Reason: `max_supported_without_large_regression`

| Threshold | Supported | Depth supported | Improved | Regressed | Median HYP error | Median Δ | Verdict |
|---:|---:|---:|---:|---:|---:|---:|---|
| 0 | 0 | 0 | 0 | 0 | -- | -- | too_strict |
| 2 | 1 | 1 | 1 | 0 | 6.9 | -6.1 | safe |
| 5 | 2 | 2 | 2 | 0 | 4.2 | -3.8 | safe |
| 10 | 2 | 2 | 2 | 0 | 4.2 | -3.8 | safe |
| 20 | 2 | 2 | 2 | 0 | 4.2 | -3.8 | safe |
| 40 | 2 | 2 | 2 | 0 | 4.2 | -3.8 | safe |
| 60 | 3 | 3 | 3 | 0 | 4.0 | -5.0 | safe |
| 80 | 3 | 3 | 3 | 0 | 4.0 | -5.0 | safe |
| 120 | 4 | 3 | 3 | 1 | 5.4 | -3.2 | unsafe |
| 160 | 4 | 3 | 3 | 1 | 5.4 | -3.2 | unsafe |

## Findings

- `recommended_threshold_60`
- `high_thresholds_admit_regressed_hyp_candidates`
- `low_thresholds_are_too_strict`
- `calibration_is_gate_only_not_search_weight`
