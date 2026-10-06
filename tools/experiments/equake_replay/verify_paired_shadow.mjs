import fs from 'node:fs';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';

const [input, firstAblation, extraAblation, output] = process.argv.slice(2);
if (!output) throw Error('Pass new replay, two prior ablation reports, new verification path');
const read = p => JSON.parse(fs.readFileSync(p, 'utf8'));
const sha = p => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const paths = [input, firstAblation, extraAblation];
const hashes = paths.map(sha);
const replay = read(input);
const prior = [...read(firstAblation).cases, ...read(extraAblation).cases];
let checked = 0;
let tied = 0;
const summaries = [];
const close = (a, b) => assert.ok(Number.isFinite(a) && Number.isFinite(b) && Math.abs(a - b) < 1e-9, `${a} != ${b}`);
for (const c of replay.cases) {
  const b = prior.find(b => b.id === c.id);
  assert.ok(b);
  assert.equal(c.rawInputSha256, b.rawInputSha256);
  assert.equal(c.missingFrameCount, b.missingFrameCount);
  const frames = c.frames.filter(f => f.magnitudeAudit?.experiment?.eventPeakCandidate?.supported);
  assert.equal(frames.length, b.frames.length);
  for (let i = 0; i < frames.length; i++) {
    const f = frames[i];
    const candidate = f.magnitudeAudit.experiment.eventPeakCandidate;
    const paired = candidate.stationPairedCandidate;
    const old = b.frames[i];
    assert.equal(f.observedAtJst, old.observedAtJst);
    assert.equal(f.estimate.magnitude, old.productionMagnitude);
    close(candidate.magnitude, old.peakNearestMagnitude);
    assert.equal(paired.supported, true);
    assert.equal(paired.feedsProduction, false);
    assert.equal(paired.readyForProduction, false);
    assert.equal(paired.labelsUsedInInference, false);
    assert.equal(paired.depthCorrectionApplied, false);
    close(paired.magnitude, old.strongestPaired.median);
    assert.equal(paired.stations.length, old.strongestStations.length);
    for (const s of paired.stations) {
      const before = old.strongestStations.find(o => o.code === s.code);
      assert.ok(before);
      close(s.intensity, before.peakIntensity);
      close(s.epicentralDistanceKm, before.epicentralDistanceKm);
      close(s.magnitude, before.pairedEpicentralMagnitude);
      close(s.clampedDistanceKm, Math.max(20, s.epicentralDistanceKm));
    }
    close(paired.minimum, Math.min(...paired.stations.map(s => s.magnitude)));
    close(paired.maximum, Math.max(...paired.stations.map(s => s.magnitude)));
    if (paired.stations.length > 1) tied++;
    checked++;
  }
  summaries.push({id: c.id, frames: frames.length, lastMagnitude:
    frames.at(-1)?.magnitudeAudit.experiment.eventPeakCandidate.stationPairedCandidate.magnitude ?? null});
}
assert.equal(prior.length, replay.cases.length);
assert.deepEqual(paths.map(sha), hashes);
const result = {feedsProduction: false, readyForProduction: false, checkedFrames: checked,
  tiedStrongestFrames: tied, inputHashes: paths.map((path, i) => ({path, sha256: hashes[i]})), summaries};
fs.writeFileSync(output, JSON.stringify(result, null, 2) + '\n', {flag: 'wx'});
console.log(JSON.stringify(result, null, 2));
