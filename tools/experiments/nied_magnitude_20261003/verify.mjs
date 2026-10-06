import assert from 'node:assert/strict';
import fs from 'node:fs';
import crypto from 'node:crypto';
import {createRequire} from 'node:module';

const require = createRequire(import.meta.url);
const {loadScratchMagnitudeRuntime, runScratchMagnitude} =
  require('../../run_srev_kaizou_magnitude.js');

const root = '.dart_tool/magnitude_review_20261003';
const read = (file) => JSON.parse(fs.readFileSync(file, 'utf8'));
const original = read(`${root}/production_audit/report.json`);
const filtered = read(`${root}/timing_filter_audit/report.json`);
const additional = read(`${root}/complete_small_captures/report.json`);
const hash = crypto.createHash('sha256').update(fs.readFileSync(
  'lib/core/source_estimation/source_estimator.dart')).digest('hex');
const close = (actual, expected) => assert.ok(Math.abs(actual - expected) < 1e-8,
  `${actual} != ${expected}`);
for (const report of [original, filtered, additional]) {
  assert.equal(report.solverSha256, hash);
  assert.equal(report.labelsUsedInInference, false);
  assert.equal(report.timerClock, 'original_frame_timestamps');
}
let identicalFrames = 0;
for (const c of filtered.cases) {
  const before = original.cases.find((b) => b.id === c.id);
  assert.ok(before);
  assert.equal(c.rawInputSha256, before.rawInputSha256);
  assert.equal(c.frames.length, before.frames.length);
  for (let i = 0; i < c.frames.length; i++) {
    assert.equal(c.frames[i].observedAtJst, before.frames[i].observedAtJst);
    for (const key of ['latitude', 'longitude', 'depthKm', 'magnitude']) {
      assert.equal(c.frames[i].estimate?.[key], before.frames[i].estimate?.[key]);
    }
    identicalFrames++;
  }
}
const frame = (caseId, timeJst) => {
  const c = filtered.cases.find((c) => c.id === caseId);
  assert.ok(c);
  const f = c.frames.find((f) => f.observedAtJst.startsWith(timeJst));
  assert.ok(f?.estimate && f.magnitudeAudit?.singleSourceComparable);
  assert.equal(Date.parse(f.magnitudeAudit.observedAtUtc), Date.parse(timeJst + '+09:00'));
  return f;
};
const yamanashi = frame('20260627_yamanashi_east_fuji_five_lakes_m24_jma_p2p',
  '2026-06-27T00:33:20');
const a = yamanashi.magnitudeAudit;
assert.equal(a.strongestStationCode, 'YMN002');
assert.equal(a.strongestStationHasTrigger, false);
assert.equal(a.strongestStationTriggerStamp, null);
close(a.allActiveHeldConvertedIntensity, 1.16);
close(a.timedActiveHeldConvertedIntensity, -1.17);
close(a.publishedMagnitude, a.freshTimedHeldMagnitude);
close(a.freshHeldMagnitude - a.freshTimedHeldMagnitude, 2.33);
assert.equal(filtered.cases[0].missingFrameCount, 5);

const kiiFrame = frame('20261003_kii_screenshot_214551_jst_candidate',
  '2026-10-03T21:46:20');
const kii = kiiFrame.magnitudeAudit;
assert.equal(kii.publishedDiagnostics.srev_kaizou_magnitude_locked, true);
close(kii.freshHeldMagnitude, kii.freshTimedHeldMagnitude);
close(kii.freshTimedHeldMagnitude - kii.publishedMagnitude, 0.33);

// Execute original Scratch formula blocks with this captured diagnostic pair.
// This verifies formula/update semantics, not the full SREV detector pipeline.
const runtime = loadScratchMagnitudeRuntime();
const scratchFirst = runScratchMagnitude({
  id: 'captured_kii_update_semantics',
  latitude: kiiFrame.estimate.latitude,
  longitude: kiiFrame.estimate.longitude,
  inputIntensity: kii.publishedDiagnostics.srev_kaizou_magnitude_input_intensity,
  dartMagnitude: kii.publishedMagnitude,
}, runtime);
close(scratchFirst.scratchMagnitude, kii.publishedMagnitude);
Object.values(runtime.stage.variables).find((v) =>
  v.name === '4リアルタイム状況(最大震度など)').value[0] =
    kii.timedActiveHeldConvertedIntensity;
runtime.interpreter.runStack(runtime.foreverSubstackId, new Map(), '');
const scratchNext = Number(Object.values(runtime.stage.variables).find((v) =>
  v.name === '4-6 推定まぐ').value[0]);
close(scratchNext, kii.freshTimedHeldMagnitude);

const aizu = frame('20260624_fukushima_aizu_m32_jma_eq5',
  '2026-06-24T13:24:49').magnitudeAudit;
close(aizu.freshTimedHeldMagnitude, aizu.publishedMagnitude);
close(aizu.instantaneousRawMagnitude - aizu.publishedMagnitude,
  aizu.allActiveRawMaximumIntensity - aizu.rawMaximumConvertedIntensity);

const deep = frame('20260702_fukushima_aizu_m46_jma_p2p',
  '2026-07-02T20:50:00');
assert.equal(deep.estimate.depthKm, 150);
close(deep.magnitudeAudit.freshTimedHeldMagnitude - deep.estimate.magnitude, 0.67);
assert.equal(deep.magnitudeAudit.freshHeldDiagnostics
  .srev_kaizou_magnitude_clamped_station_distance_km, 20);
assert.ok(deep.magnitudeAudit.strongestStationDistanceKm > 130);

process.stdout.write(JSON.stringify({
  status: 'passed', solverUnchanged: true, identicalFrames,
  scratchProjectSha256: runtime.projectSha256,
  scratchUnchangedLocationUpdate: {before: scratchFirst.scratchMagnitude, after: scratchNext},
  checks: ['untimed_strong_station_exclusion', 'report_lock_suppresses_rise',
    'quantization_loss', 'distance_pairing', 'raw_hash_parity', 'reference_not_injected'],
  limitation: 'Yamanashi M2.4 has five missing raw frames; these checks prove mechanisms, not population accuracy.',
}, null, 2) + '\n');
