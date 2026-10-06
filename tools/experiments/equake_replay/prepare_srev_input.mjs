import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const [extracted, destination] = process.argv.slice(2);
if (!extracted || !destination) throw Error('Usage: prepare_srev_input.mjs extracted new-directory');
if (fs.existsSync(destination)) throw Error('Destination must be new');
const hash = b => crypto.createHash('sha256').update(b).digest('hex');
const source = JSON.parse(fs.readFileSync(path.join(extracted, 'extraction-manifest.json'), 'utf8'));
const records = source.records.filter(r => r.layer === 'jma_s');
const verified = records.map(r => {
  if (path.basename(r.filename) !== r.filename) throw Error('Unsafe filename');
  const bytes = fs.readFileSync(path.join(extracted, r.filename));
  if (hash(bytes) !== r.sha256) throw Error(`Hash mismatch: ${r.filename}`);
  return {r, bytes};
});
fs.mkdirSync(destination, {recursive: true});
for (const {r, bytes} of verified) fs.writeFileSync(path.join(destination, r.filename), bytes, {flag: 'wx'});
fs.writeFileSync(path.join(destination, 'capture_manifest.json'), JSON.stringify({
  caseId: 'equake_wakayama_20261003_original_window',
  startTimeJst: source.startTimeJst, endTimeJst: source.endTimeJst,
  sourceExtractionManifest: path.resolve(extracted, 'extraction-manifest.json'),
  eventLabels: {catalogTruthVerified: false},
  records: records.map(r => ({observedAt: r.observedAtUtc, layer: r.layer,
    file: r.filename, ok: true, sha256: r.sha256, qualityFlags: ['original_eq_gif_bytes']})),
}, null, 2) + '\n', {flag: 'wx'});
console.log(JSON.stringify({frames: records.length, destination, rawBytesUnchanged: true}));
