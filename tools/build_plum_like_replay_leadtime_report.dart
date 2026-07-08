import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/calculator.dart';
import 'package:flutterrhythmquake/core/source_estimation/static_intensity_attenuation.dart';
import 'package:flutterrhythmquake/services/sources/jp_shindo_scale.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';

import '../test/support/nied_replay_fixture.dart';
import '../test/support/source_estimation_benchmark.dart';

const _defaultFixtureDirectory = 'test/fixtures/source_estimation';
const _defaultOutputPath = '.dart_tool/plum_like_replay_leadtime/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_like_replay_leadtime.generated.md';

const _defaultCaseIds = {
  '20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21',
  '20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8',
  '20260627_fukushima_aizu_m36_jma_equake17',
  '20260628_iwate_offshore_m41_jma',
  '20260624_fukushima_aizu_m32_jma_eq5',
  '20260625_iwate_offshore_m32_jma',
  '20260622_kushiro_offshore_m30_jma',
};

Future<void> main(List<String> args) async {
  final fixtureDirectory =
      _argument(args, '--fixture-directory') ?? _defaultFixtureDirectory;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;
  final caseIds = _caseIdsFromArgs(args) ?? _defaultCaseIds;

  final report = await buildPlumLikeReplayLeadtimeReportJson(
    fixtureDirectory: fixtureDirectory,
    caseIds: caseIds,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(plumLikeReplayLeadtimeMarkdown(report));

  stdout.writeln('wrote PLUM-like replay lead-time report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Future<Map<String, Object?>> buildPlumLikeReplayLeadtimeReportJson({
  String fixtureDirectory = _defaultFixtureDirectory,
  Set<String> caseIds = _defaultCaseIds,
}) async {
  final errors = <String>[];
  final skipped = <Map<String, Object?>>[];
  final cases = <Map<String, Object?>>[];
  final fixtureDir = Directory(fixtureDirectory);
  if (!fixtureDir.existsSync()) {
    return _emptyReport(
      errors: ['fixture_directory_missing:$fixtureDirectory'],
      fixtureDirectory: fixtureDirectory,
      caseIds: caseIds,
    );
  }

  final manifests =
      fixtureDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList(growable: false)
        ..sort((left, right) => left.path.compareTo(right.path));
  for (final manifest in manifests) {
    SourceEstimationReplayCase replayCase;
    try {
      replayCase = SourceEstimationReplayCase.fromManifest(
        manifest,
        workspaceRoot: Directory.current,
      );
    } catch (error) {
      continue;
    }
    if (!caseIds.contains(replayCase.caseId)) continue;
    if (!replayCase.captureDirectory.existsSync()) {
      skipped.add({
        'caseId': replayCase.caseId,
        'reason': 'capture_directory_missing',
        'captureDirectory': replayCase.captureDirectory.path,
      });
      continue;
    }
    final captureCompleteness = _captureCompleteness(replayCase);
    final failedGifCount = captureCompleteness['failedGifCount'] as int?;
    if (failedGifCount != null && failedGifCount > 0) {
      skipped.add({
        'caseId': replayCase.caseId,
        'reason': 'capture_manifest_failed_gifs',
        'captureDirectory': replayCase.captureDirectory.path,
        'failedGifCount': failedGifCount,
        if (captureCompleteness['downloadedGifCount'] != null)
          'downloadedGifCount': captureCompleteness['downloadedGifCount'],
        if (captureCompleteness['expectedGifCount'] != null)
          'expectedGifCount': captureCompleteness['expectedGifCount'],
      });
      continue;
    }
    try {
      cases.add(await _evaluateCase(replayCase));
    } catch (error) {
      skipped.add({
        'caseId': replayCase.caseId,
        'reason': 'case_evaluation_failed',
        'error': error.toString(),
      });
    }
  }

  if (cases.isEmpty) errors.add('no_replay_cases_evaluated');
  final missingCaseIds = caseIds.difference({
    for (final entry in cases) entry['caseId'].toString(),
    for (final entry in skipped) entry['caseId'].toString(),
  });
  if (missingCaseIds.isNotEmpty) {
    errors.add('case_ids_not_found:${missingCaseIds.join(',')}');
  }

  return {
    'schemaVersion': 'plum_like_replay_leadtime_report_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'policy': const {
      'split': 'diagnostic_replay',
      'frozenTestEvaluated': false,
      'productionReady': false,
      'productionUiConnected': false,
      'sourceIndependent': true,
      'usesSourceLatitudeLongitudeDepthMagnitude': false,
      'temporalSemantics':
          'real replay frames from jma_s GIF observations; not synthetic reveal',
      'surfaceInputOnly': true,
    },
    'inputs': {
      'fixtureDirectory': fixtureDirectory,
      'caseIds': caseIds.toList()..sort(),
      'layers': const ['jma_s'],
      'predictor': const {
        'radiusKm': 30.0,
        'dampingPer10Km': 0.25,
        'minimumEvidenceCount': 1,
      },
    },
    'summary': _summary(cases),
    'thresholds': _thresholdSummary(cases),
    'evidenceGateComparison': _evidenceGateSummary(cases),
    'persistenceGateComparison': _persistenceGateSummary(cases),
    'tuningGridComparison': _tuningGridSummary(cases),
    'cases': cases,
    'skippedCases': skipped,
    'errors': errors,
  };
}

Map<String, Object?> _captureCompleteness(
  SourceEstimationReplayCase replayCase,
) {
  final manifest = File(
    '${replayCase.captureDirectory.path}/capture_manifest.json',
  );
  if (!manifest.existsSync()) return const {};
  try {
    final decoded = jsonDecode(manifest.readAsStringSync());
    if (decoded is! Map<String, Object?>) return const {};
    return {
      'expectedGifCount': _intOrNull(decoded['expectedGifCount']),
      'downloadedGifCount': _intOrNull(decoded['downloadedGifCount']),
      'failedGifCount': _intOrNull(decoded['failedGifCount']),
    };
  } catch (_) {
    return const {};
  }
}

Future<Map<String, Object?>> _evaluateCase(
  SourceEstimationReplayCase replayCase,
) async {
  final service = LmoniImageService()..start();
  var latestStations = const <NiedStation>[];
  Completer<void>? stationFrameReady;
  final subscription = service.stationStream.listen((stations) {
    if (stations == null) return;
    latestStations = stations;
    stationFrameReady?.complete();
  });

  final states = <String, _StationThresholdState>{};
  var requestedFrames = 0;
  var decodedFrames = 0;
  var stationFrameCount = 0;
  var noPredictionStationFrameCount = 0;
  var maxObservedShindo = -3.0;
  final statesByGate = {
    for (final gate in _evidenceGateCounts)
      _gateLabel(gate): <String, _StationThresholdState>{},
  };
  final statesByPersistence = {
    for (final frames in _persistenceFrameCounts)
      _persistenceLabel(frames): <String, _StationThresholdState>{},
  };
  final statesByTuning = {
    for (final config in _tuningConfigs)
      config.label: <String, _StationThresholdState>{},
  };
  try {
    for (
      var observedAt = replayCase.startTimeJst;
      !observedAt.isAfter(replayCase.endTimeJst);
      observedAt = observedAt.add(const Duration(seconds: 1))
    ) {
      requestedFrames++;
      final surface = await decodeNiedGifFile(
        File(
          '${replayCase.captureDirectory.path}${Platform.pathSeparator}'
          '${replayCase.gifFileName(observedAt, 'jma_s')}',
        ),
      );
      if (surface == null) continue;
      stationFrameReady = Completer<void>();
      service.processPixels(
        surface.packedRgb,
        surfaceGifBytes: surface.gifBytes,
        dataTime: observedAt,
      );
      await stationFrameReady.future;
      stationFrameReady = null;
      decodedFrames++;

      final observedStations = [
        for (final station in latestStations)
          if (_stationShindo(station) != null)
            StaticIntensityStation(
              stationId: station.code,
              latitude: station.coordinate.latitude,
              longitude: station.coordinate.longitude,
              intensity: _stationShindo(station)!,
            ),
      ];
      if (observedStations.isEmpty) continue;
      for (final station in observedStations) {
        if (station.intensity > maxObservedShindo) {
          maxObservedShindo = station.intensity;
        }
      }
      for (final station in observedStations) {
        stationFrameCount++;
        final tuningPredictions = _predictTuningGrid(
          targetStation: station,
          observedStations: observedStations,
        );
        final prediction = tuningPredictions[_baselineTuningLabel]!;
        if (prediction.evidenceCount < 1) noPredictionStationFrameCount++;
        for (final gate in _evidenceGateCounts) {
          final gateStates = statesByGate[_gateLabel(gate)]!;
          final state = gateStates.putIfAbsent(
            station.stationId,
            () => _StationThresholdState(stationId: station.stationId),
          );
          if (gate == 1) states[station.stationId] = state;
          final predictedIntensity = prediction.evidenceCount >= gate
              ? prediction.intensity
              : -3.0;
          for (final threshold in _thresholds) {
            state.update(
              threshold: threshold,
              observedAt: observedAt,
              actualIntensity: station.intensity,
              predictedIntensity: predictedIntensity,
            );
          }
        }
        for (final config in _tuningConfigs) {
          final tuningStates = statesByTuning[config.label]!;
          final state = tuningStates.putIfAbsent(
            station.stationId,
            () => _StationThresholdState(stationId: station.stationId),
          );
          final tuningPrediction = tuningPredictions[config.label]!;
          for (final threshold in _thresholds) {
            state.update(
              threshold: threshold,
              observedAt: observedAt,
              actualIntensity: station.intensity,
              predictedIntensity: tuningPrediction.intensity,
            );
          }
        }
        for (final frames in _persistenceFrameCounts) {
          final persistenceStates =
              statesByPersistence[_persistenceLabel(frames)]!;
          final state = persistenceStates.putIfAbsent(
            station.stationId,
            () => _StationThresholdState(stationId: station.stationId),
          );
          for (final threshold in _thresholds) {
            state.updatePersistentPrediction(
              threshold: threshold,
              observedAt: observedAt,
              actualIntensity: station.intensity,
              predictedIntensity: prediction.intensity,
              requiredFrames: frames,
            );
          }
        }
      }
    }
  } finally {
    await subscription.cancel();
    service.stop();
    for (final station in latestStations) {
      station.terminate();
    }
  }

  final thresholdRows = {
    for (final threshold in _thresholds)
      threshold.label: _caseThresholdSummary(
        states.values.toList(growable: false),
        threshold,
      ),
  };
  final gateRows = {
    for (final gate in _evidenceGateCounts)
      _gateLabel(gate): {
        for (final threshold in _thresholds)
          threshold.label: _caseThresholdSummary(
            statesByGate[_gateLabel(gate)]!.values.toList(growable: false),
            threshold,
          ),
      },
  };
  final persistenceRows = {
    for (final frames in _persistenceFrameCounts)
      _persistenceLabel(frames): {
        for (final threshold in _thresholds)
          threshold.label: _caseThresholdSummary(
            statesByPersistence[_persistenceLabel(frames)]!.values.toList(
              growable: false,
            ),
            threshold,
          ),
      },
  };
  final tuningRows = {
    for (final config in _tuningConfigs)
      config.label: {
        for (final threshold in _thresholds)
          threshold.label: _caseThresholdSummary(
            statesByTuning[config.label]!.values.toList(growable: false),
            threshold,
          ),
      },
  };
  return {
    'caseId': replayCase.caseId,
    'caseType': replayCase.caseType.name,
    'truthSource': replayCase.truth?.source,
    'originTimeJst': replayCase.truth?.originTimeJst.toIso8601String(),
    'requestedFrameCount': requestedFrames,
    'decodedFrameCount': decodedFrames,
    'stationFrameCount': stationFrameCount,
    'noPredictionStationFrameCount': noPredictionStationFrameCount,
    'noPredictionStationFrameRate': stationFrameCount == 0
        ? 0.0
        : noPredictionStationFrameCount / stationFrameCount,
    'maxObservedShindo': maxObservedShindo,
    'thresholds': thresholdRows,
    'evidenceGates': gateRows,
    'persistenceGates': persistenceRows,
    'tuningGrid': tuningRows,
  };
}

Map<String, Object?> _caseThresholdSummary(
  List<_StationThresholdState> states,
  _Threshold threshold,
) {
  final leadTimes = <double>[];
  var actualStationCount = 0;
  var predictedStationCount = 0;
  var earlyOrOnTimeCount = 0;
  var lateCount = 0;
  var missedCount = 0;
  var falseAlarmCount = 0;
  for (final state in states) {
    final actualAt = state.actualFirstAt[threshold.label];
    final predictedAt = state.predictedFirstAt[threshold.label];
    if (actualAt != null) actualStationCount++;
    if (predictedAt != null) predictedStationCount++;
    if (actualAt != null && predictedAt != null) {
      final leadTime = actualAt.difference(predictedAt).inMilliseconds / 1000.0;
      leadTimes.add(leadTime);
      if (leadTime >= 0) {
        earlyOrOnTimeCount++;
      } else {
        lateCount++;
      }
    } else if (actualAt != null) {
      missedCount++;
    } else if (predictedAt != null) {
      falseAlarmCount++;
    }
  }
  return {
    'actualStationCount': actualStationCount,
    'predictedStationCount': predictedStationCount,
    'earlyOrOnTimeStationCount': earlyOrOnTimeCount,
    'lateStationCount': lateCount,
    'missedStationCount': missedCount,
    'falseAlarmStationCount': falseAlarmCount,
    'medianLeadSeconds': _percentile(leadTimes, 0.5),
    'p10LeadSeconds': _percentile(leadTimes, 0.1),
    'p90LeadSeconds': _percentile(leadTimes, 0.9),
  };
}

Map<String, Object?> _summary(List<Map<String, Object?>> cases) {
  final decodedFrames = cases.fold<int>(
    0,
    (sum, entry) => sum + _intValue(entry['decodedFrameCount']),
  );
  final stationFrames = cases.fold<int>(
    0,
    (sum, entry) => sum + _intValue(entry['stationFrameCount']),
  );
  final maxObserved = cases
      .map((entry) => _number(entry['maxObservedShindo']))
      .whereType<double>()
      .fold<double>(-3.0, (max, value) => value > max ? value : max);
  return {
    'caseCount': cases.length,
    'decodedFrameCount': decodedFrames,
    'stationFrameCount': stationFrames,
    'maxObservedShindo': maxObserved,
  };
}

Map<String, Object?> _thresholdSummary(List<Map<String, Object?>> cases) {
  return {
    for (final threshold in _thresholds)
      threshold.label: _aggregateThreshold(cases, threshold.label),
  };
}

Map<String, Object?> _evidenceGateSummary(List<Map<String, Object?>> cases) {
  return {
    for (final gate in _evidenceGateCounts)
      _gateLabel(gate): {
        for (final threshold in _thresholds)
          threshold.label: _aggregateGateThreshold(
            cases,
            gateLabel: _gateLabel(gate),
            thresholdLabel: threshold.label,
          ),
      },
  };
}

Map<String, Object?> _persistenceGateSummary(List<Map<String, Object?>> cases) {
  return {
    for (final frames in _persistenceFrameCounts)
      _persistenceLabel(frames): {
        for (final threshold in _thresholds)
          threshold.label: _aggregateNestedThreshold(
            cases,
            parentKey: 'persistenceGates',
            gateLabel: _persistenceLabel(frames),
            thresholdLabel: threshold.label,
          ),
      },
  };
}

Map<String, Object?> _tuningGridSummary(List<Map<String, Object?>> cases) {
  return {
    for (final config in _tuningConfigs)
      config.label: {
        'radiusKm': config.radiusKm,
        'dampingPer10Km': config.dampingPer10Km,
        for (final threshold in _thresholds)
          threshold.label: _aggregateNestedThreshold(
            cases,
            parentKey: 'tuningGrid',
            gateLabel: config.label,
            thresholdLabel: threshold.label,
          ),
      },
  };
}

Map<String, Object?> _aggregateGateThreshold(
  List<Map<String, Object?>> cases, {
  required String gateLabel,
  required String thresholdLabel,
}) {
  return _aggregateNestedThreshold(
    cases,
    parentKey: 'evidenceGates',
    gateLabel: gateLabel,
    thresholdLabel: thresholdLabel,
  );
}

Map<String, Object?> _aggregateNestedThreshold(
  List<Map<String, Object?>> cases, {
  required String parentKey,
  required String gateLabel,
  required String thresholdLabel,
}) {
  final projected = [
    for (final entry in cases)
      {
        'thresholds': {
          thresholdLabel: _map(
            _map(_map(entry[parentKey])[gateLabel])[thresholdLabel],
          ),
        },
      },
  ];
  return _aggregateThreshold(projected, thresholdLabel);
}

Map<String, Object?> _aggregateThreshold(
  List<Map<String, Object?>> cases,
  String label,
) {
  var actual = 0;
  var predicted = 0;
  var early = 0;
  var late = 0;
  var missed = 0;
  var falseAlarm = 0;
  final leadTimes = <double>[];
  for (final entry in cases) {
    final row = _map(_map(entry['thresholds'])[label]);
    actual += _intValue(row['actualStationCount']);
    predicted += _intValue(row['predictedStationCount']);
    early += _intValue(row['earlyOrOnTimeStationCount']);
    late += _intValue(row['lateStationCount']);
    missed += _intValue(row['missedStationCount']);
    falseAlarm += _intValue(row['falseAlarmStationCount']);
    final median = _number(row['medianLeadSeconds']);
    if (median != null) leadTimes.add(median);
  }
  return {
    'actualStationCount': actual,
    'predictedStationCount': predicted,
    'earlyOrOnTimeStationCount': early,
    'lateStationCount': late,
    'missedStationCount': missed,
    'falseAlarmStationCount': falseAlarm,
    'medianOfCaseMedianLeadSeconds': _percentile(leadTimes, 0.5),
    'stationRecall': actual == 0 ? 0.0 : early / actual,
    'stationFalseAlarmRatio': predicted == 0 ? 0.0 : falseAlarm / predicted,
  };
}

String plumLikeReplayLeadtimeMarkdown(Map<String, Object?> report) {
  final summary = _map(report['summary']);
  final buffer = StringBuffer()
    ..writeln('# PLUM-Like Replay Lead-Time Diagnostic')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Split: `diagnostic_replay`')
    ..writeln('- Frozen test evaluated: `false`')
    ..writeln('- Production ready: `false`')
    ..writeln('- Production UI connected: `false`')
    ..writeln('- Source independent: `true`')
    ..writeln('- Input layer: `jma_s`')
    ..writeln()
    ..writeln('## Summary')
    ..writeln()
    ..writeln('| Metric | Value |')
    ..writeln('| --- | ---: |')
    ..writeln('| Cases | ${summary['caseCount']} |')
    ..writeln('| Decoded frames | ${summary['decodedFrameCount']} |')
    ..writeln('| Station frames | ${summary['stationFrameCount']} |')
    ..writeln('| Max observed shindo | ${_fmt(summary['maxObservedShindo'])} |')
    ..writeln()
    ..writeln('## Thresholds')
    ..writeln()
    ..writeln(
      '| Threshold | Actual stations | Early/on-time | Missed | False alarms | Median case lead | Recall | False alarm ratio |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
  final thresholds = _map(report['thresholds']);
  for (final threshold in _thresholds) {
    final row = _map(thresholds[threshold.label]);
    buffer.writeln(
      '| `${threshold.label}` | ${row['actualStationCount']} | '
      '${row['earlyOrOnTimeStationCount']} | ${row['missedStationCount']} | '
      '${row['falseAlarmStationCount']} | '
      '${_fmt(row['medianOfCaseMedianLeadSeconds'])}s | '
      '${_pct(row['stationRecall'])} | '
      '${_pct(row['stationFalseAlarmRatio'])} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Evidence Gate Comparison')
    ..writeln()
    ..writeln(
      '| Gate | Shindo1 recall/false alarms | Shindo2 recall/false alarms | Shindo3 recall/false alarms | Shindo4 recall/false alarms | Shindo5- recall/false alarms |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: | ---: |');
  final gates = _map(report['evidenceGateComparison']);
  for (final gate in _evidenceGateCounts) {
    final rows = _map(gates[_gateLabel(gate)]);
    String cell(String label) {
      final row = _map(rows[label]);
      return '${_pct(row['stationRecall'])}/${row['falseAlarmStationCount']}';
    }

    buffer.writeln(
      '| `${_gateLabel(gate)}` | ${cell('shindo1')} | ${cell('shindo2')} | ${cell('shindo3')} | ${cell('shindo4')} | ${cell('shindo5-')} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Persistence Gate Comparison')
    ..writeln()
    ..writeln(
      '| Gate | Shindo1 recall/false alarms | Shindo2 recall/false alarms | Shindo3 recall/false alarms | Shindo4 recall/false alarms | Shindo5- recall/false alarms |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: | ---: |');
  final persistenceGates = _map(report['persistenceGateComparison']);
  for (final frames in _persistenceFrameCounts) {
    final rows = _map(persistenceGates[_persistenceLabel(frames)]);
    String cell(String label) {
      final row = _map(rows[label]);
      return '${_pct(row['stationRecall'])}/${row['falseAlarmStationCount']}';
    }

    buffer.writeln(
      '| `${_persistenceLabel(frames)}` | ${cell('shindo1')} | ${cell('shindo2')} | ${cell('shindo3')} | ${cell('shindo4')} | ${cell('shindo5-')} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Radius/Damping/Guard Grid Comparison')
    ..writeln()
    ..writeln(
      '| Config | Radius | Damping | Shindo1 recall/false alarms | Shindo2 recall/false alarms | Shindo3 recall/false alarms | Shindo4 recall/false alarms | Shindo5- recall/false alarms |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
  final tuningGrid = _map(report['tuningGridComparison']);
  for (final config in _tuningConfigs) {
    final rows = _map(tuningGrid[config.label]);
    String cell(String label) {
      final row = _map(rows[label]);
      return '${_pct(row['stationRecall'])}/${row['falseAlarmStationCount']}';
    }

    buffer.writeln(
      '| `${config.label}` | ${_fmt(config.radiusKm)} km | '
      '${_fmt(config.dampingPer10Km)} / 10km | '
      '${cell('shindo1')} | ${cell('shindo2')} | ${cell('shindo3')} | '
      '${cell('shindo4')} | ${cell('shindo5-')} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Cases')
    ..writeln()
    ..writeln(
      '| Case | Type | Frames | Max observed | No-prediction rate | Shindo1 lead/recall | Shindo2 lead/recall | Shindo3 lead/recall |',
    )
    ..writeln('| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |');
  for (final rawCase in _list(report['cases'])) {
    final entry = _map(rawCase);
    final thresholds = _map(entry['thresholds']);
    String cell(String label) {
      final row = _map(thresholds[label]);
      return '${_fmt(row['medianLeadSeconds'])}s/${_pct(_caseRecall(row))}';
    }

    buffer.writeln(
      '| `${entry['caseId']}` | `${entry['caseType']}` | '
      '${entry['decodedFrameCount']} | ${_fmt(entry['maxObservedShindo'])} | '
      '${_pct(entry['noPredictionStationFrameRate'])} | '
      '${cell('shindo1')} | ${cell('shindo2')} | ${cell('shindo3')} |',
    );
  }
  final skipped = _list(report['skippedCases']);
  if (skipped.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Skipped')
      ..writeln()
      ..writeln('| Case | Reason |')
      ..writeln('| --- | --- |');
    for (final raw in skipped) {
      final entry = _map(raw);
      buffer.writeln('| `${entry['caseId']}` | `${entry['reason']}` |');
    }
  }
  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- This is the first real replay-frame PLUM-like diagnostic and does not use source coordinates.',
    )
    ..writeln(
      '- It measures station-threshold lead time inside local GIF captures, not JMA final catalog station intensity.',
    )
    ..writeln(
      '- Evidence-count, persistence, radius and damping gates are diagnostic only; select an operating point only after expanding the replay set.',
    )
    ..writeln(
      '- Next step is to use the radius/damping grid to choose a false-positive control gate before frozen-test evaluation.',
    )
    ..writeln();
  return buffer.toString();
}

class _StationThresholdState {
  final String stationId;
  final actualFirstAt = <String, DateTime>{};
  final predictedFirstAt = <String, DateTime>{};
  final _predictionRuns = <String, int>{};

  _StationThresholdState({required this.stationId});

  void update({
    required _Threshold threshold,
    required DateTime observedAt,
    required double actualIntensity,
    required double predictedIntensity,
  }) {
    if (actualIntensity >= threshold.value) {
      actualFirstAt.putIfAbsent(threshold.label, () => observedAt);
    }
    if (predictedIntensity >= threshold.value) {
      predictedFirstAt.putIfAbsent(threshold.label, () => observedAt);
    }
  }

  void updatePersistentPrediction({
    required _Threshold threshold,
    required DateTime observedAt,
    required double actualIntensity,
    required double predictedIntensity,
    required int requiredFrames,
  }) {
    if (actualIntensity >= threshold.value) {
      actualFirstAt.putIfAbsent(threshold.label, () => observedAt);
    }
    final label = threshold.label;
    if (predictedIntensity >= threshold.value) {
      final run = (_predictionRuns[label] ?? 0) + 1;
      _predictionRuns[label] = run;
      if (run >= requiredFrames) {
        predictedFirstAt.putIfAbsent(label, () => observedAt);
      }
    } else {
      _predictionRuns[label] = 0;
    }
  }
}

class _Threshold {
  final String label;
  final double value;

  const _Threshold(this.label, this.value);
}

const _thresholds = [
  _Threshold('shindo1', 0.5),
  _Threshold('shindo2', 1.5),
  _Threshold('shindo3', 2.5),
  _Threshold('shindo4', 3.5),
  _Threshold('shindo5-', 4.5),
];

const _evidenceGateCounts = [1, 2, 3];

String _gateLabel(int count) => 'min_evidence_$count';

const _persistenceFrameCounts = [1, 2, 3];

String _persistenceLabel(int frames) => 'persist_${frames}f';

const _baselineTuningLabel = 'r30_d0.25_baseline';

const _tuningConfigs = [
  _PlumTuningConfig('r15_d0.25', 15, 0.25),
  _PlumTuningConfig('r20_d0.25', 20, 0.25),
  _PlumTuningConfig(_baselineTuningLabel, 30, 0.25),
  _PlumTuningConfig('r15_d0.50', 15, 0.50),
  _PlumTuningConfig('r20_d0.50', 20, 0.50),
  _PlumTuningConfig('r30_d0.50', 30, 0.50),
  _PlumTuningConfig(
    'r30_d0.50_local_contrast_r20_w3.0',
    30,
    0.50,
    localContrastRadiusKm: 20,
    localContrastWeakMaxIntensity: 3.0,
    localContrastCapMargin: 0.5,
  ),
  _PlumTuningConfig('r15_d0.75', 15, 0.75),
  _PlumTuningConfig('r20_d0.75', 20, 0.75),
  _PlumTuningConfig('r30_d0.75', 30, 0.75),
  _PlumTuningConfig('r15_d1.00', 15, 1.00),
  _PlumTuningConfig('r20_d1.00', 20, 1.00),
  _PlumTuningConfig('r30_d1.00', 30, 1.00),
];

Map<String, PlumLikeIntensityPrediction> _predictTuningGrid({
  required StaticIntensityStation targetStation,
  required List<StaticIntensityStation> observedStations,
}) {
  final scratch = {
    for (final config in _tuningConfigs) config.label: _PlumPredictionScratch(),
  };
  for (final observed in observedStations) {
    if (observed.stationId == targetStation.stationId) continue;
    final distance = QuakeCalculator.haversineDistance(
      targetStation.latitude,
      targetStation.longitude,
      observed.latitude,
      observed.longitude,
    );
    if (distance > _maximumTuningRadiusKm) continue;
    for (final config in _tuningConfigs) {
      if (distance > config.radiusKm) continue;
      scratch[config.label]!.add(
        observedStationId: observed.stationId,
        observedIntensity: observed.intensity,
        distanceKm: distance,
        dampingPer10Km: config.dampingPer10Km,
      );
    }
  }
  return {
    for (final config in _tuningConfigs)
      config.label: config.applyLocalContrastGuard(
        targetStation: targetStation,
        observedStations: observedStations,
        prediction: scratch[config.label]!.toPrediction(),
      ),
  };
}

const _maximumTuningRadiusKm = 30.0;

class _PlumTuningConfig {
  final String label;
  final double radiusKm;
  final double dampingPer10Km;
  final double? localContrastRadiusKm;
  final double? localContrastWeakMaxIntensity;
  final double localContrastCapMargin;

  const _PlumTuningConfig(
    this.label,
    this.radiusKm,
    this.dampingPer10Km, {
    this.localContrastRadiusKm,
    this.localContrastWeakMaxIntensity,
    this.localContrastCapMargin = 0.5,
  });

  PlumLikeIntensityPrediction applyLocalContrastGuard({
    required StaticIntensityStation targetStation,
    required List<StaticIntensityStation> observedStations,
    required PlumLikeIntensityPrediction prediction,
  }) {
    final guardRadius = localContrastRadiusKm;
    final weakMax = localContrastWeakMaxIntensity;
    if (guardRadius == null || weakMax == null || prediction.intensity < 3.5) {
      return prediction;
    }
    var nearestDistance = double.infinity;
    var nearestIntensity = -double.infinity;
    for (final observed in observedStations) {
      if (observed.stationId == targetStation.stationId) continue;
      final distance = QuakeCalculator.haversineDistance(
        targetStation.latitude,
        targetStation.longitude,
        observed.latitude,
        observed.longitude,
      );
      if (distance > guardRadius || distance >= nearestDistance) continue;
      nearestDistance = distance;
      nearestIntensity = observed.intensity;
    }
    if (nearestIntensity > weakMax) return prediction;
    return PlumLikeIntensityPrediction(
      intensity:
          prediction.intensity < nearestIntensity + localContrastCapMargin
          ? prediction.intensity
          : nearestIntensity + localContrastCapMargin,
      evidenceCount: prediction.evidenceCount,
      nearestEvidenceDistanceKm: prediction.nearestEvidenceDistanceKm,
      strongestEvidenceStationId: prediction.strongestEvidenceStationId,
    );
  }
}

class _PlumPredictionScratch {
  var evidenceCount = 0;
  var nearestDistanceKm = double.infinity;
  var bestIntensity = -double.infinity;
  String? bestStationId;

  void add({
    required String observedStationId,
    required double observedIntensity,
    required double distanceKm,
    required double dampingPer10Km,
  }) {
    evidenceCount++;
    if (distanceKm < nearestDistanceKm) nearestDistanceKm = distanceKm;
    final propagated = observedIntensity - dampingPer10Km * (distanceKm / 10);
    if (propagated > bestIntensity) {
      bestIntensity = propagated;
      bestStationId = observedStationId;
    }
  }

  PlumLikeIntensityPrediction toPrediction() {
    if (evidenceCount == 0) {
      return PlumLikeIntensityPrediction(
        intensity: -3.0,
        evidenceCount: 0,
        nearestEvidenceDistanceKm: nearestDistanceKm,
      );
    }
    return PlumLikeIntensityPrediction(
      intensity: bestIntensity,
      evidenceCount: evidenceCount,
      nearestEvidenceDistanceKm: nearestDistanceKm,
      strongestEvidenceStationId: bestStationId,
    );
  }
}

double? _stationShindo(NiedStation station) {
  final shindo = station.gifObservation?.shindo;
  if (shindo != null && shindo.isFinite) return shindo;
  if (station.detectLevel >= 0) {
    return JpShindoScale.rawShindoFromKanameishiLevel(station.detectLevel);
  }
  return null;
}

Map<String, Object?> _emptyReport({
  required List<String> errors,
  required String fixtureDirectory,
  required Set<String> caseIds,
}) => {
  'schemaVersion': 'plum_like_replay_leadtime_report_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'inputs': {
    'fixtureDirectory': fixtureDirectory,
    'caseIds': caseIds.toList()..sort(),
  },
  'summary': const {},
  'thresholds': const {},
  'cases': const [],
  'skippedCases': const [],
  'errors': errors,
};

String? _argument(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == name && i + 1 < args.length) return args[i + 1];
    if (arg.startsWith('$name=')) return arg.substring(name.length + 1);
  }
  return null;
}

Set<String>? _caseIdsFromArgs(List<String> args) {
  final values = <String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--case-id' && i + 1 < args.length) values.add(args[i + 1]);
    if (arg.startsWith('--case-id=')) {
      values.add(arg.substring('--case-id='.length));
    }
  }
  return values.isEmpty ? null : values;
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

List<Object?> _list(Object? value) => value is List ? value : const [];

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _intOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _percentile(List<double> values, double q) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final position = (sorted.length - 1) * q;
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sorted[lower];
  final fraction = position - lower;
  return sorted[lower] * (1 - fraction) + sorted[upper] * fraction;
}

double _caseRecall(Map<String, Object?> row) {
  final actual = _intValue(row['actualStationCount']);
  if (actual == 0) return 0;
  return _intValue(row['earlyOrOnTimeStationCount']) / actual;
}

String _fmt(Object? value) {
  final number = _number(value);
  return number == null ? '-' : number.toStringAsFixed(1);
}

String _pct(Object? value) {
  final number = _number(value);
  return number == null ? '-' : '${(number * 100).toStringAsFixed(1)}%';
}
