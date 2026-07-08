#!/usr/bin/env node
// -*- coding: utf-8 -*-

"use strict";

const assert = require("node:assert/strict");
const kotoho7 = require("./kotoho7_cloud_eew_logic.js");

function testEewContentParse() {
  const state = kotoho7.makeScratchCloudEewState();
  const content = [
    "1",          // +1 active bit
    "120",        // +4 raw field
    "3750390125", // +5 time/origin-like field
    "456",        // +6 => 131.6E
    "394",        // +7 => 39.4N
    "040",        // +8 depth 40km
    "56",         // +9 M5.6
    "3",          // +10 max/level raw
    "908",        // +3 report/id
    "0",          // slot
    "0000000000",
  ].join("");

  const result = kotoho7.parseEewContentIntoState(state, content, 0);

  assert.equal(result.updated, true);
  assert.equal(result.active, 1);
  assert.equal(kotoho7.toMetadata(state).kotoho7_eew_slots[0], 1);
  assert.equal(kotoho7.toMetadata(state).kotoho7_eew_slots[2], 908);
  assert.equal(kotoho7.toMetadata(state).kotoho7_eew_slots[5], 131.6);
  assert.equal(kotoho7.toMetadata(state).kotoho7_eew_slots[6], 39.4);
  assert.equal(kotoho7.toMetadata(state).kotoho7_eew_slots[7], 40);
  assert.equal(kotoho7.toMetadata(state).kotoho7_eew_slots[8], "5.6");
}

function testCloudC2hRoutesToLatestVariable2() {
  const state = kotoho7.makeScratchCloudEewState();
  const r2 = "1000000000000004563940405639080000000000";
  const c2h = [
    "0836540000",
    r2,
    "12",
    "0",
    "00000",
    "5".repeat(206),
    "0000000000000000000",
  ].join("");

  const result = kotoho7.updateCloudVariablesFromScratchCloud(state, {
    "☁ c2h": c2h,
  });

  assert.equal(result.accepted, true);
  assert.equal(kotoho7.toMetadata(state).kotoho7_latest_cloud_variables[1], r2);
  // Scratch reads #受信バージョン from ☁ c2h[43..44], which is inside the
  // 40-character #r[2] header span rather than after it.
  assert.equal(state.receiveVersion, r2.slice(32, 34));
}

function testCircleTriggerPromotion() {
  const state = kotoho7.makeScratchCloudEewState();
  state.eewGlobalActive = 1;
  // slot 1, 0-based backing array:
  // +1 active, +8 depth, +9 M, +12 outer radius, +13 inner/reference radius.
  state.eew[0] = 1;
  state.eew[7] = 40;
  state.eew[8] = "5.6";
  state.eew[11] = 500;
  state.eew[12] = 220;
  state.eewActiveFlags[0] = 1;
  state.eewExtra[2] = 0.2;
  kotoho7.setStationSourceDistance(state, 123, 1, 230);

  const result = kotoho7.singleTriggerCircleEewPermission(state, {
    stationIndex1: 123,
    currentState: 3,
    threshold: 3,
    pointCount: 1,
    shindo: 0,
    triggerAgeSeconds: 3,
  });

  assert.equal(result.promoted, true);
  assert.equal(result.nextState, 5);
  assert.equal(result.reason, "円の中トリガ");
  assert.equal(result.slotIndex1, 1);
}

function testEewInformationProcessingGeneratesScratchCircleState() {
  const state = kotoho7.makeScratchCloudEewState();
  const content = [
    "1",          // +1 active bit
    "120",        // +4 raw field
    "0000001000", // +5 EEW origin/announcement time in Scratch seconds
    "456",        // +6 => 131.6E
    "394",        // +7 => 39.4N
    "040",        // +8 depth 40km
    "56",         // +9 M5.6
    "3",          // +10 max/level raw
    "908",        // +3 report/id
    "0",          // slot
    "0000000000",
  ].join("");

  kotoho7.parseEewContentIntoState(state, content, 0);
  const result = kotoho7.eewInformationProcessing(state, {
    nowSeconds: 1020,
    stations: [
      { stationIndex1: 123, latitude: 39.5, longitude: 131.8 },
    ],
  });

  assert.equal(result.eewGlobalActive, 1);
  assert.equal(result.activeFlags[0], 1);
  assert.equal(state.eew[10], 20); // 0EEW +11 elapsed seconds
  assert.ok(state.eew[11] > state.eew[12]); // P radius is ahead of S radius
  assert.ok(state.eew[11] > 100);
  assert.ok(state.eew[12] > 60);
  assert.ok(kotoho7.getStationSourceDistance(state, 123, 1) > 0);
}

function testRawC2b2DoesNotBecomeLatestVariable2() {
  const state = kotoho7.makeScratchCloudEewState();
  const content = "1120375039012504563940405639080000000000";
  const packet = `08365400001236244032${content}`;
  const result = kotoho7.cloudPacketChangeCheck(state, packet, 6, true);

  assert.equal(result.changed, true);
  assert.equal(kotoho7.toMetadata(state).kotoho7_latest_cloud_variables[5], content);
  assert.equal(kotoho7.toMetadata(state).kotoho7_latest_cloud_variables[1], "");
}

testEewContentParse();
testCloudC2hRoutesToLatestVariable2();
testCircleTriggerPromotion();
testEewInformationProcessingGeneratesScratchCircleState();
testRawC2b2DoesNotBecomeLatestVariable2();

console.log("kotoho7_cloud_eew_logic_test: ok");
