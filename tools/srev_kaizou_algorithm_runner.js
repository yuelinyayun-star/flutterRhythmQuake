'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const core = require('./kotoho7_receiver_compiled_core.js');
const receiver = require('./kotoho7_receiver_bridge_runner.js');
const {
  installSrevKaizouOverrides,
} = require('./srev_kaizou_scratch_overrides.js');

const ROOT = path.resolve(__dirname, '..');
const STATION_DB_DART = path.join(ROOT, 'lib', 'models', 'nied_station_db.dart');
const EPOCH_2000_MS = Date.UTC(2000, 0, 1);
const DEFAULT_RANDOM_SEED = 20260810;

function sha256File(filePath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex').toUpperCase();
}

function sha256Json(value) {
  return crypto.createHash('sha256')
    .update(JSON.stringify(value))
    .digest('hex')
    .toUpperCase();
}

function normalizeRandomSeed(value) {
  const number = Number(value ?? DEFAULT_RANDOM_SEED);
  if (!Number.isInteger(number) || number < 0 || number > 0xFFFFFFFF) {
    throw new Error(`Random seed must be an integer from 0 to 4294967295: ${value}`);
  }
  return number >>> 0;
}

function createDeterministicRandom(seed) {
  let state = seed >>> 0;
  let drawCount = 0;
  return {
    next() {
      drawCount += 1;
      state = (state + 0x6D2B79F5) >>> 0;
      let value = state;
      value = Math.imul(value ^ (value >>> 15), value | 1);
      value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
      return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
    },
    drawCount() {
      return drawCount;
    },
  };
}

function variableByName(thread, name) {
  return core.variableByName(thread.target, name) ||
    core.variableByName(thread.target.runtime.stage, name);
}

function listByName(thread, name) {
  const variable = variableByName(thread, name);
  if (!variable || !Array.isArray(variable.value)) {
    throw new Error(`Scratch list not found: ${name}`);
  }
  return variable.value;
}

function replaceListItem(list, oneBasedIndex, value) {
  if (oneBasedIndex >= 1 && oneBasedIndex <= list.length) {
    list[oneBasedIndex - 1] = value;
  }
}

function enableSourceEstimation(thread) {
  const settings = listByName(thread, '7システム設定');
  for (const index of [51, 52, 57, 62]) replaceListItem(settings, index, true);
}

function readLocalStations() {
  const text = fs.readFileSync(STATION_DB_DART, 'utf8');
  return [...text.matchAll(/\{\s*"code":\s*"([^"]+)",\s*"name":\s*"([^"]+)",\s*"lat":\s*([0-9.\-]+),\s*"lng":\s*([0-9.\-]+)/g)]
    .map((match) => ({
      code: match[1],
      name: match[2],
      lat: Number(match[3]),
      lng: Number(match[4]),
    }));
}

function stationCodeToTenIndex(thread) {
  const x = listByName(thread, 'd ten:x').map(Number);
  const y = listByName(thread, 'd ten:y').map(Number);
  const names = listByName(thread, 'd ten:名前');
  const byName = new Map();
  for (let index = 0; index < names.length; index += 1) {
    const row = {index: index + 1, name: names[index], lat: y[index], lng: x[index]};
    if (!byName.has(row.name)) byName.set(row.name, []);
    byName.get(row.name).push(row);
  }
  const distanceKm = (left, right) => {
    const meanLatitude = (left.lat + right.lat) * Math.PI / 360;
    return Math.hypot(
      (left.lng - right.lng) * Math.cos(meanLatitude) * 111,
      (left.lat - right.lat) * 111
    );
  };
  const mapping = new Map();
  const used = new Set();
  const rankedStations = readLocalStations()
    .map((station) => ({station, candidates: byName.get(station.name) || []}))
    .sort((left, right) => left.candidates.length - right.candidates.length);
  for (const {station, candidates} of rankedStations) {
    const best = candidates
      .filter((candidate) => !used.has(candidate.index))
      .map((candidate) => ({candidate, distance: distanceKm(station, candidate)}))
      .sort((left, right) => left.distance - right.distance)[0];
    if (!best || best.distance > 25) continue;
    mapping.set(station.code, best.candidate.index);
    used.add(best.candidate.index);
  }
  mapping.scratchTenLength = names.length;
  mapping.localStationDbLength = rankedStations.length;
  mapping.mappedCount = mapping.size;
  return mapping;
}

function groupObservations(payload) {
  const rawObservations = Array.isArray(payload) ? payload : payload.observations;
  if (!Array.isArray(rawObservations)) {
    throw new Error('Expected an observations array or object with observations');
  }
  const groups = new Map();
  for (const raw of rawObservations) {
    if (!raw || raw.observedAtUtc == null) continue;
    const observedAtUtc = new Date(raw.observedAtUtc).toISOString();
    if (!groups.has(observedAtUtc)) groups.set(observedAtUtc, []);
    groups.get(observedAtUtc).push({
      stationCode: raw.stationCode,
      observedAtUtc,
      gifDecodedShindo: raw.gifDecodedShindo,
    });
  }
  return [...groups.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([observedAtUtc, observations]) => ({observedAtUtc, observations}));
}

function percentile(values, probability) {
  if (values.length === 0) return null;
  const sorted = [...values].sort((left, right) => left - right);
  const index = (sorted.length - 1) * probability;
  const lower = Math.floor(index);
  const upper = Math.ceil(index);
  if (lower === upper) return sorted[lower];
  return sorted[lower] + (sorted[upper] - sorted[lower]) * (index - lower);
}

function scratchFiniteNumber(value) {
  if (value == null || value === '') return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function sourceDiagnostics(state) {
  const sources = state.sources.map((source, index) => {
    const detection = state.activeIds[index] || null;
    const stations = state.estimatedPhaseStations.filter((station) => {
      const rawId = Number(station.raw?.[2]);
      // ten:推定用 stores the one-based detection-list position, while
      // 4-3 検出id別情報 stores the persistent detection id (often a station
      // index). Source elements use the same one-based list position.
      return !Number.isFinite(rawId) || rawId === index + 1;
    }).map((station) => {
      const observed = scratchFiniteNumber(station.primaryTime);
      const theoretical = scratchFiniteNumber(
        station.phase === 's' ? station.sArrivalTime : station.pArrivalTime
      );
      const residual = observed != null && theoretical != null
        ? observed - theoretical
        : null;
      return {
        stationCode: station.code,
        stationName: station.name,
        latitude: station.lat,
        longitude: station.lng,
        phase: station.phase,
        weight: null,
        observedArrivalSecondsSince2000: observed,
        theoreticalArrivalSecondsSince2000: theoretical,
        residualSeconds: residual,
        distanceKm: scratchFiniteNumber(station.distanceKm),
        permissionState: station.state,
        raw: station.raw,
      };
    });
    const residuals = stations
      .map((station) => station.residualSeconds)
      .filter((value) => value != null && Number.isFinite(value));
    const absoluteResiduals = residuals.map(Math.abs);
    const waveCounts = {P: 0, S: 0, O: 0, L: 0};
    for (const station of stations) {
      const phase = String(station.phase || '').toUpperCase();
      const key = Object.hasOwn(waveCounts, phase) ? phase : 'O';
      waveCounts[key] += 1;
    }
    const score = scratchFiniteNumber(detection?.bestError);
    const currentError = scratchFiniteNumber(detection?.error);
    const latitude = scratchFiniteNumber(source.lat);
    const longitude = scratchFiniteNumber(source.lon);
    const depthKm = scratchFiniteNumber(source.depthKm);
    const originTimeSecondsSince2000 = scratchFiniteNumber(source.originTime);
    const effectiveStationCount = waveCounts.P + waveCounts.S;
    const valid = latitude != null &&
      longitude != null &&
      depthKm != null &&
      originTimeSecondsSince2000 != null &&
      effectiveStationCount > 0 &&
      score != null &&
      currentError != null;
    return {
      detectionId: detection?.id ?? index + 1,
      valid,
      rejectionReason: valid ? null : 'missing_finite_source_support_or_error',
      latitude,
      longitude,
      depthKm,
      originTimeSecondsSince2000,
      originTimeEpochMs: originTimeSecondsSince2000 != null
        ? EPOCH_2000_MS + originTimeSecondsSince2000 * 1000
        : null,
      magnitude: null,
      magnitudeStatus: 'not_emitted_by_srev_hyp_source_cache',
      pStationCount: waveCounts.P,
      sStationCount: waveCounts.S,
      otherStationCount: waveCounts.O + waveCounts.L,
      waveCounts,
      candidateStationCount: scratchFiniteNumber(state.permittedStations),
      assignedStationCount: scratchFiniteNumber(detection?.appliedCount),
      effectiveStationCount,
      effectiveStationCountStatus:
        'phase_assigned_p_s_count_weight_not_exposed',
      unarrivedStationCount: stations.filter(
        (station) => station.observedArrivalSecondsSince2000 == null
      ).length,
      score: score ?? currentError,
      rmseSeconds: residuals.length === 0
        ? null
        : Math.sqrt(residuals.reduce((sum, value) => sum + value * value, 0) / residuals.length),
      meanResidualSeconds: residuals.length === 0
        ? null
        : residuals.reduce((sum, value) => sum + value, 0) / residuals.length,
      p90AbsoluteResidualSeconds: percentile(absoluteResiduals, 0.9),
      errorLevel: currentError,
      weightSum: null,
      weightSumStatus: 'not_exposed_by_srev_scratch_output',
      productionPublishability:
        'not_evaluated_because_positive_weight_cannot_be_verified',
      searchStage: state.scratch?.hyp?.phase ?? null,
      searchIterationCount: scratchFiniteNumber(state.scratch?.hyp?.calcCount),
      candidateEvaluationCount: null,
      rejectedCandidateCount: null,
      stations,
      rawDetectionState: detection,
      rawSourceState: source,
    };
  });
  return sources;
}

function createSession(projectPath) {
  const thread = core.makeThread();
  const installed = installSrevKaizouOverrides(thread, projectPath);
  thread.__srevAlwaysTimerSeconds = 0;
  core.callProcedure(thread, 'Wリセット %b', [true]);
  enableSourceEstimation(thread);
  return {
    thread,
    installed,
    mapping: stationCodeToTenIndex(thread),
    firstFrameMs: null,
  };
}

function run(
  projectPath,
  inputPath,
  {limitFrames = null, traceStations = false, randomSeed = DEFAULT_RANDOM_SEED} = {}
) {
  const normalizedRandomSeed = normalizeRandomSeed(randomSeed);
  const deterministicRandom = createDeterministicRandom(normalizedRandomSeed);
  const originalRandom = Math.random;
  Math.random = deterministicRandom.next;
  try {
    const payload = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
    const frames = groupObservations(payload);
    const session = createSession(projectPath);
    const count = limitFrames == null ? frames.length : Math.min(frames.length, limitFrames);
    const outputFrames = [];
    let peakDetectionIdCount = 0;
    let peakEstimatedStationCount = 0;
    for (let index = 0; index < count; index += 1) {
      const frame = frames[index];
      const frameMs = Date.parse(frame.observedAtUtc);
      session.firstFrameMs ??= frameMs;
      session.thread.__srevAlwaysTimerSeconds = Math.max(
        0,
        (frameMs - session.firstFrameMs) / 1000
      );
      const stopwatchStart = process.hrtime.bigint();
      const state = receiver.runFrame(
        session.thread,
        frame.observations,
        session.mapping,
        {runHyp: true, traceStations}
      );
      const runtimeMicros = Number((process.hrtime.bigint() - stopwatchStart) / 1000n);
      const sources = sourceDiagnostics(state);
      peakDetectionIdCount = Math.max(peakDetectionIdCount, state.detectionIdCount);
      peakEstimatedStationCount = Math.max(
        peakEstimatedStationCount,
        state.estimatedStations
      );
      outputFrames.push({
        frameIndex: index,
        observedAtUtc: frame.observedAtUtc,
        inputStationCount: frame.observations.length,
        appliedStationCount: state.applied,
        skippedStationCount: state.skipped,
        runtimeMicros,
        detectionIdCount: state.detectionIdCount,
        permittedStationCount: state.permittedStations,
        estimatedStationCount: state.estimatedStations,
        sources,
        ...(traceStations ? {stationTrace: state.stationTrace} : {}),
      });
    }
    const deterministicFrames = outputFrames.map(({runtimeMicros, ...frame}) => frame);
    return {
    schemaVersion: 1,
    method: 'srev_kaizou_scratch_hyp_v1',
    diagnosticOnly: true,
    writesProductionState: false,
    provenance: {
      upstream: 't0729/srev-kaizou',
      projectPath: path.resolve(projectPath),
      projectSha256: sha256File(projectPath),
      scratchTarget: '受信と検出',
      executionModel:
        'compiled_structurally_matched_hyp_core_plus_exact_srev_changed_procedure_overrides',
      algorithmBodyModified: false,
      overriddenProcedures: session.installed.overriddenProcedures,
      random: {
        deterministic: true,
        generator: 'mulberry32',
        seed: normalizedRandomSeed,
        drawCount: deterministicRandom.drawCount(),
      },
    },
    input: {
      path: path.resolve(inputPath),
      sha256: sha256File(inputPath),
      frameCount: frames.length,
      processedFrameCount: count,
      rawInputUnmodified: true,
      scratchStationCount: session.mapping.scratchTenLength,
      localStationDbCount: session.mapping.localStationDbLength,
      mappedStationCount: session.mapping.mappedCount,
    },
    summary: {
      peakDetectionIdCount,
      peakEstimatedStationCount,
      validSourceFrameCount: outputFrames.filter(
        (frame) => frame.sources.some((source) => source.valid)
      ).length,
      deterministicTrajectorySha256: sha256Json(deterministicFrames),
    },
    frames: outputFrames,
    };
  } finally {
    Math.random = originalRandom;
  }
}

function parseArgs(argv) {
  const result = {_: []};
  const args = [...argv];
  while (args.length > 0) {
    const arg = args.shift();
    if (!arg.startsWith('--')) {
      result._.push(arg);
      continue;
    }
    const key = arg.slice(2);
    if (args[0] == null || args[0].startsWith('--')) result[key] = true;
    else result[key] = args.shift();
  }
  return result;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const projectPath = args.project;
  const inputPath = args.input;
  if (!projectPath || !inputPath) {
    throw new Error(
      'Usage: node tools/srev_kaizou_algorithm_runner.js --project <project.json> --input <observations.json> [--output report.json] [--limit-frames N] [--random-seed N] [--trace-stations]'
    );
  }
  const report = run(projectPath, inputPath, {
    limitFrames: args['limit-frames'] == null ? null : Number(args['limit-frames']),
    traceStations: Boolean(args['trace-stations']),
    randomSeed: args['random-seed'] ?? DEFAULT_RANDOM_SEED,
  });
  const json = `${JSON.stringify(report, null, 2)}\n`;
  if (args.output) {
    const outputPath = path.resolve(args.output);
    fs.mkdirSync(path.dirname(outputPath), {recursive: true});
    fs.writeFileSync(outputPath, json, 'utf8');
  }
  if (!args.quiet) process.stdout.write(json);
}

module.exports = {
  DEFAULT_RANDOM_SEED,
  createDeterministicRandom,
  createSession,
  groupObservations,
  normalizeRandomSeed,
  run,
  sourceDiagnostics,
};

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${error.stack || error}\n`);
    process.exitCode = 1;
  }
}
