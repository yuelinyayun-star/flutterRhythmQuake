import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const args = process.argv.slice(2);
assert(args.length >= 3 && args.length % 2 === 1,
  'Pass shadow/ablation pairs, then a new output JSON');
const output = args.at(-1);
assert(!fs.existsSync(output) && path.extname(output) === '.json');
const root = fs.realpathSync('.dart_tool');
const parent = fs.realpathSync(path.dirname(output));
const relative = path.relative(root, parent);
assert(!path.isAbsolute(relative) && relative !== '..' && !relative.startsWith(`..${path.sep}`));
const hash = p => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const close = (a, b) => assert(Number.isFinite(a) && Number.isFinite(b) && Math.abs(a - b) < 1e-9);
const median = values => {
  const sorted = [...values].sort((a, b) => a - b), mid = sorted.length >> 1;
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};
const inputs = {}, cases = [], finalPairs = new Map();
let checkedFrames = 0, checkedStationRows = 0;
for (let index = 0; index < args.length - 1; index += 2) {
  const shadowPath = args[index], ablationPath = args[index + 1];
  inputs[shadowPath] = hash(shadowPath);
  inputs[ablationPath] = hash(ablationPath);
  const shadow = JSON.parse(fs.readFileSync(shadowPath, 'utf8'));
  const ablation = JSON.parse(fs.readFileSync(ablationPath, 'utf8'));
  assert.equal(shadow.scanPositionsSha256, hash('lib/models/nied_scan_positions.dart'));
  assert.equal(ablation.stationDbSha256, hash('lib/models/nied_station_db.dart'));
  assert.equal(ablation.inputReportSha256, inputs[shadowPath]);
  for (const c of ablation.cases) {
    assert(!cases.some(other => other.id === c.id), 'Duplicate case');
    const source = shadow.cases.find(x => x.id === c.id);
    assert(source);
    assert.equal(c.rawInputSha256, source.rawInputSha256);
    const sourceFrames = new Map(source.frames.map(f => [f.observedAtJst, f]));
    const frames = [];
    for (const f of c.frames) {
      const original = sourceFrames.get(f.observedAtJst);
      assert(original?.estimate);
      const candidate = original.magnitudeAudit.experiment.eventPeakCandidate;
      close(f.peakIntensity, candidate.peakIntensity);
      assert.equal(f.multipleSources, candidate.multipleSources);
      const rows = f.strongestStations.map(s => {
        close(s.peakIntensity, candidate.stationPeaks[s.code]);
        const processed = candidate.multipleSources && s.peakIntensity > 4
          ? (s.peakIntensity - 4) / 2 + 5 : s.peakIntensity;
        const logAmplitudeProxy = (processed - .94) / 2;
        const distanceTerm = 1.73 * Math.log10(Math.max(20, s.epicentralDistanceKm));
        const currentUnclamped = 2 * logAmplitudeProxy + distanceTerm;
        const singleExponentUnclamped = logAmplitudeProxy + distanceTerm;
        const current = Math.max(0, currentUnclamped);
        close(current, s.pairedEpicentralMagnitude);
        close(singleExponentUnclamped - currentUnclamped, -logAmplitudeProxy);
        checkedStationRows++;
        return { code: s.code, rawIntensity: s.peakIntensity, processedIntensity: processed,
          distanceKm: s.epicentralDistanceKm, distanceTerm, logAmplitudeProxy,
          currentUnclamped, current,
          singleExponentUnclamped, singleExponent: Math.max(0, singleExponentUnclamped) };
      });
      const current = median(rows.map(r => r.current));
      close(current, candidate.stationPairedCandidate.magnitude);
      frames.push({ time: f.observedAtJst, eventKey: candidate.eventKey,
        currentPaired: current, singleExponentSensitivity: median(rows.map(r => r.singleExponent)), rows });
      checkedFrames++;
    }
    // Reference labels are copied only after the arithmetic; never used to fit/select.
    cases.push({ id: c.id, rawInputSha256: c.rawInputSha256,
      referenceLabel: source.referenceLabel, eventLabels: source.eventLabels,
      frames, last: frames.at(-1) ?? null });
    finalPairs.set(c.id, c);
  }
}
const small = finalPairs.get('20260627_yamanashi_east_fuji_five_lakes_m24_jma_p2p');
const large = finalPairs.get('20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21');
let sameStationComparison = null;
if (small && large) {
  const largeStations = new Map(large.lastStationPairs.map(s => [s.code, s]));
  const rows = small.lastStationPairs.filter(s => largeStations.has(s.code)).map(s => {
    const l = largeStations.get(s.code);
    const distanceDelta = 1.73 * Math.log10(Math.max(20, l.epicentralDistanceKm) / Math.max(20, s.epicentralDistanceKm));
    assert(!small.last.multipleSources && !large.last.multipleSources);
    return { code: s.code, smallIntensity: s.peakIntensity, largeIntensity: l.peakIntensity,
      intensityDelta: l.peakIntensity - s.peakIntensity, distanceTermDelta: distanceDelta,
      currentUnclampedDelta: l.peakIntensity - s.peakIntensity + distanceDelta,
      singleExponentUnclampedDelta: (l.peakIntensity - s.peakIntensity) / 2 + distanceDelta,
      strongestInSmall: s.isStrongest, strongestInLarge: l.isStrongest };
  });
  sameStationComparison = { smallId: small.id, largeId: large.id,
    smallEstimatedGeometry: [small.last.sourceLatitude, small.last.sourceLongitude, small.last.depthKm],
    largeEstimatedGeometry: [large.last.sourceLatitude, large.last.sourceLongitude, large.last.depthKm],
    sharedStationCount: rows.length, rows,
    limits: ['Final estimated geometry, not independently fixed true geometry.',
      'Shared membership does not establish all small-event readings as earthquake signal.',
      'A single event pair cannot fit or validate an intensity-magnitude coefficient.'] };
}
for (const [p, h] of Object.entries(inputs)) assert.equal(hash(p), h);
const report = { diagnosticOnly: true, feedsProduction: false, readyForProduction: false,
  labelsUsedInInference: false, coefficientsFitted: false,
  scope: 'Algebraic transfer sensitivity, not a replacement magnitude model.',
  limits: ['Single-exponent proxy is not displacement, velocity or a validated JMA magnitude.',
    'The original branch, station selection, distances and zero floor are retained.',
    'Color intensity is not assumed to be official instrumental intensity.'],
  inputs, checkedFrames, checkedStationRows, sameStationComparison, cases };
fs.writeFileSync(output, `${JSON.stringify(report, null, 2)}\n`, { flag: 'wx' });
console.log(JSON.stringify({ checkedFrames, checkedStationRows,
  cases: cases.map(c => ({ id: c.id, lastPaired: c.last?.currentPaired,
    singleExponentSensitivity: c.last?.singleExponentSensitivity })),
  sharedStationCount: sameStationComparison?.sharedStationCount,
  sharedStrongest: sameStationComparison?.rows.filter(r => r.strongestInSmall || r.strongestInLarge) }, null, 2));
