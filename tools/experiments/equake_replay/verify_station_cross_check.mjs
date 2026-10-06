import assert from 'node:assert/strict';
import fs from 'node:fs';

const [tracePath, baselinePath, output] = process.argv.slice(2);
if (!output) throw Error('Usage: verify_station_cross_check.mjs trace baseline new-output');
if (fs.existsSync(output)) throw Error('Output already exists');
const trace = JSON.parse(fs.readFileSync(tracePath, 'utf8'));
const baseline = JSON.parse(fs.readFileSync(baselinePath, 'utf8'));
assert.equal(trace.solverSha256, baseline.solverSha256);
const cases = [];
for (const c of trace.cases) {
  const b = baseline.cases.find(b => b.id === c.id);
  assert.ok(b);
  assert.equal(c.rawInputSha256, b.rawInputSha256);
  assert.equal(c.frames.length, b.frames.length);
  assert.equal(c.missingFrameCount, b.missingFrameCount);
  let strongestExcludedFrames = 0;
  const exclusions = [];
  for (let i = 0; i < c.frames.length; i++) {
    const f = c.frames[i];
    assert.equal(f.observedAtJst, b.frames[i].observedAtJst);
    for (const field of ['latitude', 'longitude', 'depthKm', 'magnitude', 'supportingStationCount', 'originTime']) {
      assert.deepEqual(f.estimate?.[field], b.frames[i].estimate?.[field]);
    }
    const a = f.magnitudeAudit;
    if (!f.estimate || !a?.stationTrace || !a.strongestStationCode) continue;
    const included = a.stationTrace.workerInputOrder?.includes(a.strongestStationCode) ?? false;
    if (!included) {
      strongestExcludedFrames++;
      exclusions.push({observedAtJst: f.observedAtJst, strongestCode: a.strongestStationCode,
        hasTrigger: a.strongestStationHasTrigger, rawIntensity: a.allActiveRawMaximumIntensity,
        allActiveHeldIntensity: a.allActiveHeldConvertedIntensity,
        timedActiveHeldIntensity: a.timedActiveHeldConvertedIntensity,
        allActiveFreshMagnitude: a.freshHeldMagnitude, timedFreshMagnitude: a.freshTimedHeldMagnitude,
        publishedMagnitude: f.estimate.magnitude,
        singleSourceComparable: a.singleSourceComparable});
    }
  }
  cases.push({id: c.id, comparedFrames: c.frames.length, estimateFrames: c.estimateFrameCount,
    missingFrameCount: c.missingFrameCount, rawInputSha256: c.rawInputSha256,
    strongestExcludedFrames, exclusions});
}
const report = {diagnosticOnly: true, productionChanged: false,
  solverSha256: trace.solverSha256, cases};
fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n', {flag: 'wx'});
console.log(JSON.stringify(cases.map(({exclusions, ...c}) => ({...c, example: exclusions.find(e => e.strongestCode === 'YMN002') ?? exclusions[0]})), null, 2));
