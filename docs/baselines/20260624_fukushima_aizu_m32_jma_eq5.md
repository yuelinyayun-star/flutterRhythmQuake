# 20260624_fukushima_aizu_m32_jma_eq5 Early Frame Report

Generated from `.dart_tool\source_estimation_benchmark\20260624_fukushima_aizu_m32_jma_eq5.reference.json`.
This is diagnostic-only; no production estimator weights are changed.

- Case: `20260624_fukushima_aizu_m32_jma_eq5`
- Method: `nied_gif_hybrid_v1`
- Early estimate frames: 10
- Findings: 

## Frame Summary

| # | Time | Err | Jump | Candidate err | Truth in bbox | Geometry | P90u | Travel RMS base/cand/truth | Rank inv base/cand/truth | Atten RMS base/cand/truth |
| ---: | --- | ---: | ---: | ---: | --- | --- | ---: | --- | --- | --- |
| 1 | 2026-06-24T13:24:54.000 | 1.00 km | - | - | yes | surrounded | 26.0 km | 1.25 s / - / 1.23 s | 36% / - / 43% | 0.84 / - / 0.85 |
| 2 | 2026-06-24T13:24:55.000 | 15.0 km | 15.0 km | - | yes | surrounded | 26.0 km | 1.89 s / - / 1.96 s | 64% / - / 57% | 1.05 / - / 1.08 |
| 3 | 2026-06-24T13:24:56.000 | 7.00 km | 21.0 km | - | yes | surrounded | 26.0 km | 2.07 s / - / 1.96 s | 50% / - / 57% | 1.07 / - / 1.08 |
| 4 | 2026-06-24T13:24:57.000 | 5.00 km | 2.00 km | - | yes | surrounded | 26.0 km | 2.06 s / - / 1.96 s | 50% / - / 57% | 1.06 / - / 1.08 |
| 5 | 2026-06-24T13:24:58.000 | 7.00 km | 2.00 km | - | yes | surrounded | 26.0 km | 2.07 s / - / 1.96 s | 50% / - / 57% | 1.07 / - / 1.08 |
| 6 | 2026-06-24T13:24:59.000 | 7.00 km | 0.00 km | - | yes | surrounded | 26.0 km | 2.07 s / - / 1.96 s | 50% / - / 57% | 1.07 / - / 1.08 |
| 7 | 2026-06-24T13:25:00.000 | 7.00 km | 0.00 km | - | yes | surrounded | 26.0 km | 2.07 s / - / 1.96 s | 50% / - / 57% | 1.07 / - / 1.08 |
| 8 | 2026-06-24T13:25:01.000 | 8.00 km | 2.00 km | - | yes | surrounded | 26.0 km | 2.15 s / - / 1.96 s | 50% / - / 57% | 1.03 / - / 1.08 |
| 9 | 2026-06-24T13:25:02.000 | 8.00 km | 1.00 km | - | yes | surrounded | 26.0 km | 2.12 s / - / 1.96 s | 50% / - / 57% | 1.04 / - / 1.08 |
| 10 | 2026-06-24T13:25:03.000 | 8.00 km | 0.00 km | - | yes | surrounded | 26.0 km | 2.12 s / - / 1.96 s | 50% / - / 57% | 1.04 / - / 1.08 |

## Interpretation

- `Candidate err` is the diagnostic centroid-guard candidate when emitted.
- Travel RMS uses relative arrival delays with 3.8 km/s.
- Atten RMS is within-frame static attenuation scatter, not a trained production score.

## Candidate Frames

| Time | Baseline | Candidate | Truth | Baseline err | Candidate err | Travel RMS delta | Atten RMS delta |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: |
