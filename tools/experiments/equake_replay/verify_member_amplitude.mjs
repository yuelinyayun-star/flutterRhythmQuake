import assert from 'node:assert/strict';
import fs from 'node:fs';
import crypto from 'node:crypto';

const [originalPath, resultPath, outputPath] = process.argv.slice(2);
assert(originalPath && resultPath && outputPath, 'Pass baseline, result, new output');
const hash = p => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const originalHash = hash(originalPath), resultHash = hash(resultPath);
const original = JSON.parse(fs.readFileSync(originalPath, 'utf8'));
const result = JSON.parse(fs.readFileSync(resultPath, 'utf8'));
assert.equal(result.inputReportSha256, originalHash);
assert.equal(result.feedsProduction, false);
assert.equal(result.readyForProduction, false);
assert.equal(result.labelsUsedInInference, false);
for (const [path, value] of Object.entries(result.sourceHashes)) assert.equal(hash(path), value);
assert.deepEqual(result.cases.map(c => c.id), original.cases.map(c => c.id));
const close = (a, b) => assert(Number.isFinite(a) && Number.isFinite(b) && Math.abs(a - b) < 1e-9);
let verifiedFrames = 0, verifiedExtraObservations = 0, verifiedLiveFrames = 0;
const summaries = [];
for (const c of result.cases) {
  const base = original.cases.find(x => x.id === c.id);
  assert.equal(c.rawInputSha256, base.rawInputSha256);
  assert.equal(c.missingFrames, base.missingFrameCount);
  assert.equal(c.frames.length, base.frames.length);
  let previousKey = null, previousTime = null, extra = {};
  let changed = 0, raised = 0, collected = 0, multiple = 0;
  for (let i = 0; i < c.frames.length; i++) {
    const f = c.frames[i], b = base.frames[i];
    assert.equal(f.time, b.observedAtJst);
    verifiedFrames++;
    const time = Date.parse(`${f.time}+09:00`);
    if (previousTime !== null && time - previousTime !== 1000) {
      extra = {}; previousKey = null;
    }
    previousTime = time;
    const experiment = b.magnitudeAudit?.experiment;
    const candidate = experiment?.eventPeakCandidate;
    if (!b.estimate || !candidate?.supported) {
      assert.equal(f.supported, false);
      assert.equal(f.reason, 'no_live_candidate');
      extra = {}; previousKey = null;
      continue;
    }
    verifiedLiveFrames++;
    assert.equal(f.supported, true);
    assert.equal(f.eventKey, candidate.eventKey);
    assert.equal(f.collectionEnabled, !candidate.multipleSources);
    if (previousKey !== f.eventKey || !f.collectionEnabled) extra = {};
    previousKey = f.eventKey;
    const peaks = candidate.stationPeaks;
    for (const code of Object.keys(extra)) if (!(code in peaks)) delete extra[code];
    const active = new Set(b.magnitudeAudit.stationTrace.stations.map(s => s.code));
    const associated = new Set(experiment.associatedCodes);
    if (!f.collectionEnabled) {
      multiple++;
      assert.equal(f.disabledReason, 'multiple_sources');
      assert.deepEqual(f.observedInactiveMembers, {});
    }
    for (const [code, value] of Object.entries(f.observedInactiveMembers)) {
      assert(code in peaks && !active.has(code) && !associated.has(code));
      assert(Number.isFinite(value));
      extra[code] = Math.max(extra[code] ?? -Infinity, value);
      verifiedExtraObservations++;
    }
    assert.deepEqual(f.extraPeaks, extra);
    const combined = { ...peaks };
    for (const [code, value] of Object.entries(extra)) combined[code] = Math.max(combined[code], value);
    assert.deepEqual(f.combinedPeaks, combined);
    const maximum = Math.max(...Object.values(combined));
    const strongest = Object.keys(combined).filter(code => combined[code] === maximum).sort();
    assert.equal(f.peakIntensity, maximum);
    assert.equal(f.baselinePeak, candidate.peakIntensity);
    assert.equal(f.baselineMagnitude, candidate.stationPairedCandidate.magnitude);
    assert.deepEqual(f.strongestCodes, strongest);
    assert.deepEqual(f.paired.stations.map(s => s.code), strongest);
    const magnitudes = [];
    for (const s of f.paired.stations) {
      assert.equal(s.intensity, maximum);
      const intensity = candidate.multipleSources && maximum > 4 ? (maximum - 4) / 2 + 5 : maximum;
      close(s.clampedDistanceKm, Math.max(20, s.epicentralDistanceKm));
      const m = Math.max(0, intensity - .94 + 1.73 * Math.log10(s.clampedDistanceKm));
      close(s.magnitude, m);
      magnitudes.push(m);
    }
    magnitudes.sort((a, b) => a - b);
    const mid = magnitudes.length >> 1;
    close(f.paired.magnitude, magnitudes.length % 2 ? magnitudes[mid] : (magnitudes[mid - 1] + magnitudes[mid]) / 2);
    if (f.paired.magnitude !== f.baselineMagnitude) changed++;
    if (maximum > candidate.peakIntensity) raised++;
    if (Object.keys(f.observedInactiveMembers).length) collected++;
  }
  assert.equal(changed, c.summary.changedMagnitudeFrames);
  assert.equal(raised, c.summary.raisedPeakFrames);
  assert.equal(collected, c.summary.collectedFrames);
  assert.equal(multiple, c.summary.multipleSourceFrames);
  summaries.push({ id: c.id, ...c.summary });
}
assert.equal(hash(originalPath), originalHash);
assert.equal(hash(resultPath), resultHash);
const verification = { originalHash, resultHash, verifiedFrames, verifiedLiveFrames, verifiedExtraObservations,
  readyForProduction: false,
  scope: 'Independent membership, reset, accumulation and magnitude arithmetic checks. Raw pixels and geographic distance are not independently decoded/recomputed here.', summaries };
fs.writeFileSync(outputPath, `${JSON.stringify(verification, null, 2)}\n`, { flag: 'wx' });
console.log(JSON.stringify({ verifiedFrames, verifiedLiveFrames, verifiedExtraObservations, summaries }, null, 2));
