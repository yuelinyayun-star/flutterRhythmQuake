#!/usr/bin/env node
// -*- coding: utf-8 -*-
/**
 * Local JavaScript reference for kotoho7 Scratch cloud -> EEW -> circle trigger.
 *
 * This file intentionally mirrors the Scratch source structure instead of
 * trying to "improve" it:
 *
 *   クラウド変数更新したら
 *     -> 雲変化 / 雲変化チェック
 *     -> EEW %s %s
 *     -> 単独トリガ ... 円の中トリガ branch
 *
 * It is dependency-free CommonJS so it can run under Node during local replay
 * diagnostics.  Production Dart can later port these functions one-for-one or
 * call this module from a debug/tooling bridge.
 */

"use strict";

const fs = require("node:fs");
const path = require("node:path");

const DEFAULT_PROJECT_JSON_PATH = path.join(
  __dirname,
  "..",
  ".dart_tool",
  "external_refs",
  "scratch-realtime-earthquake-viewer-page",
  "docs",
  "assets",
  "project.json",
);

function scratchSlice(value, start, endInclusive) {
  const text = value == null ? "" : String(value);
  if (endInclusive == null) return text.slice(start - 1);
  return text.slice(start - 1, endInclusive);
}

function scratchLetter(index, value) {
  return scratchSlice(value, Number(index), Number(index));
}

function numberOrZero(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function scratchBool(value) {
  return value === true || value === 1 || value === "1" || value === "true";
}

function mod(value, divisor) {
  return numberOrZero(value) % divisor;
}

function joinDigits(...parts) {
  return parts.map((part) => (part == null ? "" : String(part))).join("");
}

function ensureListSlot(list, index1, fill = "") {
  while (list.length < index1) list.push(fill);
}

function item(list, index1) {
  const index = Number(index1);
  if (!Number.isFinite(index) || index < 1) return "";
  return list[index - 1] ?? "";
}

function replaceItem(list, index1, value, fill = "") {
  const index = Number(index1);
  if (!Number.isFinite(index) || index < 1) return;
  ensureListSlot(list, index, fill);
  list[index - 1] = value;
}

function makeScratchCloudEewState() {
  return {
    latestCloudVariables: Array(10).fill(""),
    updated: Array(20).fill(""),
    history: [],
    replayMode: 0,
    eew: Array(140).fill(0),
    eewActiveFlags: Array(10).fill(0), // 0-1EEW発表中
    eewExtra: Array(140).fill(""), // 0-2EEW追加情報
    stationSourceDistancesKm: new Map(), // key `${stationIndex}:${slotIndex1}`
    eewGlobalActive: 0,
    currentCloudTime: 0,
    previousReceiveChangeKey: "",
    receiveVersion: "",
    realtimeReceiveOffset: 999,
    latestEewOffset: -9,
    realtimeStatus: Array(20).fill(0), // 4リアルタイム状況(最大震度など)
    pointSourceDistanceKey: Array(10).fill(""), // @1 点震源距離用
  };
}

function loadScratchJma2001Table(projectJsonPath = DEFAULT_PROJECT_JSON_PATH) {
  const raw = fs.readFileSync(projectJsonPath, "utf8");
  const project = JSON.parse(raw);
  for (const target of project.targets || []) {
    for (const [, value] of Object.entries(target.lists || {})) {
      const [name, items] = value;
      if (name === "d JMA2001走時表近似式") {
        return items.map(numberOrZero);
      }
    }
  }
  throw new Error(`d JMA2001走時表近似式 not found in ${projectJsonPath}`);
}

let cachedJma2001Table = null;

function getScratchJma2001Table(options = {}) {
  if (Array.isArray(options.jma2001Table)) return options.jma2001Table;
  if (!cachedJma2001Table || options.projectJsonPath) {
    cachedJma2001Table = loadScratchJma2001Table(options.projectJsonPath);
  }
  return cachedJma2001Table;
}

function jma2001DistanceApproximation({
  elapsedTimeOrDistance,
  depthKm,
  pWave = false,
  travelTimeCalculation = false,
  jma2001Table,
}) {
  // Mirrors Scratch `JMA2001距離近似: %s %s %b %b`.
  // Scratch uses its list as 1-based and accumulates six polynomial terms:
  //
  //   tjma = Σ e^(counter * ln(input)) * coeff[index]
  //
  // where index is selected by depth bucket, P/S, and distance->time vs
  // time->distance mode.  The final `tjma3` is epicentral distance:
  //
  //   tjma3 = tjma * sin(acos(depth / tjma))
  const input = numberOrZero(elapsedTimeOrDistance);
  const depth = numberOrZero(depthKm);
  let hypocentralOrTravelTime = 0;
  let counter = 1;
  for (let i = 0; i < 6; i += 1) {
    const scratchIndex =
      counter +
      ((1 + Math.round(depth / 10)) * 6) +
      (scratchBool(pWave) ? 0 : 426) +
      (scratchBool(travelTimeCalculation) ? 852 : 0);
    const coefficient = numberOrZero(jma2001Table[scratchIndex - 1]);
    const term = input > 0 ? Math.exp(counter * Math.log(input)) : 0;
    hypocentralOrTravelTime += term * coefficient;
    counter += 1;
  }
  const ratio = hypocentralOrTravelTime === 0
    ? NaN
    : depth / hypocentralOrTravelTime;
  const epicentralDistanceKm = Math.abs(ratio) <= 1
    ? hypocentralOrTravelTime * Math.sin(Math.acos(ratio))
    : NaN;
  return {
    hypocentralOrTravelTime,
    epicentralDistanceKm,
  };
}

function degreesToRadians(degrees) {
  return (numberOrZero(degrees) * Math.PI) / 180;
}

function radiansToDegrees(radians) {
  return (numberOrZero(radians) * 180) / Math.PI;
}

function scratchLatLonDistanceKm(lon1, lat1, lon2, lat2) {
  // Mirrors Scratch `緯度経度で距離km(多目的0)`:
  // acos(sin(y1)sin(y2)+cos(y1)cos(y2)cos(x1-x2))*111.31949
  const y1 = degreesToRadians(lat1);
  const y2 = degreesToRadians(lat2);
  const xDelta = degreesToRadians(numberOrZero(lon1) - numberOrZero(lon2));
  const cosine =
    Math.sin(y1) * Math.sin(y2) +
    Math.cos(y1) * Math.cos(y2) * Math.cos(xDelta);
  const clamped = Math.max(-1, Math.min(1, cosine));
  return radiansToDegrees(Math.acos(clamped)) * 111.31949;
}

function cloudChange(state, {
  identifier,
  content,
  slot,
  compareContent = false,
  packetId = "",
}) {
  const previous = item(state.latestCloudVariables, slot);
  if (compareContent && `a${content}` === `a${previous}`) {
    return { changed: false, stopped: true, reason: "same_content" };
  }
  if (state.replayMode === 0) {
    replaceItem(state.latestCloudVariables, slot, content);
    replaceItem(state.updated, slot, 1);
    replaceItem(state.updated, 10 + slot, `${packetId}${identifier}`);
    if (slot === 1) state.currentCloudTime = numberOrZero(content);
  }
  return { changed: true, stopped: false, reason: "updated" };
}

function cloudPacketChangeCheck(state, cloudValue, slot, compareContent = false) {
  const value = String(cloudValue ?? "");
  const magic = scratchSlice(value, 14, 20);
  if (magic !== "6244032") {
    return { changed: false, reason: "bad_magic", magic };
  }
  const packetTime = scratchSlice(value, 1, 10);
  const packetId = scratchSlice(value, 11, 13);
  const previousUpdateKey = item(state.updated, 10 + slot);
  const updateKey = `${packetId}${packetTime}`;
  if (`a${previousUpdateKey}` === `a${updateKey}`) {
    return { changed: false, reason: "same_packet", packetId, packetTime };
  }
  const content = scratchSlice(value, 21);
  return {
    ...cloudChange(state, {
      identifier: packetTime,
      content,
      slot,
      compareContent,
      packetId,
    }),
    packetId,
    packetTime,
    content,
  };
}

function updateCloudVariablesFromScratchCloud(state, cloudVars) {
  const c2h = String(cloudVars["☁ c2h"] ?? "");
  let accepted = false;
  if (c2h.length > 256) {
    accepted = true;
  } else {
    const head = scratchLetter(1, cloudVars["☁ c2b0"]);
    accepted =
      head === scratchLetter(1, cloudVars["☁ c2b1"]) &&
      head === scratchLetter(1, cloudVars["☁ c2b2"]) &&
      head === scratchLetter(1, cloudVars["☁ c2b3"]) &&
      head === scratchLetter(1, cloudVars["☁ c2b4"]) &&
      head === scratchLetter(1, cloudVars["☁ c2b5"]) &&
      head === scratchLetter(1, cloudVars["☁ c2b6"]) &&
      head === scratchLetter(1, cloudVars["☁ c2b7"]) &&
      head === scratchLetter(45, c2h);
  }
  if (!accepted) return { accepted: false, updates: [] };

  const receiveTime = scratchSlice(c2h, 1, 10);
  const receiveChangeKey = `${receiveTime}${scratchLetter(45, c2h)}${scratchLetter(50, c2h)}`;
  if (receiveChangeKey === state.previousReceiveChangeKey) {
    return { accepted: true, changed: false, reason: "same_receive_key" };
  }
  state.previousReceiveChangeKey = receiveChangeKey;

  const updates = [];
  updates.push(cloudChange(state, {
    identifier: receiveTime,
    content: scratchSlice(c2h, 11, 50),
    slot: 2,
    compareContent: mod(receiveTime, 10) !== 0,
  }));
  state.receiveVersion = scratchSlice(c2h, 43, 44);
  updates.push(cloudChange(state, {
    identifier: receiveTime,
    content: scratchSlice(c2h, 51, 256),
    slot: 5,
    compareContent: mod(receiveTime, 10) !== 0,
  }));

  if (c2h.length > 256) {
    updates.push(cloudPacketChangeCheck(state, cloudVars["☁ c2b0"], 3, false));
    updates.push(cloudPacketChangeCheck(state, cloudVars["☁ c2b1"], 4, false));
    updates.push(cloudPacketChangeCheck(state, cloudVars["☁ c2b2"], 6, true));
    updates.push(cloudPacketChangeCheck(state, cloudVars["☁ c2b4"], 8, false));
    updates.push(cloudPacketChangeCheck(state, cloudVars["☁ c2b5"], 7, true));
    updates.push(cloudPacketChangeCheck(state, cloudVars["☁ c2b6"], 9, true));
  } else {
    let body = "";
    for (const name of [
      "☁ c2b0",
      "☁ c2b1",
      "☁ c2b2",
      "☁ c2b3",
      "☁ c2b4",
      "☁ c2b5",
      "☁ c2b6",
      "☁ c2b7",
    ]) {
      body += scratchSlice(cloudVars[name] ?? "", 2, 256);
    }
    const route = scratchLetter(50, c2h);
    const routeToSlot = {
      "0": 3,
      "1": 4,
      "2": 6,
      "4": 8,
      "5": 7,
      "6": 9,
    };
    const slot = routeToSlot[route];
    if (slot != null) {
      updates.push(cloudChange(state, {
        identifier: receiveTime,
        content: body,
        slot,
        compareContent: ["2", "5", "6"].includes(route),
      }));
    }
  }

  return { accepted: true, changed: true, receiveTime, updates };
}

function eewReset(state, offset, slotIndex1) {
  for (let i = 1; i <= 14; i += 1) {
    replaceItem(state.eew, offset + i, 0);
    replaceItem(state.eewExtra, offset + i, "");
  }
  replaceItem(state.eewActiveFlags, slotIndex1, 0);
}

function parseEewContentIntoState(state, content, offset) {
  const text = String(content ?? "");
  if (text === "") return { updated: false, reason: "empty_content" };

  // Cancel branch: letter(32, 内容) mod 2 == 1
  if (mod(scratchLetter(32, text), 2) === 1) {
    if (numberOrZero(item(state.eew, offset + 1)) > 0) {
      replaceItem(state.eew, offset + 3, numberOrZero(item(state.eew, offset + 3)) + 1);
      replaceItem(state.eew, offset + 14, state.currentCloudTime);
      replaceItem(state.eew, offset + 1, -1);
      replaceItem(state.eewActiveFlags, offset / 14 + 1, 0);
      return { updated: true, cancelled: true };
    }
    return { updated: false, cancelled: false, reason: "cancel_without_active_slot" };
  }

  const reportActive = mod(scratchLetter(1, text), 2);
  const reportNumber = numberOrZero(joinDigits(
    scratchLetter(27, text),
    scratchLetter(28, text),
    scratchLetter(29, text),
  ));
  const previousReportNumber = item(state.eew, offset + 3);
  if (reportNumber < numberOrZero(previousReportNumber)) {
    return { updated: false, reason: "older_report_number" };
  }

  if (
    reportActive === 1 &&
    (numberOrZero(item(state.eew, offset + 1)) === 0 ||
      numberOrZero(item(state.eew, offset + 1)) > 0)
  ) {
    eewReset(state, offset, offset / 14 + 1);
    replaceItem(state.realtimeStatus, 14, 1);
    replaceItem(state.eew, offset + 3, reportNumber);
    replaceItem(state.eew, offset + 14, state.currentCloudTime);
  }

  replaceItem(state.eew, offset + 1, reportActive);
  if (reportActive !== 1) {
    replaceItem(state.eewActiveFlags, offset / 14 + 1, 0);
    return { updated: true, active: false };
  }

  replaceItem(state.eewActiveFlags, offset / 14 + 1, 1);
  replaceItem(state.eew, offset + 2, Math.floor(numberOrZero(scratchLetter(1, text)) / 2) % 2);
  const idOrL = Math.floor(numberOrZero(scratchLetter(1, text)) / 4) % 2 === 1
    ? "l"
    : reportNumber;
  if (item(state.eew, offset + 3) !== idOrL) replaceItem(state.eew, offset + 3, idOrL);
  replaceItem(state.eew, offset + 4, numberOrZero(joinDigits(
    scratchLetter(2, text),
    scratchLetter(3, text),
    scratchLetter(4, text),
  )));

  const eewTime = scratchSlice(text, 5, 14);
  replaceItem(
    state.eew,
    offset + 5,
    Math.floor(numberOrZero(scratchLetter(32, text)) / 2) % 2 === 1
      ? numberOrZero(eewTime) + 2
      : eewTime,
  );
  if (
    state.latestEewOffset === -9 ||
    numberOrZero(item(state.eew, state.latestEewOffset + 5)) <
      numberOrZero(item(state.eew, offset + 5))
  ) {
    state.latestEewOffset = offset;
  }

  replaceItem(state.eew, offset + 6, numberOrZero(joinDigits(
    scratchLetter(15, text),
    scratchLetter(16, text),
    scratchLetter(17, text),
  )) / 10 + 86);
  replaceItem(state.eew, offset + 7, numberOrZero(joinDigits(
    scratchLetter(18, text),
    scratchLetter(19, text),
    scratchLetter(20, text),
  )) / 10);
  const depthText = joinDigits(scratchLetter(21, text), scratchLetter(22, text), scratchLetter(23, text));
  replaceItem(state.eew, offset + 8, depthText === "999" ? "n" : numberOrZero(depthText));
  const magnitudeText = joinDigits(scratchLetter(24, text), scratchLetter(25, text));
  replaceItem(state.eew, offset + 9, magnitudeText === "99"
    ? "n"
    : `${scratchLetter(24, text)}.${scratchLetter(25, text)}`);
  replaceItem(state.eew, offset + 10,
    scratchLetter(26, text) === "0" && mod(scratchLetter(31, text), 2) === 1
      ? "h"
      : scratchLetter(26, text));

  if (mod(scratchLetter(32, text), 2) === 1 && item(state.eew, offset + 1) === 1) {
    replaceItem(state.eew, offset + 1, -1);
    replaceItem(state.eewActiveFlags, offset / 14 + 1, 0);
  }

  replaceItem(state.eewExtra, offset + 6, joinDigits(
    Math.floor(numberOrZero(scratchLetter(32, text)) / 2) % 2,
    Math.floor(numberOrZero(scratchLetter(32, text)) / 4) % 2,
    Math.floor(numberOrZero(scratchLetter(31, text)) / 2) % 2,
    numberOrZero(scratchLetter(36, text)) > 4 ? 1 : 0,
    scratchLetter(37, text),
    scratchLetter(38, text),
  ));
  replaceItem(
    state.eewExtra,
    offset + 9,
    mod(scratchLetter(36, text), 5) > 0 ? mod(scratchLetter(36, text), 5) : "",
  );

  return {
    updated: true,
    active: item(state.eew, offset + 1),
    slotIndex1: offset / 14 + 1,
    latitude: item(state.eew, offset + 7),
    longitude: item(state.eew, offset + 6),
    depthKm: item(state.eew, offset + 8),
    magnitude: item(state.eew, offset + 9),
  };
}

function parseEewFromLatestCloudVariable2(state) {
  const content = item(state.latestCloudVariables, 2);
  const slot = numberOrZero(scratchLetter(30, content));
  return parseEewContentIntoState(state, content, 14 * slot);
}

function setStationSourceDistance(state, stationIndex1, slotIndex1, distanceKm) {
  state.stationSourceDistancesKm.set(`${stationIndex1}:${slotIndex1}`, distanceKm);
}

function getStationSourceDistance(state, stationIndex1, slotIndex1) {
  const value = state.stationSourceDistancesKm.get(`${stationIndex1}:${slotIndex1}`);
  return Number.isFinite(value) ? value : Infinity;
}

function circleInsideCheck(state, {
  stationIndex1,
  sWave = false,
  offsetKm = 0,
}) {
  for (let slot = 0; slot < 10; slot += 1) {
    const base = slot * 14;
    if (numberOrZero(item(state.eew, base + 1)) > 0) {
      const stationDistance = getStationSourceDistance(state, stationIndex1, slot + 1);
      const radius = numberOrZero(item(state.eew, base + 12 + (sWave ? 1 : 0))) + offsetKm;
      if (stationDistance < radius) {
        return { inside: true, slotIndex1: slot + 1, stationDistanceKm: stationDistance, radiusKm: radius };
      }
    }
  }
  return { inside: false };
}

function predictedDistanceIntensity(distanceKm, magnitude, depthKm) {
  // This is only a safe fallback for the circle-trigger gate.  Scratch calls
  // `距離の震度`; when production needs exactness, port that procedure too.
  const m = Number(magnitude);
  const d = Number(depthKm);
  const r = Number(distanceKm);
  if (!Number.isFinite(m) || !Number.isFinite(d) || !Number.isFinite(r)) {
    return -Infinity;
  }
  const hypocentral = Math.sqrt(r * r + d * d);
  return 0.92 + 1.63 * m - 3.49 * Math.log10(hypocentral + 7);
}

function updateStationSourceDistances(state, stations = []) {
  for (const station of stations) {
    const stationIndex1 = Number(station.stationIndex1 ?? station.index1);
    const stationLat = Number(station.lat ?? station.latitude);
    const stationLon = Number(station.lon ?? station.longitude);
    if (
      !Number.isFinite(stationIndex1) ||
      !Number.isFinite(stationLat) ||
      !Number.isFinite(stationLon)
    ) {
      continue;
    }
    for (let slot = 0; slot < 10; slot += 1) {
      const base = slot * 14;
      if (!(numberOrZero(item(state.eew, base + 1)) > 0)) continue;
      const sourceLon = Number(item(state.eew, base + 6));
      const sourceLat = Number(item(state.eew, base + 7));
      if (!Number.isFinite(sourceLon) || !Number.isFinite(sourceLat)) continue;
      setStationSourceDistance(
        state,
        stationIndex1,
        slot + 1,
        scratchLatLonDistanceKm(sourceLon, sourceLat, stationLon, stationLat),
      );
    }
  }
}

function eewInformationProcessing(state, {
  nowSeconds,
  timeOffsetSeconds = 0,
  stations = [],
  projectJsonPath,
  jma2001Table,
} = {}) {
  // Mirrors the generation side of Scratch `EEW情報の処理` that feeds
  // `円の中トリガ`: `EEW全体で発表中？`, `0EEW +11/+12/+13`,
  // `0-1EEW発表中`, `0-2EEW追加情報 +2/+3/+4`, and
  // `ten c:震源距離`.
  const table = getScratchJma2001Table({ projectJsonPath, jma2001Table });
  const now = numberOrZero(nowSeconds) + numberOrZero(timeOffsetSeconds);
  state.eewGlobalActive = 0;
  replaceItem(state.realtimeStatus, 13, 0);

  for (let slot = 0; slot < 10; slot += 1) {
    const base = slot * 14;
    const activeValue = item(state.eew, base + 1);
    if (numberOrZero(`0${activeValue}`) === 0) continue;
    if (numberOrZero(item(state.realtimeStatus, 13)) < numberOrZero(item(state.eew, base + 5))) {
      replaceItem(state.realtimeStatus, 13, item(state.eew, base + 5));
    }

    if (numberOrZero(activeValue) < 0) {
      if ((now - numberOrZero(item(state.eew, base + 14))) < 15) {
        state.eewGlobalActive = 1;
        replaceItem(state.eew, base + 11, now - numberOrZero(item(state.eew, base + 5)));
      } else {
        replaceItem(state.eew, base + 1, 0);
      }
      continue;
    }

    const elapsed = now - numberOrZero(item(state.eew, base + 5));
    // Scratch has a longer 720s branch for special update flags.  The common
    // branch that generates the P/S radii is the active 300s window.
    if (!(elapsed < 300)) {
      replaceItem(state.eew, base + 1, 0);
      continue;
    }

    state.eewGlobalActive = 1;
    replaceItem(state.eew, base + 11, elapsed);

    const depth = item(state.eew, base + 8);
    const p = jma2001DistanceApproximation({
      elapsedTimeOrDistance: elapsed,
      depthKm: depth,
      pWave: true,
      travelTimeCalculation: false,
      jma2001Table: table,
    });
    replaceItem(state.eew, base + 12, p.epicentralDistanceKm);

    const s = jma2001DistanceApproximation({
      elapsedTimeOrDistance: elapsed,
      depthKm: depth,
      pWave: false,
      travelTimeCalculation: false,
      jma2001Table: table,
    });
    replaceItem(state.eewExtra, base + 4, s.hypocentralOrTravelTime);
    replaceItem(state.eew, base + 13, s.epicentralDistanceKm);
    replaceItem(
      state.eewExtra,
      base + 2,
      predictedDistanceIntensity(
        s.epicentralDistanceKm,
        item(state.eew, base + 9),
        depth,
      ),
    );

    const sMinus70 = jma2001DistanceApproximation({
      elapsedTimeOrDistance: elapsed - 70,
      depthKm: depth,
      pWave: false,
      travelTimeCalculation: false,
      jma2001Table: table,
    });
    replaceItem(
      state.eewExtra,
      base + 3,
      numberOrZero(item(state.eew, base + 13)) === 0
        ? 0
        : sMinus70.epicentralDistanceKm / numberOrZero(item(state.eew, base + 13)),
    );
  }

  for (let slot = 0; slot < 10; slot += 1) {
    const base = slot * 14;
    replaceItem(state.eewActiveFlags, slot + 1, Math.abs(numberOrZero(item(state.eew, base + 1))));
  }
  updateStationSourceDistances(state, stations);
  return {
    eewGlobalActive: state.eewGlobalActive,
    activeFlags: state.eewActiveFlags.slice(),
    eew: state.eew.slice(),
    eewExtra: state.eewExtra.slice(),
  };
}

function singleTriggerCircleEewPermission(state, {
  stationIndex1,
  currentState,
  threshold,
  pointCount,
  shindo,
  triggerAgeSeconds,
  distanceIntensity = predictedDistanceIntensity,
}) {
  if (currentState !== 3) return { promoted: false, reason: "state_not_3" };
  if (!(threshold < 4)) return { promoted: false, reason: "threshold_not_below_4" };
  const earlyGate =
    (pointCount === 1 && !(shindo < -0.5)) ||
    (triggerAgeSeconds < 10 && !(shindo < 0.5));
  if (!earlyGate) return { promoted: false, reason: "early_gate_false" };
  if (numberOrZero(state.eewGlobalActive) !== 1) {
    return { promoted: false, reason: "eew_global_not_active" };
  }

  for (let slot = 0; slot < 10; slot += 1) {
    const base = slot * 14;
    const depthKm = item(state.eew, base + 8);
    if (!(numberOrZero(depthKm) < 150)) continue;
    if (!(numberOrZero(item(state.eewActiveFlags, slot + 1)) > 0)) continue;

    const stationDistance = getStationSourceDistance(state, stationIndex1, slot + 1);
    const intensity = stationDistance >= 200
      ? distanceIntensity(
          stationDistance,
          item(state.eew, base + 9),
          depthKm,
        )
      : Infinity;
    if (!(intensity > -0.5 || stationDistance < 200)) continue;

    const radius13 = numberOrZero(item(state.eew, base + 13));
    const radius12 = numberOrZero(item(state.eew, base + 12));
    const extraFactor = numberOrZero(item(state.eewExtra, base + 3));
    if (!(radius13 - 100 < stationDistance)) continue;
    if (!(extraFactor * radius13 < stationDistance && stationDistance < radius12 * 0.8)) {
      continue;
    }
    return {
      promoted: true,
      nextState: 5,
      reason: "円の中トリガ",
      scratchReason: "scratch_permission_circle_eew_trigger",
      slotIndex1: slot + 1,
      stationDistanceKm: stationDistance,
      predictedIntensity: intensity,
      radius12Km: radius12,
      radius13Km: radius13,
      extraFactor,
    };
  }

  return { promoted: false, reason: "no_matching_eew_circle_slot" };
}

function toMetadata(state) {
  return {
    kotoho7_eew_slots: state.eew.slice(),
    kotoho7_eew_active_flags: state.eewActiveFlags.slice(),
    kotoho7_eew_extra_info: state.eewExtra.slice(),
    kotoho7_eew_global_active: state.eewGlobalActive,
    kotoho7_latest_cloud_variables: state.latestCloudVariables.slice(),
  };
}

function fromMetadata(metadata) {
  const state = makeScratchCloudEewState();
  if (Array.isArray(metadata?.kotoho7_eew_slots)) {
    state.eew = metadata.kotoho7_eew_slots.slice();
  }
  if (Array.isArray(metadata?.kotoho7_eew_active_flags)) {
    state.eewActiveFlags = metadata.kotoho7_eew_active_flags.slice();
  }
  if (Array.isArray(metadata?.kotoho7_eew_extra_info)) {
    state.eewExtra = metadata.kotoho7_eew_extra_info.slice();
  }
  if (metadata?.kotoho7_eew_global_active != null) {
    state.eewGlobalActive = numberOrZero(metadata.kotoho7_eew_global_active);
  }
  return state;
}

module.exports = {
  scratchSlice,
  scratchLetter,
  makeScratchCloudEewState,
  updateCloudVariablesFromScratchCloud,
  loadScratchJma2001Table,
  jma2001DistanceApproximation,
  scratchLatLonDistanceKm,
  cloudChange,
  cloudPacketChangeCheck,
  parseEewContentIntoState,
  parseEewFromLatestCloudVariable2,
  eewInformationProcessing,
  updateStationSourceDistances,
  setStationSourceDistance,
  getStationSourceDistance,
  circleInsideCheck,
  singleTriggerCircleEewPermission,
  predictedDistanceIntensity,
  toMetadata,
  fromMetadata,
};

if (require.main === module) {
  const state = makeScratchCloudEewState();
  const payload = process.argv[2];
  if (!payload) {
    console.log(JSON.stringify({
      usage: "node tools/kotoho7_cloud_eew_logic.js <EEW-content>",
      note: "Parses one Scratch EEW content string into 0EEW-style slots.",
    }, null, 2));
    process.exit(0);
  }
  const result = parseEewContentIntoState(state, payload, 0);
  console.log(JSON.stringify({ result, metadata: toMetadata(state) }, null, 2));
}
