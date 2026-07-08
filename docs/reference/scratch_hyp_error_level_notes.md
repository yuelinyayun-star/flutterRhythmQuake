# `scratch-realtime-earthquake-viewer-page` HYP error-level calculation notes

This note translates the extracted HYP blocks carried by
`scratch-realtime-earthquake-viewer-page` into a portable algorithm sketch for
later Dart work. The project name is important: the public repository is the
JS/SB3 carrier we can inspect; the algorithmic reference is treated here as
JQ/JQuake-style NIED/KMoni GIF reverse decoding, not as an independent
"Scratch algorithm". This note is derived from:

- `docs/reference/scratch_hyp_algorithm_extracted.md`;
- `docs/reference/scratch_hyp_algorithm_blocks.json`;
- procedure `HYP:誤差レベル計算`;
- procedure `JMA2001距離近似`.

It is reference-only. Production still uses `nied_gif_hybrid_v1`; current
`nied_gif_hyp_v1` remains diagnostic-only.

## Inputs

`HYP:誤差レベル計算` receives:

| Scratch argument | Meaning in our terms |
|---|---|
| `経度X` | candidate longitude |
| `緯度Y` | candidate latitude |
| `深さ` | candidate depth km |
| `対象id` | detection/source id being scored |
| `おふせ` | candidate direction label/index used by caller |
| `4-3offset` | offset into the detection-id metadata list |

The candidate origin time is not passed as a normal argument. The procedure
derives the best origin time from station residuals:

```text
originCandidate = mean(observedStationTime - predictedTravelTime)
```

Then the candidate error is the weighted spread around that mean.

## Candidate bounds

The procedure rejects candidates before scoring when:

- depth `< 10 km`;
- depth `> 700 km`;
- depth `> @hyp:許可最大深さ`;
- longitude outside `115..155`;
- latitude outside `15..55`;
- distance from candidate to the first detected point exceeds
  `@hyp:許可最大距離`.

The distance from candidate to the first detected point is floored at `50 km`
for weight normalization.

## JMA2001 distance/travel-time approximation

`JMA2001距離近似` is the travel-time conversion kernel. It uses a six-term
polynomial-like approximation from list `d JMA2001走時表近似式`.

Approximate structure:

```text
result = 0
for n in 1..6:
  coefficientIndex =
      n
      + round(depthKm / 10) * 6
      + (426 if S-wave else 0)
      + (852 if travelTimeCalculation else 0)
  coefficient = JMA2001_TABLE[coefficientIndex]
  result += input^n * coefficient

hypocentralDistanceOrTravelTime = result
epicentralDistance =
    result * sin(acos(depthKm / result))
  = sqrt(result^2 - depthKm^2)
```

The boolean parameters select:

- P vs S table branch;
- travel-time calculation vs inverse distance/radius calculation.

This is materially different from our current diagnostic HYP, which uses fixed
wave speeds (`P=6.0 km/s`, `S=3.5 km/s`) instead of the JMA2001 table
approximation.

## P/S radius pre-pass

Before iterating stations, the procedure computes P and S epicentral radii from
the current elapsed time:

```text
elapsed = currentCloudTime - previousCandidateOrigin
pRadius = JMA2001(elapsed, depth, P-wave, inverse)
sRadius = JMA2001(elapsed, depth, S-wave, inverse)
radiusCap = 100 + detectedPointCount * 3
pRadius = min(pRadius, radiusCap)
sRadius = min(sRadius, radiusCap)
```

These radii are used mainly to limit candidate station/unarrived-wave checks.

## Triggered station residuals

For stations associated with the target detection id:

1. Compute epicentral distance from candidate to station.
2. Compute hypocentral distance:

   ```text
   hypoDistance = sqrt(depthKm^2 + epicentralDistanceKm^2)
   ```

3. Select phase:

   ```text
   useS =
       currentTime > firstDetectedTime + 15s
       and stationHasSFlag
   phase = S if useS else P
   ```

   This is the key phase-origin semantic: the reference does not first cluster
   P-origin and S-origin candidates and then choose the phase by nearest
   residual. It also does **not** read an externally observed GIF/S-pick field
   for `stationHasSFlag`.

   Re-reading `scratch-realtime-earthquake-viewer-page` shows that
   `stationHasSFlag` is the per-candidate derived flag stored at:

   ```text
   ten:推定用[(pointIndex - 1) * 10 + 6]
   ```

   The exact HYP condition is block `GZ`:

   ```text
   ((@hyp:最初検知時刻 + 15) < #r:最新クラウド変数[1])
   AND ten:推定用[(多目的2 + 6)]
   ```

   The flag itself is written by block `Yd`:

   ```text
   ten:推定用[(番号 - 1) * 10 + 6] =
     abs(ten:推定用[(番号 - 1) * 10 + 1]
       - ten:推定用[(番号 - 1) * 10 + 8])
     <
     abs(ten:推定用[(番号 - 1) * 10 + 1]
       - ten:推定用[(番号 - 1) * 10 + 7])
   ```

   Blocks `l|` and `l~` confirm the phase cache:

   ```text
   +7 = candidateOriginTime + JMA2001(..., P波=true,  走時計算=true)
   +8 = candidateOriginTime + JMA2001(..., P波=false, 走時計算=true)
   ```

   Therefore the portable interpretation is:

   ```text
   stationHasSFlag =
       abs(observedTime - predictedSArrival)
       < abs(observedTime - predictedPArrival)
   useS = elapsedSinceFirstDetection > 15s and stationHasSFlag
   ```

   In our data there is no separate field to hunt for. The faithful diagnostic
   port must derive the same flag from each candidate's origin/depth and P/S
   travel-time predictions.

### What changes the derived S flag

The `+6` flag depends on more than the final HYP candidate. The inspected
blocks show this state chain:

1. `ten:推定用[(番号 - 1) * 10 + 1]` is the station observation time used by
   HYP. It is not always simply "current frame time":

   ```text
   if a pre-trigger/rise cache exists at +5:
     +1 = +5
     +2 = +5
   else if a nearby 7-point cluster has an older accepted time and it is
           more than 20 s before current cloud time:
     +1 = that older nearby time
     +2 = current cloud time
   else:
     +1 = current cloud time
     +2 = current cloud time
   ```

   Therefore our replay-side `firstTriggerAt`/`firstRiseAt` choice can shift the
   S flag even when the same stations are present.

2. `ten:推定用[(番号 - 1) * 10 + 3]` is the detection id attached to the station.
   `検出id3_点にIDを登録` either assigns an existing id found by
   `検出id4_点に適用するべきIDを検索` or creates a new id, then writes the id to
   both `ten:推定用 +3` and the grid-level `grid:検出id`.

3. `ten:推定用[(番号 - 1) * 10 + 4]` is a station-to-first-detection distance
   cache. `検出id距離計算` computes it in pixel space and also updates the
   detection id's max distance in `4-3 検出id別情報[(offset + 5)]`.

4. `推定用tenPS時間計算(番号, id)` recomputes `+7/+8/+6` from the current
   detection source cache. It is called in two important places:

   ```text
   検出id適用数カウント追加(..., 距離セット=true, ...)
     -> 推定用tenPS時間計算(番号, ten:推定用[+3])
     -> 検出id距離計算(...)

   検出id_推定PS時間id別再計算(id)
     -> scan grid points whose ten:推定用[+3] == id
     -> 推定用tenPS時間計算(point, id)
   ```

5. `推定用tenPS時間計算` clears `+7/+8` when the detection id is stale or has no
   source cache:

   ```text
   if 3000 < 4-3 検出id別情報[(id - 1) * 20 + 11]
      or 4-4 検出id震源要素[(id - 1) * 10 + 2] is empty:
     +7 = empty
     +8 = empty
   ```

6. The source cache used for `+7/+8` is `4-4 検出id震源要素` with a 10-item
   stride:

   ```text
   +2 = source longitude
   +3 = source latitude
   +4 = depth
   +5 = origin time
   +6/+7 = P/S radii or auxiliary caches used elsewhere
   ```

   New ids are initialized around the first detected point with depth `10` and
   origin time from `4-3 検出id別情報[(offset + 3)]`. HYP later writes the best
   candidate back:

   ```text
   +2 = @hyp:震源候補 経度X
   +3 = @hyp:震源候補 緯度Y
   +4 = @hyp:震源候補 深さ
   +5 = @hyp:震源候補 発生時刻
   ```

7. The 15 s S gate uses the detection id's first detection time, not the
   station observation time:

   ```text
   @hyp:最初検知時刻 = 4-3 検出id別情報[(4-3offset + 3)]
   useS = (#r:最新クラウド変数[1] > @hyp:最初検知時刻 + 15)
          and ten:推定用[+6]
   ```

8. Early HYP has a separate initial-source rule. If the source cache is empty or
   the detection id age is under 10 s, the provisional source is seeded from the
   first detected point with:

   ```text
   provisionalDepth = 10
   provisionalOrigin = @hyp:最初検知時刻 - 2
   ```

   This means early-frame S/P behavior is strongly affected by the reference
   state machine's provisional source, not just by final candidate scoring.

4. Convert hypocentral distance to predicted travel time using
   `JMA2001距離近似(..., travelTimeCalculation=true)`.
5. Store residual origin-time candidate:

   ```text
   residualTime = observedStationTime - predictedTravelTime
   ```

6. Store distance weight:

   ```text
   stationDistanceForWeight = max(50, epicentralDistanceKm)
   weight = firstDetectedDistanceKm / stationDistanceForWeight
   ```

The procedure also counts S-phase assignments. Later, more S support reduces
the final error multiplier.

## Unarrived-wave penalty

For stations/points that are not associated with the target id, the procedure
adds an unarrived candidate when the station is geographically relevant:

```text
if stationDistance < pRadius + 30
   or stationGridAlreadyBelongsToTarget:
  predictedPTravelTime = JMA2001(hypoDistance, depth, P-wave, travelTime)
  unarrivedTravelTimes.add(predictedPTravelTime)
```

After the best origin time is computed, each unarrived candidate contributes a
flat penalty if the P wave should already have arrived:

```text
if unarrivedTravelTime + originCandidate < currentTime:
  squaredError += 1
```

So the JQ-style unarrived penalty is a count-like penalty, not a
continuous overdue-seconds penalty. Our current `nied_gif_hyp_v1` instead uses a
continuous overdue penalty, so this is a porting difference to test.

## Final error formula

Let:

```text
N = triggeredResiduals.length
originCandidate = mean(triggeredResiduals)
weightedSquaredResidual =
    sum_i(weight_i * (triggeredResidual_i - originCandidate)^2)
weightedCount = sum_i(weight_i)
unarrivedPenalty = count of overdue unarrived P waves
```

Then:

```text
baseVariance =
    (weightedSquaredResidual + unarrivedPenalty) / weightedCount

sFactor =
    1 - (sCount * 3 / N)
sFactor = max(0.25, sFactor)

sampleSizePenalty =
    30
    + 20000 / (1 + N^2)
    + 2000 / (50 + N)

errorLevel =
    sFactor * baseVariance * sampleSizePenalty
```

If `errorLevel < @hyp:最小誤差レベル`, the procedure updates:

- best error level;
- candidate longitude;
- candidate latitude;
- candidate depth;
- candidate origin time (`originCandidate`);
- distance from first detected point to candidate.

## Search caller shape

`HYP:震源検出` and the compare procedures do a staged local search around the
current provisional source:

```text
start-h2
start-h10
start-h10-v50
start-h10-v10
start-h60
```

`HYP:誤差レベル比較` tries neighboring candidates in longitude, latitude, and
depth. `HYP:誤差レベル比較繰り返し` repeats that comparison until the search stops
improving or reaches the configured limit.

## Porting implications for our algorithm

1. Replace fixed P/S speeds with a JMA2001 table approximation experiment.
2. Score origin time as the mean of `observed - predictedTravelTime`, then score
   residual spread around that mean.
3. Use distance weights based on the first detected station distance.
4. Treat S support as a multiplier that can reduce final error down to `0.25x`.
5. Test JQ-style flat unarrived penalties against our current continuous
   overdue penalty.
6. Keep this as `nied_gif_hyp_jma2001_experiment` first; do not promote it to
   production coordinates until replay metrics beat the current hybrid safely.

## Implemented experiment hook

Implemented the synchronous helper:

- `lib/core/source_estimation/jma2001_travel_time_approximation.dart`;
- test: `test/jma2001_travel_time_approximation_test.dart`.

The helper embeds the `1704` JMA2001 coefficients extracted from the
`scratch-realtime-earthquake-viewer-page` carrier as a Dart `const` table and
uses the verified index formula:

```text
offset =
    round(depthKm / 10) * 6
    + (426 if S-wave else 0)
    + (852 if travel-time calculation else 0)
```

This was checked against the existing `assets/travel_times.json` JMA2001 table;
the no-`+1` depth-bin offset is the matching formula.

`NiedGifHybridSourceEstimator` now has an opt-in diagnostic switch:

```dart
emitJma2001HypExperiment: true
```

When enabled, diagnostics include:

```text
diagnostics.nied_gif_hyp_jma2001_experiment
```

The switch defaults to `false` so production does not pay for a second HYP grid
search until replay metrics justify it.
