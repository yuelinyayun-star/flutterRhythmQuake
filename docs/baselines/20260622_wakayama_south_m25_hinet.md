# 20260622_wakayama_south_m25_hinet Early Frame Report

Generated from `.dart_tool\source_estimation_benchmark\20260622_wakayama_south_m25_hinet.reference.json`.
This is diagnostic-only; no production estimator weights are changed.

- Case: `20260622_wakayama_south_m25_hinet`
- Method: `nied_gif_hybrid_v1`
- Early estimate frames: 10
- Findings: `one_sided_early_geometry`

## Frame Summary

| # | Time | Err | Jump | Candidate err | Truth in bbox | Geometry | P90u | Travel RMS base/cand/truth | Rank inv base/cand/truth | Atten RMS base/cand/truth |
| ---: | --- | ---: | ---: | ---: | --- | --- | ---: | --- | --- | --- |
| 1 | 2026-06-22T09:51:33.000 | 138 km | - | - | yes | one_sided | 249 km | 3.04 s / - / 4.22 s | 22% / - / 22% | 0.44 / - / 0.40 |
| 2 | 2026-06-22T09:51:34.000 | 49.0 km | 186 km | - | yes | one_sided | 80.2 km | 3.42 s / - / 4.18 s | 36% / - / 29% | 0.40 / - / 0.41 |
| 3 | 2026-06-22T09:51:35.000 | 4.00 km | 48.0 km | - | yes | surrounded | 26.0 km | 3.43 s / - / 3.85 s | 29% / - / 29% | 0.36 / - / 0.39 |
| 4 | 2026-06-22T09:51:36.000 | 6.00 km | 4.00 km | - | yes | surrounded | 26.0 km | 3.83 s / - / 4.18 s | 29% / - / 29% | 0.40 / - / 0.41 |
| 5 | 2026-06-22T09:51:37.000 | 6.00 km | 0.00 km | - | yes | surrounded | 26.0 km | 3.83 s / - / 4.18 s | 29% / - / 29% | 0.40 / - / 0.41 |
| 6 | 2026-06-22T09:51:38.000 | 4.00 km | 4.00 km | - | yes | surrounded | 26.0 km | 3.43 s / - / 3.85 s | 29% / - / 29% | 0.38 / - / 0.42 |
| 7 | 2026-06-22T09:51:39.000 | 7.00 km | 5.00 km | - | yes | surrounded | 26.0 km | 3.81 s / - / 4.18 s | 29% / - / 29% | 0.38 / - / 0.42 |
| 8 | 2026-06-22T09:51:40.000 | 5.00 km | 2.00 km | - | yes | surrounded | 26.0 km | 3.87 s / - / 4.18 s | 36% / - / 29% | 0.38 / - / 0.42 |
| 9 | 2026-06-22T09:51:41.000 | 3.00 km | 4.00 km | - | yes | surrounded | 26.0 km | 3.45 s / - / 3.85 s | 29% / - / 29% | 0.38 / - / 0.42 |
| 10 | 2026-06-22T09:51:42.000 | 5.00 km | 3.00 km | - | yes | surrounded | 26.0 km | 3.88 s / - / 4.18 s | 36% / - / 29% | 0.39 / - / 0.42 |

## Interpretation

- `Candidate err` is the diagnostic centroid-guard candidate when emitted.
- Travel RMS uses relative arrival delays with 3.8 km/s.
- Atten RMS is within-frame static attenuation scatter, not a trained production score.

## Candidate Frames

| Time | Baseline | Candidate | Truth | Baseline err | Candidate err | Travel RMS delta | Atten RMS delta |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: |
