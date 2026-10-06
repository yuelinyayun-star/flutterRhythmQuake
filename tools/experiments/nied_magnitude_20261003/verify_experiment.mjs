import assert from 'node:assert/strict';
import fs from 'node:fs';
import crypto from 'node:crypto';

const read = (path) => JSON.parse(fs.readFileSync(path, 'utf8'));
const root = '.dart_tool/magnitude_review_20261003';
const report = read(`${root}/associated_experiment/report.json`);
const baselines = [read(`${root}/production_audit/report.json`),
  read('.dart_tool/small_depth_review_20261003/timed_before/report.json')]
  .flatMap((r) => r.cases);
const solverHash = crypto.createHash('sha256').update(fs.readFileSync(
  'lib/core/source_estimation/source_estimator.dart')).digest('hex');
assert.equal(report.solverSha256, solverHash);
let comparedFrames = 0;
for (const c of report.cases) {
  const b = baselines.find((b) => b.id === c.id);
  assert.ok(b);
  assert.equal(c.rawInputSha256, b.rawInputSha256);
  assert.equal(c.frames.length, b.frames.length);
  for (let i = 0; i < c.frames.length; i++) {
    const f = c.frames[i];
    assert.equal(f.observedAtJst, b.frames[i].observedAtJst);
    for (const key of ['latitude', 'longitude', 'depthKm', 'magnitude']) {
      assert.equal(f.estimate?.[key], b.frames[i].estimate?.[key]);
    }
    const e = f.magnitudeAudit?.experiment;
    if (e?.supported) {
      assert.ok(f.estimate);
      assert.equal(e.feedsProduction, false);
      assert.equal(e.modelChanged, false);
    }
    comparedFrames++;
  }
}
const getCase = (id) => report.cases.find((c) => c.id === id);
const supported = (c) => c.frames.filter((f) => f.magnitudeAudit?.experiment?.supported);
const last = (c) => supported(c).at(-1).magnitudeAudit.experiment;
const small = getCase('20260627_yamanashi_east_fuji_five_lakes_m24_jma_p2p');
assert.equal(small.missingFrameCount, 5);
assert.ok(supported(small).some((f) => f.magnitudeAudit.experiment.associatedCodes.includes('YMN002')
  && f.magnitudeAudit.strongestStationHasTrigger === false));
assert.ok(last(small).associatedContinuousPeakMagnitude > small.finalEstimate.magnitude + 1);
assert.ok(last(small).associatedContinuousRefreshedMagnitude < 1);

const multi = getCase('20260622_wakayama_south_m25_hinet');
const multiFrame = multi.frames.find((f) => f.observedAtJst.startsWith('2026-06-22T09:51:31'));
const me = multiFrame.magnitudeAudit.experiment;
assert.equal(me.multipleSources, true);
assert.ok(me.rejectedCounts.other_event > 0);
assert.ok(!me.associatedCodes.includes('HKD127'));
assert.ok(me.associatedCodes.includes('WKYH04'));

const quiet = getCase('quiet_20260625_233535_jst_live');
assert.equal(quiet.processedFrameCount, 300);
assert.equal(quiet.estimateFrameCount, 0);
assert.equal(supported(quiet).length, 0);

const strong = getCase('20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21');
const strongFrames = supported(strong);
const peak = Math.max(...strongFrames.map((f) => f.magnitudeAudit.experiment.associatedContinuousPeakMagnitude));
const final = last(strong).associatedContinuousPeakMagnitude;
assert.ok(new Set(strongFrames.map((f) => f.magnitudeAudit.experiment.eventKey)).size > 1);
assert.ok(peak > 6.6 && final < 4.9);

const result = {
  verification: 'passed: reproduced observations, including candidate regressions',
  readyForProduction: false,
  comparedFrames,
  rawInputsUnchanged: true,
  originalOutputsUnchanged: true,
  checks: ['untimed_station_recovered', 'other_event_not_borrowed', 'quiet_has_no_estimate',
    'continuous_refresh_tail_decline_reproduced', 'cluster_identity_peak_loss_reproduced'],
  strongEvent: {peak, final, productionFinal: strong.finalEstimate.magnitude},
  blockers: ['cluster-merge state inheritance', 'tail/peak publication lifecycle',
    'model bias persists in Wakayama and strong-event references',
    'ambiguous ownership branch has no observed coverage in this batch'],
};
const json = JSON.stringify(result, null, 2) + '\n';
if (process.argv[2]) fs.writeFileSync(process.argv[2], json, {encoding: 'utf8', flag: 'wx'});
process.stdout.write(json);
