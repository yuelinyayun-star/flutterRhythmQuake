// UTF-8 browser/WebView runtime wrapper for kotoho7 receiver logic.
// Requires kotoho7_receiver_compiled_core.js to have populated window.module.exports.
(function () {
  'use strict';

  const core = window.module && window.module.exports;
  const EPOCH_2000_MS = Date.UTC(2000, 0, 1);
  const sessions = new Map();

  function secondsSince2000(date) {
    return (date.getTime() - EPOCH_2000_MS) / 1000;
  }

  function variable(target, name) {
    const value = core.variableByName(target, name);
    if (!value) throw new Error(`Scratch variable/list not found: ${name}`);
    return value;
  }

  function stageVariable(thread, name) {
    return variable(thread.target.runtime.stage, name);
  }

  function listValue(thread, name) {
    const value =
      core.variableByName(thread.target.runtime.stage, name) ||
      core.variableByName(thread.target, name);
    if (!value) throw new Error(`Scratch list not found: ${name}`);
    return value.value;
  }

  function replaceScratchListItem(list, oneBasedIndex, value) {
    if (oneBasedIndex < 1 || oneBasedIndex > list.value.length) return;
    list.value[oneBasedIndex - 1] = value;
  }

  function enableSourceEstimationFlags(thread) {
    const settings = stageVariable(thread, '7システム設定');
    for (const index of [51, 52, 57, 62]) {
      replaceScratchListItem(settings, index, true);
    }
  }

  function initializeThread() {
    const thread = core.makeThread();
    core.callProcedure(thread, 'Wリセット %b', [true]);
    enableSourceEstimationFlags(thread);
    return thread;
  }

  function sessionFor(key, reset) {
    if (reset || !sessions.has(key)) {
      sessions.set(key, {
        thread: initializeThread(),
        frameCount: 0,
        peakDetectionIdCount: 0,
        peakEstimatedStations: 0,
        lastWithSource: null,
        bestSourceByError: null,
        final: null,
      });
    }
    return sessions.get(key);
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

  function scratchLevelIndexToJmaClass(thread, value) {
    const numeric = Number(value);
    if (!Number.isFinite(numeric) || numeric < 1) return null;
    const table = listValue(thread, 'd #震度換算30段階').map(Number);
    const instrumental = table[Math.round(numeric) - 1];
    if (!Number.isFinite(instrumental)) return null;
    if (instrumental < 0.5) return 0;
    if (instrumental < 1.5) return 1;
    if (instrumental < 2.5) return 2;
    if (instrumental < 3.5) return 3;
    if (instrumental < 4.5) return 4;
    if (instrumental < 5.5) return 5;
    if (instrumental < 6.5) return 6;
    return 7;
  }

  function parseMapDisplayMax(thread, raw) {
    if (raw == null || raw === '' || raw === -3 || raw === '-3') {
      return {
        raw,
        mode: null,
        scratchLevel: null,
        jmaClass: null,
      };
    }
    const text = String(raw);
    const mode = Number(text.slice(0, 1));
    const valueText = text.slice(1);
    const scratchLevel = Number(valueText);
    const finiteScratchLevel = Number.isFinite(scratchLevel) ? scratchLevel : null;
    return {
      raw,
      mode: Number.isFinite(mode) ? mode : null,
      scratchLevel: finiteScratchLevel,
      jmaClass: finiteScratchLevel == null
        ? null
        : scratchLevelIndexToJmaClass(thread, finiteScratchLevel),
    };
  }

  function setFrameTime(thread, observedAt) {
    const date = observedAt instanceof Date ? observedAt : new Date(observedAt);
    if (Number.isNaN(date.getTime())) throw new Error(`Invalid observedAt: ${observedAt}`);
    core.setNowMs(date.getTime());
    const latestCloud = stageVariable(thread, '#r:最新クラウド変数');
    replaceScratchListItem(latestCloud, 1, secondsSince2000(date));
    return date;
  }

  function summarize(thread, observations) {
    const stage = thread.target.runtime.stage;
    const list = name => (core.variableByName(stage, name) || core.variableByName(thread.target, name))?.value || [];
    const detectionInfo = list('4-3 検出id別情報');
    const sourceElements = list('4-4 検出id震源要素');
    const tenEstimated = list('ten:推定用');
    const tenPermission = list('ten c:揺れ検出許可');
    const tenShindoIndex = list('ten:震度').map(Number);
    const tenPermittedShindo = list('ten c:検出許可済み震度').map(Number);
    const mapDisplayedShindo = list('map:表示する震度');
    const mapDisplayedMax = parseMapDisplayMax(thread, mapDisplayedShindo[194]);
    const finiteMax = values => {
      let max = null;
      for (const value of values) {
        if (!Number.isFinite(value)) continue;
        if (max === null || value > max) max = value;
      }
      return max;
    };
    const maxScratchShindoIndex = finiteMax(tenShindoIndex);
    const maxScratchShindo = finiteMax(tenPermittedShindo);
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
    const rows = [];
    const scratchX = core.SNAPSHOT.stage.variables['K=dB~/Qs0QP8?S-nu[mN'].value.map(Number);
    const scratchY = core.SNAPSHOT.stage.variables['o}-u@H4`+v8X:~`A_r6%'].value.map(Number);
    const codeByTenIndex = new Map();
    for (const row of observations || []) {
      const tenIndex = Number(row.tenIndex || row.scratchTenIndex || 0);
      const code = row.stationCode == null ? '' : String(row.stationCode);
      if (tenIndex && code) codeByTenIndex.set(tenIndex, code);
    }
    let estimatedStations = 0;
    for (let offset = 0; offset < tenEstimated.length; offset += 10) {
      if (tenEstimated[offset + 2] === '') continue;
      estimatedStations += 1;
      const i = offset / 10;
      const raw = tenEstimated.slice(offset, offset + 10);
      const hasSFlag = raw[5] === true || String(raw[5]).toLowerCase() === 'true';
      const hasPredictedTimes = raw[6] !== '' || raw[7] !== '';
      const hasPrimaryArrival = raw[4] !== '';
      rows.push({
        tenIndex: i + 1,
        code: codeByTenIndex.get(i + 1) || null,
        lat: scratchY[i],
        lng: scratchX[i],
        phase: hasSFlag ? 's' : (hasPredictedTimes || hasPrimaryArrival ? 'p' : 'other'),
      });
    }
    return {
      detectionIdCount: activeIds.length,
      activeIds,
      sources,
      estimatedStations,
      estimatedPhaseStations: rows,
      permittedStations: tenPermission.filter(v => Number(v) > 1).length,
      maxScratchShindoIndex,
      maxScratchShindo,
      mapDisplayedMaxShindoRaw: mapDisplayedMax.raw,
      mapDisplayedMaxShindoMode: mapDisplayedMax.mode,
      mapDisplayedMaxScratchLevel: mapDisplayedMax.scratchLevel,
      mapDisplayedMaxShindoClass: mapDisplayedMax.jmaClass,
    };
  }

  function compactFrameResult(frameResult) {
    if (!frameResult) return null;
    return {
      frame: frameResult.frame,
      applied: frameResult.applied,
      skipped: frameResult.skipped,
      inputMode: frameResult.inputMode,
      detectionIdCount: frameResult.detectionIdCount,
      estimatedStations: frameResult.estimatedStations,
      permittedStations: frameResult.permittedStations,
      maxScratchShindoIndex: frameResult.maxScratchShindoIndex,
      maxScratchShindo: frameResult.maxScratchShindo,
      mapDisplayedMaxShindoRaw: frameResult.mapDisplayedMaxShindoRaw,
      mapDisplayedMaxShindoMode: frameResult.mapDisplayedMaxShindoMode,
      mapDisplayedMaxScratchLevel: frameResult.mapDisplayedMaxScratchLevel,
      mapDisplayedMaxShindoClass: frameResult.mapDisplayedMaxShindoClass,
    };
  }

  function runFrame(thread, observations, runHyp) {
    if (!observations.length) return summarize(thread, observations);
    const date = setFrameTime(thread, observations[0].observedAtUtc);
    const latestCloud = stageVariable(thread, '#r:最新クラウド変数');
    replaceScratchListItem(latestCloud, 3, encodeCloudRtShindoFrame(thread, observations, date));

    core.callProcedure(thread, 'W震度復元');
    core.callProcedure(thread, 'W揺れ検出許可');
    core.callProcedure(thread, 'W検出許可震度算出');
    core.callProcedure(thread, 'W検出id1_全点へ適用');
    core.callProcedure(thread, 'W円検出の毎処理 %b', [true]);

    let applied = 0;
    let skipped = 0;
    for (const row of observations) {
      const tenIndex = Number(row.tenIndex || row.scratchTenIndex || 0);
      if (!tenIndex) {
        skipped += 1;
        continue;
      }
      applied += 1;
    }
    if (runHyp !== false) {
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
    core.callProcedure(thread, 'W地図表示震度決定');
    return { ...summarize(thread, observations), frame: date.toISOString(), applied, skipped, inputMode: 'in-app-webview' };
  }

  function encodeCloudRtShindoFrame(thread, observations, observedAt) {
    const stationCount = core.SNAPSHOT.stage.variables['K=dB~/Qs0QP8?S-nu[mN'].value.length;
    // The app only forwards NIED scan-mapped stations to this runtime. Treat
    // the baseline as scanned zero-shindo points, matching the upstream cloud
    // RT path for observation points; actual GIF values overwrite below.
    const encoded = Array(stationCount).fill('00');
    for (const row of observations) {
      const tenIndex = Number(row.tenIndex || row.scratchTenIndex || 0);
      if (!tenIndex || tenIndex < 1 || tenIndex > stationCount) continue;
      const shindo = Number(row.gifDecodedShindo);
      if (!Number.isFinite(shindo)) continue;
      const rawValue = shindo * 10 + 30;
      const value = Math.max(0, Math.min(98, Math.floor(rawValue)));
      encoded[tenIndex - 1] = String(value).padStart(2, '0');
    }
    const key = String(Math.floor(secondsSince2000(observedAt))).padStart(10, '0').slice(-10);
    return key + '0'.repeat(20) + encoded.join('');
  }

  function observeSource(session, frameResult) {
    session.frameCount += 1;
    session.peakDetectionIdCount = Math.max(session.peakDetectionIdCount, frameResult.detectionIdCount || 0);
    session.peakEstimatedStations = Math.max(session.peakEstimatedStations, frameResult.estimatedStations || 0);
    session.final = frameResult;
    if (Array.isArray(frameResult.sources) && frameResult.sources.length > 0) {
      session.lastWithSource = frameResult;
      for (const id of frameResult.activeIds || []) {
        if (id.bestError === '' || id.bestError == null) continue;
        const source = frameResult.sources[(Number(id.id) || 1) - 1] || frameResult.sources[0];
        const candidate = {
          frame: frameResult.frame,
          id: id.id,
          error: Number(id.bestError),
          appliedCount: id.appliedCount,
          source,
          phaseStations: frameResult.estimatedPhaseStations,
        };
        if (!session.bestSourceByError || candidate.error < session.bestSourceByError.error) {
          session.bestSourceByError = candidate;
        }
      }
    }
  }

  function normalizeObservations(raw) {
    if (Array.isArray(raw.observations)) return raw.observations;
    if (!Array.isArray(raw.compactObservations)) return [];
    const observedAtUtc = raw.observedAtUtc;
    return raw.compactObservations.map(row => ({
      tenIndex: row[0],
      gifDecodedShindo: row[1],
      stationCode: row[2] == null ? '' : String(row[2]),
      observedAtUtc,
    }));
  }

  function handleReceiverRequest(raw) {
    const session = sessionFor(raw.sessionKey || 'default', raw.reset === true);
    const frameResult = runFrame(session.thread, normalizeObservations(raw), raw.runHyp !== false);
    observeSource(session, frameResult);
    return {
      sessionKey: raw.sessionKey || 'default',
      frameCount: session.frameCount,
      processedFrameCount: session.frameCount,
      peakDetectionIdCount: session.peakDetectionIdCount,
      peakEstimatedStations: session.peakEstimatedStations,
      bestSourceByError: session.bestSourceByError,
      final: compactFrameResult(session.final),
    };
  }

  window.Kotoho7ReceiverRuntime = {
    handle: handleReceiverRequest,
  };

  if (window.chrome && window.chrome.webview) {
    window.chrome.webview.addEventListener('message', event => {
      let raw = event.data;
      try {
        if (typeof raw === 'string') raw = JSON.parse(raw);
        const result = handleReceiverRequest(raw || {});
        window.chrome.webview.postMessage({
          id: raw && raw.id,
          ok: true,
          result,
        });
      } catch (error) {
        window.chrome.webview.postMessage({
          id: raw && raw.id,
          ok: false,
          error: String(error && error.stack ? error.stack : error),
        });
      }
    });
  }
})();
