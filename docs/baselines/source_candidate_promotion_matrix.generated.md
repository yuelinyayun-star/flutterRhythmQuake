# Source Candidate Promotion Report

Generated from early-frame reports in `.dart_tool\source_estimation_early_frame_report\matrix`. This report is diagnostic-only and does not change production source coordinates.

## Gate

- Production-available rule: accept a diagnostic candidate only when rank inversion or static attenuation scatter supports it.
- Hard reject: rank inversion and attenuation scatter both strongly regress.
- Travel-time RMS remains diagnostic-only because it worsens in both positive offshore cases and the Fukushima failure case.
- Delayed confirmation is also diagnostic-only: a rejected candidate is marked recoverable only if the same candidate area is accepted within 5 seconds and 30 km.
- Truth-error columns below are offline evaluation labels, not production inputs.

## Case Summary

| Case | Candidate frames | Accepted | Rejected | Offline improved | False accepts | Missed positives | Delayed recovered | Delayed false | Findings |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `20260610_nara_m36` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | `no_candidate_frames` |
| `20260620_gifu_hida_m28_ref` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | `no_candidate_frames` |
| `20260620_iwate_offshore_m34_ref` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | `no_candidate_frames` |
| `20260621_fukushima_offshore_m32_eq6` | 8 | 0 | 8 | 7 | 0 | 7 | 0 | 0 | `gate_rejects_all_candidate_frames`, `no_offline_false_accepts`, `offline_missed_positive_frames`, `dual_residual_regression_present` |
| `20260622_fukushima_offshore_m22_eq4` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | `no_candidate_frames` |
| `20260622_iwate_east_offshore_m30_hinet` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | `no_candidate_frames` |
| `20260622_iwate_offshore_m30_eq10` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | `no_candidate_frames` |
| `20260622_kushiro_offshore_m30_jma` | 8 | 5 | 3 | 8 | 0 | 3 | 3 | 0 | `no_offline_false_accepts`, `offline_missed_positive_frames` |
| `20260622_tomakomai_south_offshore_m35_hinet` | 3 | 3 | 0 | 3 | 0 | 0 | 0 | 0 | `gate_accepts_all_candidate_frames`, `no_offline_false_accepts` |
| `20260622_wakayama_south_m25_hinet` | 1 | 1 | 0 | 1 | 0 | 0 | 0 | 0 | `gate_accepts_all_candidate_frames`, `no_offline_false_accepts` |
| `20260623_tokachi_southeast_offshore_m34_hinet` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | `no_candidate_frames` |
| `20260624_fukushima_aizu_m32_jma_eq5` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | `no_candidate_frames` |
| `20260625_iwate_offshore_m32_jma` | 3 | 0 | 3 | 3 | 0 | 3 | 0 | 0 | `gate_rejects_all_candidate_frames`, `no_offline_false_accepts`, `offline_missed_positive_frames` |

## Candidate Frames

### 20260610_nara_m36

| Time | Base err | Cand err | Decision | Rank delta | Atten delta | Atten ratio | Travel ratio | Delayed confirm | Reason |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| -- | -- | -- | `no_candidate` | -- | -- | -- | -- | -- |

### 20260620_gifu_hida_m28_ref

| Time | Base err | Cand err | Decision | Rank delta | Atten delta | Atten ratio | Travel ratio | Delayed confirm | Reason |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| -- | -- | -- | `no_candidate` | -- | -- | -- | -- | -- |

### 20260620_iwate_offshore_m34_ref

| Time | Base err | Cand err | Decision | Rank delta | Atten delta | Atten ratio | Travel ratio | Delayed confirm | Reason |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| -- | -- | -- | `no_candidate` | -- | -- | -- | -- | -- |

### 20260621_fukushima_offshore_m32_eq6

| Time | Base err | Cand err | Decision | Rank delta | Atten delta | Atten ratio | Travel ratio | Delayed confirm | Reason |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| `2026-06-21T23:41:50.000` | 120.1 | 138.1 | `reject` | 0.000 | 0.088 | 1.28 | 3.99 | -- | `no_rank_or_attenuation_support` |
| `2026-06-21T23:41:51.000` | 306.8 | 136.7 | `reject` | 0.143 | 0.344 | 2.63 | 2.26 | -- | `no_rank_or_attenuation_support`, `rank_and_attenuation_regress_together` |
| `2026-06-21T23:41:52.000` | 310.5 | 132.3 | `reject` | 0.286 | 0.362 | 2.71 | 2.44 | -- | `no_rank_or_attenuation_support`, `rank_and_attenuation_regress_together` |
| `2026-06-21T23:41:53.000` | 310.5 | 132.3 | `reject` | 0.286 | 0.362 | 2.71 | 2.44 | -- | `no_rank_or_attenuation_support`, `rank_and_attenuation_regress_together` |
| `2026-06-21T23:41:54.000` | 310.5 | 132.3 | `reject` | 0.286 | 0.362 | 2.71 | 2.44 | -- | `no_rank_or_attenuation_support`, `rank_and_attenuation_regress_together` |
| `2026-06-21T23:41:55.000` | 312.7 | 131.1 | `reject` | 0.214 | 0.330 | 2.56 | 2.53 | -- | `no_rank_or_attenuation_support`, `rank_and_attenuation_regress_together` |
| `2026-06-21T23:41:56.000` | 312.7 | 131.1 | `reject` | 0.214 | 0.337 | 2.69 | 2.53 | -- | `no_rank_or_attenuation_support`, `rank_and_attenuation_regress_together` |
| `2026-06-21T23:41:57.000` | 312.7 | 131.3 | `reject` | 0.214 | 0.327 | 2.63 | 2.53 | -- | `no_rank_or_attenuation_support`, `rank_and_attenuation_regress_together` |

### 20260622_fukushima_offshore_m22_eq4

| Time | Base err | Cand err | Decision | Rank delta | Atten delta | Atten ratio | Travel ratio | Delayed confirm | Reason |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| -- | -- | -- | `no_candidate` | -- | -- | -- | -- | -- |

### 20260622_iwate_east_offshore_m30_hinet

| Time | Base err | Cand err | Decision | Rank delta | Atten delta | Atten ratio | Travel ratio | Delayed confirm | Reason |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| -- | -- | -- | `no_candidate` | -- | -- | -- | -- | -- |

### 20260622_iwate_offshore_m30_eq10

| Time | Base err | Cand err | Decision | Rank delta | Atten delta | Atten ratio | Travel ratio | Delayed confirm | Reason |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| -- | -- | -- | `no_candidate` | -- | -- | -- | -- | -- |

### 20260622_kushiro_offshore_m30_jma

| Time | Base err | Cand err | Decision | Rank delta | Atten delta | Atten ratio | Travel ratio | Delayed confirm | Reason |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| `2026-06-22T16:38:23.000` | 101.6 | 10.6 | `reject` | 0.067 | 0.285 | 1.41 | 1.72 | 4.0s / 13.9km | `no_rank_or_attenuation_support` |
| `2026-06-22T16:38:24.000` | 101.6 | 10.6 | `reject` | 0.067 | 0.285 | 1.41 | 1.72 | 3.0s / 13.9km | `no_rank_or_attenuation_support` |
| `2026-06-22T16:38:25.000` | 101.6 | 10.6 | `reject` | 0.067 | 0.285 | 1.41 | 1.72 | 2.0s / 13.9km | `no_rank_or_attenuation_support` |
| `2026-06-22T16:38:27.000` | 119.6 | 23.2 | `accept` | -0.267 | -0.138 | 0.80 | 1.67 | -- |  |
| `2026-06-22T16:38:28.000` | 136.3 | 22.5 | `accept` | -0.267 | -0.104 | 0.85 | 2.16 | -- |  |
| `2026-06-22T16:38:29.000` | 136.3 | 22.5 | `accept` | -0.267 | -0.104 | 0.85 | 2.16 | -- |  |
| `2026-06-22T16:38:30.000` | 139.2 | 24.1 | `accept` | -0.267 | -0.080 | 0.89 | 1.89 | -- |  |
| `2026-06-22T16:38:31.000` | 139.2 | 24.1 | `accept` | -0.267 | -0.078 | 0.89 | 1.88 | -- |  |

### 20260622_tomakomai_south_offshore_m35_hinet

| Time | Base err | Cand err | Decision | Rank delta | Atten delta | Atten ratio | Travel ratio | Delayed confirm | Reason |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| `2026-06-22T20:38:18.000` | 136.8 | 27.8 | `accept` | -0.462 | -0.253 | 0.43 | 2.25 | -- |  |
| `2026-06-22T20:38:19.000` | 136.8 | 27.8 | `accept` | -0.462 | -0.251 | 0.44 | 2.27 | -- |  |
| `2026-06-22T20:38:20.000` | 136.8 | 27.3 | `accept` | -0.462 | -0.176 | 0.60 | 2.60 | -- |  |

### 20260622_wakayama_south_m25_hinet

| Time | Base err | Cand err | Decision | Rank delta | Atten delta | Atten ratio | Travel ratio | Delayed confirm | Reason |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| `2026-06-22T09:51:34.000` | 158.0 | 16.5 | `accept` | 0.067 | -0.134 | 0.78 | 1.62 | -- |  |

### 20260623_tokachi_southeast_offshore_m34_hinet

| Time | Base err | Cand err | Decision | Rank delta | Atten delta | Atten ratio | Travel ratio | Delayed confirm | Reason |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| -- | -- | -- | `no_candidate` | -- | -- | -- | -- | -- |

### 20260624_fukushima_aizu_m32_jma_eq5

| Time | Base err | Cand err | Decision | Rank delta | Atten delta | Atten ratio | Travel ratio | Delayed confirm | Reason |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| -- | -- | -- | `no_candidate` | -- | -- | -- | -- | -- |

### 20260625_iwate_offshore_m32_jma

| Time | Base err | Cand err | Decision | Rank delta | Atten delta | Atten ratio | Travel ratio | Delayed confirm | Reason |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| `2026-06-25T19:21:57.000` | 143.9 | 23.8 | `reject` | 0.357 | 0.061 | 1.06 | 2.23 | -- | `no_rank_or_attenuation_support` |
| `2026-06-25T19:21:58.000` | 122.9 | 29.1 | `reject` | 0.333 | 0.088 | 1.09 | 2.02 | -- | `no_rank_or_attenuation_support` |
| `2026-06-25T19:21:59.000` | 122.9 | 30.0 | `reject` | 0.000 | 0.053 | 1.05 | 2.05 | -- | `no_rank_or_attenuation_support` |

## Validation

- Status: `pass`.
- Violations: none.

## Decision

- Accepted candidate cases: `20260622_kushiro_offshore_m30_jma`, `20260622_tomakomai_south_offshore_m35_hinet`, `20260622_wakayama_south_m25_hinet`.
- Offline missed-positive cases: `20260621_fukushima_offshore_m32_eq6`, `20260622_kushiro_offshore_m30_jma`, `20260625_iwate_offshore_m32_jma`.
- Missed-positive cases still not recovered by residual-only delayed confirmation: `20260621_fukushima_offshore_m32_eq6`, `20260625_iwate_offshore_m32_jma`.
- Residual-only delayed confirmation recovers pending candidates for: `20260622_kushiro_offshore_m30_jma`.
- Local-support delayed recovery is reported separately in `source_candidate_region_timeline.generated.md` so candidate-coordinate diagnostics and local member-growth diagnostics stay distinct.
- Offline false-accept cases: none.
- Candidate coordinates remain diagnostic-only. The refreshed matrix now shows that the gate is conservative enough to avoid false accepts, but residual-only promotion still misses real-positive patterns such as Iwate-style early one-sided candidates.
