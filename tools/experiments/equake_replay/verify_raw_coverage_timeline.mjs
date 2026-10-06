import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';

const [baselinePath, layeredPath, outputPath] = process.argv.slice(2);
assert(baselinePath && layeredPath && outputPath,
  'Pass previous surface timeline, multilayer timeline, new output');
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const baselineBytes = readFileSync(baselinePath);
const layeredBytes = readFileSync(layeredPath);
const baseline = JSON.parse(baselineBytes);
const layered = JSON.parse(layeredBytes);
for (const key of ['caseId', 'fixtureSha256', 'reportSha256',
  'manifestSha256', 'scanPositionsSha256', 'firstSelected', 'lastSelected']) {
  assert.equal(layered[key], baseline[key], key);
}
assert.equal(digest(readFileSync('lib/models/nied_scan_positions.dart')),
  layered.scanPositionsSha256);
assert.equal(layered.unequalSnapshotValues, 0);
assert.equal(layered.stations.length, baseline.stations.length);
const timesByLayer = new Map();
for (const file of layered.files) {
  assert.equal(digest(readFileSync(file.path)), file.sha256, file.path);
  if (!timesByLayer.has(file.layer)) timesByLayer.set(file.layer, new Set());
  const times = timesByLayer.get(file.layer);
  assert(!times.has(file.time), `Duplicate ${file.layer} ${file.time}`);
  times.add(file.time);
}
const surfaceTimes = timesByLayer.get('jma_s');
const maximum = (rows, field) => rows.reduce((best, row) =>
  Number.isFinite(row[field]) && (!best || row[field] > best[field])
    ? row : best, null);
const summarize = rows => {
  const best = maximum(rows, 'rawIntensity');
  return { validSamples: rows.filter(row => Number.isFinite(row.rawIntensity)).length,
    maximum: best?.rawIntensity ?? null, firstPeakTime: best?.time ?? null };
};
let verifiedSamples = 0;
let verifiedPhysicalRows = 0;
const stationSummaries = [];
for (const station of layered.stations) {
  const before = baseline.stations.find(s => s.code === station.code);
  assert(before, station.code);
  for (const key of ['samples', 'peakRows', 'maximum', 'candidatePeak']) {
    assert.deepEqual(station[key], before[key], `${station.code} ${key}`);
  }
  assert.deepEqual(new Set(station.samples.map(row => row.time)), surfaceTimes);
  assert.equal(station.samples.length, surfaceTimes.size);
  verifiedSamples += station.samples.length;
  const physical = {};
  for (const layer of ['acmap_s', 'vcmap_s', 'dcmap_s']) {
    const rows = station.physicalSamples.filter(row => row.layer === layer);
    const expected = timesByLayer.get(layer) ?? new Set();
    assert.deepEqual(new Set(rows.map(row => row.time)), expected);
    assert.equal(rows.length, expected.size);
    for (const row of rows) {
      assert.equal(row.rgb.length, 3);
      assert(row.rgb.every(v => Number.isInteger(v) && v >= 0 && v <= 255));
      assert(row.value === null || (Number.isFinite(row.value) && row.value > 0));
    }
    verifiedPhysicalRows += rows.length;
    const best = maximum(rows, 'value');
    physical[layer] = { files: rows.length,
      validSamples: rows.filter(row => row.value !== null).length,
      peak: best?.value ?? null, firstPeakTime: best?.time ?? null };
  }
  stationSummaries.push({ code: station.code, savedPeak: station.candidatePeak,
    distanceKm: station.distanceKm,
    beforeSelection: summarize(station.samples.filter(r => r.time < layered.firstSelected)),
    selectedWindow: summarize(station.samples.filter(r =>
      r.time >= layered.firstSelected && r.time <= layered.lastSelected)),
    afterSelection: summarize(station.samples.filter(r => r.time > layered.lastSelected)),
    physical });
}
const previouslyAssociated = stationSummaries.filter(row => row.savedPeak !== null);
const missedWithinWindow = previouslyAssociated.filter(row =>
  row.selectedWindow.maximum !== null && row.selectedWindow.maximum > row.savedPeak);
const result = { feedsProduction: false, readyForProduction: false,
  scope: 'Raw file hashes, exact surface regression, per-layer sample coverage. Physical color decoding is not independently reimplemented.',
  limits: ['Selection intervals do not establish earthquake signal identity.',
    'Whole-window physical peaks must not be substituted for event peaks.',
    'Null pixels remain unavailable, not zero; no missing frames are filled.'],
  inputHashes: { baseline: digest(baselineBytes), layered: digest(layeredBytes) },
  verifiedFiles: layered.files.length, verifiedSamples, verifiedPhysicalRows,
  layerFileCounts: Object.fromEntries([...timesByLayer].map(([k, v]) => [k, v.size])),
  unavailableScanPositions: layered.unavailableScanPositions,
  missedWithinWindow, stations: stationSummaries };
assert.equal(digest(readFileSync(baselinePath)), result.inputHashes.baseline);
assert.equal(digest(readFileSync(layeredPath)), result.inputHashes.layered);
writeFileSync(outputPath, `${JSON.stringify(result, null, 2)}\n`, { flag: 'wx' });
console.log(JSON.stringify({ outputPath, verifiedFiles: result.verifiedFiles,
  verifiedSamples, verifiedPhysicalRows,
  missedWithinWindow: missedWithinWindow.map(({ code, savedPeak, selectedWindow }) =>
    ({ code, savedPeak, selectedWindow })) }, null, 2));
