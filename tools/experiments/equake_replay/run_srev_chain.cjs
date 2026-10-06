'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const core = require('../../kotoho7_receiver_compiled_core.js');
const receiver = require('../../kotoho7_receiver_bridge_runner.js');
const srev = require('../../srev_kaizou_algorithm_runner.js');
const {loadScratchMagnitudeRuntime} = require('../../run_srev_kaizou_magnitude.js');

const [input, output, seedArgument] = process.argv.slice(2);
if (!input || !output) throw Error('Usage: run_srev_chain.cjs observations.json new-report.json [seed]');
if (fs.existsSync(output)) throw Error('Report already exists');
const project = path.resolve('.dart_tool/srev_kaizou_diagnostic/upstream/srev-s/assets/project.json');
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const raw = fs.readFileSync(input);
const inputHash = sha(raw);
const payload = JSON.parse(raw.toString('utf8'));
const groups = srev.groupObservations(payload);
const randomSeed = srev.normalizeRandomSeed(seedArgument ?? srev.DEFAULT_RANDOM_SEED);
const random = srev.createDeterministicRandom(randomSeed);
const previousRandom = Math.random;
Math.random = random.next;
const variable = (target, name) => {
  const v = core.variableByName(target, name);
  if (!v) throw Error(`Missing original variable: ${name}`);
  return v;
};
try {
  const session = srev.createSession(project);
  const traceStations = process.env.SREV_STATION_TRACE === '1';
  const stationTraces = [];
  let currentObservations = new Map();
  let permissionTrace = null;
  const stage = session.thread.target.runtime.stage;
  const stationTable = [...session.mapping.entries()].map(([code, index]) => ({
    code, index, name: variable(stage, 'd ten:名前').value[index - 1],
    latitude: variable(stage, 'd ten:y').value[index - 1],
    longitude: variable(stage, 'd ten:x').value[index - 1],
  }));
  const calledProcedures = {};
  for (const [name, original] of Object.entries(session.thread.procedures)) {
    session.thread.procedures[name] = (...args) => {
      calledProcedures[name] = (calledProcedures[name] ?? 0) + 1;
      const result = original(...args);
      if (traceStations && name === 'W検出許可震度算出') {
        const permission = variable(stage, 'ten c:揺れ検出許可').value;
        const permittedIntensity = variable(stage, 'ten c:検出許可済み震度').value;
        const intensity = variable(stage, 'ten:震度100').value;
        const levels = variable(stage, 'ten:震度').value;
        const realtimeState = variable(stage, '4リアルタイム状況(最大震度など)').value;
        permissionTrace = {
          realtimeIntensity: realtimeState[0],
          maximumStationIndex: realtimeState[2],
          stations: stationTable.filter(s => currentObservations.has(s.code) || Number(permission[s.index - 1]) >= 4)
            .map(s => ({code: s.code, index: s.index, permission: permission[s.index - 1],
              permittedIntensity: permittedIntensity[s.index - 1],
              intensity: intensity[s.index - 1], level: levels[s.index - 1],
              observedRawIntensity: currentObservations.get(s.code) ?? null})),
        };
      }
      return result;
    };
  }
  const mag = loadScratchMagnitudeRuntime();
  // Share the receiver's own stage, not an injected source or our estimate.
  mag.stage = stage;
  mag.target.runtime.stage = stage;
  const frames = [];
  const start = Date.parse(groups[0].observedAtUtc);
  for (const group of groups) {
    currentObservations = new Map(group.observations.map(s => [s.stationCode, s.gifDecodedShindo]));
    permissionTrace = null;
    session.thread.__srevAlwaysTimerSeconds = (Date.parse(group.observedAtUtc) - start) / 1000;
    const state = receiver.runFrame(session.thread, group.observations, session.mapping, {runHyp: true});
    // Retain the original magnitude sprite's source-distance cache across frames.
    mag.interpreter.statementCount = 0;
    mag.interpreter.runStack(mag.foreverSubstackId, new Map(), '');
    const magnitudes = variable(stage, '4-6 推定まぐ').value;
    const realtime = variable(stage, '4リアルタイム状況(最大震度など)').value;
    const detection = variable(stage, '4-3 検出id別情報').value;
    const sourceElements = variable(stage, '4-4 検出id震源要素').value;
    if (detection.length % 20 !== 0 || sourceElements.length % 10 !== 0 ||
        detection.length / 20 !== sourceElements.length / 10 ||
        state.sources.length !== sourceElements.length / 10 ||
        magnitudes.length < state.sources.length) {
      throw Error(`Original source/magnitude slot layout mismatch at ${group.observedAtUtc}`);
    }
    const sources = srev.sourceDiagnostics(state).map((source, index) => {
      const rawMagnitude = magnitudes[index];
      const {stations, ...summary} = source;
      return {...summary, magnitude: rawMagnitude === '' || rawMagnitude == null ? null : Number(rawMagnitude),
        magnitudeStatus: 'original_magnitude_blocks_after_srev_receiver_hyp',
        rawMagnitude, detectionIntensity: detection[index * 20 + 5]};
    });
    frames.push({observedAtUtc: group.observedAtUtc, inputStationCount: group.observations.length,
      applied: state.applied, skipped: state.skipped, detectionIdCount: state.detectionIdCount,
      permittedStationCount: state.permittedStations, realtimeIntensity: realtime[0], sources});
    if (traceStations) {
      if (!permissionTrace) throw Error('Permission procedure was not observed');
      stationTraces.push({observedAtUtc: group.observedAtUtc, ...permissionTrace});
    }
  }
  if (sha(fs.readFileSync(input)) !== inputHash) throw Error('Observations changed during run');
  const emitted = frames.flatMap(f => f.sources.filter(s => s.valid && Number.isFinite(s.magnitude))
    .map(s => ({observedAtUtc: f.observedAtUtc, ...s})));
  const report = {
    schemaVersion: 1, diagnosticOnly: true, productionChanged: false, fullBrowserReplay: false,
    method: 'same_gif_decoded_observations_to_srev_receiver_hyp_and_original_magnitude_blocks',
    limits: [
      'Existing GIF decoder and station-code-to-Scratch-table mapping are used.',
      'Bridge chooses nearest 30-level index; no synthetic cloud packet or altered raw GIF is supplied.',
      'Headless once-per-input-frame scheduling is not a browser VM timing equivalence claim.',
      'Source-estimation settings 51, 52, 57, 62 are enabled by the existing diagnostic session.',
      'Original project magnitude sprite blocks run on receiver stage; no external location or magnitude injected.',
      'EQ output is not catalog truth.'
    ],
    projectSha256: sha(fs.readFileSync(project)), inputSha256: inputHash,
    bridgeSha256: sha(fs.readFileSync(require.resolve('../../kotoho7_receiver_bridge_runner.js'))),
    levelMapping: 'nearest_in_first_30_intensity_values_only',
    random: {seed: randomSeed, draws: random.drawCount()},
    enabledSystemSettingPositions: [51, 52, 57, 62],
    frameProcedureCallCounts: calledProcedures,
    mapping: {local: session.mapping.localStationDbLength, scratch: session.mapping.scratchTenLength,
      mapped: session.mapping.mappedCount},
    summary: {frames: frames.length, emittedSourceFrames: emitted.length,
      first: emitted[0] ?? null, last: emitted.at(-1) ?? null,
      peak: emitted.reduce((a, b) => !a || b.magnitude > a.magnitude ? b : a, null)},
    trajectorySha256: sha(Buffer.from(JSON.stringify(frames))), frames,
    ...(traceStations ? {stationTable, stationTraces} : {}),
  };
  fs.mkdirSync(path.dirname(output), {recursive: true});
  fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n', {flag: 'wx'});
  console.log(JSON.stringify({output, mapping: report.mapping, summary: report.summary}, null, 2));
} finally {
  Math.random = previousRandom;
}
