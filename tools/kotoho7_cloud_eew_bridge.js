#!/usr/bin/env node
// -*- coding: utf-8 -*-

"use strict";

const fs = require("node:fs");
const kotoho7 = require("./kotoho7_cloud_eew_logic.js");

function readStdin() {
  return fs.readFileSync(0, "utf8");
}

function writeJson(value) {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

function fail(message, details = {}) {
  writeJson({ ok: false, error: message, ...details });
  process.exitCode = 1;
}

function stateFromInput(input) {
  if (input.state) return kotoho7.fromMetadata(input.state);
  if (input.metadata) return kotoho7.fromMetadata(input.metadata);
  return kotoho7.makeScratchCloudEewState();
}

function main() {
  let input;
  try {
    input = JSON.parse(process.argv[2] || readStdin());
  } catch (error) {
    fail("invalid_json_stdin", { detail: String(error) });
    return;
  }

  const command = input.command;
  const state = stateFromInput(input);

  try {
    if (command === "updateCloud") {
      const result = kotoho7.updateCloudVariablesFromScratchCloud(
        state,
        input.cloudVariables || {},
      );
      writeJson({ ok: true, result, metadata: kotoho7.toMetadata(state) });
      return;
    }

    if (command === "parseEewContent") {
      const offset = Number(input.offset || 0);
      const result = kotoho7.parseEewContentIntoState(
        state,
        input.content || "",
        offset,
      );
      writeJson({ ok: true, result, metadata: kotoho7.toMetadata(state) });
      return;
    }

    if (command === "processEewInformation") {
      const result = kotoho7.eewInformationProcessing(state, {
        nowSeconds: Number(input.nowSeconds),
        timeOffsetSeconds: Number(input.timeOffsetSeconds || 0),
        stations: input.stations || [],
        projectJsonPath: input.projectJsonPath,
      });
      writeJson({ ok: true, result, metadata: kotoho7.toMetadata(state) });
      return;
    }

    if (command === "circleTrigger") {
      for (const entry of input.stationDistances || []) {
        kotoho7.setStationSourceDistance(
          state,
          Number(entry.stationIndex1),
          Number(entry.slotIndex1),
          Number(entry.distanceKm),
        );
      }
      const result = kotoho7.singleTriggerCircleEewPermission(state, {
        stationIndex1: Number(input.stationIndex1),
        currentState: Number(input.currentState),
        threshold: Number(input.threshold),
        pointCount: Number(input.pointCount),
        shindo: Number(input.shindo),
        triggerAgeSeconds: Number(input.triggerAgeSeconds),
      });
      writeJson({ ok: true, result, metadata: kotoho7.toMetadata(state) });
      return;
    }

    fail("unknown_command", {
      command,
      supportedCommands: [
        "updateCloud",
        "parseEewContent",
        "processEewInformation",
        "circleTrigger",
      ],
    });
  } catch (error) {
    fail("command_failed", { command, detail: String(error), stack: error?.stack });
  }
}

main();
