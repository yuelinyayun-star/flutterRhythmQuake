# 20260622_tomakomai_south_offshore_m35_hinet Early Frame Report

Generated from `.dart_tool\source_estimation_benchmark\20260622_tomakomai_south_offshore_m35_hinet.reference.json`.
This is diagnostic-only; no production estimator weights are changed.

- Case: `20260622_tomakomai_south_offshore_m35_hinet`
- Method: `nied_gif_hybrid_v1`
- Early estimate frames: 10
- Findings: `one_sided_early_geometry`, `candidate_improves_all_candidate_frames`, `large_travel_time_residuals_do_not_uniquely_select_truth`

## Frame Summary

| # | Time | Err | Jump | Candidate err | Truth in bbox | Geometry | P90u | Travel RMS base/cand/truth | Rank inv base/cand/truth | Atten RMS base/cand/truth |
| ---: | --- | ---: | ---: | ---: | --- | --- | ---: | --- | --- | --- |
| 1 | 2026-06-22T20:38:16.000 | 55.0 km | - | - | yes | one_sided | 46.8 km | 1.85 s / - / 6.88 s | 56% / - / 11% | 0.60 / - / 0.22 |
| 2 | 2026-06-22T20:38:17.000 | 55.0 km | 0.00 km | - | yes | one_sided | 46.8 km | 1.85 s / - / 6.88 s | 56% / - / 11% | 0.60 / - / 0.22 |
| 3 | 2026-06-22T20:38:18.000 | 137 km | 87.0 km | 27.8 km | yes | one_sided | 196 km | 4.25 s / 9.59 s / 7.21 s | 46% / 0% / 8% | 0.44 / 0.19 / 0.21 |
| 4 | 2026-06-22T20:38:19.000 | 137 km | 0.00 km | 27.8 km | yes | one_sided | 196 km | 4.25 s / 9.64 s / 7.21 s | 46% / 0% / 8% | 0.44 / 0.19 / 0.21 |
| 5 | 2026-06-22T20:38:20.000 | 137 km | 0.00 km | 27.3 km | yes | one_sided | 193 km | 4.25 s / 11.1 s / 7.21 s | 46% / 0% / 8% | 0.44 / 0.27 / 0.21 |
| 6 | 2026-06-22T20:38:21.000 | 60.0 km | 78.0 km | - | yes | one_sided | 45.1 km | 5.49 s / - / 7.21 s | 23% / - / 8% | 0.41 / - / 0.21 |
| 7 | 2026-06-22T20:38:22.000 | 31.0 km | 31.0 km | - | yes | surrounded | 26.0 km | 6.34 s / - / 7.21 s | 31% / - / 8% | 0.39 / - / 0.21 |
| 8 | 2026-06-22T20:38:23.000 | 31.0 km | 0.00 km | - | yes | surrounded | 26.0 km | 6.34 s / - / 7.21 s | 31% / - / 8% | 0.39 / - / 0.21 |
| 9 | 2026-06-22T20:38:24.000 | 34.0 km | 3.00 km | - | yes | surrounded | 26.0 km | 6.20 s / - / 7.21 s | 23% / - / 8% | 0.37 / - / 0.21 |
| 10 | 2026-06-22T20:38:25.000 | 13.0 km | 27.0 km | - | yes | surrounded | 26.0 km | 14.6 s / - / 15.7 s | 38% / - / 8% | 0.40 / - / 0.27 |

## Interpretation

- `Candidate err` is the diagnostic centroid-guard candidate when emitted.
- Travel RMS uses relative arrival delays with 3.8 km/s.
- Atten RMS is within-frame static attenuation scatter, not a trained production score.

## Candidate Frames

| Time | Baseline | Candidate | Truth | Baseline err | Candidate err | Travel RMS delta | Atten RMS delta |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: |
| 2026-06-22T20:38:18.000 | 42.0894, 139.6900 | 41.9960, 141.0229 | 42.0630, 141.3470 | 137 km | 27.8 km | +5.33 s | -0.25 |
| 2026-06-22T20:38:19.000 | 42.0894, 139.6900 | 41.9942, 141.0228 | 42.0630, 141.3470 | 137 km | 27.8 km | +5.38 s | -0.25 |
| 2026-06-22T20:38:20.000 | 42.0894, 139.6900 | 41.9287, 141.0702 | 42.0630, 141.3470 | 137 km | 27.3 km | +6.80 s | -0.18 |
