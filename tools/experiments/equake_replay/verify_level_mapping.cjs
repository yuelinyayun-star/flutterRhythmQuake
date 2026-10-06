'use strict';
const fs = require('node:fs');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const core = require('../../kotoho7_receiver_compiled_core.js');
const srev = require('../../srev_kaizou_algorithm_runner.js');
const receiver = require('../../kotoho7_receiver_bridge_runner.js');

const input = process.argv[2];
if (!input) throw Error('Pass original decoded observations.json');
const bytes = fs.readFileSync(input);
const observations = JSON.parse(bytes.toString('utf8')).observations;
const session = srev.createSession('.dart_tool/srev_kaizou_diagnostic/upstream/srev-s/assets/project.json');
const table = core.variableByName(session.thread.target.runtime.stage, 'd #震度換算30段階').value;
assert.equal(table.length, 90);
let previouslyInvalidLevels = 0;
let checked = 0;
for (const row of observations) {
  const value = row.gifDecodedShindo;
  assert.ok(Number.isFinite(value));
  const nearest = values => values.reduce((best, v, i) =>
    Math.abs(Number(v) - value) < best.distance ? {index: i + 1, distance: Math.abs(Number(v) - value)} : best,
  {index: 1, distance: Infinity}).index;
  const oldLevel = nearest(table);
  const expected = nearest(table.slice(0, 30));
  const actual = receiver.shindoToScratchLevelIndex(session.thread, value);
  assert.equal(actual, expected);
  assert.ok(actual >= 1 && actual <= 30);
  if (oldLevel > 30) previouslyInvalidLevels++;
  checked++;
}
assert.ok(previouslyInvalidLevels > 0, 'Original sample must exercise the regression');
assert.deepEqual(fs.readFileSync(input), bytes);
console.log(JSON.stringify({checked, previouslyInvalidLevels, correctedRange: [1, 30],
  inputSha256: crypto.createHash('sha256').update(bytes).digest('hex'), rawInputUnchanged: true}, null, 2));
