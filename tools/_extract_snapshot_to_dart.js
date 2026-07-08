// Generates tools/reference_dart_port/kotoho7_snapshot_initializer.dart
// from the SNAPSHOT object exported by kotoho7_receiver_compiled_core.js.
//
// This is a one-time codegen step. Re-run after the upstream JS snapshot
// changes. Output is committed (not generated at build time) so the port
// remains self-contained and does not require Node during Flutter builds.
'use strict';

const fs = require('fs');
const path = require('path');
const core = require('./kotoho7_receiver_compiled_core.js');

const SNAPSHOT = core.SNAPSHOT;
const OUT_PATH = path.join(__dirname, 'reference_dart_port', 'kotoho7_snapshot_initializer.dart');

function escapeDartString(s) {
  // Escape for Dart single-quoted string literal.
  // NOTE: `$` triggers string interpolation in Dart (both '$x' and '${x}').
  // Variable IDs/names from the SNAPSHOT frequently contain `$`, so we
  // escape every `$` as `\$` to ensure literal output.
  let out = '';
  for (const ch of s) {
    const code = ch.codePointAt(0);
    if (ch === '\\') out += '\\\\';
    else if (ch === "'") out += "\\'";
    else if (ch === '$') out += '\\$';
    else if (ch === '\n') out += '\\n';
    else if (ch === '\r') out += '\\r';
    else if (ch === '\t') out += '\\t';
    else if (code < 0x20) out += '\\u' + code.toString(16).padStart(4, '0').toUpperCase();
    else out += ch;
  }
  return "'" + out + "'";
}

function renderValue(v, indent) {
  const pad = '  '.repeat(indent);
  const padInner = '  '.repeat(indent + 1);
  if (v === null || v === undefined) return 'null';
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  if (typeof v === 'number') {
    if (Number.isNaN(v)) return 'double.nan';
    if (Number.isFinite(v)) {
      // Preserve full precision; JS Number formats the same way Dart doubles parse.
      if (Number.isInteger(v) && Math.abs(v) < 1e15) return String(v);
      return String(v);
    }
    if (v === Infinity) return 'double.infinity';
    if (v === -Infinity) return 'double.negativeInfinity';
    return 'double.nan';
  }
  if (typeof v === 'string') return escapeDartString(v);
  if (Array.isArray(v)) {
    if (v.length === 0) return '<Object?>[]';
    const items = v.map(item => padInner + renderValue(item, indent + 1));
    return '<Object?>[\n' + items.join(',\n') + ',\n' + pad + ']';
  }
  // Fallback: object → JSON
  return escapeDartString(JSON.stringify(v));
}

function renderVariable(key, varObj, indent) {
  const pad = '  '.repeat(indent);
  const padInner = '  '.repeat(indent + 1);
  const id = varObj.id;
  const name = varObj.name || '';
  const type = varObj.type || '';
  // broadcast_msg: omit value to keep output small; the runtime makeTarget
  // only needs id/name/type for broadcast_msg vars (value is unused).
  const hasValue = type !== 'broadcast_msg';
  const lines = [];
  lines.push(pad + escapeDartString(key) + ': {');
  lines.push(padInner + "'id': " + escapeDartString(id) + ',');
  lines.push(padInner + "'name': " + escapeDartString(name) + ',');
  lines.push(padInner + "'type': " + escapeDartString(type) + ',');
  if (hasValue) {
    lines.push(padInner + "'value': " + renderValue(varObj.value, indent + 1) + ',');
  } else {
    lines.push(padInner + "'value': null,");
  }
  lines.push(pad + '},');
  return lines.join('\n');
}

function renderTarget(targetName, targetObj, indent) {
  const pad = '  '.repeat(indent);
  const padInner = '  '.repeat(indent + 1);
  const padVar = '  '.repeat(indent + 2);
  const vars = targetObj.variables || {};
  const keys = Object.keys(vars);
  const lines = [];
  lines.push(pad + escapeDartString(targetName) + ': {');
  lines.push(padInner + "'name': " + escapeDartString(targetObj.name || '') + ',');
  lines.push(padInner + "'variables': <String, Map<String, dynamic>>{");
  for (const k of keys) {
    lines.push(renderVariable(k, vars[k], indent + 2));
  }
  lines.push(padInner + '},');
  lines.push(pad + '},');
  return lines.join('\n');
}

const stageVars = SNAPSHOT.stage.variables;
const recvVars = SNAPSHOT.receiver.variables;
const stageKeys = Object.keys(stageVars);
const recvKeys = Object.keys(recvVars);
let stageListItems = 0, recvListItems = 0;
for (const k of stageKeys) if (stageVars[k].type === 'list') stageListItems += stageVars[k].value.length;
for (const k of recvKeys) if (recvVars[k].type === 'list') recvListItems += recvVars[k].value.length;

const header = [
  '// GENERATED. Do not edit. Re-run: node tools/_extract_snapshot_to_dart.js',
  '//',
  '// 1:1 Dart mirror of the SNAPSHOT object exported by',
  '// tools/kotoho7_receiver_compiled_core.js (line 166+).',
  '//',
  '// Source snapshot stats:',
  '//   stage:    ' + stageKeys.length + ' variables (' + stageKeys.filter(k => stageVars[k].type === 'list').length + ' lists, ' + stageListItems + ' list items)',
  '//   receiver: ' + recvKeys.length + ' variables (' + recvKeys.filter(k => recvVars[k].type === 'list').length + ' lists, ' + recvListItems + ' list items)',
  '//',
  '// Non-production: this file lives under tools/reference_dart_port/ and is',
  '// NOT compiled into the Flutter app. It mirrors the JS SNAPSHOT so that',
  '// tools/reference_dart_port/kotoho7_path_procedures.dart can build a Thread',
  '// without requiring the JS runtime at test time.',
  '',
  '/// Mirror of JS `const SNAPSHOT = { stage: {...}, receiver: {...} }`.',
  '///',
  '/// Shape matches what `makeTarget` expects: each target has a `name`',
  '/// (string) and a `variables` map keyed by hashed variable id, with each',
  '/// entry being `{id, name, type, value}`. Lists are inlined as',
  '/// `<Object?>[...]` so the const map stays self-contained.',
  'final Map<String, Map<String, dynamic>> kotoho7Snapshot = <String, Map<String, dynamic>>{',
].join('\n');

const body = [
  renderTarget('stage', SNAPSHOT.stage, 1),
  renderTarget('receiver', SNAPSHOT.receiver, 1),
  '};',
].join('\n');

const output = header + '\n' + body + '\n';

// Ensure directory exists
const outDir = path.dirname(OUT_PATH);
if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });

fs.writeFileSync(OUT_PATH, output, 'utf8');
const sizeKB = (Buffer.byteLength(output, 'utf8') / 1024).toFixed(1);
console.log('Wrote ' + OUT_PATH);
console.log('  size: ' + sizeKB + ' KB');
console.log('  stage:    ' + stageKeys.length + ' vars (' + stageKeys.filter(k => stageVars[k].type === 'list').length + ' lists, ' + stageListItems + ' items)');
console.log('  receiver: ' + recvKeys.length + ' vars (' + recvKeys.filter(k => recvVars[k].type === 'list').length + ' lists, ' + recvListItems + ' items)');
console.log('  total:    ' + (stageKeys.length + recvKeys.length) + ' vars, ' + (stageListItems + recvListItems) + ' list items');
