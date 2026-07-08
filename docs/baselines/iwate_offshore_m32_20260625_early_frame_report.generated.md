# 20260625_iwate_offshore_m32_jma Early Frame Report

Generated from `.dart_tool\source_estimation_benchmark\20260625_iwate_offshore_m32_jma.reference.json`.
This is diagnostic-only; no production estimator weights are changed.

- Case: `20260625_iwate_offshore_m32_jma`
- Method: `nied_gif_hybrid_v1`
- Early estimate frames: 10
- Findings: `one_sided_early_geometry`, `candidate_improves_all_candidate_frames`, `large_travel_time_residuals_do_not_uniquely_select_truth`

## Frame Summary

| # | Time | Err | Jump | Candidate err | Truth in bbox | Geometry | P90u | Travel RMS base/cand/truth | Rank inv base/cand/truth | Atten RMS base/cand/truth |
| ---: | --- | ---: | ---: | ---: | --- | --- | ---: | --- | --- | --- |
| 1 | 2026-06-25T19:21:57.000 | 144 km | - | 23.8 km | yes | one_sided | 273 km | 3.31 s / 7.37 s / 8.51 s | 14% / 50% / 36% | 0.95 / 1.01 / 0.89 |
| 2 | 2026-06-25T19:21:58.000 | 123 km | 23.0 km | 29.1 km | yes | one_sided | 234 km | 3.37 s / 6.83 s / 8.51 s | 20% / 53% / 40% | 0.93 / 1.01 / 0.89 |
| 3 | 2026-06-25T19:21:59.000 | 123 km | 0.00 km | 30.0 km | yes | one_sided | 234 km | 3.37 s / 6.90 s / 8.51 s | 36% / 36% / 43% | 1.00 / 1.05 / 1.11 |
| 4 | 2026-06-25T19:22:00.000 | 40.0 km | 123 km | - | yes | surrounded | 26.0 km | 4.37 s / - / 8.51 s | 43% / - / 43% | 1.01 / - / 1.11 |
| 5 | 2026-06-25T19:22:01.000 | 40.0 km | 0.00 km | - | yes | surrounded | 26.0 km | 4.39 s / - / 8.51 s | 43% / - / 43% | 1.01 / - / 1.11 |
| 6 | 2026-06-25T19:22:02.000 | 39.0 km | 2.00 km | - | yes | surrounded | 26.0 km | 4.54 s / - / 8.51 s | 43% / - / 43% | 1.02 / - / 1.11 |
| 7 | 2026-06-25T19:22:03.000 | 27.0 km | 12.0 km | - | yes | surrounded | 26.0 km | 6.54 s / - / 8.51 s | 36% / - / 43% | 1.09 / - / 1.11 |
| 8 | 2026-06-25T19:22:04.000 | 33.0 km | 8.00 km | - | yes | surrounded | 26.0 km | 5.33 s / - / 8.51 s | 36% / - / 43% | 1.03 / - / 1.11 |
| 9 | 2026-06-25T19:22:05.000 | 27.0 km | 10.0 km | - | yes | surrounded | 26.0 km | 6.56 s / - / 8.51 s | 36% / - / 43% | 1.10 / - / 1.11 |
| 10 | 2026-06-25T19:22:06.000 | 27.0 km | 1.00 km | - | yes | surrounded | 26.0 km | 6.69 s / - / 8.51 s | 36% / - / 43% | 1.11 / - / 1.11 |

## Interpretation

- `Candidate err` is the diagnostic centroid-guard candidate when emitted.
- Travel RMS uses relative arrival delays with 3.8 km/s.
- Atten RMS is within-frame static attenuation scatter, not a trained production score.

## Candidate Frames

| Time | Baseline | Candidate | Truth | Baseline err | Candidate err | Travel RMS delta | Atten RMS delta |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: |
| 2026-06-25T19:21:57.000 | 40.8384, 142.9073 | 39.7176, 141.8221 | 39.7000, 142.1000 | 144 km | 23.8 km | +4.06 s | +0.06 |
| 2026-06-25T19:21:58.000 | 40.7080, 142.6946 | 39.7014, 141.7594 | 39.7000, 142.1000 | 123 km | 29.1 km | +3.46 s | +0.09 |
| 2026-06-25T19:21:59.000 | 40.7080, 142.6946 | 39.6943, 141.7489 | 39.7000, 142.1000 | 123 km | 30.0 km | +3.53 s | +0.05 |
