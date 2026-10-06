import fs from 'node:fs';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';

const [beforePath, afterPath, output] = process.argv.slice(2);
if (!output) throw Error('Pass before/after replay reports and new output path');
const read = p => JSON.parse(fs.readFileSync(p, 'utf8'));
const digest = p => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const beforeHash = digest(beforePath), afterHash = digest(afterPath);
const before = read(beforePath), after = read(afterPath);
assert.equal(before.solverSha256, after.solverSha256);
assert.equal(after.scanPositionsSha256, digest('lib/models/nied_scan_positions.dart'));
assert.deepEqual(before.cases.map(c => c.id), after.cases.map(c => c.id));
const changes = [];
const newCodes = ['HKD063', 'HKD126', 'ISK006', 'TKY023'];
for (const c of after.cases) {
  const b = before.cases.find(b => b.id === c.id);
  assert.equal(b.rawInputSha256, c.rawInputSha256);
  assert.equal(b.frames.length, c.frames.length);
  assert.equal(b.missingFrameCount, c.missingFrameCount);
  const changedFrames = [];
  const newStationFrames = Object.fromEntries(newCodes.map(code => [code, 0]));
  let changedExistingSnapshotValues = 0;
  const changedExistingCodes = new Set();
  for (let i = 0; i < c.frames.length; i++) {
    const old = b.frames[i], current = c.frames[i];
    assert.equal(old.observedAtJst, current.observedAtJst);
    const changedFields = [];
    for (const key of ['latitude', 'longitude', 'depthKm', 'magnitude', 'supportingStationCount', 'originTime']) {
      if (JSON.stringify(old.estimate?.[key]) !== JSON.stringify(current.estimate?.[key])) changedFields.push(key);
    }
    const p = f => f.magnitudeAudit?.experiment?.eventPeakCandidate?.stationPairedCandidate?.magnitude ?? null;
    if (p(old) !== p(current)) changedFields.push('pairedShadowMagnitude');
    if (changedFields.length) changedFrames.push({time: current.observedAtJst, fields: changedFields,
      beforeMagnitude: old.estimate?.magnitude ?? null, afterMagnitude: current.estimate?.magnitude ?? null,
      beforeShadow: p(old), afterShadow: p(current)});
    const oldStations = new Map((old.magnitudeAudit?.stationTrace?.stations ?? []).map(s => [s.code, s]));
    for (const station of current.magnitudeAudit?.stationTrace?.stations ?? []) {
      if (newCodes.includes(station.code)) newStationFrames[station.code]++;
      const former = oldStations.get(station.code);
      if (former && former.rawIntensity !== station.rawIntensity) {
        changedExistingSnapshotValues++;
        changedExistingCodes.add(station.code);
      }
    }
  }
  const final = c.frames.filter(f => f.estimate).at(-1);
  changes.push({id: c.id, frames: c.frames.length, estimateFrames: c.estimateFrameCount,
    missing: c.missingFrameCount, changedFrameCount: changedFrames.length,
    newStationActiveSnapshotFrames: newStationFrames,
    changedExistingSnapshotValues, changedExistingCodes: [...changedExistingCodes],
    last: final ? {time: final.observedAtJst, production: final.estimate.magnitude,
      pairedShadow: final.magnitudeAudit?.experiment?.eventPeakCandidate?.stationPairedCandidate?.magnitude} : null,
    changedFrames});
}
assert.equal(digest(beforePath), beforeHash);
assert.equal(digest(afterPath), afterHash);
const result = {rawInputUnchanged: true, solverUnchanged: true, stationMappingChanged: true,
  beforeReportSha256: beforeHash, afterReportSha256: afterHash,
  afterScanVersion: after.scanPositionsVersion, afterScanSha256: after.scanPositionsSha256,
  limitation: 'Absent active snapshots do not prove that a station has no decoded observation.', cases: changes};
fs.writeFileSync(output, JSON.stringify(result, null, 2) + '\n', {flag: 'wx'});
console.log(JSON.stringify(changes.map(({changedFrames, ...c}) => c), null, 2));
