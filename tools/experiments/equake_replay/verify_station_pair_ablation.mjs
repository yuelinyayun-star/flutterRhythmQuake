import fs from 'node:fs';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';

const [inputPath, resultPath, outputPath] = process.argv.slice(2);
if (!outputPath) throw Error('Pass original candidate report, paired report, new verification path');
const hash = p => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const inputHash = hash(inputPath);
const resultHash = hash(resultPath);
const input = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
const result = JSON.parse(fs.readFileSync(resultPath, 'utf8'));
assert.equal(result.inputReportSha256, inputHash);
assert.equal(result.stationDbSha256, hash('lib/models/nied_station_db.dart'));
assert.equal(result.feedsProduction, false);
assert.equal(result.labelsUsedInInference, false);
assert.equal(result.readyForProduction, false);
assert.deepEqual(result.cases.map(c => c.id), input.cases.map(c => c.id));
const close = (a, b) => {
  assert.ok(Number.isFinite(a) && Number.isFinite(b));
  assert.ok(Math.abs(a - b) < 1e-9, `${a} != ${b}`);
};
const quantile = (values, p) => {
  const sorted = [...values].sort((a, b) => a - b);
  const i = (sorted.length - 1) * p;
  return sorted[Math.floor(i)] + (sorted[Math.ceil(i)] - sorted[Math.floor(i)]) * (i % 1);
};
const checkStats = (stats, values) => {
  assert.equal(stats.count, values.length);
  if (!values.length) {
    assert.equal(stats.median, null);
    assert.equal(stats.iqr, null);
    return;
  }
  for (const [key, p] of [['p25', .25], ['median', .5], ['p75', .75]]) close(stats[key], quantile(values, p));
  close(stats.iqr, quantile(values, .75) - quantile(values, .25));
};
let verifiedFrames = 0;
let verifiedPairs = 0;
let totalPeaks = 0;
const summaries = [];
for (const c of result.cases) {
  const original = input.cases.find(o => o.id === c.id);
  assert.equal(c.rawInputSha256, original.rawInputSha256);
  const frames = original.frames.filter(f => f.magnitudeAudit?.experiment?.eventPeakCandidate?.supported);
  assert.equal(c.frames.length, frames.length);
  assert.equal(c.comparedFrames, frames.length);
  assert.deepEqual(c.first, c.frames[0] ?? null);
  assert.deepEqual(c.last, c.frames.at(-1) ?? null);
  function checkRow(row, f, candidate) {
    const estimate = f.estimate;
    close(row.peakIntensity, candidate.stationPeaks[row.code]);
    const lat = Math.round(estimate.latitude * 10) / 10;
    const lon = Math.round(estimate.longitude * 10) / 10;
    const dy = (lat - row.latitude) * 111.2;
    const dx = 6371 * (lon - row.longitude) * (3.1416 / 180) * Math.cos((lat + row.latitude) / 2 * Math.PI / 180);
    const distance = Math.hypot(dx, dy);
    close(row.epicentralDistanceKm, distance);
    const intensity = candidate.multipleSources && row.peakIntensity > 4
      ? (row.peakIntensity - 4) / 2 + 5 : row.peakIntensity;
    const magnitude = d => Math.max(0, intensity - .94 + 1.73 * Math.log10(Math.max(20, d)));
    close(row.pairedEpicentralMagnitude, magnitude(distance));
    close(row.geometricDepthSensitivityMagnitude, magnitude(Math.hypot(distance, estimate.depthKm)));
    assert.equal(row.isStrongest, row.peakIntensity === candidate.peakIntensity);
    verifiedPairs++;
  }
  for (let i = 0; i < frames.length; i++) {
    const f = frames[i];
    const r = c.frames[i];
    const p = f.magnitudeAudit.experiment.eventPeakCandidate;
    assert.equal(r.observedAtJst, f.observedAtJst);
    assert.equal(r.eventKey, p.eventKey);
    assert.equal(r.productionMagnitude, f.estimate.magnitude);
    assert.equal(r.sourceLatitude, f.estimate.latitude);
    assert.equal(r.sourceLongitude, f.estimate.longitude);
    assert.equal(r.depthKm, f.estimate.depthKm);
    assert.equal(r.multipleSources, p.multipleSources);
    close(r.peakNearestMagnitude, p.magnitude);
    const codes = Object.entries(p.stationPeaks).filter(([, v]) => v === p.peakIntensity).map(([code]) => code).sort();
    assert.deepEqual(r.strongestStations.map(s => s.code).sort(), codes);
    for (const row of r.strongestStations) checkRow(row, f, p);
    checkStats(r.strongestPaired, r.strongestStations.map(s => s.pairedEpicentralMagnitude));
    assert.equal(r.allPaired.count, Object.keys(p.stationPeaks).length);
    totalPeaks += r.allPaired.count;
    verifiedFrames++;
  }
  if (frames.length) {
    const f = frames.at(-1);
    const p = f.magnitudeAudit.experiment.eventPeakCandidate;
    assert.deepEqual(c.lastStationPairs.map(s => s.code).sort(), Object.keys(p.stationPeaks).sort());
    for (const row of c.lastStationPairs) checkRow(row, f, p);
    checkStats(c.last.allPaired, c.lastStationPairs.map(s => s.pairedEpicentralMagnitude));
    checkStats(c.last.depthSensitivity, c.lastStationPairs.map(s => s.geometricDepthSensitivityMagnitude));
    const bands = { '0_50km': [], '50_100km': [], '100_200km': [], '200km_plus': [] };
    for (const row of c.lastStationPairs) {
      const d = row.epicentralDistanceKm;
      bands[d < 50 ? '0_50km' : d < 100 ? '50_100km' : d < 200 ? '100_200km' : '200km_plus'].push(row.pairedEpicentralMagnitude);
    }
    for (const [key, values] of Object.entries(bands)) checkStats(c.last.distanceBands[key], values);
  } else assert.equal(c.lastStationPairs.length, 0);
  summaries.push({id: c.id, frames: frames.length, production: c.last?.productionMagnitude ?? null,
    eventPeakNearest: c.last?.peakNearestMagnitude ?? null,
    strongestPaired: c.last?.strongestPaired.median ?? null,
    allPairedMedian: c.last?.allPaired.median ?? null});
}
assert.equal(result.examinedFrames, verifiedFrames);
assert.equal(result.examinedStationPeaks, totalPeaks);
assert.equal(hash(inputPath), inputHash);
assert.equal(hash(resultPath), resultHash);
const verification = {inputHash, resultHash, verifiedFrames, verifiedPairs,
  scope: 'Independent strongest-station math on every frame; full station pairs and distributions on final frames. Earlier all-station distributions not independently recalculated.',
  readyForProduction: false, summaries};
fs.writeFileSync(outputPath, JSON.stringify(verification, null, 2) + '\n', {flag: 'wx'});
console.log(JSON.stringify(verification, null, 2));
