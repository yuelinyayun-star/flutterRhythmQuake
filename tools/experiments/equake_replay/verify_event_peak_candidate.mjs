import fs from 'node:fs';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';

const [reportPath, output] = process.argv.slice(2);
if (!output) throw Error('Usage: verify_event_peak_candidate.mjs report new-output');
if (fs.existsSync(output)) throw Error('Output already exists');
const read = p => JSON.parse(fs.readFileSync(p, 'utf8'));
const report = read(reportPath);
const baselines = [
  '.dart_tool/magnitude_review_20261003/equake_original_window/report.json',
  '.dart_tool/magnitude_review_20261003/associated_experiment/report.json',
  '.dart_tool/magnitude_review_20261003/production_audit/report.json',
  '.dart_tool/magnitude_review_20261003/complete_small_captures/report.json',
].flatMap(p => read(p).cases);
assert.equal(report.solverSha256, crypto.createHash('sha256').update(
  fs.readFileSync('lib/core/source_estimation/source_estimator.dart')).digest('hex'));
const cases = [];
for (const c of report.cases) {
  const b = baselines.find(b => b.id === c.id);
  assert.ok(b, c.id);
  assert.equal(c.rawInputSha256, b.rawInputSha256);
  assert.equal(c.frames.length, b.frames.length);
  assert.equal(c.missingFrameCount, b.missingFrameCount);
  const witnessed = new Map();
  const rows = [];
  const migrations = [];
  for (let i = 0; i < c.frames.length; i++) {
    const f = c.frames[i];
    assert.equal(f.observedAtJst, b.frames[i].observedAtJst);
    for (const field of ['latitude', 'longitude', 'depthKm', 'magnitude', 'supportingStationCount', 'originTime']) {
      assert.deepEqual(f.estimate?.[field], b.frames[i].estimate?.[field]);
    }
    const e = f.magnitudeAudit?.experiment;
    const candidate = e?.eventPeakCandidate;
    if (!candidate?.supported) continue;
    assert.ok(f.estimate);
    assert.equal(candidate.feedsProduction, false);
    assert.equal(candidate.inheritanceEvidenceIsOfficialMergeProof, false);
    const peaks = witnessed.get(e.eventKey) ?? new Map();
    witnessed.set(e.eventKey, peaks);
    for (const transfer of candidate.inheritanceDecisions) {
      if (transfer.reason !== 'unique_membership_containment') continue;
      assert.equal(transfer.predecessorAssignedStationCodeCount, transfer.matchedAssignedStationCodeCount);
      const ancestor = witnessed.get(transfer.predecessorEventKey);
      if (transfer.transferredStationPeakCount > 0) assert.ok(ancestor);
      for (const [code, value] of ancestor ?? []) peaks.set(code, Math.max(peaks.get(code) ?? -Infinity, value));
      migrations.push({time: f.observedAtJst, ...transfer});
    }
    const snapshot = new Map(f.magnitudeAudit.stationTrace.stations.map(s => [s.code, s]));
    for (const code of e.associatedCodes) {
      const value = snapshot.get(code)?.rawIntensity;
      assert.ok(Number.isFinite(value), `${f.observedAtJst} ${code}`);
      peaks.set(code, Math.max(peaks.get(code) ?? -Infinity, value));
    }
    assert.deepEqual(Object.fromEntries(peaks), candidate.stationPeaks,
      `Every candidate peak must be attributable to actual associated observations: ${f.observedAtJst}`);
    assert.equal(candidate.peakIntensity, Math.max(...peaks.values()));
    if (c.id === '20260622_wakayama_south_m25_hinet' && f.observedAtJst.startsWith('2026-06-22T09:51:31')) {
      assert.ok(e.rejectedCounts.other_event > 0);
      assert.ok(!Object.hasOwn(candidate.stationPeaks, 'HKD127'));
      assert.ok(Object.hasOwn(candidate.stationPeaks, 'WKYH04'));
    }
    rows.push({time: f.observedAtJst, key: e.eventKey, candidate: candidate.magnitude,
      published: f.estimate.magnitude, formerCandidate: e.associatedContinuousPeakMagnitude,
      peakIntensity: candidate.peakIntensity, strongest: candidate.peakStationCodes});
  }
  if (c.id.startsWith('quiet_')) {
    assert.equal(c.estimateFrameCount, 0);
    assert.equal(rows.length, 0);
  }
  cases.push({id: c.id, comparedFrames: c.frames.length, missing: c.missingFrameCount,
    candidateFrames: rows.length, first: rows[0] ?? null, last: rows.at(-1) ?? null,
    maximum: rows.length ? Math.max(...rows.map(r => r.candidate)) : null,
    migrations, rows});
}
const result = {verification: 'raw observations and unchanged production output verified',
  readyForProduction: false, empiricalAccuracyValidated: false,
  limits: ['Membership containment is evidence, not explicit production merge lineage.',
    'Existing intensity-to-magnitude model retained; not calibrated to JMA final magnitudes.',
    'Ambiguous lineage and false association require independent real counterexamples.'], cases};
fs.writeFileSync(output, JSON.stringify(result, null, 2) + '\n', {flag: 'wx'});
console.log(JSON.stringify(cases.map(({rows, migrations, ...c}) => ({...c, migrationCount: migrations.length})), null, 2));
