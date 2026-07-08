# Fukushima/Miyagi M3.2 Early Frame Report

Generated from `.dart_tool/source_estimation_benchmark/20260621_fukushima_offshore_m32_eq6.reference.json`.
This is diagnostic-only; no production estimator weights are changed.

- Case: `20260621_fukushima_offshore_m32_eq6`
- Method: `nied_gif_hybrid_v1`
- Early estimate frames: 10
- Findings: `truth_outside_search_box_in_early_frames`, `one_sided_early_geometry`, `catastrophic_early_error`, `candidate_has_mixed_early_frame_effect`, `large_travel_time_residuals_do_not_uniquely_select_truth`

## Frame Summary

| # | Time | Err | Jump | Candidate err | Truth in bbox | Geometry | P90u | Travel RMS base/cand/truth | Rank inv base/cand/truth | Atten RMS base/cand/truth |
| ---: | --- | ---: | ---: | ---: | --- | --- | ---: | --- | --- | --- |
| 1 | 2026-06-21T23:41:50.000 | 120 km | - | 138 km | no | one_sided | 240 km | 1.56 s / 6.21 s / 7.77 s | 56% / 56% / 67% | 0.32 / 0.40 / 0.29 |
| 2 | 2026-06-21T23:41:51.000 | 307 km | 278 km | 137 km | no | one_sided | 228 km | 6.27 s / 14.2 s / 15.3 s | 29% / 43% / 71% | 0.21 / 0.56 / 0.37 |
| 3 | 2026-06-21T23:41:52.000 | 311 km | 6.00 km | 132 km | no | one_sided | 220 km | 6.00 s / 14.6 s / 15.3 s | 29% / 57% / 71% | 0.21 / 0.57 / 0.37 |
| 4 | 2026-06-21T23:41:53.000 | 311 km | 0.00 km | 132 km | no | one_sided | 220 km | 6.00 s / 14.6 s / 15.3 s | 29% / 57% / 71% | 0.21 / 0.57 / 0.37 |
| 5 | 2026-06-21T23:41:54.000 | 311 km | 0.00 km | 132 km | no | one_sided | 220 km | 6.00 s / 14.6 s / 15.3 s | 29% / 57% / 71% | 0.21 / 0.57 / 0.37 |
| 6 | 2026-06-21T23:41:55.000 | 313 km | 3.00 km | 131 km | no | one_sided | 216 km | 5.88 s / 14.9 s / 15.3 s | 29% / 50% / 71% | 0.21 / 0.54 / 0.37 |
| 7 | 2026-06-21T23:41:56.000 | 313 km | 0.00 km | 131 km | no | one_sided | 216 km | 5.88 s / 14.9 s / 15.3 s | 29% / 50% / 71% | 0.20 / 0.54 / 0.36 |
| 8 | 2026-06-21T23:41:57.000 | 313 km | 0.00 km | 131 km | no | one_sided | 216 km | 5.88 s / 14.9 s / 15.3 s | 21% / 43% / 79% | 0.20 / 0.53 / 0.37 |
| 9 | 2026-06-21T23:41:58.000 | 165 km | 159 km | - | no | one_sided | 43.0 km | 8.72 s / - / 14.0 s | 21% / - / 86% | 0.65 / - / 0.47 |
| 10 | 2026-06-21T23:41:59.000 | 165 km | 0.00 km | - | no | one_sided | 43.0 km | 8.72 s / - / 14.0 s | 21% / - / 86% | 0.65 / - / 0.47 |

## Interpretation

- `Candidate err` is the diagnostic centroid-guard candidate when emitted.
- Travel RMS uses relative arrival delays with 3.8 km/s.
- Atten RMS is within-frame static attenuation scatter, not a trained production score.

## Candidate Frames

| Time | Baseline | Candidate | Truth | Baseline err | Candidate err | Travel RMS delta | Atten RMS delta |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: |
| 2026-06-21T23:41:50.000 | 37.2052, 141.0212 | 38.4056, 141.0618 | 37.6160, 142.2790 | 120 km | 138 km | +4.65 s | +0.09 |
| 2026-06-21T23:41:51.000 | 39.4661, 139.6612 | 38.3822, 141.0583 | 37.6160, 142.2790 | 307 km | 137 km | +7.90 s | +0.34 |
| 2026-06-21T23:41:52.000 | 39.5161, 139.6612 | 38.3494, 141.0902 | 37.6160, 142.2790 | 311 km | 132 km | +8.62 s | +0.36 |
| 2026-06-21T23:41:53.000 | 39.5161, 139.6612 | 38.3494, 141.0902 | 37.6160, 142.2790 | 311 km | 132 km | +8.62 s | +0.36 |
| 2026-06-21T23:41:54.000 | 39.5161, 139.6612 | 38.3494, 141.0902 | 37.6160, 142.2790 | 311 km | 132 km | +8.62 s | +0.36 |
| 2026-06-21T23:41:55.000 | 39.5453, 139.6612 | 38.3043, 141.0653 | 37.6160, 142.2790 | 313 km | 131 km | +9.03 s | +0.33 |
| 2026-06-21T23:41:56.000 | 39.5453, 139.6612 | 38.3040, 141.0641 | 37.6160, 142.2790 | 313 km | 131 km | +9.02 s | +0.34 |
| 2026-06-21T23:41:57.000 | 39.5453, 139.6612 | 38.3032, 141.0613 | 37.6160, 142.2790 | 313 km | 131 km | +9.01 s | +0.33 |
