# 20260620_iwate_offshore_m34_ref Early Frame Report

Generated from `.dart_tool\source_estimation_benchmark\20260620_iwate_offshore_m34_ref.reference.json`.
This is diagnostic-only; no production estimator weights are changed.

- Case: `20260620_iwate_offshore_m34_ref`
- Method: `nied_gif_hybrid_v1`
- Early estimate frames: 10
- Findings: `one_sided_early_geometry`

## Frame Summary

| # | Time | Err | Jump | Candidate err | Truth in bbox | Geometry | P90u | Travel RMS base/cand/truth | Rank inv base/cand/truth | Atten RMS base/cand/truth |
| ---: | --- | ---: | ---: | ---: | --- | --- | ---: | --- | --- | --- |
| 1 | 2026-06-20T21:25:49.000 | 57.0 km | - | - | yes | surrounded | 26.0 km | 3.49 s / - / 4.82 s | 10% / - / 20% | 0.35 / - / 0.49 |
| 2 | 2026-06-20T21:25:50.000 | 53.0 km | 4.00 km | - | yes | surrounded | 26.0 km | 3.49 s / - / 5.06 s | 7% / - / 14% | 0.16 / - / 0.41 |
| 3 | 2026-06-20T21:25:51.000 | 53.0 km | 0.00 km | - | yes | surrounded | 26.0 km | 3.49 s / - / 5.06 s | 7% / - / 13% | 0.69 / - / 0.81 |
| 4 | 2026-06-20T21:25:52.000 | 53.0 km | 0.00 km | - | yes | surrounded | 26.0 km | 3.49 s / - / 5.06 s | 7% / - / 13% | 0.64 / - / 0.77 |
| 5 | 2026-06-20T21:25:53.000 | 53.0 km | 3.00 km | - | yes | surrounded | 26.0 km | 3.64 s / - / 5.06 s | 7% / - / 13% | 0.64 / - / 0.77 |
| 6 | 2026-06-20T21:25:54.000 | 85.0 km | 33.0 km | - | yes | surrounded | 26.0 km | 4.73 s / - / 5.06 s | 47% / - / 13% | 0.95 / - / 0.77 |
| 7 | 2026-06-20T21:25:55.000 | 85.0 km | 0.00 km | - | yes | surrounded | 26.0 km | 4.73 s / - / 5.06 s | 40% / - / 20% | 0.86 / - / 0.81 |
| 8 | 2026-06-20T21:25:56.000 | 85.0 km | 0.00 km | - | yes | surrounded | 26.0 km | 4.76 s / - / 5.06 s | 40% / - / 20% | 0.86 / - / 0.81 |
| 9 | 2026-06-20T21:25:57.000 | 49.0 km | 36.0 km | - | yes | one_sided | 43.0 km | 3.66 s / - / 5.06 s | 14% / - / 21% | 0.69 / - / 0.84 |
| 10 | 2026-06-20T21:25:58.000 | 44.0 km | 6.00 km | - | yes | one_sided | 43.0 km | 3.93 s / - / 5.06 s | 27% / - / 33% | 0.79 / - / 0.89 |

## Interpretation

- `Candidate err` is the diagnostic centroid-guard candidate when emitted.
- Travel RMS uses relative arrival delays with 3.8 km/s.
- Atten RMS is within-frame static attenuation scatter, not a trained production score.

## Candidate Frames

| Time | Baseline | Candidate | Truth | Baseline err | Candidate err | Travel RMS delta | Atten RMS delta |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: |
