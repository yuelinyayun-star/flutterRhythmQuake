# 20260622_iwate_east_offshore_m30_hinet Early Frame Report

Generated from `.dart_tool\source_estimation_benchmark\20260622_iwate_east_offshore_m30_hinet.reference.json`.
This is diagnostic-only; no production estimator weights are changed.

- Case: `20260622_iwate_east_offshore_m30_hinet`
- Method: `nied_gif_hybrid_v1`
- Early estimate frames: 10
- Findings: `one_sided_early_geometry`

## Frame Summary

| # | Time | Err | Jump | Candidate err | Truth in bbox | Geometry | P90u | Travel RMS base/cand/truth | Rank inv base/cand/truth | Atten RMS base/cand/truth |
| ---: | --- | ---: | ---: | ---: | --- | --- | ---: | --- | --- | --- |
| 1 | 2026-06-22T11:27:08.000 | 111 km | - | - | yes | one_sided | 240 km | 0.52 s / - / 6.45 s | 60% / - / 50% | 0.71 / - / 0.93 |
| 2 | 2026-06-22T11:27:09.000 | 117 km | 8.00 km | - | yes | one_sided | 247 km | 0.51 s / - / 5.89 s | 47% / - / 47% | 0.69 / - / 0.88 |
| 3 | 2026-06-22T11:27:10.000 | 71.0 km | 68.0 km | - | yes | one_sided | 105 km | 1.13 s / - / 5.89 s | 47% / - / 47% | 0.72 / - / 0.88 |
| 4 | 2026-06-22T11:27:11.000 | 71.0 km | 0.00 km | - | yes | one_sided | 105 km | 1.13 s / - / 5.89 s | 40% / - / 40% | 0.69 / - / 0.85 |
| 5 | 2026-06-22T11:27:12.000 | 46.0 km | 64.0 km | - | yes | surrounded | 26.0 km | 3.86 s / - / 5.89 s | 67% / - / 40% | 1.01 / - / 0.85 |
| 6 | 2026-06-22T11:27:13.000 | 45.0 km | 1.00 km | - | yes | surrounded | 26.0 km | 3.99 s / - / 5.89 s | 67% / - / 40% | 1.02 / - / 0.85 |
| 7 | 2026-06-22T11:27:14.000 | 45.0 km | 0.00 km | - | yes | surrounded | 26.0 km | 3.99 s / - / 5.89 s | 67% / - / 40% | 1.02 / - / 0.85 |
| 8 | 2026-06-22T11:27:15.000 | 45.0 km | 0.00 km | - | yes | surrounded | 26.0 km | 3.99 s / - / 5.89 s | 67% / - / 40% | 1.02 / - / 0.85 |
| 9 | 2026-06-22T11:27:16.000 | 44.0 km | 2.00 km | - | yes | surrounded | 26.0 km | 3.99 s / - / 5.89 s | 67% / - / 40% | 1.02 / - / 0.85 |
| 10 | 2026-06-22T11:27:17.000 | 44.0 km | 0.00 km | - | yes | surrounded | 26.0 km | 3.99 s / - / 5.89 s | 80% / - / 53% | 1.01 / - / 0.82 |

## Interpretation

- `Candidate err` is the diagnostic centroid-guard candidate when emitted.
- Travel RMS uses relative arrival delays with 3.8 km/s.
- Atten RMS is within-frame static attenuation scatter, not a trained production score.

## Candidate Frames

| Time | Baseline | Candidate | Truth | Baseline err | Candidate err | Travel RMS delta | Atten RMS delta |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: |
