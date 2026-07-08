# 20260622_kushiro_offshore_m30_jma Early Frame Report

Generated from `.dart_tool\source_estimation_benchmark\20260622_kushiro_offshore_m30_jma.reference.json`.
This is diagnostic-only; no production estimator weights are changed.

- Case: `20260622_kushiro_offshore_m30_jma`
- Method: `nied_gif_hybrid_v1`
- Early estimate frames: 10
- Findings: `one_sided_early_geometry`, `candidate_improves_all_candidate_frames`

## Frame Summary

| # | Time | Err | Jump | Candidate err | Truth in bbox | Geometry | P90u | Travel RMS base/cand/truth | Rank inv base/cand/truth | Atten RMS base/cand/truth |
| ---: | --- | ---: | ---: | ---: | --- | --- | ---: | --- | --- | --- |
| 1 | 2026-06-22T16:38:23.000 | 102 km | - | 10.6 km | yes | one_sided | 194 km | 2.43 s / 4.17 s / 3.52 s | 53% / 60% / 80% | 0.69 / 0.97 / 0.97 |
| 2 | 2026-06-22T16:38:24.000 | 102 km | 0.00 km | 10.6 km | yes | one_sided | 194 km | 2.43 s / 4.17 s / 3.52 s | 53% / 60% / 80% | 0.69 / 0.97 / 0.97 |
| 3 | 2026-06-22T16:38:25.000 | 102 km | 0.00 km | 10.6 km | yes | one_sided | 194 km | 2.43 s / 4.17 s / 3.52 s | 53% / 60% / 80% | 0.69 / 0.97 / 0.97 |
| 4 | 2026-06-22T16:38:26.000 | 32.0 km | 73.0 km | - | yes | one_sided | 62.0 km | 2.88 s / - / 3.52 s | 73% / - / 80% | 0.84 / - / 0.97 |
| 5 | 2026-06-22T16:38:27.000 | 120 km | 149 km | 23.2 km | yes | one_sided | 210 km | 3.16 s / 5.26 s / 3.52 s | 67% / 40% / 80% | 0.70 / 0.56 / 0.97 |
| 6 | 2026-06-22T16:38:28.000 | 136 km | 253 km | 22.5 km | yes | one_sided | 249 km | 2.50 s / 5.39 s / 3.52 s | 73% / 47% / 80% | 0.70 / 0.60 / 0.97 |
| 7 | 2026-06-22T16:38:29.000 | 136 km | 0.00 km | 22.5 km | yes | one_sided | 249 km | 2.50 s / 5.39 s / 3.52 s | 73% / 47% / 80% | 0.70 / 0.60 / 0.97 |
| 8 | 2026-06-22T16:38:30.000 | 139 km | 6.00 km | 24.1 km | yes | one_sided | 242 km | 2.51 s / 4.75 s / 3.52 s | 67% / 40% / 80% | 0.70 / 0.62 / 0.97 |
| 9 | 2026-06-22T16:38:31.000 | 139 km | 0.00 km | 24.1 km | yes | one_sided | 242 km | 2.51 s / 4.72 s / 3.52 s | 67% / 40% / 80% | 0.70 / 0.62 / 0.97 |
| 10 | 2026-06-22T16:38:32.000 | 62.0 km | 81.0 km | - | yes | one_sided | 65.7 km | 2.49 s / - / 3.52 s | 60% / - / 80% | 0.70 / - / 0.97 |

## Interpretation

- `Candidate err` is the diagnostic centroid-guard candidate when emitted.
- Travel RMS uses relative arrival delays with 3.8 km/s.
- Atten RMS is within-frame static attenuation scatter, not a trained production score.

## Candidate Frames

| Time | Baseline | Candidate | Truth | Baseline err | Candidate err | Travel RMS delta | Atten RMS delta |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: |
| 2026-06-22T16:38:23.000 | 42.2238, 144.8340 | 42.9927, 144.0288 | 42.9000, 144.0000 | 102 km | 10.6 km | +1.74 s | +0.28 |
| 2026-06-22T16:38:24.000 | 42.2238, 144.8340 | 42.9927, 144.0288 | 42.9000, 144.0000 | 102 km | 10.6 km | +1.74 s | +0.28 |
| 2026-06-22T16:38:25.000 | 42.2238, 144.8340 | 42.9927, 144.0288 | 42.9000, 144.0000 | 102 km | 10.6 km | +1.74 s | +0.28 |
| 2026-06-22T16:38:27.000 | 43.6038, 142.8840 | 43.0708, 144.1627 | 42.9000, 144.0000 | 120 km | 23.2 km | +2.10 s | -0.14 |
| 2026-06-22T16:38:28.000 | 41.8338, 144.8194 | 43.0849, 144.1134 | 42.9000, 144.0000 | 136 km | 22.5 km | +2.90 s | -0.10 |
| 2026-06-22T16:38:29.000 | 41.8338, 144.8194 | 43.0849, 144.1134 | 42.9000, 144.0000 | 136 km | 22.5 km | +2.90 s | -0.10 |
| 2026-06-22T16:38:30.000 | 41.8338, 144.8887 | 43.1152, 144.0344 | 42.9000, 144.0000 | 139 km | 24.1 km | +2.24 s | -0.08 |
| 2026-06-22T16:38:31.000 | 41.8338, 144.8887 | 43.1155, 144.0321 | 42.9000, 144.0000 | 139 km | 24.1 km | +2.20 s | -0.08 |
