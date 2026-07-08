import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutterrhythmquake/core/nied_replay_logger.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_event_tracker.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_source_estimation_driver.dart';

import 'support/nied_replay_fixture.dart';

void main() {
  test('analyzes current downloaded NIED capture windows', () async {
    final captureDirectory = Directory(
      r'C:\Users\Rhythm\Desktop\nied_capture_20260630_110914\raw\jma_s',
    );
    expect(captureDirectory.existsSync(), isTrue);

    final cases = [
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

    final reports = <Map<String, Object?>>[];
    for (final replayCase in cases) {
      reports.add(await _runCase(captureDirectory, replayCase));
    }

    final outDir = Directory('.dart_tool/current_capture_replay_analysis')
      ..createSync(recursive: true);
    final jsonFile = File('${outDir.path}/report.json');
    jsonFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'schemaVersion': 'current_capture_replay_analysis_v1', 'createdAtUtc': DateTime.now().toUtc().toIso8601String(), 'captureDirectory': captureDirectory.path, 'cases': reports})}\n',
    );
    final mdFile = File('${outDir.path}/report.md');
    mdFile.writeAsStringSync(_markdown(reports));
  });
}

Future<Map<String, Object?>> _runCase(
  Directory captureDirectory,
  _ReplayCase replayCase,
) async {
  NiedReplayLogger.instance.resetForTest();
  StationEventTracker.instance.resetNied();
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
    imageService.processPixels(
      decoded.packedRgb,
      surfaceGifBytes: decoded.gifBytes,
      dataTime: t,
      receivedAt: t,
    );
    await Future<void>.delayed(Duration.zero);
    final stations = latestStations;
    if (stations == null) continue;
    final detection = driver.processStations(stations.cast(), observedAt: t);
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
      'estimate': estimate == null
          ? null
          : {
              'latitude': estimate.latitude,
              'longitude': estimate.longitude,
              'confidence': estimate.confidence,
              'supportingStationCount': estimate.supportingStationCount,
              'method': estimate.method,
              'originTime': estimate.originTime?.toIso8601String(),
              'errorKm': replayCase.truth == null
                  ? null
                  : _distanceKm(estimatePoint!, replayCase.truth!),
              'equakeErrorKm': replayCase.equake == null
                  ? null
                  : _distanceKm(estimatePoint!, replayCase.equake!),
              'diagnostics': estimate.diagnostics,
            },
      'metadata': event?.metadata,
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
