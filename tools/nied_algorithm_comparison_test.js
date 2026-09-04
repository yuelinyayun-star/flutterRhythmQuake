#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const path = require('node:path');

const comparison = require('./build_nied_algorithm_comparison.js');
const kanameishi = require('./kanameishi_reference_algorithm_runner.js');
const srev = require('./srev_kaizou_algorithm_runner.js');

const KANAMEISHI_ROOT = 'D:\\Users\\Rhythm\\Downloads\\kanameishi-dev';

test('loads the exact kanameishi-dev original module and dependencies', async () => {
  const loaded = await kanameishi.loadFindNiedHypocenter(KANAMEISHI_ROOT);
  assert.equal(typeof loaded.FindNiedHypocenter, 'function');
  assert.equal(
    loaded.provenance.algorithmSourceSha256,
    'E52FF3F6B9A28B8FC70EFFD7DA6CA0E63A008F0A3F2D4FE11D3E4C67F148A5C2'
  );
  assert.equal(
    loaded.provenance.utilitiesSourceSha256,
    'F8CC321D83F0AC1C2B00DFACB2197E23FF30DB58F0765946479EE9B35639929F'
  );
  assert.equal(
    loaded.provenance.travelTimesSourceSha256,
    '57F03384FED98998AB14A6F2E8E16C2C8915A5E689123693FD954D66328468E6'
  );
  assert.equal(loaded.provenance.algorithmBodyModified, false);
  assert.equal(path.resolve(KANAMEISHI_ROOT), loaded.provenance.root);
});

test('production UTC origin time is parsed without a local/JST reinterpretation', () => {
  const frames = comparison.canonicalProduction({
    cases: [{
      frames: [{
        observedAtJst: '2026-08-10T17:02:12.000',
        estimate: {
          latitude: 32.5,
          longitude: 130.6,
          depthKm: 10,
          supportingStationCount: 3,
          originTime: '2026-08-10T08:02:06.000Z',
          diagnostics: {
            effective_station_count: 3,
            weight_sum: 2.5,
            score: 1,
            error_level: 1,
          },
        },
      }],
    }],
  });
  assert.equal(frames[0].sources[0].originTimeEpochMs, Date.parse('2026-08-10T08:02:06.000Z'));
});

test('missing srev metrics remain null', () => {
  const frames = comparison.canonicalSrev({
    frames: [{
      observedAtUtc: '2026-08-10T08:02:00.000Z',
      sources: [{
        valid: true,
        detectionId: 1,
        originTimeEpochMs: null,
        weightSum: null,
        candidateEvaluationCount: null,
      }],
    }],
  });
  assert.equal(frames[0].sources[0].originTimeEpochMs, null);
  assert.equal(frames[0].sources[0].weightSum, null);
  assert.equal(frames[0].sources[0].candidateEvaluationCount, null);
  assert.equal(frames[0].candidateEvaluationCount, null);
  assert.equal(frames[0].runtimeMicros, null);
});

test('same-frame audit detects both matching and missing timestamps', () => {
  const timeA = Date.parse('2026-08-10T08:02:00.000Z');
  const timeB = Date.parse('2026-08-10T08:02:01.000Z');
  const matching = comparison.frameSetAudit({
    production: [{observedAtEpochMs: timeA}, {observedAtEpochMs: timeB}],
    kanameishi: [{observedAtEpochMs: timeA}, {observedAtEpochMs: timeB}],
    srev: [{observedAtEpochMs: timeA}, {observedAtEpochMs: timeB}],
  });
  assert.equal(matching.sameFrameSet, true);

  const missing = comparison.frameSetAudit({
    production: [{observedAtEpochMs: timeA}, {observedAtEpochMs: timeB}],
    kanameishi: [{observedAtEpochMs: timeA}],
    srev: [{observedAtEpochMs: timeA}, {observedAtEpochMs: timeB}],
  });
  assert.equal(missing.sameFrameSet, false);
  assert.deepEqual(missing.missingEpochMsByAlgorithm.kanameishi, [timeB]);
});

test('station membership changes are detected even when phase counts do not change', () => {
  const frames = [
    {
      frameIndex: 0,
      observedAt: '2026-08-10T08:02:00.000Z',
      observedAtEpochMs: Date.parse('2026-08-10T08:02:00.000Z'),
      sources: [{
        valid: true,
        sourceId: 1,
        latitude: 32.5,
        longitude: 130.6,
        depthKm: 10,
        originTimeEpochMs: Date.parse('2026-08-10T08:02:00.000Z'),
        effectiveStationCount: 2,
        weightSum: 2,
        score: 1,
        errorLevel: 1,
        waveCounts: {P: 1, S: 1, O: 0, L: 0},
        memberStationIds: ['A', 'B'],
      }],
    },
    {
      frameIndex: 1,
      observedAt: '2026-08-10T08:02:01.000Z',
      observedAtEpochMs: Date.parse('2026-08-10T08:02:01.000Z'),
      sources: [{
        valid: true,
        sourceId: 1,
        latitude: 32.5,
        longitude: 130.6,
        depthKm: 10,
        originTimeEpochMs: Date.parse('2026-08-10T08:02:00.000Z'),
        effectiveStationCount: 2,
        weightSum: 2,
        score: 1,
        errorLevel: 1,
        waveCounts: {P: 1, S: 1, O: 0, L: 0},
        memberStationIds: ['A', 'C'],
      }],
    },
  ];
  const summary = comparison.summarizeAlgorithm('test', 'test', frames, {
    latitude: 32.5,
    longitude: 130.6,
    depthKm: 10,
    originTimeEpochMs: Date.parse('2026-08-10T08:02:00.000Z'),
  });
  assert.equal(summary.stability.phaseCountChangedFrameCount, 0);
  assert.equal(summary.stability.membershipChangedFrameCount, 1);
  assert.equal(summary.stability.membershipComparedFrameCount, 1);
  assert.deepEqual(summary.frames[1].primary.memberStationIds, ['A', 'C']);
});

test('srev detection-list positions produce real P/S/O counts and preserve empty values', () => {
  const state = {
    sources: [{lat: 32.5, lon: 130.6, depthKm: 10, originTime: 100}],
    activeIds: [{id: 42, bestError: 2, error: 3, appliedCount: 4}],
    permittedStations: 4,
    estimatedPhaseStations: [
      {code: 'P1', phase: 'p', primaryTime: 101, pArrivalTime: 100, raw: [0, 0, 1]},
      {code: 'S1', phase: 's', primaryTime: 102, sArrivalTime: 100, raw: [0, 0, 1]},
      {code: 'O1', phase: '', primaryTime: '', pArrivalTime: '', raw: [0, 0, 1]},
      {code: 'OTHER', phase: 'p', primaryTime: 103, pArrivalTime: 100, raw: [0, 0, 2]},
    ],
    scratch: {hyp: {phase: 'end1', calcCount: ''}},
  };
  const [source] = srev.sourceDiagnostics(state);
  assert.deepEqual(source.waveCounts, {P: 1, S: 1, O: 1, L: 0});
  assert.equal(source.effectiveStationCount, 2);
  assert.equal(source.stations.length, 3);
  assert.equal(source.stations[2].observedArrivalSecondsSince2000, null);
  assert.equal(source.searchIterationCount, null);

  const [emptySource] = srev.sourceDiagnostics({
    ...state,
    sources: [{lat: '', lon: '', depthKm: '', originTime: ''}],
    activeIds: [{id: 42, bestError: '', error: '', appliedCount: ''}],
  });
  assert.equal(emptySource.valid, false);
  assert.equal(emptySource.latitude, null);
  assert.equal(emptySource.longitude, null);
  assert.equal(emptySource.depthKm, null);
  assert.equal(emptySource.originTimeEpochMs, null);
  assert.equal(emptySource.score, null);
  assert.equal(emptySource.errorLevel, null);
  assert.equal(emptySource.assignedStationCount, null);
});

test('fixed srev PRNG seed yields a reproducible sequence', () => {
  const first = srev.createDeterministicRandom(20260810);
  const second = srev.createDeterministicRandom(20260810);
  const firstValues = Array.from({length: 20}, () => first.next());
  const secondValues = Array.from({length: 20}, () => second.next());
  assert.deepEqual(firstValues, secondValues);
  assert.equal(first.drawCount(), 20);
  assert.equal(second.drawCount(), 20);
  assert.throws(() => srev.normalizeRandomSeed(-1), /Random seed/);
  assert.throws(() => srev.normalizeRandomSeed(4294967296), /Random seed/);
});
