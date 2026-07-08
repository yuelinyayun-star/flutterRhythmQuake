// UTF-8 persistent bridge for upstream kotoho7/TurboWarp receiver logic.
// One Node process keeps Scratch receiver state alive per event session.
'use strict';

const readline = require('readline');
const runner = require('./kotoho7_receiver_bridge_runner.js');

const sessions = new Map();

function sessionFor(key, { reset = false } = {}) {
  if (reset || !sessions.has(key)) {
    sessions.set(key, {
      thread: runner.initializeUpstreamThread({ enableSource: true }),
      stationCodeToTenIndex: runner.readStationCodeToTenIndex(),
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

function observeSource(session, frameResult) {
  session.frameCount += 1;
  session.peakDetectionIdCount = Math.max(
    session.peakDetectionIdCount,
    frameResult.detectionIdCount || 0,
  );
  session.peakEstimatedStations = Math.max(
    session.peakEstimatedStations,
    frameResult.estimatedStations || 0,
  );
  session.final = frameResult;

  if (Array.isArray(frameResult.sources) && frameResult.sources.length > 0) {
    session.lastWithSource = frameResult;
    for (const id of frameResult.activeIds || []) {
      if (id.bestError === '' || id.bestError == null) continue;
      const source =
        frameResult.sources[(Number(id.id) || 1) - 1] ||
        frameResult.sources[0];
      const candidate = {
        frame: frameResult.frame,
        id: id.id,
        error: Number(id.bestError),
        appliedCount: id.appliedCount,
        source,
        phaseStations: frameResult.estimatedPhaseStations,
      };
      if (
        !session.bestSourceByError ||
        candidate.error < session.bestSourceByError.error
      ) {
        session.bestSourceByError = candidate;
      }
    }
  }
}

function handleRequest(raw) {
  const id = raw.id;
  const sessionKey = raw.sessionKey || 'default';
  const observations = Array.isArray(raw.observations) ? raw.observations : [];
  const session = sessionFor(sessionKey, { reset: raw.reset === true });
  const frameResult = raw.cloudRt === false
    ? runner.runFrame(session.thread, observations, session.stationCodeToTenIndex, {
        runHyp: raw.runHyp !== false,
        traceStations: raw.traceStations === true,
      })
    : runner.runFrameViaCloudRt(session.thread, observations, session.stationCodeToTenIndex, {
        runHyp: raw.runHyp !== false,
        traceStations: raw.traceStations === true,
      });
  observeSource(session, frameResult);
  return {
    id,
    ok: true,
    result: {
      sessionKey,
      frameCount: session.frameCount,
      processedFrameCount: session.frameCount,
      peakDetectionIdCount: session.peakDetectionIdCount,
      peakEstimatedStations: session.peakEstimatedStations,
      lastWithSource: session.lastWithSource,
      bestSourceByError: session.bestSourceByError,
      final: session.final,
    },
  };
}

const rl = readline.createInterface({
  input: process.stdin,
  crlfDelay: Infinity,
});

rl.on('line', line => {
  if (!line.trim()) return;
  let raw = null;
  try {
    raw = JSON.parse(line);
    const response = handleRequest(raw);
    process.stdout.write(JSON.stringify(response) + '\n');
  } catch (error) {
    process.stdout.write(JSON.stringify({
      id: raw && raw.id != null ? raw.id : null,
      ok: false,
      error: String(error && error.stack ? error.stack : error),
    }) + '\n');
  }
});
