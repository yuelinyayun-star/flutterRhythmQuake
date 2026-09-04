import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutterrhythmquake/core/nied_replay_logger.dart';
import 'package:flutterrhythmquake/core/source_estimation/jma2001_travel_time_approximation.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimator.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_event_tracker.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_source_estimation_driver.dart';

import 'support/nied_replay_fixture.dart';

void main() {
  const runPolicyMatrix = bool.fromEnvironment(
    'CURRENT_CAPTURE_WRITEBACK_POLICY_MATRIX',
  );
  if (runPolicyMatrix) {
    test(
      'compares NIED HYP writeback policies across captures',
      () async {
        await _runWritebackPolicyMatrix();
      },
      timeout: const Timeout(Duration(minutes: 20)),
    );
    return;
  }

  test('analyzes current downloaded NIED capture windows', () async {
    const captureOverride = String.fromEnvironment('CURRENT_CAPTURE_DIRECTORY');
    const caseIdOverride = String.fromEnvironment('CURRENT_CAPTURE_CASE_ID');
    const caseLabelOverride = String.fromEnvironment(
      'CURRENT_CAPTURE_CASE_LABEL',
    );
    const startOverride = String.fromEnvironment('CURRENT_CAPTURE_START_JST');
    const endOverride = String.fromEnvironment('CURRENT_CAPTURE_END_JST');
    const truthLatitudeOverride = String.fromEnvironment(
      'CURRENT_CAPTURE_TRUTH_LATITUDE',
    );
    const truthLongitudeOverride = String.fromEnvironment(
      'CURRENT_CAPTURE_TRUTH_LONGITUDE',
    );
    const outputDirectoryOverride = String.fromEnvironment(
      'CURRENT_CAPTURE_OUTPUT_DIRECTORY',
    );
    const writebackPolicyOverride = String.fromEnvironment(
      'CURRENT_CAPTURE_WRITEBACK_POLICY',
      defaultValue: 'scratch_1_7',
    );
    const searchScheduleOverride = String.fromEnvironment(
      'CURRENT_CAPTURE_SEARCH_SCHEDULE',
      defaultValue: 'scratch_five_stage',
    );
    const compactReport = bool.fromEnvironment(
      'CURRENT_CAPTURE_COMPACT_REPORT',
    );
    final writebackExperiment = _writebackExperiment(
      writebackPolicyOverride,
      searchSchedule: _searchSchedule(searchScheduleOverride),
    );
    StationEventTracker.instance.setNiedEstimator(
      writebackExperiment.estimator,
    );
    addTearDown(StationEventTracker.instance.useDefaultNiedEstimator);
    final captureDirectory = Directory(
      captureOverride.isEmpty
          ? r'C:\Users\Rhythm\Desktop\nied_capture_20260630_110914\raw\jma_s'
          : captureOverride,
    );
    expect(captureDirectory.existsSync(), isTrue);

    final defaultCases = [
      _ReplayCase(
        id: '20260630_fukushima_hamadori_m34',
        label: '福島県浜通り M3.4',
        startJst: DateTime(2026, 6, 30, 12, 8, 45),
        endJst: DateTime(2026, 6, 30, 12, 9, 50),
        truth: const LatLng(37.3, 141.0),
        equake: const LatLng(37.35, 140.97),
      ),
      _ReplayCase(
        id: '20260630_iwate_offshore_m36',
        label: '岩手県沖 M3.6',
        startJst: DateTime(2026, 6, 30, 12, 24, 20),
        endJst: DateTime(2026, 6, 30, 12, 25, 55),
        truth: const LatLng(40.4, 142.2),
        equake: const LatLng(40.43, 142.29),
      ),
      _ReplayCase(
        id: '20260630_noise_1215',
        label: '12:15 noise trigger',
        startJst: DateTime(2026, 6, 30, 12, 15, 0),
        endJst: DateTime(2026, 6, 30, 12, 15, 45),
        truth: null,
        equake: null,
      ),
    ];
    final cases = startOverride.isEmpty
        ? defaultCases
        : [
            _ReplayCase(
              id: caseIdOverride,
              label: caseLabelOverride,
              startJst: DateTime.parse(startOverride),
              endJst: DateTime.parse(endOverride),
              truth: LatLng(
                double.parse(truthLatitudeOverride),
                double.parse(truthLongitudeOverride),
              ),
              equake: null,
            ),
          ];

    final reports = <Map<String, Object?>>[];
    for (final replayCase in cases) {
      reports.add(
        await _runCase(
          captureDirectory,
          replayCase,
          compactReport: compactReport,
          estimator: writebackExperiment.estimator,
        ),
      );
    }

    final outDir = Directory(
      outputDirectoryOverride.isEmpty
          ? '.dart_tool/current_capture_replay_analysis'
          : outputDirectoryOverride,
    )..createSync(recursive: true);
    final jsonFile = File('${outDir.path}/report.json');
    jsonFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'schemaVersion': 'current_capture_replay_analysis_v1', 'createdAtUtc': DateTime.now().toUtc().toIso8601String(), 'captureDirectory': captureDirectory.path, 'writebackPolicy': writebackExperiment.label, 'compactReport': compactReport, 'cases': reports})}\n',
    );
    final mdFile = File('${outDir.path}/report.md');
    mdFile.writeAsStringSync(_markdown(reports));
  });
}

Future<void> _runWritebackPolicyMatrix() async {
  const outputDirectory = String.fromEnvironment(
    'CURRENT_CAPTURE_OUTPUT_DIRECTORY',
    defaultValue: '.dart_tool/nied_hyp_writeback_policy_matrix',
  );
  final cases = <({String directory, _ReplayCase replayCase})>[
    (
      directory:
          'tmp/captures/20260626_yamanashi_east_fuji_five_lakes_m56_jma_p2p',
      replayCase: _ReplayCase(
        id: '20260626_yamanashi_east_fuji_five_lakes_m56',
        label: '山梨県東部・富士五湖 M5.6',
        startJst: DateTime(2026, 6, 26, 22, 28, 30),
        endJst: DateTime(2026, 6, 26, 22, 31),
        truth: const LatLng(35.6, 139.0),
        equake: null,
      ),
    ),
    (
      directory: 'tmp/captures/20260628_iwate_offshore_m41_jma',
      replayCase: _ReplayCase(
        id: '20260628_iwate_offshore_m41',
        label: '岩手県沖 M4.1',
        startJst: DateTime(2026, 6, 28, 14, 39, 7),
        endJst: DateTime(2026, 6, 28, 14, 41, 37),
        truth: const LatLng(40.1, 142.4),
        equake: null,
      ),
    ),
    (
      directory: 'tmp/captures/20260702_fukushima_aizu_m46_jma_p2p',
      replayCase: _ReplayCase(
        id: '20260702_fukushima_aizu_m46',
        label: '福島県会津 M4.6',
        startJst: DateTime(2026, 7, 2, 20, 47, 30),
        endJst: DateTime(2026, 7, 2, 20, 50),
        truth: const LatLng(37.2, 139.5),
        equake: null,
      ),
    ),
    (
      directory: 'tmp/captures/20260702_shizuoka_west_m36_jma_p2p',
      replayCase: _ReplayCase(
        id: '20260702_shizuoka_west_m36',
        label: '静岡県西部 M3.6',
        startJst: DateTime(2026, 7, 2, 20, 12, 30),
        endJst: DateTime(2026, 7, 2, 20, 15),
        truth: const LatLng(34.7, 137.5),
        equake: null,
      ),
    ),
    (
      directory: 'tmp/captures/20260718_chiba_east_offshore_m43_jma',
      replayCase: _ReplayCase(
        id: '20260718_chiba_east_offshore_m43',
        label: '千葉県東方沖 M4.3',
        startJst: DateTime(2026, 7, 18, 4, 44, 52),
        endJst: DateTime(2026, 7, 18, 4, 47, 22),
        truth: const LatLng(35.7, 141.1),
        equake: null,
      ),
    ),
  ];
  const policyOverride = String.fromEnvironment(
    'CURRENT_CAPTURE_POLICY_MATRIX_POLICIES',
  );
  const searchScheduleOverride = String.fromEnvironment(
    'CURRENT_CAPTURE_SEARCH_SCHEDULE',
    defaultValue: 'scratch_five_stage',
  );
  const fullReport = bool.fromEnvironment('CURRENT_CAPTURE_FULL_REPORT');
  const caseIdOverride = String.fromEnvironment(
    'CURRENT_CAPTURE_POLICY_MATRIX_CASE_IDS',
  );
  final searchSchedule = _searchSchedule(searchScheduleOverride);
  final selectedCases = caseIdOverride.isEmpty
      ? cases
      : cases
            .where(
              (item) => caseIdOverride
                  .split(',')
                  .map((value) => value.trim())
                  .contains(item.replayCase.id),
            )
            .toList(growable: false);
  expect(
    selectedCases,
    isNotEmpty,
    reason: 'No policy-matrix capture matches: $caseIdOverride',
  );
  final policies = policyOverride.isEmpty
      ? const <String>[
          'scratch_1_7',
          'historical_1_0',
          'current_non_increasing',
        ]
      : policyOverride
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
  final runs = <Map<String, Object?>>[];
  try {
    for (final item in selectedCases) {
      final directory = Directory(item.directory);
      expect(directory.existsSync(), isTrue, reason: item.directory);
      for (final policy in policies) {
        final experiment = _writebackExperiment(
          policy,
          searchSchedule: searchSchedule,
        );
        StationEventTracker.instance.setNiedEstimator(experiment.estimator);
        final report = await _runCase(
          directory,
          item.replayCase,
          compactReport: !fullReport,
          estimator: experiment.estimator,
        );
        final firstEstimateFrame =
            (report['firstEstimateFrame']! as Map<String, Object?>);
        final firstEstimate =
            firstEstimateFrame['estimate']! as Map<String, Object?>;
        final firstDiagnostics =
            firstEstimate['diagnostics']! as Map<String, Object?>;
        expect(
          firstDiagnostics['search_result_writeback_policy'],
          experiment.estimator.writebackPolicy.name,
        );
        expect(
          firstDiagnostics['historical_minimum_score_multiplier'],
          experiment.estimator.historicalMinimumMultiplier,
        );
        runs.add({
          'caseId': item.replayCase.id,
          'caseLabel': item.replayCase.label,
          'captureDirectory': directory.path,
          'policy': experiment.label,
          'summary': _matrixRunSummary(report),
          'report': report,
        });
      }
    }
  } finally {
    StationEventTracker.instance.useDefaultNiedEstimator();
  }

  final outDir = Directory(outputDirectory)..createSync(recursive: true);
  File('${outDir.path}/report.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'schemaVersion': 'nied_hyp_writeback_policy_matrix_v1', 'createdAtUtc': DateTime.now().toUtc().toIso8601String(), 'searchSchedule': searchSchedule.name, 'runs': runs})}\n',
  );
  File('${outDir.path}/report.md').writeAsStringSync(_matrixMarkdown(runs));
}

Map<String, Object?> _matrixRunSummary(Map<String, Object?> report) {
  final frames = (report['frames'] as List).cast<Map<String, Object?>>();
  final estimateFrames = frames
      .where((frame) => frame['estimate'] != null)
      .toList(growable: false);
  if (estimateFrames.isEmpty) {
    return const <String, Object?>{'estimateFrameCount': 0};
  }
  final finalEstimate =
      estimateFrames.last['estimate']! as Map<String, Object?>;
  var acceptedCount = 0;
  var rejectedCount = 0;
  for (final frame in estimateFrames) {
    final estimate = frame['estimate']! as Map<String, Object?>;
    final diagnostics = estimate['diagnostics']! as Map<String, Object?>;
    if (diagnostics['search_result_accepted'] == true) {
      acceptedCount += 1;
    } else if (diagnostics['search_result_accepted'] == false) {
      rejectedCount += 1;
    }
  }
  final minErrorKm = (report['minErrorKm']! as num).toDouble();
  final finalErrorKm = (finalEstimate['errorKm']! as num).toDouble();
  final finalDiagnostics =
      finalEstimate['diagnostics']! as Map<String, Object?>;
  return <String, Object?>{
    'estimateFrameCount': estimateFrames.length,
    'acceptedFrameCount': acceptedCount,
    'rejectedFrameCount': rejectedCount,
    'minErrorKm': minErrorKm,
    'finalErrorKm': finalErrorKm,
    'finalMinusMinErrorKm': finalErrorKm - minErrorKm,
    'finalLatitude': finalEstimate['latitude'],
    'finalLongitude': finalEstimate['longitude'],
    'finalDepthKm': finalEstimate['depthKm'],
    'finalSupportingStationCount': finalEstimate['supportingStationCount'],
    'finalErrorLevel': finalDiagnostics['error_level'],
    'finalScore': finalDiagnostics['score'],
  };
}

String _matrixMarkdown(List<Map<String, Object?>> runs) {
  final buffer = StringBuffer()
    ..writeln('# NIED HYP writeback policy matrix')
    ..writeln()
    ..writeln(
      '| Event | Policy | Min km | Final km | Drift km | Depth | Accepted | Rejected | Final error level | Final score |',
    )
    ..writeln('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|');
  String number(Object? value, [int digits = 2]) =>
      value is num ? value.toDouble().toStringAsFixed(digits) : '-';
  for (final run in runs) {
    final summary = run['summary']! as Map<String, Object?>;
    buffer.writeln(
      '| ${run['caseLabel']} | ${run['policy']} | '
      '${number(summary['minErrorKm'])} | ${number(summary['finalErrorKm'])} | '
      '${number(summary['finalMinusMinErrorKm'])} | ${number(summary['finalDepthKm'], 0)} | '
      '${summary['acceptedFrameCount'] ?? 0} | ${summary['rejectedFrameCount'] ?? 0} | '
      '${number(summary['finalErrorLevel'])} | ${number(summary['finalScore'])} |',
    );
  }
  return buffer.toString();
}

Future<Map<String, Object?>> _runCase(
  Directory captureDirectory,
  _ReplayCase replayCase, {
  required bool compactReport,
  NiedDartHypSourceEstimator? estimator,
}) async {
  NiedReplayLogger.instance.resetForTest();
  StationEventTracker.instance.resetNied();
  if (estimator != null) {
    StationEventTracker.instance.setNiedEstimator(estimator);
  }
  final imageService = LmoniImageService()
    ..stop()
    ..start();
  final driver = NiedSourceEstimationDriver();

  List<dynamic>? latestStations;
  final sub = imageService.stationStream.listen((stations) {
    latestStations = stations;
  });

  final frames = <Map<String, Object?>>[];
  var missing = 0;
  for (
    var t = replayCase.startJst;
    !t.isAfter(replayCase.endJst);
    t = t.add(const Duration(seconds: 1))
  ) {
    final file = File(
      '${captureDirectory.path}${Platform.pathSeparator}'
      '${formatNiedTimeKey(t)}.jma_s.gif',
    );
    if (!file.existsSync()) {
      missing++;
      continue;
    }
    final decoded = await decodeNiedGifFile(file);
    if (decoded == null) {
      frames.add({
        'observedAtJst': t.toIso8601String(),
        'file': file.path,
        'decodeFailed': true,
      });
      continue;
    }
    final observedAt = _jstWallClockToUtc(t);
    imageService.processPixels(
      decoded.packedRgb,
      surfaceGifBytes: decoded.gifBytes,
      dataTime: observedAt,
      receivedAt: observedAt,
    );
    await Future<void>.delayed(Duration.zero);
    final stations = latestStations;
    if (stations == null) continue;
    final algorithmStopwatch = Stopwatch()..start();
    final detection = driver.processStations(
      stations.cast(),
      observedAt: observedAt,
    );
    algorithmStopwatch.stop();
    final event = StationEventTracker.instance.currentNiedEvent.value;
    final estimate = event?.estimate;
    final estimatePoint = estimate == null
        ? null
        : LatLng(estimate.latitude, estimate.longitude);
    frames.add({
      'observedAtJst': t.toIso8601String(),
      'detectionState': detection.state.name,
      'memberCount': detection.memberStationIds.length,
      'eventId': detection.eventId,
      'stage': event?.stageName,
      'algorithmRuntimeMicros': algorithmStopwatch.elapsedMicroseconds,
      'estimate': estimate == null
          ? null
          : {
              'latitude': estimate.latitude,
              'longitude': estimate.longitude,
              'depthKm': estimate.depthKm,
              'magnitude': estimate.magnitude,
              'confidence': estimate.confidence,
              'supportingStationCount': estimate.supportingStationCount,
              'method': estimate.method,
              'originTime': estimate.originTime?.toUtc().toIso8601String(),
              'errorKm': replayCase.truth == null
                  ? null
                  : _distanceKm(estimatePoint!, replayCase.truth!),
              'equakeErrorKm': replayCase.equake == null
                  ? null
                  : _distanceKm(estimatePoint!, replayCase.equake!),
              'truthActiveTimingProbe':
                  compactReport || replayCase.truth == null
                  ? null
                  : _truthActiveTimingProbe(estimate, replayCase.truth!),
              'diagnostics': compactReport
                  ? _compactDiagnostics(estimate.diagnostics)
                  : _snapshotReplayValue(estimate.diagnostics),
            },
      'metadata': compactReport ? null : _snapshotReplayValue(event?.metadata),
    });
  }

  await sub.cancel();
  imageService.stop();

  final estimateFrames = frames
      .where((frame) => frame['estimate'] != null)
      .toList(growable: false);
  Map<String, Object?>? finalEstimate;
  if (estimateFrames.isNotEmpty) {
    finalEstimate = estimateFrames.last['estimate'] as Map<String, Object?>;
  }
  final errors = estimateFrames
      .map((frame) => (frame['estimate'] as Map<String, Object?>)['errorKm'])
      .whereType<num>()
      .map((value) => value.toDouble())
      .toList(growable: false);

  return {
    'id': replayCase.id,
    'label': replayCase.label,
    'window': {
      'startJst': replayCase.startJst.toIso8601String(),
      'endJst': replayCase.endJst.toIso8601String(),
    },
    'truth': replayCase.truth == null
        ? null
        : {
            'latitude': replayCase.truth!.latitude,
            'longitude': replayCase.truth!.longitude,
          },
    'equake': replayCase.equake == null
        ? null
        : {
            'latitude': replayCase.equake!.latitude,
            'longitude': replayCase.equake!.longitude,
          },
    'processedFrameCount': frames.length,
    'missingFrameCount': missing,
    'estimateFrameCount': estimateFrames.length,
    'firstEstimateFrame': estimateFrames.isEmpty ? null : estimateFrames.first,
    'finalEstimate': finalEstimate,
    'minErrorKm': errors.isEmpty ? null : errors.reduce(math.min),
    'maxErrorKm': errors.isEmpty ? null : errors.reduce(math.max),
    'frames': frames,
    'findings': _findings(frames, replayCase),
  };
}

DateTime _jstWallClockToUtc(DateTime wallClock) => DateTime.utc(
  wallClock.year,
  wallClock.month,
  wallClock.day,
  wallClock.hour,
  wallClock.minute,
  wallClock.second,
  wallClock.millisecond,
  wallClock.microsecond,
).subtract(const Duration(hours: 9));

({NiedDartHypSourceEstimator estimator, String label}) _writebackExperiment(
  String value, {
  NiedHypSearchSchedule searchSchedule =
      NiedHypSearchSchedule.scratchViewerFiveStage,
}) {
  return switch (value) {
    'historical_1_05' => (
      estimator: NiedDartHypSourceEstimator(
        historicalMinimumMultiplier: 1.05,
        searchSchedule: searchSchedule,
      ),
      label: 'historical_minimum_times_1_05',
    ),
    'historical_1_1' => (
      estimator: NiedDartHypSourceEstimator(
        historicalMinimumMultiplier: 1.1,
        searchSchedule: searchSchedule,
      ),
      label: 'historical_minimum_times_1_1',
    ),
    'historical_1_2' => (
      estimator: NiedDartHypSourceEstimator(
        historicalMinimumMultiplier: 1.2,
        searchSchedule: searchSchedule,
      ),
      label: 'historical_minimum_times_1_2',
    ),
    'historical_1_4' => (
      estimator: NiedDartHypSourceEstimator(
        historicalMinimumMultiplier: 1.4,
        searchSchedule: searchSchedule,
      ),
      label: 'historical_minimum_times_1_4',
    ),
    'historical_1_0' => (
      estimator: NiedDartHypSourceEstimator(
        historicalMinimumMultiplier: 1.0,
        searchSchedule: searchSchedule,
      ),
      label: 'historical_minimum_times_1_0',
    ),
    'current_non_increasing' => (
      estimator: NiedDartHypSourceEstimator(
        writebackPolicy: NiedHypWritebackPolicy.nonIncreasingCurrent,
        searchSchedule: searchSchedule,
      ),
      label: 'non_increasing_current_score',
    ),
    _ => (
      estimator: NiedDartHypSourceEstimator(searchSchedule: searchSchedule),
      label: 'scratch_historical_minimum_times_1_7',
    ),
  };
}

NiedHypSearchSchedule _searchSchedule(String value) => switch (value) {
  'reference_broad_four_stage' => NiedHypSearchSchedule.referenceBroadFourStage,
  'scratch_with_broad_rescue' =>
    NiedHypSearchSchedule.scratchFiveStageWithBroadRescue,
  'scratch_joint_neighborhood' =>
    NiedHypSearchSchedule.scratchFiveStageJointNeighborhood,
  _ => NiedHypSearchSchedule.scratchViewerFiveStage,
};

Map<String, Object?> _compactDiagnostics(Map<String, Object?> diagnostics) {
  const keys = <String>[
    'elapsed_since_detection_id_created_s',
    'search_result_accepted',
    'historical_minimum_published_score',
    'search_result_writeback_policy',
    'search_schedule',
    'search_schedule_reference',
    'historical_minimum_score_multiplier',
    'score',
    'error_level',
    'rmse',
    'inactive_penalty',
    'effective_station_count',
    'search_candidate_score_call_count',
    'search_elapsed_ms',
    'travel_time_curve_frozen',
    'selected_detection_id',
    'nied_dart_hyp_report_num',
    'nied_dart_hyp_stable',
    'nied_dart_hyp_stable_update_count',
    'nied_dart_hyp_stable_update_threshold',
    'nied_dart_hyp_calculation_complete',
    'srev_kaizou_magnitude_supported',
    'srev_kaizou_magnitude',
    'srev_kaizou_magnitude_input_intensity',
    'srev_kaizou_magnitude_processed_intensity',
    'srev_kaizou_magnitude_branch',
    'srev_kaizou_magnitude_active_detection_count',
  ];
  return <String, Object?>{
    for (final key in keys)
      if (diagnostics.containsKey(key)) key: diagnostics[key],
  };
}

Map<String, Object?>? _truthActiveTimingProbe(
  SourceEstimate estimate,
  LatLng truth,
) {
  final rawPanels = estimate.diagnostics['travel_time_curve_panels'];
  if (rawPanels is! Iterable) return null;
  Map<Object?, Object?>? selectedPanel;
  for (final panel in rawPanels) {
    if (panel is Map && panel['selected'] == true) {
      selectedPanel = panel;
      break;
    }
  }
  final rawSamples = selectedPanel?['samples'];
  if (rawSamples is! Iterable) return null;
  final samples = <Map<String, Object?>>[];
  for (final raw in rawSamples) {
    if (raw is! Map) continue;
    final triggerStamp = raw['trigger_stamp'];
    final latitude = raw['latitude'];
    final longitude = raw['longitude'];
    if (triggerStamp is! num || latitude is! num || longitude is! num) continue;
    samples.add({
      'code': raw['code']?.toString() ?? '',
      'trigger_stamp': triggerStamp.toInt(),
      'latitude': latitude.toDouble(),
      'longitude': longitude.toDouble(),
      'wave': raw['wave']?.toString() == 'S' ? 'S' : 'P',
    });
  }
  if (samples.length < 5) return null;
  samples.sort((left, right) {
    final byTime = (left['trigger_stamp']! as int).compareTo(
      right['trigger_stamp']! as int,
    );
    return byTime != 0
        ? byTime
        : (left['code']! as String).compareTo(right['code']! as String);
  });
  final earliestStamp = samples.first['trigger_stamp']! as int;
  final rawConstraints = estimate.diagnostics['candidate_constraints'];
  final firstStationCode = rawConstraints is Map
      ? rawConstraints['first_station_code']?.toString()
      : null;
  Map<String, Object?>? firstStationSample;
  for (final sample in samples) {
    if (sample['code'] == firstStationCode) {
      firstStationSample = sample;
      break;
    }
  }
  if (firstStationSample == null) return null;
  final firstPoint = LatLng(
    firstStationSample['latitude']! as double,
    firstStationSample['longitude']! as double,
  );
  final firstDistanceKm = _distanceKm(truth, firstPoint);
  final firstDistanceWeightKm = math.max(50.0, firstDistanceKm);
  final rawMaxAllowedDepthKm = rawConstraints is Map
      ? rawConstraints['max_allowed_depth_km']
      : null;
  final maxAllowedDepthKm = rawMaxAllowedDepthKm is num
      ? math.min(700.0, rawMaxAllowedDepthKm.toDouble())
      : 700.0;
  var bestErrorLevel = double.infinity;
  var bestRmse = double.infinity;
  var bestDepthKm = 10.0;
  for (var depthKm = 10.0; depthKm <= maxAllowedDepthKm; depthKm += 10.0) {
    final origins = <double>[];
    final weights = <double>[];
    var weightSum = 0.0;
    for (final sample in samples) {
      final stationPoint = LatLng(
        sample['latitude']! as double,
        sample['longitude']! as double,
      );
      final surfaceDistanceKm = _distanceKm(truth, stationPoint);
      final hypocentralDistanceKm = math.sqrt(
        surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
      );
      final travelSeconds = Jma2001TravelTimeApproximation.travelTimeSeconds(
        hypocentralDistanceKm: hypocentralDistanceKm,
        depthKm: depthKm,
        pWave: sample['wave'] != 'S',
      );
      final observedSeconds =
          ((sample['trigger_stamp']! as int) - earliestStamp) / 1000.0;
      origins.add(observedSeconds - travelSeconds);
      final weight = surfaceDistanceKm <= 50.0
          ? 1.0
          : firstDistanceWeightKm / surfaceDistanceKm;
      weights.add(weight);
      weightSum += weight;
    }
    final originMean =
        origins.reduce((left, right) => left + right) / origins.length;
    var errorLevel = 0.0;
    for (var index = 0; index < origins.length; index++) {
      final residual = origins[index] - originMean;
      errorLevel += residual * residual * weights[index];
    }
    if (errorLevel < bestErrorLevel) {
      bestErrorLevel = errorLevel;
      bestRmse = math.sqrt(errorLevel / weightSum);
      bestDepthKm = depthKm;
    }
  }
  final waveCounts = <String, int>{'P': 0, 'S': 0};
  for (final sample in samples) {
    final wave = sample['wave']! as String;
    waveCounts[wave] = waveCounts[wave]! + 1;
  }
  final bestOrigins = <double>[];
  final bestWeights = <double>[];
  final bestDistances = <double>[];
  for (final sample in samples) {
    final stationPoint = LatLng(
      sample['latitude']! as double,
      sample['longitude']! as double,
    );
    final surfaceDistanceKm = _distanceKm(truth, stationPoint);
    final hypocentralDistanceKm = math.sqrt(
      surfaceDistanceKm * surfaceDistanceKm + bestDepthKm * bestDepthKm,
    );
    final travelSeconds = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: hypocentralDistanceKm,
      depthKm: bestDepthKm,
      pWave: sample['wave'] != 'S',
    );
    final observedSeconds =
        ((sample['trigger_stamp']! as int) - earliestStamp) / 1000.0;
    bestOrigins.add(observedSeconds - travelSeconds);
    bestWeights.add(
      surfaceDistanceKm <= 50.0
          ? 1.0
          : firstDistanceWeightKm / surfaceDistanceKm,
    );
    bestDistances.add(surfaceDistanceKm);
  }
  final bestOriginMean =
      bestOrigins.reduce((left, right) => left + right) / bestOrigins.length;
  final residualSamples =
      <Map<String, Object?>>[
        for (var index = 0; index < samples.length; index++)
          {
            'code': samples[index]['code'],
            'wave': samples[index]['wave'],
            'distance_km': bestDistances[index],
            'origin_s': bestOrigins[index],
            'origin_residual_s': bestOrigins[index] - bestOriginMean,
            'weight': bestWeights[index],
            'weighted_squared_residual':
                bestWeights[index] *
                math.pow(bestOrigins[index] - bestOriginMean, 2),
          },
      ]..sort(
        (left, right) => (right['weighted_squared_residual']! as num).compareTo(
          left['weighted_squared_residual']! as num,
        ),
      );
  final currentResidualSquares =
      estimate.diagnostics['weighted_residual_squares'];
  final currentResidual = currentResidualSquares is num
      ? currentResidualSquares.toDouble()
      : null;
  return {
    'model':
        'active_timing_residual_only_same_station_wave_js_depth_domain_not_total_score',
    'first_station_code': firstStationCode,
    'station_count': samples.length,
    'wave_counts': waveCounts,
    'max_allowed_depth_km': maxAllowedDepthKm,
    'best_depth_km': bestDepthKm,
    'truth_weighted_residual_squares': bestErrorLevel,
    'truth_rmse': bestRmse,
    'truth_origin_mean_s': bestOriginMean,
    'largest_truth_residuals': residualSamples.take(8).toList(growable: false),
    'current_weighted_residual_squares': currentResidual,
    'truth_minus_current_weighted_residual_squares': currentResidual == null
        ? null
        : bestErrorLevel - currentResidual,
  };
}

List<String> _findings(List<Map<String, Object?>> frames, _ReplayCase c) {
  final findings = <String>[];
  final estimateFrames = frames
      .where((frame) => frame['estimate'] != null)
      .toList(growable: false);
  if (estimateFrames.isEmpty) {
    findings.add('no_estimate');
    return findings;
  }
  final first = estimateFrames.first;
  final firstTime = DateTime.parse(first['observedAtJst']! as String);
  final delay = firstTime.difference(c.startJst).inSeconds;
  if (delay > 5) findings.add('late_first_estimate_${delay}s');
  final finalEstimate = estimateFrames.last['estimate'] as Map<String, Object?>;
  final finalError = finalEstimate['errorKm'];
  if (finalError is num && finalError > 40) {
    findings.add('large_final_error_${finalError.toStringAsFixed(1)}km');
  }
  final jumps = <double>[];
  LatLng? previous;
  for (final frame in estimateFrames) {
    final estimate = frame['estimate'] as Map<String, Object?>;
    final point = LatLng(
      (estimate['latitude']! as num).toDouble(),
      (estimate['longitude']! as num).toDouble(),
    );
    if (previous != null) jumps.add(_distanceKm(previous, point));
    previous = point;
  }
  if (jumps.any((jump) => jump > 50)) findings.add('large_estimate_jump');
  final lowSupport = estimateFrames.any((frame) {
    final estimate = frame['estimate'] as Map<String, Object?>;
    final support = estimate['supportingStationCount'];
    return support is num && support < 6;
  });
  if (lowSupport) findings.add('low_support_estimate');
  return findings;
}

Object? _snapshotReplayValue(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): _snapshotReplayValue(entry.value),
    };
  }
  if (value is Iterable) {
    return <Object?>[for (final item in value) _snapshotReplayValue(item)];
  }
  if (value is DateTime) return value.toIso8601String();
  return value;
}

String _markdown(List<Map<String, Object?>> reports) {
  final b = StringBuffer()
    ..writeln('# Current capture replay analysis')
    ..writeln()
    ..writeln(
      '| Case | Frames | Estimates | Missing | Final | Error | Findings |',
    )
    ..writeln('|---|---:|---:|---:|---|---:|---|');
  for (final report in reports) {
    final finalEstimate = report['finalEstimate'] as Map<String, Object?>?;
    final error = finalEstimate?['errorKm'];
    final finalText = finalEstimate == null
        ? '--'
        : '${_num(finalEstimate['latitude'], 3)}, ${_num(finalEstimate['longitude'], 3)}'
              ' / depth ${_num(finalEstimate['depthKm'], 0)} km'
              ' / conf ${_num(finalEstimate['confidence'], 2)}'
              ' / support ${finalEstimate['supportingStationCount']}';
    b.writeln(
      '| ${report['label']} '
      '| ${report['processedFrameCount']} '
      '| ${report['estimateFrameCount']} '
      '| ${report['missingFrameCount']} '
      '| $finalText '
      '| ${error is num ? error.toStringAsFixed(1) : '--'} '
      '| ${(report['findings'] as List).join(', ')} |',
    );
  }
  return b.toString();
}

String _num(Object? value, int digits) =>
    value is num ? value.toStringAsFixed(digits) : '--';

double _distanceKm(LatLng a, LatLng b) {
  const radiusKm = 6371.0;
  final dLat = _rad(b.latitude - a.latitude);
  final dLng = _rad(b.longitude - a.longitude);
  final lat1 = _rad(a.latitude);
  final lat2 = _rad(b.latitude);
  final h =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * radiusKm * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

double _rad(double deg) => deg * math.pi / 180;

class _ReplayCase {
  final String id;
  final String label;
  final DateTime startJst;
  final DateTime endJst;
  final LatLng? truth;
  final LatLng? equake;

  const _ReplayCase({
    required this.id,
    required this.label,
    required this.startJst,
    required this.endJst,
    required this.truth,
    required this.equake,
  });
}
