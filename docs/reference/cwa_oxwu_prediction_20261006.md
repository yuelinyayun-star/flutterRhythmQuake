# CWA prediction audit against the installed desktop client

## Scope and evidence

Audited the installed OXWU 4.2.0 client on 2026-10-06. Its original compiled
renderer was loaded in a separate offline Electron RunAsNode process. Network,
notifications, audio and real DOM operations were not enabled. Installation
files and the running client's settings were not edited.

The audit invokes the original `getDistanceCWB`, `getIntensity` and
`updateWarningIntensity` functions. This is a numerical interoperability check,
not a source-code extraction or a license to redistribute the client's assets.

Original input evidence:

- User replay: `RhythmQuake_1791276087572.rqreplay`, SHA-256
  `703f6dea6ed9fc5ed9d4b886798581621fd26d0f9d895f2dbda9990bab872ea9`.
- Its unchanged Jian `sourcePayload`: event `1150075`, latitude `22.45`,
  longitude `120.34`, depth `30 km`, magnitude `4.7`, report `1`.
- Two published EEW parameter rows from
  <https://eew.earthquake.tw/?act=eew_detail&identifier=1130465>:
  `(23.88, 121.54, 20 km, M6.8)` and `(23.89, 121.56, 20 km, M6.8)`.
  These are EEW estimates, not the later final M7.2 earthquake report.
- Downloaded historical HTML SHA-256:
  `28bd2f1e4834066ab92043c96c5b33e157ba58d9d252fc0fe5e0c7ec526d38bd`.
- Original renderer SHA-256:
  `e67ad0aa1ddf439f79c12e7187110c84d7fc00986e3e2fdffa8466bdc6dd0539`.
- Original location table SHA-256:
  `14a39bc4b3749af9b9cc6d6d2a69f5b95b7696daa8f869988d2b6c8c2356a3fb`.

## Verified numerical path

Let `L = (latitudeOrigin + latitudeTown) / 2`, in degrees.
The following independent distance expression reproduced the client results:

```text
kmPerLatitudeDegree =
  -0.000003885162 L^3 + 0.0005279958 L^2 - 0.004162794 L + 110.60424
kmPerLongitudeDegree =
   0.0000614022 L^3 - 0.0204 L^2 + 0.091614 L + 110.44248

dx = (longitudeOrigin - longitudeTown) * kmPerLongitudeDegree
dy = (latitudeOrigin - latitudeTown) * kmPerLatitudeDegree
surfaceDistanceKm = sqrt(dx^2 + dy^2)
R = sqrt(surfaceDistanceKm^2 + depthKm^2)
PGA = 1.657 * e^(1.533 * magnitude) * R^(-1.607) * siteFactor * pgaAdj
```

The original helper takes depth and returns surface distance in metres. Unit
conversion must not be skipped when integrating with the app's kilometre fields.

Verified PGA boundaries, in Gal, with increasing grade at each boundary:

| PGA Range | Grade | Original Numeric Representation |
| --- | --- | --- |
| < 0.8 | 0 | 0 |
| 0.8 to < 2.5 | 1 | 1 |
| 2.5 to < 8 | 2 | 2 |
| 8 to < 25 | 3 | 3 |
| 25 to < 80 | 4 | 4 |
| 80 to < 140 | 5 weak | 5 |
| 140 to < 250 | 5 strong | 5.5 |
| 250 to < 440 | 6 weak | 6 |
| 440 to < 800 | 6 strong | 6.5 |
| >= 800 | 7 | 7 |

These half-step representations are discrete grades, not continuous instrumental
intensity. Do not use ordinary rounding on them. The tested desktop path uses PGA
boundaries; it is not the legacy TREM PGA-to-log-intensity / high-intensity PGV
replacement path, nor the app's Chinese intensity estimator.

The desktop fill works on 368 town reference points. Its `applySiteEffect`
setting was enabled in the actual installed configuration. The public TREM
legacy location table matched all 368 desktop latitude/longitude entries and
all explicitly provided desktop site factors. This verifies the table, not the
TREM calculator. No proprietary location or boundary file has been added to
production assets by this audit.

## Validation Results

- Three real EEW parameter sets times 368 towns: 1,104 comparisons.
- Independently calculated grades vs original `getIntensity`: zero differences.
- Independently calculated fill categories vs original
  `updateWarningIntensity`: zero differences across all 1,104 towns.
- Independent distance expression vs original helper: maximum absolute error
  `1.1641532182693481e-10` metres across these comparisons.
- Nine PGA boundaries, with a mathematical probe immediately below and above
  each boundary: 18 checks, zero differences. These probes are unit tests, not
  fabricated source events or modified replay packets.
- The user's replay yields maximum predicted grade 3 under the audited inputs.

All event comparisons above use `pgaAdj = 1`. This is an explicit audit parameter,
not an observed value from a captured live OXWU packet. The user's original Jian
packet has no `pgaAdj` field.

## Integration Constraints

The OXWU ingress accesses `messages[0].pgaAdj` and passes it into its prediction
path. Omitting this argument from its original helper produces a non-finite
result; the original renderer does not establish a default of 1 at that point.
Its live upstream value and origin still require verification before claiming
unconditional equivalence for all live messages.

The official website's county reference-point aggregation must not be treated
as the desktop town fill oracle. For example, the published event `1150075`
county table lists Pingtung at grade 2, while the audited desktop town path with
site effect enabled and `pgaAdj = 1` includes Pingtung towns at grade 3.
Source: <https://eew.earthquake.tw/?act=eew_detail&identifier=1150075>.

Production map code has not been changed by this investigation. Current issues
to fix once the upstream correction question is resolved:

- `quake_map_view.dart` currently selects the Chinese-intensity fill mode for CWA.
- `TopoJsonLoader.loadTwEew()` currently returns the full China dataset rather
  than a separate Taiwan dataset.
- Taiwan prediction must not fall back to a polygon centre or a Chinese
  attenuation formula when a reference point is missing.
- Use the app's existing CWA palette for display, not the client's colors.
- Do not alter any original report fields, and do not overwrite a source-supplied
  intensity with a locally estimated value.

Local diagnostic artifacts: `tmp/oxwu-reference/probe.cjs`,
`tmp/oxwu-reference/probe.result.json`, `tmp/oxwu-reference/extract_eew.py`.
These are offline audit tools, not application runtime dependencies.
