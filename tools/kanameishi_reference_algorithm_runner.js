'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const NIED_SOURCE = path.join('src', 'classes', 'NiedHypoInf.js');
const UTILS_SOURCE = path.join('src', 'utils', 'Utils.js');
const TRAVEL_TIMES_SOURCE = path.join('src', 'utils', 'TravelTimes.js');

function sha256File(filePath) {
  return crypto
    .createHash('sha256')
    .update(fs.readFileSync(filePath))
    .digest('hex')
    .toUpperCase();
}

function dataModule(source) {
  return `data:text/javascript;base64,${Buffer.from(source, 'utf8').toString('base64')}`;
}

function sourceSlice(source, startMarker, endMarker) {
  const start = source.indexOf(startMarker);
  const end = source.indexOf(endMarker, start + startMarker.length);
  if (start < 0 || end < 0 || end <= start) {
    throw new Error(`Unable to extract upstream helper: ${startMarker}`);
  }
  return source.slice(start, end).trim();
}

function buildUtilsModule(utilsSource) {
  return [
    sourceSlice(
      utilsSource,
      'const EARTH_RADIUS_KM = 6371.0088;',
      'export const calcBearingDeg'
    ),
    sourceSlice(
      utilsSource,
      'export const calcReachTime',
      'export const extractNumbers'
    ),
    sourceSlice(
      utilsSource,
      'export const exactRound',
      'export const getCoordByDistanceBearing'
    ),
  ].join('\n\n');
}

async function loadFindNiedHypocenter(kanameishiRoot) {
  const root = path.resolve(kanameishiRoot);
  const niedPath = path.join(root, NIED_SOURCE);
  const utilsPath = path.join(root, UTILS_SOURCE);
  const travelTimesPath = path.join(root, TRAVEL_TIMES_SOURCE);
  for (const filePath of [niedPath, utilsPath, travelTimesPath]) {
    if (!fs.existsSync(filePath)) {
      throw new Error(`Required kanameishi source file not found: ${filePath}`);
    }
  }

  const utilsSource = fs.readFileSync(utilsPath, 'utf8');
  const travelTimesSource = fs.readFileSync(travelTimesPath, 'utf8');
  let niedSource = fs.readFileSync(niedPath, 'utf8');
  const utilsSpecifier = dataModule(buildUtilsModule(utilsSource));
  const travelTimesSpecifier = dataModule(travelTimesSource);
  const utilsImport = "from '@/utils/Utils'";
  const travelTimesImport = "from '@/utils/TravelTimes'";
  if (!niedSource.includes(utilsImport) || !niedSource.includes(travelTimesImport)) {
    throw new Error('Unexpected NiedHypoInf.js import contract');
  }
  niedSource = niedSource
    .replace(utilsImport, `from '${utilsSpecifier}'`)
    .replace(travelTimesImport, `from '${travelTimesSpecifier}'`);
  const module = await import(dataModule(niedSource));
  if (typeof module.FindNiedHypocenter !== 'function') {
    throw new Error('FindNiedHypocenter export was not loaded');
  }
  return {
    FindNiedHypocenter: module.FindNiedHypocenter,
    provenance: {
      upstream: 'kanameishi-dev',
      root,
      algorithmSourcePath: niedPath,
      algorithmSourceSha256: sha256File(niedPath),
      utilitiesSourcePath: utilsPath,
      utilitiesSourceSha256: sha256File(utilsPath),
      travelTimesSourcePath: travelTimesPath,
      travelTimesSourceSha256: sha256File(travelTimesPath),
      executionModel:
        'original_es_module_with_import_specifiers_redirected_to_exact_local_dependencies',
      algorithmBodyModified: false,
    },
  };
}

function finiteNumber(value) {
  if (value == null || value === '' || typeof value === 'boolean') return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function list(value) {
  return Array.isArray(value) ? value : [];
}

function map(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
}

function instrumentFinder(finder) {
  const counters = {
    searchInvocationCount: 0,
    candidateEvaluationCount: 0,
    rejectedCandidateCount: 0,
  };
  const wrap = (name, counterName, inspectResult = false) => {
    if (typeof finder[name] !== 'function') return;
    const original = finder[name].bind(finder);
    finder[name] = (...args) => {
      counters[counterName] += 1;
      const result = original(...args);
      if (inspectResult && !Number.isFinite(Number(result?.score))) {
        counters.rejectedCandidateCount += 1;
      }
      return result;
    };
  };
  wrap('findBestHypocenter', 'searchInvocationCount');
  wrap('calcScenarioLikelihood', 'candidateEvaluationCount', true);
  wrap('calcPreviousWaveScenarioLikelihood', 'candidateEvaluationCount', true);
  return counters;
}

function resetCounters(counters) {
  for (const key of Object.keys(counters)) counters[key] = 0;
}

function serializeStation(result) {
  const station = map(result?.station);
  return {
    stationId: station.id ?? null,
    latitude: finiteNumber(station.latLng?.[0]),
    longitude: finiteNumber(station.latLng?.[1]),
    triggerStamp: finiteNumber(station.triggerStamp),
    updateStamp: finiteNumber(station.updateStamp),
    wave: result?.wave ?? null,
    weight: finiteNumber(result?.weight),
    originStamp: finiteNumber(result?.originStamp),
    reachTimeSeconds: finiteNumber(result?.reachTime),
    distanceKm: finiteNumber(result?.distance),
    maxAscend: finiteNumber(result?.maxAscend),
    maxLevel: finiteNumber(station.maxLevel),
  };
}

function serializeSource(result) {
  const stations = list(result?.stations).map(serializeStation);
  const waveCounts = {P: 0, S: 0, O: 0, L: 0};
  for (const station of stations) {
    const wave = Object.hasOwn(waveCounts, station.wave) ? station.wave : 'O';
    waveCounts[wave] += 1;
  }
  const weightSum = stations.reduce(
    (sum, station) => sum + (station.weight == null ? 0 : station.weight),
    0
  );
  const hypocenter = map(result?.hypocenter);
  const latitude = finiteNumber(hypocenter.lat);
  const longitude = finiteNumber(hypocenter.lng);
  const depthKm = finiteNumber(hypocenter.depth);
  const score = finiteNumber(result?.score);
  const rmseSeconds = finiteNumber(result?.rmse);
  const effectiveStationCount = finiteNumber(result?.effectiveStationCount);
  const valid = latitude != null &&
    longitude != null &&
    depthKm != null &&
    score != null &&
    rmseSeconds != null &&
    effectiveStationCount > 0 &&
    weightSum > 0;
  return {
    sourceId: result?.clusterId ?? null,
    valid,
    rejectionReason: valid ? null : 'missing_finite_source_support_or_positive_weight',
    latitude,
    longitude,
    depthKm,
    originTimeEpochMs: finiteNumber(result?.originStamp),
    score,
    rmseSeconds,
    errorLevel: score,
    candidateStationCount: list(result?.cluster).length,
    assignedStationCount: stations.length,
    effectiveStationCount,
    weightSum,
    waveCounts,
    inactivePenalty: finiteNumber(result?.inactivePenalty),
    inactivePenaltyWeight: finiteNumber(result?.inactivePenaltyWeight),
    waveCountPenaltyMultiplier: finiteNumber(result?.waveCountPenaltyMultiplier),
    qualityScore: finiteNumber(result?.qualityScore),
    qualityRank: result?.qualityRank ?? null,
    scenario: result?.scenario ?? null,
    firstWave: result?.firstWave ?? null,
    lastWave: result?.lastWave ?? null,
    filterStageLevel: finiteNumber(result?.filterStageLevel),
    clusterUpdates: finiteNumber(result?.updates),
    reportNumber: finiteNumber(result?.reportNum),
    stable: result?.stable === true,
    stations,
  };
}

function extractCases(payload) {
  if (Array.isArray(payload?.cases)) return payload.cases;
  if (Array.isArray(payload?.frames)) return [payload];
  throw new Error('Expected current capture report with cases or a single case with frames');
}

async function run(kanameishiRoot, inputPath) {
  const loaded = await loadFindNiedHypocenter(kanameishiRoot);
  const payload = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
  const cases = [];
  for (const inputCase of extractCases(payload)) {
    let finder = null;
    let counters = null;
    const frames = [];
    for (let frameIndex = 0; frameIndex < list(inputCase.frames).length; frameIndex += 1) {
      const frame = inputCase.frames[frameIndex];
      const metadata = map(frame?.metadata);
      const newActiveStations = list(metadata.nied_hypocenter_new_active_stations);
      const activeStations = list(metadata.nied_hypocenter_active_stations);
      const inactiveStations = list(metadata.nied_hypocenter_inactive_stations);
      const adjStationIds = map(metadata.nied_hypocenter_adj_station_ids);
      if (!finder && Object.keys(metadata).length > 0) {
        finder = new loaded.FindNiedHypocenter(inactiveStations, adjStationIds);
        counters = instrumentFinder(finder);
      }
      let rawSources = [];
      let runtimeMicros = 0;
      if (finder) {
        resetCounters(counters);
        const started = process.hrtime.bigint();
        rawSources = finder.update(newActiveStations, inactiveStations, activeStations);
        runtimeMicros = Number((process.hrtime.bigint() - started) / 1000n);
      }
      const sources = list(rawSources).map(serializeSource);
      frames.push({
        frameIndex,
        observedAt: frame?.observedAtJst ?? null,
        input: {
          newActiveStationCount: newActiveStations.length,
          activeStationCount: activeStations.length,
          inactiveStationCount: inactiveStations.length,
          adjacencyStationCount: Object.keys(adjStationIds).length,
        },
        runtimeMicros,
        searchInvocationCount: counters?.searchInvocationCount ?? 0,
        candidateEvaluationCount: counters?.candidateEvaluationCount ?? 0,
        rejectedCandidateCount: counters?.rejectedCandidateCount ?? 0,
        sources,
        rejectionReason: sources.some((source) => source.valid)
          ? null
          : (finder ? 'no_finite_supported_result' : 'algorithm_not_started_without_active_input'),
      });
    }
    cases.push({
      id: inputCase.id ?? null,
      label: inputCase.label ?? null,
      truth: inputCase.truth ?? null,
      frames,
    });
  }
  return {
    schemaVersion: 1,
    method: 'kanameishi_find_nied_hypocenter_original_js_v1',
    diagnosticOnly: true,
    writesProductionState: false,
    provenance: loaded.provenance,
    input: {
      path: path.resolve(inputPath),
      sha256: sha256File(inputPath),
      sourceContract: 'nied_hypocenter_metadata_from_same_dart_decoded_frames',
    },
    cases,
  };
}

function parseArgs(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index];
    if (!key.startsWith('--')) throw new Error(`Unexpected argument: ${key}`);
    const value = argv[index + 1];
    if (value == null || value.startsWith('--')) throw new Error(`Missing value for ${key}`);
    result[key.slice(2)] = value;
    index += 1;
  }
  return result;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args['kanameishi-root'] || !args.input) {
    throw new Error(
      'Usage: node tools/kanameishi_reference_algorithm_runner.js ' +
      '--kanameishi-root <kanameishi-dev> --input <current-report.json> ' +
      '[--output <report.json>]'
    );
  }
  const report = await run(args['kanameishi-root'], args.input);
  const json = `${JSON.stringify(report, null, 2)}\n`;
  if (args.output) {
    const outputPath = path.resolve(args.output);
    fs.mkdirSync(path.dirname(outputPath), {recursive: true});
    fs.writeFileSync(outputPath, json, 'utf8');
  } else {
    process.stdout.write(json);
  }
}

module.exports = {loadFindNiedHypocenter, run, serializeSource};

if (require.main === module) {
  main().catch((error) => {
    process.stderr.write(`${error.stack || error}\n`);
    process.exitCode = 1;
  });
}
