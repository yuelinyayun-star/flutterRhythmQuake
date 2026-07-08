# Source Estimation P5 Stability Report

> Updated: 2026-06-25

## Scope

This report records the current P5 late-drift stability gate for NIED GIF source
estimation. It is a replay-deterministic posterior acceptance gate, not a
coordinate smoothing filter.

## Implementation

- Code: `lib/core/source_estimation/seismic_source_tracker.dart`
- NIED configuration: `lib/core/source_estimation/station_event_tracker.dart`
- Benchmark integration: `test/support/source_estimation_benchmark.dart`
- Unit coverage: `test/seismic_source_tracker_test.dart`

Policy:

- accept estimates during the warmup window;
- after warmup, reject a candidate if it jumps more than 60 km from the
  previous accepted estimate;
- also reject it if it is more than 100 km from the warmup anchor;
- held estimates reuse the previous estimate and do not increment
  `estimate_revision`;
- diagnostic metadata records the rejected candidate and rejected distances.

The stability gate is enabled for the NIED source-estimation path. Generic
source tracking remains ungated unless an explicit `SourceEstimateStabilityConfig`
is supplied.

## Current Reference Metrics

`nied_gif_hybrid_v1` after the P5 gate:

| Case | Candidate | Confirmed | Median error | P90 error | P90 jump | Estimate count |
|---|---:|---:|---:|---:|---:|---:|
| Fukushima/Miyagi offshore M3.2 | 37s | 38s | 165 km | 311 km | 4.5 km | 47 |
| Kushiro offshore M3.0 | 9s | 11s | 28 km | 118.2 km | 30 km | 42 |
| Iwate east offshore M3.0 | 15s | 18s | 40 km | 51 km | 16.3 km | 39 |
| Iwate northeast offshore M3.4 | 26s | 29s | 24 km | 54.4 km | 22 km | 47 |
| Iwate offshore M3.4 | 21s | 22s | 43 km | 54 km | 21.4 km | 53 |
| Iwate offshore M3.2 | 7s | 8s | 25 km | 66 km | 24.8 km | 56 |
| Wakayama south M2.5 | 15s | 16s | 5 km | 6.8 km | 10.4 km | 43 |
| Tomakomai south offshore M3.5 | 22s | 29s | 13 km | 55 km | 27 km | 42 |
| Fukushima offshore M2.2 countercase | 49s | -- | -- | -- | -- | 0 |

## Result

The gate fixes the largest late-frame drift on the Iwate and Wakayama reference
cases and keeps the Fukushima M2.2 false association rejected. Together with
the source-trigger continuity gate, it also suppresses the Fukushima/Miyagi
late replacement jump, but it does not fix the early one-sided offshore
absolute location error.

## Next Step

Do not continue tuning the stability thresholds first. The next algorithm step
should target offshore geometry scoring and uncertainty:

1. distinguish one-sided offshore station geometry from well-surrounded local
   support;
2. report larger uncertainty when near-source support is weak;
3. compare weighted centroid, hybrid grid search and future attenuation scoring
   per event type;
4. keep physical layers as independent observations, but do not add them to
   production scoring until multi-event validation shows stable gain.

## Geometry Diagnostic Update

Candidate-relative azimuthal gap, nearest-station distance, and search-boundary
margin are now exported by the production estimator without changing its
coordinates or confidence. The refreshed traces show that Fukushima and
Kushiro both produce one-sided south-boundary solutions, while only Fukushima
has truth outside the search box. A boundary-directed expansion alone would
therefore be underconstrained and may worsen Kushiro. The next comparison must
evaluate one-sided geometry scoring and uncertainty across all offshore cases,
with Nara retained as the surrounded inland control.

## Offshore Geometry Experiment Update

`docs/baselines/source_estimation_offshore_geometry_experiment.generated.md`
compares baseline, symmetric search expansion, expanded weak-center scoring, a
default-off centroid guard, and soft one-sided boundary penalties for one-sided
boundary solutions.

The experiment rejects symmetric expansion and expanded weak-center scoring.
The centroid guard is not production-ready because it improves Fukushima/Miyagi,
Kushiro, and one Iwate reference but worsens other Iwate offshore tails.
Soft one-sided penalties are safer but still insufficient: the strongest tested
penalty improves Kushiro P90 118.2 -> 84.7 km, but leaves Fukushima/Miyagi
unchanged and worsens one Iwate jump tail.

Next algorithm step: keep P5 thresholds and production coordinate scoring fixed.
Use the new `geometry_penalty` and horizontal uncertainty diagnostics to mark
one-sided/near-boundary frames as less reliable, then inspect attenuation or
travel-time residual features for Fukushima/Miyagi before changing production
coordinates.

## Candidate Correction Diagnostic Update

The 2026-06-23 offshore experiment adds a diagnostic-only guarded-candidate
path. `emitOneSidedBoundaryCentroidGuardCandidate` can emit
`diagnostics.candidate_corrections.one_sided_boundary_centroid_guard` without
changing the production `latitude` and `longitude`. The applied hard guard
remains default-off.

The narrow trigger tested in replay is:

- one-sided station geometry;
- search-boundary hit;
- horizontal uncertainty P90 at least 180 km;
- nearest station distance at least 80 km.

Current replay result:

| Case | Baseline P90 | Applied narrow guard P90 | Diagnostic candidate P90 | Candidate frames | Applied in diagnostic mode |
|---|---:|---:|---:|---:|---:|
| Tomakomai south offshore M3.5 | 55 km | 31 km | 27.8 km | 3 | 0 |
| Kushiro offshore M3.0 | 118.2 km | 40 km | 24.1 km | 8 | 0 |
| Iwate offshore M3.4 | 54 km | 54 km | -- | 0 | 0 |
| Iwate east offshore M3.0 | 51 km | 49 km | 63.6 km | 2 | 0 |
| Fukushima/Miyagi offshore M3.2 | 311 km | 168 km | 136.7 km | 8 | 0 |

Decision:

- keep production coordinates on the baseline estimator;
- keep the applied centroid guard default-off;
- keep diagnostic-only candidate output as the next evidence path;
- do not promote candidate coordinates until countercase and residual reports
  show frame-level baseline error versus candidate error for each large-error
  frame.

Report/tooling status: `tools/build_source_estimation_countercase_report.dart`
now shows candidate correction count, applied count, candidate median/P90
error, large-error coverage, improved large-error coverage, and worst-frame
baseline-versus-candidate error. `tools/build_source_estimation_residual_report.dart`
now shows candidate error, candidate RMS, candidate rank inversion, and median
pick-distance estimate/candidate/truth for selected frames when candidate
diagnostics are present.

Matrix status: `docs/baselines/source_estimation_offshore_geometry_experiment.generated.md`
now includes a promotion/rejection matrix. Tomakomai and Kushiro are
`positive_boundary_candidate`, Iwate offshore is `pass_no_candidate`, Iwate
east offshore is `reject_regression_risk`, and Fukushima/Miyagi is
`reject_as_primary_fix`.

Next algorithm step: inspect Fukushima/Miyagi early travel-time residuals,
attenuation residuals, and one-sided search-box construction. The candidate
correction covers only 8/47 large-error frames there, so it must stay
diagnostic-only until that separate early-frame failure mode has an
independent explanation.

Fukushima/Miyagi trace status: the refreshed
`docs/baselines/source_estimation_failure_trace.generated.md` shows the selected
Fukushima/Miyagi frames keep the truth outside the search bounding box. After
the continuity gate, the largest jump is 278 km at
`2026-06-21T23:41:51.000`, when early Fukushima/Miyagi/Iwate support expands
inside the same source-trigger event while geometry remains one-sided and the
truth is still outside the search box. Treat this as an early search-window and
travel-time/attenuation scoring failure first.

Member-evolution report:
`docs/baselines/fukushima_miyagi_m32_member_evolution.generated.md` still shows
the later source-trigger event replacement at `2026-06-21T23:42:49.000`, with
`GNM010, IBR015, KNG006, YMN002` 319.0 km from the Hi-net truth. The continuity
gate now holds that far replacement for 20 replay frames and keeps the
effective source event on `nied_gif-2026-06-21T23:41:49.000`, reducing the
late-frame jump tail.

The 2026-06-23 candidate-promotion diagnostic adds
`tools/build_source_candidate_promotion_report.dart` and
`docs/baselines/source_candidate_promotion_report.generated.md`. The gate uses
only production-available residual signals: accept a diagnostic candidate when
rank inversion or static attenuation scatter supports it, and reject when rank
and attenuation both strongly regress. Truth error is kept in a separate
offline-evaluation section.

Replay result:

| Case | Candidate frames | Accepted | Rejected | Offline false accepts | Offline missed positives |
| --- | ---: | ---: | ---: | ---: | ---: |
| Fukushima/Miyagi offshore M3.2 | 8 | 0 | 8 | 0 | 7 |
| Kushiro offshore M3.0 | 8 | 5 | 3 | 0 | 3 |
| Tomakomai south offshore M3.5 | 3 | 3 | 0 | 0 | 0 |

Decision: the diagnostic gate is useful evidence, but it is not
production-ready. It rejects the Fukushima/Miyagi false-promotion pattern, but
still misses several offline-positive Kushiro frames. Keep candidate coordinates
diagnostic-only until the broader offshore/countercase refresh finds an
additional production-available signal that recovers those positives without
accepting Fukushima.

The broader 2026-06-23 matrix refresh uses the new batch mode in
`tools/build_source_estimation_early_frame_report.dart` and writes
`docs/baselines/source_candidate_promotion_matrix.generated.md`. It covers 10
truth-labeled early-frame cases from `.dart_tool/source_estimation_benchmark`
and skips only `source_estimation_p0.json` because it has no truth
latitude/longitude.

Broader matrix result: no new false accepts. Seven cases emit no diagnostic
candidate; Fukushima/Miyagi remains fully rejected; Kushiro still has three
rejected-but-offline-positive early frames; Tomakomai remains fully accepted.

Next algorithm step: inspect the three rejected Kushiro positive frames for a
production-available recovery signal, especially geometry growth, station-member
evolution, candidate distance from the source-trigger centroid, and
consecutive-frame persistence.

The delayed-confirmation diagnostic in
`tools/build_source_candidate_promotion_report.dart` now marks a rejected
candidate recoverable only when a later candidate in the same area is accepted
within 5 seconds and 30 km. On the broad matrix it recovers all three Kushiro
missed positives after 2-4 seconds with a 13.9 km cluster distance, while
Fukushima/Miyagi has 0 delayed recoveries and 0 delayed false recoveries.

Next algorithm step: design a pending candidate-region state machine. It should
not change immediate production coordinates. It should only expose/promote a
candidate region after later residual support confirms the same spatial cluster,
then replay against Fukushima/Miyagi and Kushiro before any production switch.

The pending candidate-region state machine now exists in
`lib/core/source_estimation/source_candidate_region_tracker.dart`, with coverage
in `test/source_candidate_region_tracker_test.dart`. It keeps unsupported
candidate regions pending, confirms same-region candidates after later residual
support within 5 seconds and 30 km, and never allows an immediate production
coordinate switch. `SourceCandidateResidualGate` can derive the
`residualSupported` observation from production `SourceEstimate.diagnostics`.
`NiedGifHybridSourceEstimator` now includes station coordinates in
`top_timing_picks`, so this gate can run without the offline station DB.

Next algorithm step: wire the tracker behind diagnostics metadata only. The
integration should annotate current events with pending/confirmed candidate
region state while leaving the displayed/source `SourceEstimate` coordinate
unchanged.

`SeismicSourceTracker` now performs that metadata-only integration. It evaluates
candidate corrections with `SourceCandidateResidualGate` and annotates event
metadata as `candidate_region` and `candidate_region_residual_gate`.
`SourceEstimate.latitude/longitude` are unchanged and
`production_coordinate_switch_allowed` remains false. Tracker tests cover both
delayed confirmation without coordinate mutation and unsupported candidates
remaining pending.

Next algorithm step: replay Fukushima/Miyagi and Kushiro through the tracker
metadata path and compare the resulting `candidate_region` timeline against the
offline promotion matrix before exposing this metadata in production UI.

The metadata replay is now captured by
`tools/build_source_candidate_region_timeline_report.dart` and
`docs/baselines/source_candidate_region_timeline.generated.md`. The benchmark
export now includes per-method `eventMetadata`, so the replay report reads the
same `candidate_region` metadata that downstream UI would consume.

Result:

| Case | Candidate-region frames | Pending | Confirmed delayed | Confirmed immediate | Expired | Coordinate switches |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Fukushima/Miyagi offshore M3.2 | 8 | 7 | 0 | 0 | 1 | 0 |
| Kushiro offshore M3.0 | 8 | 3 | 1 | 4 | 0 | 0 |

Decision: the tracker metadata path matches the offline promotion matrix and
still performs zero production coordinate switches. Next step is UI/diagnostic
exposure of `candidate_region` as pending/confirmed alternative-region evidence,
not as an estimated epicenter replacement.

The unified source-estimation card now exposes this metadata in the quality
line. `AlertModule` appends candidate-region text only when
`production_coordinate_switch_allowed == false`, so the displayed hypocenter
remains the actual `SourceEstimate` coordinate. Widget coverage in
`test/source_estimation_card_test.dart` verifies that the card shows
`候选区域 待确认` while retaining the estimate coordinate.

Next UI step: consider a separate map overlay for candidate regions only after a
design pass. It must not reuse the estimated-epicenter marker or auto-focus
logic.

The map overlay is now implemented in `QuakeMapView` as a separate
candidate-region layer. It reads `candidate_region` metadata, draws a
semi-transparent 30 km minimum region circle with a status label, and remains
gated behind the existing source-estimation visibility setting. It is drawn
separately from the estimated-epicenter marker and is not used for camera
follow, P/S waves, or source-coordinate replacement.

Next UI step: visually replay Fukushima and Kushiro to verify the overlay
placement and label legibility before adding a separate setting or legend.

## 2026-06-25 Iwate Offshore Addendum

The JMA-verified Iwate offshore M3.2 event adds another useful offshore
positive case. The source trigger confirms quickly (+8 s) and the hybrid
estimator reaches a good +20 s error (26 km), but frames 1-3 are one-sided
boundary frames with 144/123/123 km baseline error. The diagnostic
candidate-region path improves those same frames to 23.8/29.1/30.0 km without
changing production coordinates. This supports continuing with delayed
candidate-region reliability evaluation rather than immediate coordinate
switching.

The refreshed 11-case promotion matrix exposes a new limitation: the current
rank/attenuation residual gate rejects all three Iwate candidate frames, and
the pending candidate-region tracker never confirms them later. This is
different from Kushiro, where delayed confirmation recovers early rejected
positives, and different from Fukushima/Miyagi, where rejecting candidates is
still desired. The next algorithm step is therefore not to loosen the existing
gate globally. Instead, inspect production-available signals that identify
Iwate-style true early one-sided candidates without accepting Fukushima/Miyagi:
candidate persistence, post-candidate baseline convergence, station-member
evolution and local support growth.

The first member-evolution pass makes local support growth the strongest next
candidate signal. Iwate starts with local source members: first-estimate
member-centroid distance is about 28.6 km, truth is inside the search box, and
members grow from 5 to 10 while the baseline estimate recovers from 144 km to
40 km. Fukushima/Miyagi starts far from truth: first-estimate member-centroid
distance is about 137.6 km, truth is outside the search box, and the later
replacement drifts to a 319 km member centroid. The next implementation should
turn this into a diagnostic gate input before any production coordinate switch.

## 2026-06-25 Local Support Gate Result

The local-support diagnostic gate is now implemented behind candidate-region
metadata only. It confirms only an existing pending candidate-region and keeps
`production_coordinate_switch_allowed=false` in every confirmed case.

The refreshed candidate-region timeline separates the cases as intended:

| Case | Result |
| --- | --- |
| `20260625_iwate_offshore_m32_jma` | local-support `confirmedDelayed` after 3 pending frames |
| `20260621_fukushima_offshore_m32_eq6` | pending/expired only, no local-support confirmation |
| `20260622_kushiro_offshore_m30_jma` | existing residual delayed/immediate confirmations preserved |
| `20260622_tomakomai_south_offshore_m35_hinet` | residual immediate confirmations only, no local-support confirmation |
| `20260623_tokachi_southeast_offshore_m34_hinet` | no candidate-region frames |

The important guard added after replay is that local support must start from a
low-member pending frame and then cross the member threshold. This blocks the
Fukushima/Miyagi replacement segment, where the new pending candidate already
starts with mature member support and should not be recovered by this gate.

Tokachi and Tomakomai have now been replayed through the same metadata path.
They show no local-support false recovery. The timeline tool defaults now cover
the six core cases above.

The first UI exposure is now in the unified source-estimation card quality
line. When `candidate_region_local_support_gate` exists, the card appends local
member count/growth, estimate-to-member-centroid distance and convergence to the
candidate-region status. This remains diagnostic-only: the card still renders
the current `SourceEstimate` hypocenter and does not switch to candidate-region
coordinates.

`DebugPage` now provides the fuller read-only view in the `NIED Source
Estimation` card. It shows candidate-region status/reason/point, coordinate
switch flag, residual gate support and local-support member/geometry convergence
from the same metadata. This is still diagnostic-only.

The six-case timeline now has an automated local guard:
`test/source_candidate_region_timeline_report_test.dart`. It consumes the
generated `source_candidate_region_timeline_report/report.json` and asserts
that coordinate switches remain zero, Iwate is the only local-support recovered
case, Fukushima/Miyagi is not recovered, Kushiro/Tomakomai keep their residual
confirmation behavior and Tokachi/Aizu remain without candidate-region frames.
Run it after regenerating the timeline report.

The timeline report itself now carries the same check as
`validation.status`/`validation.violations`, and the generated Markdown includes
a `Validation` section. The current six-case report passes with no violations.
It also splits delayed confirmations by evidence source: Kushiro is the only
residual-delayed confirmation, while the Iwate M3.2 recovery is the only
local-support-delayed confirmation.

Use `tools\validate_source_candidate_region_timeline.ps1` for the local guard.
It regenerates the timeline report and immediately runs the timeline test, so a
stale JSON report cannot accidentally pass review.
The timeline builder now reads
`docs/data/source_candidate_region_validation_manifest.json` by default. That
manifest records each replay case's validation role, benchmark input and
expected diagnostic counters. Add future live/replay cases there first, then run
the suite; do not hand-edit the generated timeline expectations.

Use `tools\validate_source_candidate_promotion_matrix.ps1` for the residual
promotion guard. It rebuilds the early-frame matrix, regenerates
`source_candidate_promotion_matrix.generated.md`, and verifies that the residual
gate still has zero offline false accepts and zero delayed false recoveries
while preserving the current Fukushima/Iwate rejection and Kushiro/Tomakomai
acceptance behavior. The promotion report now also carries this check as
`validation.status` and `validation.violations`.

Use `tools\validate_source_candidate_region_suite.ps1` after adding or
refreshing replay cases. It runs both the residual promotion guard and the
local-support timeline guard in sequence, then runs the lightweight validation
script structure test. A successful run writes
`.dart_tool/source_candidate_region_suite/summary.json`, including the embedded
report validation status and violations from the promotion matrix and timeline.
The suite exits with failure if either embedded report validation is not `pass`
or has any violations.
`test/source_candidate_validation_scripts_test.dart` protects the guard scripts
from being reordered or reduced to only one matrix.
`test/source_candidate_region_suite_summary_test.dart` checks the generated
summary artifact itself after the suite writes it.

For the broader source-estimation guard, use
`tools\validate_source_estimation_suite.ps1`. It runs the split audit first and
then the candidate-region suite, writing
`.dart_tool/source_estimation_validation_suite/summary.json`. This does not
expand the candidate-region production role; it only proves the current
diagnostic metadata and split isolation guards are fresh.
The split audit now includes the second independent quiet-window fixture
`quiet_20260625_233535_jst_live`; the quiet-window target/current/remaining
state is `2/2/0`, and the quiet replay test verifies zero detection candidates,
zero confirmations and zero source estimates across 300 decoded frames.

Next step: observe more live/replay events. If future offshore cases show false
recovery, tune only the local-support thresholds; do not loosen the residual
rank or attenuation gate and do not enable production coordinate switching from
this metadata.

## Split Assignment Readiness Queue

The source-estimation validation suite now includes a stronger split assignment
readiness report. Besides proving that no `unassigned_reference` case enters
frozen metrics, the report identifies which cases are blocked only by manual
event-level split assignment.

Current state:

| Metric | Value |
| --- | --- |
| Ready for frozen split | 1 |
| Ready for manual split assignment | 0 |
| Manual split assignment pending | 12 |

`20260622_fukushima_offshore_m22_eq4` has now completed the constrained
reference-only split assignment: it is in validation as `validation_reference`,
while `includeInDetectionMetrics=false`, `catalogTruthVerified=false` and the
no-final-test-claims constraint remain intact. Recent JMA source/intensity
cases remain blocked by final-catalog linkage, and Hi-net preliminary cases
remain blocked by truth-quality review.

The split assignment plan still records the constrained recommendation for that
case so the patch dry-run remains idempotent and auditable.

This keeps the candidate-region and local-support work from leaking into frozen
train/validation/test metrics while still exposing a concrete next action for
dataset curation.

The split assignment is mechanically auditable. The patch dry-run tool
`tools/build_source_estimation_split_assignment_patch.dart` produces
`docs/baselines/source_estimation_split_assignment_patch.generated.md` without
modifying the split manifest. The current dry-run reports one already-applied
proposal for `20260622_fukushima_offshore_m22_eq4`, with zero ready-to-apply
actions. The source-estimation validation suite runs this dry-run guard and
records `applyRequested=false`; the guarded test still executes `--apply` on
temporary files, confirming that the apply path edits only the requested split
manifest and fixture.

The remaining blockers now have their own queue report:
`docs/baselines/source_estimation_split_blocker_queue.generated.md`. The queue
is regenerated by `tools\validate_source_estimation_split_blocker_queue.ps1`
after readiness, and the full source-estimation suite records it before the
patch dry-run. Current queue state is 12 blocked cases and one completed split
assignment. The action buckets are 3 JMA catalog links, 6 Hi-net preliminary
truth reviews, 1 Hi-net truth review, 1 final-catalog-or-Hi-net-revision link
and 1 Noto trigger-threshold/capture review. This gives the next curation work a
stable order without allowing ad hoc train/validation/test assignment.
