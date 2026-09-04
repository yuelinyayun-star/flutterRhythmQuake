'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const projectPath = path.resolve(
  '.dart_tool',
  'srev_kaizou_diagnostic',
  'upstream',
  'srev-s',
  'assets',
  'project.json'
);
const outputPath = path.resolve(
  'lib',
  'core',
  'source_estimation',
  'srev_kaizou_scratch_station_table.dart'
);
const expectedSha256 =
  '13C441EDC1F865CEFA9A5399AD2AD9721E6B0868B6B2E7B20325E745B3335B3A';
const expectedStationCount = 1748;

function findStageList(stage, name) {
  for (const value of Object.values(stage.lists || {})) {
    if (value[0] === name) return value[1];
  }
  throw new Error(`Scratch list not found: ${name}`);
}

function dartString(value) {
  return JSON.stringify(String(value)).replaceAll('$', '\\$');
}

const projectBytes = fs.readFileSync(projectPath);
const actualSha256 = crypto
  .createHash('sha256')
  .update(projectBytes)
  .digest('hex')
  .toUpperCase();
if (actualSha256 !== expectedSha256) {
  throw new Error(
    `Unexpected project.json SHA-256: ${actualSha256}; expected ${expectedSha256}`
  );
}

const project = JSON.parse(projectBytes.toString('utf8'));
const stage = project.targets.find((target) => target.isStage);
if (!stage) throw new Error('Scratch Stage target not found');

const longitudes = findStageList(stage, 'd ten:x');
const latitudes = findStageList(stage, 'd ten:y');
const names = findStageList(stage, 'd ten:名前');
for (const [name, values] of Object.entries({longitudes, latitudes, names})) {
  if (values.length !== expectedStationCount) {
    throw new Error(
      `${name} has ${values.length} entries; expected ${expectedStationCount}`
    );
  }
}

const rows = longitudes.map((longitude, index) => {
  const latitude = latitudes[index];
  if (!Number.isFinite(longitude) || !Number.isFinite(latitude)) {
    throw new Error(`Non-finite coordinate at Scratch station ${index + 1}`);
  }
  return `  (longitude: ${longitude}, latitude: ${latitude}, name: ${dartString(names[index])}),`;
});

const output = [
  '// GENERATED FILE. DO NOT EDIT.',
  '// Source: t0729/srev-kaizou@fe881fe9a172c02e81c88011792af22804255a84',
  `// project.json SHA-256: ${expectedSha256}`,
  '// Scratch Stage lists: d ten:x, d ten:y, d ten:名前.',
  '',
  `const String srevKaizouScratchProjectSha256 = '${expectedSha256}';`,
  '',
  'const List<({double longitude, double latitude, String name})>',
  'srevKaizouScratchStationTable =',
  '    <({double longitude, double latitude, String name})>[',
  ...rows,
  '    ];',
  '',
].join('\n');

fs.writeFileSync(outputPath, output, {encoding: 'utf8'});
console.log(`Generated ${rows.length} stations at ${outputPath}`);
