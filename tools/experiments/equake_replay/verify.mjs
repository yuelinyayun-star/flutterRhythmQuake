import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {parseGifDat} from './extract.mjs';

const [source, extracted] = process.argv.slice(2);
if (!source || !extracted) throw new Error('Usage: node verify.mjs source-directory extracted-directory');
const sha = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');
const manifest = JSON.parse(fs.readFileSync(path.join(extracted, 'extraction-manifest.json'), 'utf8'));
const downloads = JSON.parse(fs.readFileSync(path.join(source, 'download-manifest.json'), 'utf8'));
const results = [];
for (const layer of ['jma_s', 'acmap_s']) {
  const raw = fs.readFileSync(path.join(source, layer + '.dat'));
  assert.equal(sha(raw), manifest.sourceHashes[layer]);
  const frames = parseGifDat(raw);
  assert.equal(frames.length, manifest.layerCounts[layer]);
  const rebuilt = Buffer.concat(frames.flatMap((frame) => [
    Buffer.from(frame.stamp, 'ascii'), frame.gif, Buffer.from('!&@^#*'),
  ]));
  assert.deepEqual(rebuilt, raw);
  for (const frame of frames) {
    const name = `${frame.stamp}.${layer}.gif`;
    assert.deepEqual(fs.readFileSync(path.join(extracted, name)), frame.gif);
  }
  // Corruption checks use byte prefixes of real files, never synthetic observations.
  assert.throws(() => parseGifDat(raw.subarray(0, 13)), /Truncated timestamp/);
  assert.throws(() => parseGifDat(raw.subarray(0, raw.length - 1)), /Missing separator/);
  const first = frames[0];
  assert.throws(() => parseGifDat(raw.subarray(0, first.gifOffset + first.length - 1)), /Truncated GIF/);
  results.push({layer, frames: frames.length, sha256: sha(raw), roundTripExact: true});
}
console.log(JSON.stringify({passed: true, results, downloadManifestPresent: !!downloads,
  scope: 'Raw container and GIF integrity only; no EQ inference or accuracy claim'}, null, 2));
