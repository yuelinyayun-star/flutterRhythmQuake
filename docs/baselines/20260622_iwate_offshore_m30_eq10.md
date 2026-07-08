# 20260622_iwate_offshore_m30_eq10 Early Frame Report

Generated from `.dart_tool\source_estimation_benchmark\20260622_iwate_offshore_m30_eq10.reference.json`.
This is diagnostic-only; no production estimator weights are changed.

- Case: `20260622_iwate_offshore_m30_eq10`
- Method: `nied_gif_hybrid_v1`
- Early estimate frames: 10
- Findings: `one_sided_early_geometry`, `large_travel_time_residuals_do_not_uniquely_select_truth`

## Frame Summary

| # | Time | Err | Jump | Candidate err | Truth in bbox | Geometry | P90u | Travel RMS base/cand/truth | Rank inv base/cand/truth | Atten RMS base/cand/truth |
| ---: | --- | ---: | ---: | ---: | --- | --- | ---: | --- | --- | --- |
| 1 | 2026-06-22T09:28:52.000 | 50.0 km | - | - | yes | one_sided | 69.3 km | 3.98 s / - / 6.06 s | 44% / - / 33% | 0.27 / - / 0.36 |
| 2 | 2026-06-22T09:28:53.000 | 112 km | 80.0 km | - | yes | one_sided | 43.0 km | 5.24 s / - / 5.77 s | 57% / - / 43% | 0.52 / - / 0.29 |
| 3 | 2026-06-22T09:28:54.000 | 115 km | 7.00 km | - | yes | one_sided | 43.0 km | 5.52 s / - / 5.77 s | 57% / - / 43% | 0.53 / - / 0.31 |
| 4 | 2026-06-22T09:28:55.000 | 115 km | 0.00 km | - | yes | one_sided | 43.0 km | 5.52 s / - / 5.77 s | 57% / - / 43% | 0.52 / - / 0.33 |
| 5 | 2026-06-22T09:28:56.000 | 58.0 km | 57.0 km | - | yes | surrounded | 26.0 km | 4.64 s / - / 5.77 s | 38% / - / 46% | 0.45 / - / 0.38 |
| 6 | 2026-06-22T09:28:57.000 | 55.0 km | 5.00 km | - | yes | surrounded | 26.0 km | 5.04 s / - / 5.77 s | 29% / - / 21% | 0.37 / - / 0.37 |
| 7 | 2026-06-22T09:28:58.000 | 54.0 km | 4.00 km | - | yes | surrounded | 26.0 km | 5.36 s / - / 5.77 s | 21% / - / 21% | 0.39 / - / 0.37 |
| 8 | 2026-06-22T09:28:59.000 | 18.0 km | 35.0 km | - | yes | one_sided | 47.5 km | 5.58 s / - / 5.77 s | 14% / - / 21% | 0.34 / - / 0.37 |
| 9 | 2026-06-22T09:29:00.000 | 17.0 km | 2.00 km | - | yes | one_sided | 47.7 km | 5.48 s / - / 5.77 s | 14% / - / 21% | 0.34 / - / 0.37 |
| 10 | 2026-06-22T09:29:01.000 | 24.0 km | 7.00 km | - | yes | one_sided | 43.0 km | 5.55 s / - / 5.77 s | 21% / - / 21% | 0.33 / - / 0.37 |

## Interpretation

- `Candidate err` is the diagnostic centroid-guard candidate when emitted.
- Travel RMS uses relative arrival delays with 3.8 km/s.
- Atten RMS is within-frame static attenuation scatter, not a trained production score.

## Candidate Frames

| Time | Baseline | Candidate | Truth | Baseline err | Candidate err | Travel RMS delta | Atten RMS delta |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: |
