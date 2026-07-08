# K-NET Confirmation Alignment Report

- Status: `pass`
- Event set: 2 confirmed official CSV waveform pairs
- Source observations: `surface` GIF observations exported from local capture packages

## Event Summaries

| Event | GIF samples | Stations | Mean diff (GIF - waveform) | Mean absolute diff | RMSE |
| --- | ---: | ---: | ---: | ---: | ---: |
| `fukushima_aizu_20260624_m32_jma_eq5` | `164` | `3` | `0.6061` | `0.9160` | `1.0360` |
| `yamanashi_east_fuji_five_lakes_20260626_m56_jma_equake21` | `15357` | `198` | `0.9330` | `1.1456` | `1.4277` |

## Evidence

- GIF observations exported from:
  - `tmp/knet_confirmation_gif_observations/fukushima_aizu.json`
  - `tmp/knet_confirmation_gif_observations/yamanashi_m56.json`
- Waveform features exported from:
  - `tmp/knet_confirmation_features/fukushima_aizu_20260624_m32_jma_eq5_features.json`
  - `tmp/knet_confirmation_features/yamanashi_east_fuji_five_lakes_20260626_m56_jma_equake21_features.json`
- Alignment outputs:
  - `tmp/knet_confirmation_alignment/fukushima_aizu.json`
  - `tmp/knet_confirmation_alignment/yamanashi_m56.json`

## Decision

- The first two confirmed official CSV pairs now have full local GIF / waveform alignment outputs.
- The remaining six provisional overlaps stay unresolved and remain in the confirmation queue.
- This report is diagnostic-only and does not change source estimation or frozen metrics.
