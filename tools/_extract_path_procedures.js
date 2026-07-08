// Temporary extractor: dumps the JS source for procedures along the
// cloud-RT -> W震度復元 -> W揺れ検出許可 -> W検出id1_全点へ適用 -> W円検出の毎処理 -> HYP path
// so they can be reviewed/ported line-by-line.
'use strict';

const fs = require('fs');
const path = require('path');
const core = require('./kotoho7_receiver_compiled_core.js');

const sources = core.PROCEDURE_FACTORY_SOURCES;
const entryPoints = [
  'Wクラウド変数更新したら',
  'W震度復元',
  'W揺れ検出許可',
  'W検出id1_全点へ適用',
  'W円検出の毎処理 %b',
  'ZHYP:震源検出 %s %s',
];

// Collect transitively-referenced procedures by scanning for quoted call keys.
function collectReachable(seedKeys) {
  const seen = new Set();
  const ordered = [];
  const queue = [...seedKeys];
  while (queue.length) {
    const key = queue.shift();
    if (seen.has(key)) continue;
    seen.add(key);
    ordered.push(key);
    const src = sources[key];
    if (!src) continue;
    const callRegex = /thread\.procedures\["([^"]+)"\]/g;
    let m;
    while ((m = callRegex.exec(src)) !== null) {
      if (!seen.has(m[1])) queue.push(m[1]);
    }
  }
  return ordered;
}

const ordered = collectReachable(entryPoints);
const out = [];
out.push(`// Reachable procedures: ${ordered.length}`);
for (const key of ordered) {
  const src = sources[key];
  if (!src) {
    out.push(`\n// MISSING: ${key}`);
    continue;
  }
  out.push(`\n// === ${key} ===\n`);
  // The factory source is a JS string literal body; unfold common escapes
  // so the dumped file is readable line-by-line.
  out.push(src.replace(/\\n/g, '\n').replace(/\\t/g, '\t').replace(/\\"/g, '"'));
}
const outPath = path.join(__dirname, '_extracted_path_procedures.js');
fs.writeFileSync(outPath, out.join('\n'), 'utf8');
console.log(`Wrote ${ordered.length} procedures to ${outPath}`);
console.log('Order:');
ordered.forEach((k, i) => console.log(`  ${i + 1}. ${k}`));
