'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const {
  ScratchOverrideInterpreter,
  syncTargetVariables,
} = require('./srev_kaizou_scratch_overrides.js');

const root = path.resolve(__dirname, '..');
const projectPath = path.join(
  root,
  '.dart_tool',
  'srev_kaizou_diagnostic',
  'upstream',
  'srev-s',
  'assets',
  'project.json'
);
const expectedProjectSha256 =
  '13C441EDC1F865CEFA9A5399AD2AD9721E6B0868B6B2E7B20325E745B3335B3A';

function variableByName(target, name) {
  const variable = Object.values(target.variables).find(
    (candidate) => candidate.name === name
  );
  if (!variable) throw new Error(`Scratch variable or list not found: ${name}`);
  return variable;
}

function inputBlockId(block, name) {
  const value = block.inputs?.[name];
  return Array.isArray(value) && typeof value[1] === 'string'
    ? value[1]
    : null;
}

class MagnitudeTargetInterpreter extends ScratchOverrideInterpreter {
  callCompiled(block, env, prefix) {
    const proccode = block.mutation?.proccode;
    const definition = this.definitions.get(proccode);
    if (!definition) return super.callCompiled(block, env, prefix);

    const argumentIds = JSON.parse(block.mutation?.argumentids || '[]');
    const args = argumentIds.map((id) => this.input(block, id, env));
    const nestedEnv = new Map();
    for (let index = 0; index < definition.argumentNames.length; index += 1) {
      nestedEnv.set(definition.argumentNames[index], args[index] ?? '');
    }
    this.runStack(definition.bodyId, nestedEnv, prefix);
  }
}

function loadScratchMagnitudeRuntime() {
  const projectBytes = fs.readFileSync(projectPath);
  const projectSha256 = crypto
    .createHash('sha256')
    .update(projectBytes)
    .digest('hex')
    .toUpperCase();
  if (projectSha256 !== expectedProjectSha256) {
    throw new Error(
      `Unexpected project SHA-256: ${projectSha256}; expected ${expectedProjectSha256}`
    );
  }

  const project = JSON.parse(projectBytes.toString('utf8'));
  const stage = project.targets.find((target) => target.isStage);
  const magnitudeTarget = project.targets.find(
    (target) => target.name === 'マグニチュード計算'
  );
  if (!stage || !magnitudeTarget) {
    throw new Error('Scratch Stage or マグニチュード計算 target not found');
  }

  const runtimeStage = {variables: {}};
  const runtimeTarget = {
    variables: {},
    runtime: {stage: runtimeStage},
  };
  const thread = {target: runtimeTarget, procedures: {}};
  syncTargetVariables(runtimeStage, stage);
  syncTargetVariables(runtimeTarget, magnitudeTarget);

  const broadcastHat = Object.values(magnitudeTarget.blocks).find(
    (block) =>
      block.topLevel &&
      block.opcode === 'event_whenbroadcastreceived' &&
      block.fields?.BROADCAST_OPTION?.[0] === 'スタート'
  );
  if (!broadcastHat) throw new Error('Scratch スタート broadcast hat not found');

  let block = broadcastHat;
  while (block && block.opcode !== 'control_forever') {
    block = magnitudeTarget.blocks[block.next];
  }
  const foreverSubstackId = block && inputBlockId(block, 'SUBSTACK');
  if (!foreverSubstackId) {
    throw new Error('Scratch magnitude forever-loop body not found');
  }

  return {
    projectSha256,
    stage: runtimeStage,
    target: runtimeTarget,
    interpreter: new MagnitudeTargetInterpreter(thread, magnitudeTarget),
    foreverSubstackId,
  };
}

function readReplayCase(reportPath) {
  const absolutePath = path.resolve(reportPath);
  const report = JSON.parse(fs.readFileSync(absolutePath, 'utf8'));
  const estimate = report.finalEstimate;
  const diagnostics = estimate?.srevKaizouMagnitudeDiagnostics;
  if (!estimate || !diagnostics) {
    throw new Error(`Replay report has no srev magnitude diagnostics: ${reportPath}`);
  }
  const fallbackSnapshot = {
    observedAtUtc: null,
    latitude: Number(estimate.latitude),
    longitude: Number(estimate.longitude),
    inputIntensity: Number(
      diagnostics.srev_kaizou_magnitude_input_intensity
    ),
    dartMagnitude: Number(estimate.magnitude),
  };
  const trajectory = Array.isArray(report.srevKaizouMagnitudeTrajectory)
    ? report.srevKaizouMagnitudeTrajectory
    : [fallbackSnapshot];
  return {
    id: path.basename(report.captureDirectory || absolutePath),
    reportPath: absolutePath,
    truthMagnitude: Number(report.p2pTruth?.magnitude),
    snapshots: trajectory.map((snapshot) => ({
      id: path.basename(report.captureDirectory || absolutePath),
      observedAtUtc: snapshot.observedAtUtc ?? null,
      latitude: Number(snapshot.latitude),
      longitude: Number(snapshot.longitude),
      inputIntensity: Number(snapshot.inputIntensity),
      dartMagnitude: Number(snapshot.dartMagnitude),
      truthMagnitude: Number(report.p2pTruth?.magnitude),
    })),
  };
}

function runScratchMagnitude(input, runtime = loadScratchMagnitudeRuntime()) {
  const sourceElements = Array(10).fill(0);
  sourceElements[0] = 1;
  sourceElements[1] = input.longitude;
  sourceElements[2] = input.latitude;

  const detectionInfo = Array(20).fill(0);
  detectionInfo[5] = input.inputIntensity;

  const realtime = variableByName(
    runtime.stage,
    '4リアルタイム状況(最大震度など)'
  ).value;
  realtime[0] = input.inputIntensity;
  variableByName(runtime.stage, '4-4 検出id震源要素').value = sourceElements;
  variableByName(runtime.stage, '4-3 検出id別情報').value = detectionInfo;
  variableByName(runtime.stage, '4-6 推定まぐ').value = Array(100).fill('');
  variableByName(runtime.target, '揺れ検出震源達').value = Array(50).fill(0);

  runtime.interpreter.runStack(runtime.foreverSubstackId, new Map(), '');

  const sourceCache = variableByName(runtime.target, '揺れ検出震源達').value;
  const magnitudeList = variableByName(runtime.stage, '4-6 推定まぐ').value;
  return {
    id: input.id,
    observedAtUtc: input.observedAtUtc ?? null,
    projectSha256: runtime.projectSha256,
    execution: 'interpreted_original_project_json_blocks',
    sourceLatitude: input.latitude,
    sourceLongitude: input.longitude,
    inputIntensity: input.inputIntensity,
    scratchRoundedLongitude: sourceCache[0],
    scratchRoundedLatitude: sourceCache[1],
    scratchNearestStationDistanceKm: Number(sourceCache[4]),
    scratchMagnitude: Number(magnitudeList[0]),
    dartMagnitude: input.dartMagnitude,
    absoluteDifference: Math.abs(Number(magnitudeList[0]) - input.dartMagnitude),
    truthMagnitude: input.truthMagnitude,
  };
}

function main(argv) {
  if (argv.length === 0) {
    throw new Error(
      'Usage: node tools/run_srev_kaizou_magnitude.js <replay-report.json> [...]'
    );
  }
  const runtime = loadScratchMagnitudeRuntime();
  const results = argv.map(readReplayCase).map((replay) => {
    const trajectory = replay.snapshots.map((snapshot) =>
      runScratchMagnitude(snapshot, runtime)
    );
    if (trajectory.length === 0) {
      throw new Error(`Replay contains no supported magnitude frame: ${replay.id}`);
    }
    const peak = trajectory.reduce((best, current) =>
      current.scratchMagnitude > best.scratchMagnitude ? current : best
    );
    return {
      id: replay.id,
      truthMagnitude: replay.truthMagnitude,
      frameCount: trajectory.length,
      first: trajectory[0],
      peak,
      final: trajectory[trajectory.length - 1],
      maximumAbsoluteDartDifference: Math.max(
        ...trajectory.map((snapshot) => snapshot.absoluteDifference)
      ),
    };
  });
  process.stdout.write(`${JSON.stringify(results, null, 2)}\n`);
}

if (require.main === module) {
  main(process.argv.slice(2));
}

module.exports = {loadScratchMagnitudeRuntime, runScratchMagnitude};
