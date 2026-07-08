# Static Intensity Probability Gate Literature Notes

Date: 2026-06-27

Scope: literature support for converting the `gt_200km` positive residual into
a threshold probability/confidence gate instead of directly mutating raw
predicted intensity fields.

## Sources

1. JMA, "Limitations of the Earthquake Early Warning"
   <https://www.jma.go.jp/jma/en/Activities/eew3.html>

   JMA explicitly lists seismic-intensity estimation as limited by statistical
   attenuation formulas and land-surface amplification prediction. This supports
   keeping the current correction diagnostic-only until it is validated as an
   uncertainty/confidence component.

2. Hoshiba et al., "How precisely can we anticipate seismic intensities? A
   study of uncertainty of anticipated seismic intensities for the Earthquake
   Early Warning method in Japan"
   <https://link.springer.com/article/10.5047/eps.2010.07.013>

   The paper frames predicted ground motion as source, path and site factors.
   It notes that JMA EEW uses a distance/depth attenuation formulation, and
   that source and site factors represented as scalars leave substantial
   uncertainty. This matches our observed distance residual: a single static
   attenuation model cannot safely explain all far-field station behavior.

3. Nojima, "Uncertainties of Seismic Intensities Predicted by Use of Seismic
   Source Information Provided by Earthquake Early Warning"
   <https://www.jstage.jst.go.jp/article/jisss/13/0/13_397/_article/-char/en>

   The abstract describes error propagation from magnitude, depth and epicenter
   estimates into PGV/JMA intensity estimates, and models probability
   distributions of realistic intensity conditional on estimated intensity from
   actual JMA EEW records. This directly supports our next step: estimate
   threshold exceedance probability conditional on predicted intensity plus
   distance/residual features.

4. Minson et al., "The limits of earthquake early warning accuracy and best
   alerting strategy"
   <https://pubs.usgs.gov/publication/70215102>

   The paper emphasizes that ground-motion variability causes unavoidable false
   and missed alerts, even when source information is correct. It supports
   evaluating alert strategy as a false-alert/missed-alert tradeoff rather than
   optimizing only point predictions.

5. JMA, "PLUM method"
   <https://www.data.jma.go.jp/eew/data/nc/plum/index.html>

   JMA explains that PLUM predicts intensity directly from observed shaking
   without estimating source or magnitude, and that current JMA prediction uses
   a hybrid of conventional and PLUM methods. This is relevant because our
   probability gate should remain a threshold decision layer, not a replacement
   for the source/intensity field itself.

6. Kagawa et al., "Application of the Modified PLUM Method to a Dense Seismic
   Intensity Network of a Local Government in Japan"
   <https://www.frontiersin.org/journals/earth-science/articles/10.3389/feart.2021.672613/full>

   The paper reports overestimation from undamped propagation and introduces
   attenuation/damping in propagation; one demonstration uses an intensity
   decrease of 1.0 per 10 km. This supports our finding that distance-dependent
   residuals can strongly affect high-intensity false positives, but it also
   warns that damping choices are model assumptions requiring validation.

7. Yamada et al., "Earthquake early warning for the 2016 Kumamoto earthquake:
   performance evaluation of the current system and the next-generation methods
   of the Japan Meteorological Agency"
   <https://link.springer.com/article/10.1186/s40623-016-0567-1>

   The paper describes PLUM using real-time intensities at stations within
   30 km of target points and reports overprediction from a mismatch in
   strong-motion attenuation. This reinforces that distance/attenuation
   mismatch is a known failure mode.

8. Meier et al., "How good are real-time ground motion predictions from
   Earthquake Early Warning systems?"
   <https://agupubs.onlinelibrary.wiley.com/doi/10.1002/2017JB014025>

   The abstracted search result states that site alert decisions may be based
   either on a scalar ground-motion prediction exceeding a threshold or on
   exceedance probability exceeding a probability threshold. This supports
   comparing a probability gate against the raw threshold baseline.

## Project Decision

- Do not apply the `gt_200km` correction directly to runtime predicted
  intensity fields.
- Convert the far-distance residual into a diagnostic probability feature:
  `P(observed_shindo >= threshold | predicted_shindo, distance_bucket,
  residual_corrected_prediction, uncertainty_bucket)`.
- Evaluate shindo `3`, `4`, and `5-` thresholds separately.
- Select operating points by validation precision/recall/F1 and
  underestimation constraints, not by station MAE alone.
- Keep frozen test closed until the probability gate has fixed validation
  acceptance criteria.

## Immediate Implementation Plan

1. Build `static_intensity_probability_gate` validation report.
2. Inputs per station prediction:
   - raw predicted intensity;
   - distance bucket;
   - `gt_200km` residual-corrected predicted intensity;
   - event maximum predicted class;
   - location uncertainty bucket where available.
3. For each threshold (`shindo3`, `shindo4`, `shindo5-`), scan probability
   operating points and compare:
   - raw threshold baseline;
   - hard `gt_200km` residual correction;
   - probability gate.
4. Acceptance direction:
   - improve shindo `4` and `5-` precision;
   - do not materially reduce recall;
   - do not change raw intensity field or maximum-shindo display.
