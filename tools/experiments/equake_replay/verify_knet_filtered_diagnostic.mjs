import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
assert.equal(args.length, 5, 'Pass full diagnostic, Aizu rerun, two feature packages, new output');
const buffers = args.slice(0, 4).map(p => readFileSync(p));
const [diagnostic, rerun, ...packages] = buffers.map(b => JSON.parse(b));
const sha = b => createHash('sha256').update(b).digest('hex');
assert.equal(diagnostic.feedsProduction, false);
assert.equal(diagnostic.readyForCalibration, false);
assert.deepEqual(diagnostic.archives[0], rerun.archives[0], 'Raw Aizu rerun must match');
assert.equal(diagnostic.archives.length, packages.length);
let records = 0;
let seconds = 0;
let maximumProxyDifference = 0;
for (const [index, archive] of diagnostic.archives.entries()) {
  assert.equal(sha(readFileSync(archive.input)), archive.sha256);
  const legacy = packages[index];
  assert.equal(legacy.inputs.length, 1);
  assert.equal(path.resolve(legacy.inputs[0]), path.resolve(archive.input));
  assert.equal(archive.stations.length, legacy.features.length);
  for (const station of archive.stations) {
    const matches = legacy.features.filter(s => s.stationCode === station.station && s.sensorRole === 'surface');
    assert.equal(matches.length, 1, `Exact unique station required: ${station.station}`);
    const previous = matches[0];
    assert.equal(previous.samplingHz, station.samplingHz);
    assert.deepEqual([...previous.availableComponents].sort(), ['EW', 'NS', 'UD']);
    assert.equal(previous.seconds.length, station.seconds.length);
    const start = Date.parse(station.sampleStartJst.replaceAll('/', '-').replace(' ', 'T') + '+09:00');
    assert.ok(Number.isFinite(start));
    assert.equal(start, Date.parse(previous.sampleStartTimeUtc));
    for (const [i, second] of station.seconds.entries()) {
      const old = previous.seconds[i];
      assert.equal(second.second, old.secondIndex);
      assert.equal(start + i * 1000, Date.parse(old.startTimeUtc));
      const a = second.unfiltered.continuousIntensity;
      const b = old.jmaIntensityApprox;
      if (a === null || b === null) {
        assert.equal(a, b);
      } else {
        assert.ok(Number.isFinite(a) && Number.isFinite(b));
        const difference = Math.abs(a - b);
        assert.ok(difference < 1e-10, `${station.station} second ${i}: ${difference}`);
        maximumProxyDifference = Math.max(maximumProxyDifference, difference);
      }
      seconds++;
    }
    records++;
  }
}
for (const [i, buffer] of buffers.entries()) {
  assert.equal(sha(readFileSync(args[i])), sha(buffer), 'Input report changed');
}
const output = args[4];
const root = realpathSync('.dart_tool');
const parent = realpathSync(path.dirname(output));
const relative = path.relative(root, parent);
assert.ok(relative === '' || (!relative.startsWith('..') && !path.isAbsolute(relative)));
assert.equal(path.extname(output), '.json');
assert.equal(existsSync(output), false);
const result = {
  records, seconds, maximumProxyDifference, aizuRerunIdentical: true,
  inputSha256: args.slice(0, 4).map((file, i) => ({ file, sha256: sha(buffers[i]) })),
  scope: 'Real record alignment and unfiltered comparator against existing Dart extraction; filtered diagnostic reproducibility only. Not an independent JMA filter oracle or GIF timing validation.',
};
writeFileSync(output, JSON.stringify(result, null, 2) + '\n', { encoding: 'utf8', flag: 'wx' });
console.log(JSON.stringify(result));
