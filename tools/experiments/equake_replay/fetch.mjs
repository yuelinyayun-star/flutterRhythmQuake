import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const origin = 'https://file.he83e9571.nyat.app:15404';
const [remoteDirectory, output] = process.argv.slice(2);
if (!remoteDirectory?.startsWith('/') || !output) {
  throw new Error('Usage: node fetch.mjs /remote-directory new-local-directory');
}
const root = path.resolve(output);
if (fs.existsSync(root)) throw new Error('Choose a new output directory');
async function api(endpoint, body) {
  const r = await fetch(`${origin}/api/fs/${endpoint}`, {
    method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify(body), signal: AbortSignal.timeout(30000),
  });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  const text = await r.text();
  const result = JSON.parse(text);
  if (result.code !== 200) throw new Error(`${endpoint}: ${result.message}`);
  return {text, data: result.data};
}
const listing = await api('list', {
  path: remoteDirectory, password: '', page: 1, per_page: 100, refresh: false,
});
if (listing.data.total !== listing.data.content.length) {
  throw new Error('Directory requires pagination; refusing partial download');
}
const files = listing.data.content;
if (files.some((f) => f.is_dir || !/^[A-Za-z0-9_.-]+$/.test(f.name))) {
  throw new Error('Unexpected nested directory or unsafe filename');
}
if (files.reduce((s, f) => s + f.size, 0) > 50 * 1024 * 1024) {
  throw new Error('Selected directory exceeds 50 MiB inspection budget');
}
fs.mkdirSync(root, {recursive: true});
fs.writeFileSync(path.join(root, 'listing.response.json'), listing.text, {flag: 'wx'});
const records = [];
for (const f of files) {
  const remotePath = `${remoteDirectory}/${f.name}`;
  const entry = await api('get', {path: remotePath, password: ''});
  const url = new URL(entry.data.raw_url);
  if (!['http:', 'https:'].includes(url.protocol)) throw new Error('Unsupported download URL');
  const r = await fetch(url, {signal: AbortSignal.timeout(60000)});
  if (!r.ok) throw new Error(`${f.name}: HTTP ${r.status}`);
  const bytes = Buffer.from(await r.arrayBuffer());
  if (bytes.length !== f.size) throw new Error(`${f.name}: size mismatch`);
  fs.writeFileSync(path.join(root, f.name), bytes, {flag: 'wx'});
  const sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
  records.push({name: f.name, size: bytes.length, sha256, remotePath,
    retrievedAtUtc: new Date().toISOString()});
  console.log(`${f.name}: ${bytes.length} bytes ${sha256}`);
}
fs.writeFileSync(path.join(root, 'download-manifest.json'), JSON.stringify({
  source: origin, remoteDirectory, files: records,
  rawBytesPreserved: true, contentExecuted: false,
}, null, 2) + '\n', {flag: 'wx'});
