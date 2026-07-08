# P3 Static Intensity Attenuation Baseline

- Model: `static_intensity_attenuation_v1`
- Training source: JMA final station intensity synthetic-reveal dataset,
  2020-2022
- Training split: `train`
- Evaluation split: `validation`
- Frozen test split: not evaluated
- Production status: diagnostic baseline only

## Parameters

| Parameter | Value |
| --- | ---: |
| log-distance coefficient | 3.0 |
| linear-distance coefficient | 0.0 |
| near-distance km | 20.0 |
| Huber delta | 1.0 |
| robust residual scale | 0.4342412309688169 |
| centroid penalty / km | 0.0025 |

## Validation

| Metric | P3 | Weighted centroid |
| --- | ---: | ---: |
| Median error | 33.98 km | 35.68 km |
| P90 error | 92.55 km | 94.91 km |

| Coverage | Value |
| --- | ---: |
| P50 coverage | 60.3% |
| P90 coverage | 78.2% |

## Mask Rates

| Mask | Cases | P3 median | P3 P90 | Centroid median |
| ---: | ---: | ---: | ---: | ---: |
| 20pct | 896 | 33.04 km | 91.49 km | 35.43 km |
| 50pct | 896 | 33.59 km | 92.59 km | 34.83 km |
| 80pct | 896 | 35.43 km | 93.56 km | 36.92 km |

## Decision

- The baseline is usable as a reference model for intensity-only source
  inversion and attenuation diagnostics.
- The improvement over weighted centroid is small, so it is not production
  ready.
- Frozen test remains unopened. Do not tune thresholds or production behavior
  from this validation report alone.
- This is not yet a real-time maximum-shindo forecast model; it uses final
  peak station intensities with synthetic reveal masks.
