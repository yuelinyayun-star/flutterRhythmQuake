# Waveform Projected GIF Temporal Baseline

- Schema: `waveform_projected_gif_spatial_baseline_v1_temporal`
- Split: leave-one-event-out; station-seconds never cross folds
- Input: surface sensors, origin through origin+120 seconds
- Model: 60-second station history; event running peak; exponentially decayed relative first arrival
- Selection guard: at least 25% frame coverage in every training event
- Domain: projected official waveform, not real NIED GIF

| Held-out event | Min intensity | Weight exponent | Arrival decay | Drop | Frames | Coverage | First delay | First error | Median | P90 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fukushima_offshore_20210213_m73 | 1.50 | 1.25 | 5.00 s | 0% | 117/121 | 96.7% | 4.00 s | 64.60 km | 73.78 km | 73.79 km |
| fukushima_offshore_20210213_m73 | 1.50 | 1.25 | 5.00 s | 20% | 117/121 | 96.7% | 4.00 s | 64.60 km | 72.85 km | 72.85 km |
| fukushima_offshore_20210213_m73 | 1.50 | 1.25 | 5.00 s | 50% | 115/121 | 95.0% | 6.00 s | 51.98 km | 75.09 km | 75.09 km |
| fukushima_offshore_20210213_m73 | 1.50 | 1.25 | 5.00 s | 80% | 105/121 | 86.8% | 16.00 s | 89.67 km | 83.36 km | 89.19 km |
| hokkaido_iburi_20180906_m66 | 1.50 | 1.25 | 5.00 s | 0% | 115/121 | 95.0% | 6.00 s | 12.49 km | 13.58 km | 13.58 km |
| hokkaido_iburi_20180906_m66 | 1.50 | 1.25 | 5.00 s | 20% | 114/121 | 94.2% | 7.00 s | 11.88 km | 15.03 km | 15.03 km |
| hokkaido_iburi_20180906_m66 | 1.50 | 1.25 | 5.00 s | 50% | 114/121 | 94.2% | 7.00 s | 13.02 km | 19.09 km | 19.09 km |
| hokkaido_iburi_20180906_m66 | 1.50 | 1.25 | 5.00 s | 80% | 114/121 | 94.2% | 7.00 s | 8.41 km | 18.93 km | 18.93 km |
| kumamoto_20160416_m73 | 1.50 | 0.75 | 5.00 s | 0% | 112/121 | 92.6% | 9.00 s | 2.31 km | 4.69 km | 4.69 km |
| kumamoto_20160416_m73 | 1.50 | 0.75 | 5.00 s | 20% | 110/121 | 90.9% | 11.00 s | 4.05 km | 5.73 km | 5.73 km |
| kumamoto_20160416_m73 | 1.50 | 0.75 | 5.00 s | 50% | 108/121 | 89.3% | 13.00 s | 12.87 km | 10.52 km | 10.52 km |
| kumamoto_20160416_m73 | 1.50 | 0.75 | 5.00 s | 80% | 106/121 | 87.6% | 15.00 s | 15.71 km | 15.63 km | 15.63 km |
| noto_peninsula_20240101_m76 | 1.50 | 0.75 | 5.00 s | 0% | 98/121 | 81.0% | 23.00 s | 2.22 km | 7.58 km | 7.63 km |
| noto_peninsula_20240101_m76 | 1.50 | 0.75 | 5.00 s | 20% | 98/121 | 81.0% | 23.00 s | 2.22 km | 7.78 km | 7.78 km |
| noto_peninsula_20240101_m76 | 1.50 | 0.75 | 5.00 s | 50% | 96/121 | 79.3% | 25.00 s | 3.71 km | 4.33 km | 4.33 km |
| noto_peninsula_20240101_m76 | 1.50 | 0.75 | 5.00 s | 80% | 87/121 | 71.9% | 34.00 s | 59.22 km | 59.47 km | 59.53 km |

## Held-out summary

- Median frame error: 10.58 km
- Median first-estimate error: 7.40 km
- Median projected-level quantization MAE: 0.083 intensity units

These values do not measure real GIF detection delay, missing frames, transport latency, or production readiness.
