'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const DEFAULT_TARGET = '受信と検出';
const DEFAULT_OUTPUT = path.join(
  '.dart_tool',
  'srev_kaizou_diagnostic',
  'procedure_comparison.json'
);

const INCLUDED_PROCEDURE_PATTERNS = [
  /^HYP:/,
  /^JMA2001距離近似:/,
  /^点-震源 距離計算/,
  /^検出id/,
];

function usage() {
  return [
    'Usage:',
    '  node tools/extract_srev_kaizou_procedures.js',
    '    --srev-project <project.json>',
    '    [--compare-project <project.json>]',
    '    [--output <report.json>]',
    '    [--target <Scratch target name>]',
    '    [--all-procedures]',
    '',
    'The report is a read-only structural comparison of Scratch procedures.',
    'Block ids, variable ids, coordinates, and editor-only metadata are ignored.',
  ].join('\n');
}

function parseArgs(argv) {
  const values = {
    output: DEFAULT_OUTPUT,
    target: DEFAULT_TARGET,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--help' || arg === '-h') {
      values.help = true;
      continue;
    }
    if (arg === '--all-procedures') {
      values.allProcedures = true;
      continue;
    }
    if (!arg.startsWith('--')) {
      throw new Error(`Unexpected argument: ${arg}`);
    }
    const key = arg.slice(2).replace(/-([a-z])/g, (_, letter) =>
      letter.toUpperCase()
    );
    const value = argv[index + 1];
    if (value == null || value.startsWith('--')) {
      throw new Error(`Missing value for ${arg}`);
    }
    values[key] = value;
    index += 1;
  }
  return values;
}

function sha256Buffer(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex').toUpperCase();
}

function sha256Json(value) {
  return sha256Buffer(Buffer.from(JSON.stringify(value), 'utf8'));
}

function readProject(projectPath, targetName) {
  const absolutePath = path.resolve(projectPath);
  const bytes = fs.readFileSync(absolutePath);
  const project = JSON.parse(bytes.toString('utf8'));
  const target = project.targets.find((item) => item.name === targetName);
  if (!target) {
    throw new Error(`Target ${JSON.stringify(targetName)} not found in ${absolutePath}`);
  }
  const symbols = new Map();
  for (const item of project.targets) {
    for (const [id, value] of Object.entries(item.variables || {})) {
      symbols.set(id, {name: value[0], kind: 'variable'});
    }
    for (const [id, value] of Object.entries(item.lists || {})) {
      symbols.set(id, {name: value[0], kind: 'list'});
    }
  }
  return {
    absolutePath,
    sha256: sha256Buffer(bytes),
    target,
    symbols,
  };
}

function parseJsonArray(value) {
  if (Array.isArray(value)) return value;
  if (typeof value !== 'string') return [];
  try {
    const parsed = JSON.parse(value);
    return Array.isArray(parsed) ? parsed : [];
  } catch (_) {
    return [];
  }
}

function fieldValue(value, symbols) {
  if (Array.isArray(value)) {
    const symbol = symbols.get(value[1]);
    return symbol?.name || value[0];
  }
  return value;
}

function normalizeLiteral(value, symbols) {
  if (!Array.isArray(value)) return value;
  if ((value[0] === 12 || value[0] === 13) && symbols.has(value[2])) {
    const symbol = symbols.get(value[2]);
    return [value[0], symbol.name];
  }
  return value.map((item) => normalizeLiteral(item, symbols));
}

function referencedBlockId(input) {
  if (!Array.isArray(input)) return null;
  return typeof input[1] === 'string' ? input[1] : null;
}

function canonicalInput(input, blocks, symbols, visiting) {
  const blockId = referencedBlockId(input);
  if (blockId && blocks[blockId]) {
    return {
      kind: 'block',
      value: canonicalBlock(blockId, blocks, symbols, visiting),
    };
  }
  return {
    kind: 'literal',
    value: normalizeLiteral(input, symbols),
  };
}

function canonicalInputNames(block) {
  const mutation = block.mutation || {};
  const argumentIds = parseJsonArray(mutation.argumentids);
  const argumentNames = parseJsonArray(mutation.argumentnames);
  const names = new Map();
  for (let index = 0; index < argumentIds.length; index += 1) {
    names.set(argumentIds[index], argumentNames[index] || `argument_${index + 1}`);
  }
  return names;
}

function canonicalMutation(block) {
  const mutation = block.mutation;
  if (!mutation) return undefined;
  const result = {};
  if (mutation.proccode != null) result.proccode = mutation.proccode;
  if (mutation.argumentnames != null) {
    result.argumentNames = parseJsonArray(mutation.argumentnames);
  }
  if (mutation.warp != null) result.warp = String(mutation.warp);
  return Object.keys(result).length === 0 ? undefined : result;
}

function canonicalBlock(blockId, blocks, symbols, visiting) {
  if (visiting.has(blockId)) {
    return {cycle: blocks[blockId]?.opcode || 'unknown'};
  }
  const block = blocks[blockId];
  if (!block) return {missingBlock: true};
  const nextVisiting = new Set(visiting);
  nextVisiting.add(blockId);

  const result = {opcode: block.opcode};
  const fields = Object.entries(block.fields || {})
    .sort(([left], [right]) => left.localeCompare(right, 'en'))
    .map(([name, value]) => [name, fieldValue(value, symbols)]);
  if (fields.length > 0) result.fields = Object.fromEntries(fields);

  const mutation = canonicalMutation(block);
  if (mutation) result.mutation = mutation;

  const inputNames = canonicalInputNames(block);
  const inputs = Object.entries(block.inputs || {}).map(([name, value]) => {
    const canonicalName = inputNames.get(name) || name;
    return [
      canonicalName,
      canonicalInput(value, blocks, symbols, nextVisiting),
    ];
  });
  inputs.sort(([left], [right]) => left.localeCompare(right, 'ja'));
  if (inputs.length > 0) result.inputs = Object.fromEntries(inputs);

  if (block.next != null) {
    result.next = canonicalBlock(block.next, blocks, symbols, nextVisiting);
  }
  return result;
}

function findProcedureDefinitions(target) {
  const blocks = target.blocks || {};
  const definitions = new Map();
  for (const [definitionId, definition] of Object.entries(blocks)) {
    if (definition.opcode !== 'procedures_definition') continue;
    const prototypeId = referencedBlockId(definition.inputs?.custom_block);
    const prototype = prototypeId == null ? null : blocks[prototypeId];
    const proccode = prototype?.mutation?.proccode;
    if (typeof proccode !== 'string') continue;
    definitions.set(proccode, {
      definitionId,
      bodyId: definition.next,
      warp: String(prototype.mutation?.warp || 'false'),
      argumentNames: parseJsonArray(prototype.mutation?.argumentnames),
    });
  }
  return definitions;
}

function isIncludedProcedure(name) {
  return INCLUDED_PROCEDURE_PATTERNS.some((pattern) => pattern.test(name));
}

function extractProcedures(project, {allProcedures = false} = {}) {
  const blocks = project.target.blocks || {};
  const definitions = findProcedureDefinitions(project.target);
  const procedures = {};
  for (const name of [...definitions.keys()].sort((a, b) => a.localeCompare(b, 'ja'))) {
    if (!allProcedures && !isIncludedProcedure(name)) continue;
    const definition = definitions.get(name);
    const body = definition.bodyId == null
      ? null
      : canonicalBlock(definition.bodyId, blocks, project.symbols, new Set());
    const canonical = {
      proccode: name,
      argumentNames: definition.argumentNames,
      warp: definition.warp,
      body,
    };
    procedures[name] = {
      sha256: sha256Json(canonical),
      canonical,
    };
  }
  return procedures;
}

function structuralDifferences(left, right, currentPath = '$', differences = []) {
  if (differences.length >= 80) return differences;
  if (Object.is(left, right)) return differences;
  if (left == null || right == null || typeof left !== typeof right) {
    differences.push({path: currentPath, srev: left, comparison: right});
    return differences;
  }
  if (typeof left !== 'object') {
    differences.push({path: currentPath, srev: left, comparison: right});
    return differences;
  }
  if (Array.isArray(left) || Array.isArray(right)) {
    if (!Array.isArray(left) || !Array.isArray(right)) {
      differences.push({path: currentPath, srev: left, comparison: right});
      return differences;
    }
    const length = Math.max(left.length, right.length);
    for (let index = 0; index < length; index += 1) {
      structuralDifferences(
        left[index],
        right[index],
        `${currentPath}[${index}]`,
        differences
      );
      if (differences.length >= 80) break;
    }
    return differences;
  }
  const keys = new Set([...Object.keys(left), ...Object.keys(right)]);
  for (const key of [...keys].sort((a, b) => a.localeCompare(b, 'ja'))) {
    const escaped = /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(key)
      ? `.${key}`
      : `[${JSON.stringify(key)}]`;
    structuralDifferences(
      left[key],
      right[key],
      `${currentPath}${escaped}`,
      differences
    );
    if (differences.length >= 80) break;
  }
  return differences;
}

function compareProcedures(srev, reference) {
  if (!reference) return null;
  const names = new Set([...Object.keys(srev), ...Object.keys(reference)]);
  const rows = [];
  for (const name of [...names].sort((a, b) => a.localeCompare(b, 'ja'))) {
    const left = srev[name];
    const right = reference[name];
    let status;
    if (!left) status = 'missing_in_srev';
    else if (!right) status = 'missing_in_comparison';
    else if (left.sha256 === right.sha256) status = 'identical';
    else status = 'different';
    rows.push({
      proccode: name,
      status,
      srevSha256: left?.sha256 || null,
      comparisonSha256: right?.sha256 || null,
      differences: status === 'different'
        ? structuralDifferences(left.canonical, right.canonical)
        : [],
    });
  }
  return {
    identicalCount: rows.filter((row) => row.status === 'identical').length,
    differentCount: rows.filter((row) => row.status === 'different').length,
    missingInSrevCount: rows.filter((row) => row.status === 'missing_in_srev').length,
    missingInComparisonCount: rows.filter(
      (row) => row.status === 'missing_in_comparison'
    ).length,
    procedures: rows,
  };
}

function projectSummary(project, procedures) {
  return {
    path: project.absolutePath,
    projectSha256: project.sha256,
    target: project.target.name,
    procedureCount: Object.keys(procedures).length,
    procedures,
  };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  if (!args.srevProject) {
    throw new Error(`--srev-project is required\n\n${usage()}`);
  }

  const srevProject = readProject(args.srevProject, args.target);
  const srevProcedures = extractProcedures(srevProject, {
    allProcedures: args.allProcedures === true,
  });
  const comparisonProject = args.compareProject
    ? readProject(args.compareProject, args.target)
    : null;
  const comparisonProcedures = comparisonProject
    ? extractProcedures(comparisonProject, {
        allProcedures: args.allProcedures === true,
      })
    : null;
  const report = {
    schemaVersion: 1,
    generatedAtUtc: new Date().toISOString(),
    normalization: {
      includes: INCLUDED_PROCEDURE_PATTERNS.map((pattern) => pattern.source),
      allProcedures: args.allProcedures === true,
      ignores: [
        'Scratch block ids',
        'variable and list ids while retaining visible names',
        'parent links',
        'editor coordinates and comments',
      ],
    },
    srev: projectSummary(srevProject, srevProcedures),
    comparison: comparisonProject
      ? projectSummary(comparisonProject, comparisonProcedures)
      : null,
    result: compareProcedures(srevProcedures, comparisonProcedures),
  };

  const outputPath = path.resolve(args.output);
  fs.mkdirSync(path.dirname(outputPath), {recursive: true});
  fs.writeFileSync(outputPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  process.stdout.write(`${JSON.stringify({
    output: outputPath,
    srevProjectSha256: srevProject.sha256,
    srevProcedureCount: Object.keys(srevProcedures).length,
    comparisonProjectSha256: comparisonProject?.sha256 || null,
    comparisonProcedureCount: comparisonProcedures
      ? Object.keys(comparisonProcedures).length
      : null,
    result: report.result == null
      ? null
      : {
          identicalCount: report.result.identicalCount,
          differentCount: report.result.differentCount,
          missingInSrevCount: report.result.missingInSrevCount,
          missingInComparisonCount: report.result.missingInComparisonCount,
        },
  }, null, 2)}\n`);
}

try {
  main();
} catch (error) {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
}
