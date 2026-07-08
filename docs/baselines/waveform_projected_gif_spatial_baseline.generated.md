# Waveform Projected GIF Spatial Baseline

- Schema: `waveform_projected_gif_spatial_baseline_v1`
- Split: leave-one-event-out; station-seconds never cross folds
- Input: surface sensors, origin through origin+120 seconds
- Model: current-frame intensity weighted centroid
- Selection guard: at least 25% frame coverage in every training event
- Domain: projected official waveform, not real NIED GIF

| Held-out event | Min intensity | Weight exponent | Arrival decay | Drop | Frames | Coverage | First delay | First error | Median | P90 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fukushima_offshore_20210213_m73 | 2.50 | 0.25 | - | 0% | 116/121 | 95.9% | 5.00 s | 58.45 km | 123.88 km | 198.89 km |
| fukushima_offshore_20210213_m73 | 2.50 | 0.25 | - | 20% | 116/121 | 95.9% | 5.00 s | 58.45 km | 123.98 km | 189.12 km |
| fukushima_offshore_20210213_m73 | 2.50 | 0.25 | - | 50% | 114/121 | 94.2% | 7.00 s | 61.39 km | 120.93 km | 182.45 km |
| fukushima_offshore_20210213_m73 | 2.50 | 0.25 | - | 80% | 102/121 | 84.3% | 19.00 s | 99.02 km | 117.65 km | 229.66 km |
| fukushima_offshore_20210213_m73 | 2.50 | 0.25 | - | 0% | 116/121 | 95.9% | 5.00 s | 58.44 km | 123.88 km | 198.35 km |
| fukushima_offshore_20210213_m73 | 2.50 | 0.25 | - | 20% | 115/121 | 95.0% | 6.00 s | 63.72 km | 123.55 km | 202.09 km |
| fukushima_offshore_20210213_m73 | 2.50 | 0.25 | - | 50% | 115/121 | 95.0% | 6.00 s | 63.72 km | 125.04 km | 201.70 km |
| fukushima_offshore_20210213_m73 | 2.50 | 0.25 | - | 80% | 112/121 | 92.6% | 9.00 s | 79.14 km | 112.34 km | 171.64 km |
| hokkaido_iburi_20180906_m66 | 1.00 | 1.00 | - | 0% | 115/121 | 95.0% | 6.00 s | 10.79 km | 35.41 km | 93.72 km |
| hokkaido_iburi_20180906_m66 | 1.00 | 1.00 | - | 20% | 115/121 | 95.0% | 6.00 s | 7.83 km | 40.54 km | 81.55 km |
| hokkaido_iburi_20180906_m66 | 1.00 | 1.00 | - | 50% | 114/121 | 94.2% | 7.00 s | 7.32 km | 42.38 km | 77.14 km |
| hokkaido_iburi_20180906_m66 | 1.00 | 1.00 | - | 80% | 108/121 | 89.3% | 13.00 s | 10.27 km | 48.87 km | 80.78 km |
| hokkaido_iburi_20180906_m66 | 1.00 | 1.00 | - | 0% | 121/121 | 100.0% | 0.00 s | 12.45 km | 37.44 km | 68.10 km |
| hokkaido_iburi_20180906_m66 | 1.00 | 1.00 | - | 20% | 121/121 | 100.0% | 0.00 s | 9.39 km | 38.69 km | 57.32 km |
| hokkaido_iburi_20180906_m66 | 1.00 | 1.00 | - | 50% | 116/121 | 95.9% | 5.00 s | 11.80 km | 53.49 km | 90.85 km |
| hokkaido_iburi_20180906_m66 | 1.00 | 1.00 | - | 80% | 105/121 | 86.8% | 16.00 s | 63.98 km | 87.65 km | 178.64 km |
| kumamoto_20160416_m73 | 0.00 | 1.25 | - | 0% | 114/121 | 94.2% | 7.00 s | 67.72 km | 58.10 km | 135.01 km |
| kumamoto_20160416_m73 | 0.00 | 1.25 | - | 20% | 111/121 | 91.7% | 10.00 s | 15.69 km | 71.94 km | 172.08 km |
| kumamoto_20160416_m73 | 0.00 | 1.25 | - | 50% | 110/121 | 90.9% | 11.00 s | 16.61 km | 76.90 km | 189.08 km |
| kumamoto_20160416_m73 | 0.00 | 1.25 | - | 80% | 108/121 | 89.3% | 13.00 s | 26.28 km | 96.15 km | 203.50 km |
| kumamoto_20160416_m73 | 0.00 | 1.25 | - | 0% | 112/121 | 92.6% | 9.00 s | 3.72 km | 58.08 km | 135.20 km |
| kumamoto_20160416_m73 | 0.00 | 1.25 | - | 20% | 110/121 | 90.9% | 11.00 s | 2.54 km | 46.35 km | 119.31 km |
| kumamoto_20160416_m73 | 0.00 | 1.25 | - | 50% | 108/121 | 89.3% | 13.00 s | 4.73 km | 54.82 km | 170.65 km |
| kumamoto_20160416_m73 | 0.00 | 1.25 | - | 80% | 105/121 | 86.8% | 16.00 s | 30.43 km | 55.52 km | 252.27 km |
| noto_peninsula_20240101_m76 | 2.50 | 0.25 | - | 0% | 103/121 | 85.1% | 18.00 s | 12.00 km | 74.16 km | 112.29 km |
| noto_peninsula_20240101_m76 | 2.50 | 0.25 | - | 20% | 103/121 | 85.1% | 18.00 s | 9.88 km | 71.67 km | 111.56 km |
| noto_peninsula_20240101_m76 | 2.50 | 0.25 | - | 50% | 97/121 | 80.2% | 24.00 s | 25.37 km | 72.80 km | 133.64 km |
| noto_peninsula_20240101_m76 | 2.50 | 0.25 | - | 80% | 76/121 | 62.8% | 45.00 s | 67.41 km | 100.07 km | 167.08 km |
| noto_peninsula_20240101_m76 | 2.50 | 0.25 | - | 0% | 95/121 | 78.5% | 26.00 s | 16.44 km | 95.32 km | 117.73 km |
| noto_peninsula_20240101_m76 | 2.50 | 0.25 | - | 20% | 88/121 | 72.7% | 32.00 s | 54.68 km | 104.00 km | 127.08 km |
| noto_peninsula_20240101_m76 | 2.50 | 0.25 | - | 50% | 86/121 | 71.1% | 35.00 s | 57.74 km | 100.63 km | 127.83 km |
| noto_peninsula_20240101_m76 | 2.50 | 0.25 | - | 80% | 76/121 | 62.8% | 45.00 s | 90.96 km | 108.69 km | 146.08 km |

## Held-out summary

- Median frame error: 66.13 km
- Median first-estimate error: 14.44 km
- Median projected-level quantization MAE: 0.084 intensity units

These values do not measure real GIF detection delay, missing frames, transport latency, or production readiness.
