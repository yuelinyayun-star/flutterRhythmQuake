# 20260623_tokachi_southeast_offshore_m34_hinet Early Frame Report

Generated from `.dart_tool\source_estimation_benchmark\20260623_tokachi_southeast_offshore_m34_hinet.reference.json`.
This is diagnostic-only; no production estimator weights are changed.

- Case: `20260623_tokachi_southeast_offshore_m34_hinet`
- Method: `nied_gif_hybrid_v1`
- Early estimate frames: 10
- Findings: `one_sided_early_geometry`

## Frame Summary

| # | Time | Err | Jump | Candidate err | Truth in bbox | Geometry | P90u | Travel RMS base/cand/truth | Rank inv base/cand/truth | Atten RMS base/cand/truth |
| ---: | --- | ---: | ---: | ---: | --- | --- | ---: | --- | --- | --- |
| 1 | 2026-06-23T23:13:25.000 | 57.0 km | - | - | yes | surrounded | 26.0 km | 1.27 s / - / 4.36 s | 20% / - / 10% | 0.73 / - / 0.49 |
| 2 | 2026-06-23T23:13:26.000 | 20.0 km | 59.0 km | - | yes | one_sided | 58.8 km | 3.85 s / - / 4.41 s | 0% / - / 14% | 0.51 / - / 0.44 |
| 3 | 2026-06-23T23:13:27.000 | 20.0 km | 1.00 km | - | yes | one_sided | 51.9 km | 3.85 s / - / 4.41 s | 7% / - / 27% | 0.62 / - / 0.65 |
| 4 | 2026-06-23T23:13:28.000 | 20.0 km | 0.00 km | - | yes | one_sided | 51.9 km | 3.85 s / - / 4.41 s | 27% / - / 47% | 0.66 / - / 0.68 |
| 5 | 2026-06-23T23:13:29.000 | 20.0 km | 0.00 km | - | yes | one_sided | 51.9 km | 3.85 s / - / 4.41 s | 27% / - / 47% | 0.66 / - / 0.68 |
| 6 | 2026-06-23T23:13:30.000 | 13.0 km | 22.0 km | - | yes | surrounded | 26.0 km | 4.08 s / - / 4.41 s | 27% / - / 47% | 0.61 / - / 0.64 |
| 7 | 2026-06-23T23:13:31.000 | 13.0 km | 0.00 km | - | yes | surrounded | 26.0 km | 4.08 s / - / 4.41 s | 27% / - / 47% | 0.61 / - / 0.64 |
| 8 | 2026-06-23T23:13:32.000 | 12.0 km | 2.00 km | - | yes | surrounded | 26.0 km | 4.06 s / - / 4.41 s | 27% / - / 47% | 0.61 / - / 0.64 |
| 9 | 2026-06-23T23:13:33.000 | 13.0 km | 3.00 km | - | yes | surrounded | 26.0 km | 4.07 s / - / 4.41 s | 27% / - / 47% | 0.61 / - / 0.64 |
| 10 | 2026-06-23T23:13:34.000 | 13.0 km | 0.00 km | - | yes | surrounded | 26.0 km | 4.07 s / - / 4.41 s | 27% / - / 47% | 0.61 / - / 0.64 |

## Interpretation

- `Candidate err` is the diagnostic centroid-guard candidate when emitted.
- Travel RMS uses relative arrival delays with 3.8 km/s.
- Atten RMS is within-frame static attenuation scatter, not a trained production score.

## Candidate Frames

| Time | Baseline | Candidate | Truth | Baseline err | Candidate err | Travel RMS delta | Atten RMS delta |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: |
