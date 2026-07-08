// UTF-8 diagnostic runner for the extracted upstream kotoho7/TurboWarp receiver logic.
// This file intentionally lives under .dart_tool: it does not modify production Dart code.
// It runs upstream JS procedures for ten / detection-id / 4-3 / 4-4 / HYP state.
'use strict';

const fs = require('fs');
const path = require('path');
const core = require('./kotoho7_receiver_compiled_core.js');

const ROOT = path.resolve(__dirname, '..');
const STATION_DB_DART = path.join(ROOT, 'lib', 'models', 'nied_station_db.dart');
const SCAN_POSITIONS_DART = path.join(ROOT, 'lib', 'models', 'nied_scan_positions.dart');
const EPOCH_2000_MS = Date.UTC(2000, 0, 1);

function secondsSince2000(date) {
  return (date.getTime() - EPOCH_2000_MS) / 1000;
}

function readStationCodeToTenIndex() {
  const text = fs.readFileSync(STATION_DB_DART, 'utf8');
  const stations = [...text.matchAll(/\{\s*"code":\s*"([^"]+)",\s*"name":\s*"([^"]+)",\s*"lat":\s*([0-9.\-]+),\s*"lng":\s*([0-9.\-]+)/g)]
    .map(m => ({ code: m[1], name: m[2], lat: Number(m[3]), lng: Number(m[4]) }));
  const scratchX = core.SNAPSHOT.stage.variables['K=dB~/Qs0QP8?S-nu[mN'].value.map(Number);
  const scratchY = core.SNAPSHOT.stage.variables['o}-u@H4`+v8X:~`A_r6%'].value.map(Number);
  const scratchName = core.SNAPSHOT.stage.variables['5F%|f/{h*d~4KS[%l+kq'].value;
  const byName = new Map();
  for (let index = 0; index < scratchName.length; index++) {
    const entry = {
      index: index + 1,
      name: scratchName[index],
      lat: scratchY[index],
      lng: scratchX[index],
    };
    if (!byName.has(entry.name)) byName.set(entry.name, []);
    byName.get(entry.name).push(entry);
  }
  const distanceKm = (a, b) => {
    const meanLat = ((a.lat + b.lat) / 2) * Math.PI / 180;
    const dx = (a.lng - b.lng) * Math.cos(meanLat) * 111;
    const dy = (a.lat - b.lat) * 111;
    return Math.hypot(dx, dy);
  };
  const map = new Map();
  const used = new Set();
  const sortedStations = stations
    .map(station => ({ station, candidates: byName.get(station.name) || [] }))
    .sort((a, b) => a.candidates.length - b.candidates.length);
  for (const { station, candidates } of sortedStations) {
    if (candidates.length === 0) continue;
    const ranked = candidates
      .filter(candidate => !used.has(candidate.index))
      .map(candidate => ({ candidate, distance: distanceKm(station, candidate) }))
      .sort((a, b) => a.distance - b.distance);
    const best = ranked[0];
    if (!best || best.distance > 25) continue;
    map.set(station.code, best.candidate.index);
    used.add(best.candidate.index);
  }
  map.scratchTenLength = scratchName.length;
  map.localStationDbLength = stations.length;
  map.mappedCount = map.size;
  return map;
}

function readScratchStationRows(stationCodeToTenIndex = null) {
  const scratchX = core.SNAPSHOT.stage.variables['K=dB~/Qs0QP8?S-nu[mN'].value.map(Number);
  const scratchY = core.SNAPSHOT.stage.variables['o}-u@H4`+v8X:~`A_r6%'].value.map(Number);
  const scratchName = core.SNAPSHOT.stage.variables['5F%|f/{h*d~4KS[%l+kq'].value;
  const codeByTenIndex = new Map();
  if (stationCodeToTenIndex) {
    for (const [code, index] of stationCodeToTenIndex.entries()) {
      codeByTenIndex.set(index, code);
    }
  }
  return scratchName.map((name, zeroIndex) => ({
    tenIndex: zeroIndex + 1,
    code: codeByTenIndex.get(zeroIndex + 1) || null,
    name,
    lat: scratchY[zeroIndex],
    lng: scratchX[zeroIndex],
  }));
}

function readScanPositionCodes() {
  const text = fs.readFileSync(SCAN_POSITIONS_DART, 'utf8');
  return new Set([...text.matchAll(/"([A-Z0-9]+)":\s*NiedScanPoint/g)].map(m => m[1]));
}

function variable(target, name) {
  const value = core.variableByName(target, name);
  if (!value) throw new Error(`Scratch variable/list not found: ${name}`);
  return value;
}

function stageVariable(thread, name) {
  return variable(thread.target.runtime.stage, name);
}

function receiverVariable(thread, name) {
  return variable(thread.target, name);
}

function listValue(thread, name) {
  const v = core.variableByName(thread.target.runtime.stage, name) || core.variableByName(thread.target, name);
  if (!v) throw new Error(`Scratch list not found: ${name}`);
  return v.value;
}

function setAnyVariableByName(thread, name, value) {
  const v = core.variableByName(thread.target.runtime.stage, name) || core.variableByName(thread.target, name);
  if (!v) throw new Error(`Scratch variable/list not found: ${name}`);
  v.value = value;
}

function replaceScratchListItem(list, oneBasedIndex, value) {
  if (oneBasedIndex < 1 || oneBasedIndex > list.value.length) return;
  list.value[oneBasedIndex - 1] = value;
}

function enableSourceEstimationFlags(thread) {
  const settings = stageVariable(thread, '7システム設定');
  // Keep upstream values by default; these are the upstream switches that gate source/detection code paths.
  // 51: 円検出/HYP related display calculation
  // 52,57: P/S circle radius updates in 円検出の毎処理
  // 62: 揺れ検出許可 / detection-id pipeline
  for (const index of [51, 52, 57, 62]) {
    replaceScratchListItem(settings, index, true);
  }
}

function initializeUpstreamThread({ enableSource = true } = {}) {
  const thread = core.makeThread();
  core.callProcedure(thread, 'Wリセット %b', [true]);
  if (enableSource) enableSourceEstimationFlags(thread);
  return thread;
}

function extractCloudValuesFromSnapshot(snapshot) {
  if (snapshot?.best?.values) return snapshot.best.values;
  if (snapshot?.values) return snapshot.values;
  return snapshot;
}

function summarizeCloudState(thread) {
  const latest = listValue(thread, '#r:最新クラウド変数');
  const updated = listValue(thread, '#r:更新済み');
  const valueSummary = {};
  for (let index = 1; index <= latest.length; index++) {
    const value = String(latest[index - 1] ?? '');
    valueSummary[index] = {
      length: value.length,
      first80: value.slice(0, 80),
      last80: value.slice(-80),
      updated: updated[index - 1] ?? '',
      updateKey: updated[index + 9] ?? '',
    };
  }
  const rt = String(latest[2] ?? '');
  return {
    latestCloudVariables: valueSummary,
    rtShindo: {
      length: rt.length,
      oldFormat2040: rt.length === 2040,
      newFormatGt3500: rt.length > 3500,
      header30: rt.slice(0, 30),
      char30: rt.charAt(29),
      stationPairCount: rt.length > 30 ? Math.floor((rt.length - 30) / 2) : 0,
      first20Pairs: Array.from({ length: Math.min(20, Math.floor((rt.length - 30) / 2)) }, (_, i) => rt.slice(30 + i * 2, 32 + i * 2)),
    },
  };
}

function applyDownloadedCloudValues(thread, values, { runDetection = true, runHyp = true } = {}) {
  for (const [name, value] of Object.entries(values)) {
    if (name.startsWith('☁ ')) {
      setAnyVariableByName(thread, name, String(value));
    }
  }
  core.callProcedure(thread, 'Wクラウド変数更新したら');

  const beforeDetection = {
    cloud: summarizeCloudState(thread),
    scratch: core.snapshotCore(thread),
  };

  if (runDetection) {
    core.callProcedure(thread, 'W震度復元');
    core.callProcedure(thread, 'W揺れ検出許可');
    core.callProcedure(thread, 'W検出許可震度算出');
    core.callProcedure(thread, 'W検出id1_全点へ適用');
    core.callProcedure(thread, 'W円検出の毎処理 %b', [true]);

    if (runHyp) {
      const detectionInfo = listValue(thread, '4-3 検出id別情報');
      const idCount = Math.floor(detectionInfo.length / 20);
      for (let id = 1; id <= idCount; id++) {
        const offset = (id - 1) * 20;
        if (detectionInfo[offset + 1]) {
          core.callProcedure(thread, 'ZHYP:震源検出 %s %s', [id, offset]);
        }
      }
      core.callProcedure(thread, 'W円検出の毎処理 %b', [false]);
    }
  }

  return {
    beforeDetection,
    afterDetection: {
      cloud: summarizeCloudState(thread),
      source: summarize(thread),
    },
  };
}

function shindoToScratchLevelIndex(thread, shindo) {
  if (shindo == null || Number.isNaN(Number(shindo))) return 0;
  const table = listValue(thread, 'd #震度換算30段階').map(Number);
  let bestIndex = 1;
  let bestDistance = Infinity;
  for (let i = 0; i < table.length; i++) {
    const distance = Math.abs(table[i] - Number(shindo));
    if (distance < bestDistance) {
      bestDistance = distance;
      bestIndex = i + 1;
    }
  }
  return bestIndex;
}

function setFrameTime(thread, observedAt) {
  const date = observedAt instanceof Date ? observedAt : new Date(observedAt);
  if (Number.isNaN(date.getTime())) throw new Error(`Invalid observedAt: ${observedAt}`);
  core.setNowMs(date.getTime());
  const latestCloud = stageVariable(thread, '#r:最新クラウド変数');
  replaceScratchListItem(latestCloud, 1, secondsSince2000(date));
  return date;
}

function runFrame(thread, observations, stationCodeToTenIndex, { runHyp = true, traceStations = false } = {}) {
  if (observations.length === 0) return summarize(thread, stationCodeToTenIndex, { traceStations });
  const date = setFrameTime(thread, observations[0].observedAtUtc);

  // Matches the upstream per-RT-shindo update path around 震度復元:
  // 1. shift global ten history timestamps
  // 2. process each station's shindo via 点震度の処理
  // 3. run upstream permission, detection-id, 4-3/4-4 and circle/HYP update procedures
  core.callProcedure(thread, 'W震度履歴時間管理 %s %s', ['', '']);

  let applied = 0;
  let skipped = 0;
  for (const row of observations) {
    const stationCode = row.stationCode;
    const tenIndex = stationCodeToTenIndex.get(stationCode);
    if (!tenIndex) {
      skipped += 1;
      continue;
    }
    const shindo = Number(row.gifDecodedShindo);
    const levelIndex = shindoToScratchLevelIndex(thread, shindo);
    // Upstream 点震度の処理 takes zero-based point number, 30-step level index, raw shindo100-like value.
    core.callProcedure(thread, 'W点震度の処理 %s %s %s', [tenIndex - 1, levelIndex, shindo]);
    applied += 1;
  }

  core.callProcedure(thread, 'W揺れ検出許可');
  core.callProcedure(thread, 'W検出許可震度算出');
  core.callProcedure(thread, 'W検出id1_全点へ適用');
  core.callProcedure(thread, 'W円検出の毎処理 %b', [true]);

  if (runHyp) {
    const detectionInfo = listValue(thread, '4-3 検出id別情報');
    const idCount = Math.floor(detectionInfo.length / 20);
    for (let id = 1; id <= idCount; id++) {
      const offset = (id - 1) * 20;
      if (detectionInfo[offset + 1]) {
        core.callProcedure(thread, 'ZHYP:震源検出 %s %s', [id, offset]);
      }
    }
    core.callProcedure(thread, 'W円検出の毎処理 %b', [false]);
  }

  return { ...summarize(thread, stationCodeToTenIndex, { traceStations }), frame: date.toISOString(), applied, skipped };
}

function encodeCloudRtShindoFrame(observations, stationCodeToTenIndex, observedAt, {
  quantization = 'floor',
  scannedDefaultPair = '00',
  noScanDefaultPair = '99',
} = {}) {
  const stationCount = stationCodeToTenIndex.scratchTenLength || stageTenLength();
  const scanPositionCodes = readScanPositionCodes();
  const encoded = Array(stationCount).fill(noScanDefaultPair);
  for (const [code, tenIndex] of stationCodeToTenIndex.entries()) {
    encoded[tenIndex - 1] = scanPositionCodes.has(code) ? scannedDefaultPair : noScanDefaultPair;
  }
  for (const row of observations) {
    const tenIndex = stationCodeToTenIndex.get(row.stationCode);
    if (!tenIndex) continue;
    const shindo = Number(row.gifDecodedShindo);
    if (!Number.isFinite(shindo)) continue;
    // Upstream 震度復元 decodes two digits as rawShindo = (value - 30) / 10.
    // 99 means no point data.
    const rawValue = shindo * 10 + 30;
    const value = Math.max(0, Math.min(98, quantization === 'round' ? Math.round(rawValue) : Math.floor(rawValue)));
    encoded[tenIndex - 1] = String(value).padStart(2, '0');
  }
  // Upstream live content uses a 30-char header: 10 digit seconds-since-2000 key + 20 zero/config chars.
  // 震度復元 reads character 30 as realtime-shindo source discriminator, then station pairs from char 31.
  const date = observedAt instanceof Date ? observedAt : new Date(observedAt || observations[0]?.observedAtUtc);
  const key = String(Math.floor(secondsSince2000(date))).padStart(10, '0').slice(-10);
  return key + '0'.repeat(20) + encoded.join('');
}

function stageTenLength() {
  return core.SNAPSHOT.stage.variables['K=dB~/Qs0QP8?S-nu[mN'].value.length;
}

function runFrameViaCloudRt(thread, observations, stationCodeToTenIndex, { runHyp = true, traceStations = false } = {}) {
  if (observations.length === 0) return summarize(thread, stationCodeToTenIndex, { traceStations });
  const date = setFrameTime(thread, observations[0].observedAtUtc);
  const latestCloud = stageVariable(thread, '#r:最新クラウド変数');
  replaceScratchListItem(latestCloud, 3, encodeCloudRtShindoFrame(observations, stationCodeToTenIndex, date));

  core.callProcedure(thread, 'W震度復元');
  core.callProcedure(thread, 'W揺れ検出許可');
  core.callProcedure(thread, 'W検出許可震度算出');
  core.callProcedure(thread, 'W検出id1_全点へ適用');
  core.callProcedure(thread, 'W円検出の毎処理 %b', [true]);

  if (runHyp) {
    const detectionInfo = listValue(thread, '4-3 検出id別情報');
    const idCount = Math.floor(detectionInfo.length / 20);
    for (let id = 1; id <= idCount; id++) {
      const offset = (id - 1) * 20;
      if (detectionInfo[offset + 1]) {
        core.callProcedure(thread, 'ZHYP:震源検出 %s %s', [id, offset]);
      }
    }
    core.callProcedure(thread, 'W円検出の毎処理 %b', [false]);
  }

  return {
    ...summarize(thread, stationCodeToTenIndex, { traceStations }),
    frame: date.toISOString(),
    applied: observations.length,
    skipped: observations.filter(row => !stationCodeToTenIndex.has(row.stationCode)).length,
    inputMode: 'cloud-rt',
  };
}

function buildStationTrace(thread, stationCodeToTenIndex) {
  const stage = thread.target.runtime.stage;
  const list = name => (core.variableByName(stage, name) || core.variableByName(thread.target, name))?.value || [];
  const rows = readScratchStationRows(stationCodeToTenIndex);
  const tenPermission = list('ten c:揺れ検出許可');
  const tenEstimated = list('ten:推定用');
  const tenAssignedId = list('ten:検出id割り当て済み番号');
  const tenShindo = list('ten:震度');
  const tenSpeed = list('ten:震度変化速度');
  const state56Stations = [];
  const estimatedStations = [];
  for (let i = 0; i < rows.length; i++) {
    const state = Number(tenPermission[i] || 0);
    const common = {
      ...rows[i],
      state,
      assignedId: tenAssignedId[i] ?? '',
      shindo: tenShindo[i] ?? '',
      speed: tenSpeed[i] ?? '',
    };
    if (state === 5 || state === 6) {
      state56Stations.push(common);
    }
    const estimatedOffset = i * 10;
    if (tenEstimated[estimatedOffset + 2] !== '') {
      estimatedStations.push({
        ...common,
        estimatedRaw: tenEstimated.slice(estimatedOffset, estimatedOffset + 10),
      });
    }
  }
  return {
    state56Count: state56Stations.length,
    estimatedStationCount: estimatedStations.length,
    state56Stations,
    estimatedStations,
  };
}

function buildEstimatedPhaseStations(thread, stationCodeToTenIndex) {
  const stage = thread.target.runtime.stage;
  const list = name => (core.variableByName(stage, name) || core.variableByName(thread.target, name))?.value || [];
  const rows = readScratchStationRows(stationCodeToTenIndex);
  const tenEstimated = list('ten:推定用');
  const tenPermission = list('ten c:揺れ検出許可');
  const tenShindo = list('ten:震度');
  const tenSpeed = list('ten:震度変化速度');
  const stations = [];
  for (let i = 0; i < rows.length; i++) {
    const offset = i * 10;
    const raw = tenEstimated.slice(offset, offset + 10);
    if (raw[2] === '') continue;
    const hasSFlag = raw[5] === true || String(raw[5]).toLowerCase() === 'true';
    const hasPredictedTimes = raw[6] !== '' || raw[7] !== '';
    const hasPrimaryArrival = raw[4] !== '';
    const phase = hasSFlag ? 's' : (hasPredictedTimes || hasPrimaryArrival ? 'p' : 'other');
    stations.push({
      ...rows[i],
      phase,
      state: Number(tenPermission[i] || 0),
      shindo: tenShindo[i] ?? '',
      speed: tenSpeed[i] ?? '',
      distanceKm: raw[3],
      primaryTime: raw[4],
      sFlag: hasSFlag,
      pArrivalTime: raw[6],
      sArrivalTime: raw[7],
      raw,
    });
  }
  return stations;
}

function summarize(thread, stationCodeToTenIndex = null, { traceStations = false } = {}) {
  const stage = thread.target.runtime.stage;
  const list = name => (core.variableByName(stage, name) || core.variableByName(thread.target, name))?.value || [];
  const detectionInfo = list('4-3 検出id別情報');
  const sourceElements = list('4-4 検出id震源要素');
  const tenEstimated = list('ten:推定用');
  const tenPermission = list('ten c:揺れ検出許可');
  const activeIds = [];
  for (let offset = 0; offset < detectionInfo.length; offset += 20) {
    activeIds.push({
      id: detectionInfo[offset],
      active: detectionInfo[offset + 1],
      startedAt: detectionInfo[offset + 2],
      appliedCount: detectionInfo[offset + 3],
      maxDistance: detectionInfo[offset + 4],
      state: detectionInfo[offset + 7],
      error: detectionInfo[offset + 10],
      firstDistance: detectionInfo[offset + 11],
      updatedAt: detectionInfo[offset + 17],
      bestError: detectionInfo[offset + 18],
    });
  }
  const sources = [];
  for (let offset = 0; offset < sourceElements.length; offset += 10) {
    sources.push({
      id: 1 + offset / 10,
      lon: sourceElements[offset + 1],
      lat: sourceElements[offset + 2],
      depthKm: sourceElements[offset + 3],
      originTime: sourceElements[offset + 4],
      pRadiusKm: sourceElements[offset + 5],
      sRadiusKm: sourceElements[offset + 6],
    });
  }
  let estimatedStations = 0;
  for (let offset = 0; offset < tenEstimated.length; offset += 10) {
    if (tenEstimated[offset + 2] !== '') estimatedStations += 1;
  }
  return {
    scratch: core.snapshotCore(thread),
    detectionIdCount: activeIds.length,
    activeIds,
    sources,
    estimatedStations,
    estimatedPhaseStations: buildEstimatedPhaseStations(thread, stationCodeToTenIndex),
    permittedStations: tenPermission.filter(v => Number(v) > 1).length,
    ...(traceStations ? { stationTrace: buildStationTrace(thread, stationCodeToTenIndex) } : {}),
  };
}

function groupObservationsByFrame(observations) {
  const groups = new Map();
  for (const raw of observations) {
    if (!raw || raw.observedAtUtc == null) continue;
    const key = new Date(raw.observedAtUtc).toISOString();
    const row = {
      stationCode: raw.stationCode,
      observedAtUtc: key,
      gifDecodedShindo: raw.gifDecodedShindo,
    };
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(row);
  }
  return [...groups.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([observedAtUtc, rows]) => ({ observedAtUtc, rows }));
}

function runObservationFile(filePath, options = {}) {
  const payload = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const observations = Array.isArray(payload) ? payload : payload.observations;
  if (!Array.isArray(observations)) throw new Error('Expected an observations array or gif_station_second_observations_v1 payload.');
  const thread = initializeUpstreamThread({ enableSource: options.enableSource !== false });
  const stationCodeToTenIndex = readStationCodeToTenIndex();
  const frames = groupObservationsByFrame(observations);
  const limit = options.limitFrames == null ? frames.length : Math.min(frames.length, options.limitFrames);
  let last = summarize(thread, stationCodeToTenIndex, { traceStations: !!options.traceStations });
  let lastWithSource = null;
  let peakDetectionIdCount = 0;
  let peakEstimatedStations = 0;
  let bestSourceByError = null;
  const frameTraces = [];
  for (let i = 0; i < limit; i++) {
    last = options.cloudRt
      ? runFrameViaCloudRt(thread, frames[i].rows, stationCodeToTenIndex, { runHyp: options.runHyp !== false, traceStations: !!options.traceStations })
      : runFrame(thread, frames[i].rows, stationCodeToTenIndex, { runHyp: options.runHyp !== false, traceStations: !!options.traceStations });
    peakDetectionIdCount = Math.max(peakDetectionIdCount, last.detectionIdCount);
    peakEstimatedStations = Math.max(peakEstimatedStations, last.estimatedStations);
    if (options.traceStations) {
      frameTraces.push({
        frame: last.frame,
        detectionIdCount: last.detectionIdCount,
        activeIds: last.activeIds,
        sources: last.sources,
        estimatedStations: last.estimatedStations,
        permittedStations: last.permittedStations,
        stationTrace: last.stationTrace,
      });
    }
    if (last.sources.length > 0) {
      lastWithSource = last;
      for (const id of last.activeIds) {
        if (id.bestError === '' || id.bestError == null) continue;
        const source = last.sources[(Number(id.id) || 1) - 1] || last.sources[0];
        const candidate = {
          frame: last.frame,
          id: id.id,
          error: Number(id.bestError),
          appliedCount: id.appliedCount,
          source,
          phaseStations: last.estimatedPhaseStations,
        };
        if (!bestSourceByError || candidate.error < bestSourceByError.error) {
          bestSourceByError = candidate;
        }
      }
    }
  }
  return {
    input: path.resolve(filePath),
    frameCount: frames.length,
    processedFrameCount: limit,
    peakDetectionIdCount,
    peakEstimatedStations,
    lastWithSource,
    bestSourceByError,
    final: last,
    ...(options.traceStations ? { frameTraces } : {}),
  };
}

function parseArgs(argv) {
  const args = [...argv];
  const out = { _: [] };
  while (args.length) {
    const arg = args.shift();
    if (arg.startsWith('--')) {
      const key = arg.slice(2);
      const next = args[0];
      if (next == null || next.startsWith('--')) out[key] = true;
      else out[key] = args.shift();
    } else {
      out._.push(arg);
    }
  }
  return out;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const cmd = args._[0] || 'smoke';
  if (cmd === 'smoke') {
    const thread = initializeUpstreamThread({ enableSource: true });
    const stationCodeToTenIndex = readStationCodeToTenIndex();
    const now = new Date('2026-06-30T03:08:45.000Z');
    const result = runFrame(thread, [
      { stationCode: 'FKS001', observedAtUtc: now.toISOString(), gifDecodedShindo: 0.6 },
      { stationCode: 'FKS002', observedAtUtc: now.toISOString(), gifDecodedShindo: 0.9 },
      { stationCode: 'MYG001', observedAtUtc: now.toISOString(), gifDecodedShindo: 0.4 },
    ], stationCodeToTenIndex);
    console.log(JSON.stringify(result, null, 2));
    return;
  }
  if (cmd === 'observations') {
    const input = args._[1];
    if (!input) throw new Error('Usage: node kotoho7_receiver_bridge_runner.js observations <gif_observations.json> [--limit-frames N] [--no-hyp]');
    const result = runObservationFile(input, {
      limitFrames: args['limit-frames'] == null ? null : Number(args['limit-frames']),
      runHyp: !args['no-hyp'],
      enableSource: !args['no-enable-source'],
      cloudRt: !!args['cloud-rt'],
      traceStations: !!args['trace-stations'],
    });
    const json = JSON.stringify(result, null, 2);
    if (args.output) {
      fs.mkdirSync(path.dirname(path.resolve(args.output)), { recursive: true });
      fs.writeFileSync(args.output, json, 'utf8');
    }
    if (!args.quiet) console.log(json);
    return;
  }
  if (cmd === 'summary') {
    const thread = initializeUpstreamThread({ enableSource: true });
    console.log(JSON.stringify(summarize(thread), null, 2));
    return;
  }
  if (cmd === 'cloud-snapshot') {
    const input = args._[1];
    if (!input) throw new Error('Usage: node kotoho7_receiver_bridge_runner.js cloud-snapshot <cloud_vars.json> [--output result.json] [--no-detection] [--no-hyp]');
    const snapshot = JSON.parse(fs.readFileSync(input, 'utf8'));
    const thread = initializeUpstreamThread({ enableSource: !args['no-enable-source'] });
    if (snapshot.generatedAt) {
      const ms = Date.parse(snapshot.generatedAt);
      if (Number.isFinite(ms)) core.setNowMs(ms);
    }
    const result = {
      input: path.resolve(input),
      generatedAt: new Date().toISOString(),
      cloudSource: snapshot.best ? {
        host: snapshot.best.host,
        projectId: snapshot.best.projectId,
        valueNames: Object.keys(snapshot.best.values || {}),
      } : null,
      result: applyDownloadedCloudValues(thread, extractCloudValuesFromSnapshot(snapshot), {
        runDetection: !args['no-detection'],
        runHyp: !args['no-hyp'],
      }),
    };
    const json = JSON.stringify(result, null, 2);
    if (args.output) {
      fs.mkdirSync(path.dirname(path.resolve(args.output)), { recursive: true });
      fs.writeFileSync(args.output, json, 'utf8');
    }
    if (!args.quiet) console.log(json);
    return;
  }
  throw new Error(`Unknown command: ${cmd}`);
}

module.exports = {
  initializeUpstreamThread,
  runFrame,
  runFrameViaCloudRt,
  runObservationFile,
  encodeCloudRtShindoFrame,
  summarize,
  readStationCodeToTenIndex,
  readScanPositionCodes,
  shindoToScratchLevelIndex,
  applyDownloadedCloudValues,
  summarizeCloudState,
};

if (require.main === module) main();
