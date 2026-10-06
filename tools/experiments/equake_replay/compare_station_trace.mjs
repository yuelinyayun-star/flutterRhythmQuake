import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const [productionPath, baselinePath, srevPath, srevBaselinePath, output] = process.argv.slice(2);
if (!output) throw Error('Usage: compare_station_trace.mjs production baseline srev srev-baseline new-output');
if (fs.existsSync(output)) throw Error('Output already exists');
const read = p => JSON.parse(fs.readFileSync(p, 'utf8'));
const sha = p => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const production = read(productionPath).cases[0];
const baseline = read(baselinePath).cases.find(c => c.id === production.id);
const srev = read(srevPath);
const srevBaseline = read(srevBaselinePath);
assert.ok(baseline);
assert.equal(production.rawInputSha256, baseline.rawInputSha256);
assert.equal(production.frames.length, baseline.frames.length);
assert.equal(srev.trajectorySha256, srevBaseline.trajectorySha256);
assert.deepEqual(srev.frames, srevBaseline.frames);
const tableByCode = new Map(srev.stationTable.map(s => [s.code, s]));
const tracesByTime = new Map(srev.stationTraces.map(f => [f.observedAtUtc, f]));
const sourcesByTime = new Map(srev.frames.map(f => [f.observedAtUtc, f.sources]));
const fields = ['latitude', 'longitude', 'depthKm', 'magnitude', 'supportingStationCount', 'originTime'];
const baselineByTime = new Map(baseline.frames.map(f => [f.observedAtJst, f]));
const frames = [];
let checkedWorkerFrames = 0;
let identicalRawObservations = 0;
let noCurrentRawObservation = 0;
for (const frame of production.frames) {
  const old = baselineByTime.get(frame.observedAtJst);
  assert.ok(old);
  for (const field of fields) assert.deepEqual(frame.estimate?.[field], old.estimate?.[field]);
  const audit = frame.magnitudeAudit;
  if (!audit?.stationTrace) continue;
  const time = audit.observedAtUtc;
  const trace = tracesByTime.get(time);
  assert.ok(trace);
  const workers = new Set(audit.stationTrace.workerInputOrder ?? []);
  const originalRows = new Map(trace.stations.map(s => [s.code, s]));
  for (const station of audit.stationTrace.stations) {
    const original = originalRows.get(station.code)?.observedRawIntensity;
    if (original == null) {
      noCurrentRawObservation++;
      continue;
    }
    assert.equal(station.rawIntensity, original, `${time} ${station.code} raw input mismatch`);
    identicalRawObservations++;
  }
  const diagnostic = audit.publishedDiagnostics;
  const candidates = audit.stationTrace.stations.filter(s => workers.has(s.code));
  if (diagnostic?.srev_kaizou_magnitude_active_detection_count === 1) {
    const maximum = Math.max(...candidates.map(s => s.timedHeldConvertedIntensity).filter(v => v != null));
    assert.equal(maximum, audit.timedActiveHeldConvertedIntensity);
    checkedWorkerFrames++;
  }
  const permitted = trace.stations.filter(s => Number(s.permission) >= 4 &&
    Number(s.permittedIntensity) > 0 && s.intensity !== '' && s.intensity != null);
  const maximum = permitted.length ? Math.max(...permitted.map(s => Number(s.intensity))) : null;
  // Original procedure starts from -3, then takes the permitted maximum.
  assert.equal(Number(trace.realtimeIntensity), Math.max(-3, maximum ?? -3));
  const strongest = audit.stationTrace.stations.find(s => s.code === audit.strongestStationCode);
  const nearestIndex = Number(diagnostic?.srev_kaizou_magnitude_nearest_station_code?.split(':')[1]);
  const nearest = srev.stationTable.find(s => s.index === nearestIndex);
  const selectedCodes = new Set([strongest?.code, nearest?.code].filter(Boolean));
  const stations = [...selectedCodes].map(code => ({
    ...tableByCode.get(code),
    production: audit.stationTrace.stations.find(s => s.code === code) ?? null,
    productionWorkerIncluded: workers.has(code),
    srev: trace.stations.find(s => s.code === code) ?? null,
  }));
  frames.push({observedAtUtc: time, productionMagnitude: frame.estimate?.magnitude ?? null,
    publishedIntensity: diagnostic?.srev_kaizou_magnitude_input_intensity ?? null,
    reportNumber: diagnostic?.srev_kaizou_magnitude_target_report_num ?? null,
    locked: diagnostic?.srev_kaizou_magnitude_locked ?? null,
    workerCount: workers.size, activeCount: audit.activeStationCount,
    strongestCode: strongest?.code ?? null, strongestWorkerIncluded: strongest ? workers.has(strongest.code) : null,
    freshQuantizedMagnitude: audit.freshTimedHeldMagnitude ?? null,
    continuousInstantaneousMagnitude: audit.instantaneousRawMagnitude ?? null,
    nearestDistanceKm: diagnostic?.srev_kaizou_magnitude_nearest_station_distance_km ?? null,
    strongestDistanceKm: audit.strongestStationDistanceKm ?? null,
    srevRealtimeIntensity: trace.realtimeIntensity,
    srevMaximumStations: permitted.filter(s => Number(s.intensity) === maximum).map(s => s.code),
    srevSources: sourcesByTime.get(time).map(s => ({id: s.detectionId, valid: s.valid, magnitude: s.magnitude})),
    stations});
}
const report = {diagnosticOnly: true, productionChanged: false, fullBrowserReplay: false,
  caseId: production.id, rawInputSha256: production.rawInputSha256,
  inputs: [productionPath, baselinePath, srevPath, srevBaselinePath].map(p => ({path: p, sha256: sha(p)})),
  checks: {unchangedProductionFrames: production.frames.length, unchangedSrevFrames: srev.frames.length,
    workerMaximumFrames: checkedWorkerFrames, alignedFrames: frames.length,
    identicalRawObservations, noCurrentRawObservation},
  firstLockedAt: frames.find(f => f.locked)?.observedAtUtc ?? null,
  strongestExcludedFrames: frames.filter(f => f.strongestCode && !f.strongestWorkerIncluded).length,
  frames};
fs.mkdirSync(path.dirname(output), {recursive: true});
fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n', {flag: 'wx'});
console.log(JSON.stringify({output, checks: report.checks, firstLockedAt: report.firstLockedAt,
  strongestExcludedFrames: report.strongestExcludedFrames}, null, 2));
