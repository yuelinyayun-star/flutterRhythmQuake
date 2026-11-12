import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/nied_replay_logger.dart';
import 'package:flutterrhythmquake/core/source_estimation/native_observation_history.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimator.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_event_tracker.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_observation_history.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_source_estimation_driver.dart';
import 'package:flutterrhythmquake/services/sources/shake_detection_service.dart';
import 'package:latlong2/latlong.dart';

import 'support/nied_history_queries_before_20261018.dart';
import 'support/nied_replay_fixture.dart';

final _reference = BeforeNiedHistoryQueries();

void verify(
  SeismicStationEventRecord original,
  StationObservationHistory native,
  DateTime now,
) {
  for (final time in [
    now,
    now.add(const Duration(microseconds: 1500999)),
    now.add(const Duration(microseconds: 1501000)),
    null,
  ]) {
    final summary = native.niedSummary(time)!;
    for (final seconds in [1, 4, 9]) {
      expect(
        summary.change(seconds, original.lastAscend),
        _reference.change(original, time, seconds),
      );
    }
    if (time != null) {
      expect(
        summary.immediateChange(original.lastAscend),
        _reference.immediate(original, time),
      );
      for (final digit in [0, 1, 3, 9]) {
        expect(
          native.nativeFastRiseExceeds(time, digit),
          _reference.fast(original, time, digit),
        );
      }
    }
  }
  final earliest = original.firstObservedAt;
  expect(
    native.nativePretriggerSeconds(earliest, now),
    _reference.pretrigger(original, earliest, now),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'original Nara GIF histories match all frozen queries without exporting windows',
    () async {
      final directory = Directory('tmp/captures/20260610_180130_jst_nara_m36');
      if (!directory.existsSync()) {
        markTestSkipped('Original local capture required');
        return;
      }
      final tracker = StationEventTracker.instance
        ..resetNied()
        ..setNiedEstimator(_NoEstimate());
      final driver = NiedSourceEstimationDriver();
      final image = LmoniImageService()..start();
      final detector = ShakeDetectionService()..setSensitivity(2);
      final histories = <String, StationObservationHistory>{};
      final sessions = NativeObservationHistory.diagnostics['sessions'];
      var stationFrames = 0;
      try {
        for (var second = 20; second <= 70; second++) {
          final time = DateTime(2026, 6, 10, 18, 1, second);
          final file = File(
            '${directory.path}/${formatNiedTimeKey(time)}.lmoni.jma_s.gif',
          );
          final decoded = (await decodeNiedGifFile(file))!;
          final next = image.stationStream.firstWhere((v) => v != null);
          image.processPixels(
            decoded.packedRgb,
            surfaceGifBytes: decoded.gifBytes,
            dataTime: time,
            receivedAt: time,
          );
          final stations = (await next)!;
          detector.setStations(stations);
          detector.processUpdate();
          driver.processStations(stations, observedAt: time);
          for (final record
              in tracker.currentNiedEvent.value?.records ??
                  <SeismicStationEventRecord>[]) {
            final native = histories.putIfAbsent(
              record.descriptor.code,
              StationObservationHistory.native,
            );
            final frame = record.observationHistory.latest;
            if (frame == null) continue;
            native.add(frame);
            // This is a reference calculation over original recorded observations;
            // the native queries must not materialize the full window in Dart.
            final snapshots =
                NativeObservationHistory.diagnostics['snapshotCalls'];
            verify(record, native, time);
            expect(
              NativeObservationHistory.diagnostics['snapshotCalls'],
              snapshots,
            );
            stationFrames++;
          }
        }
        expect(stationFrames, greaterThan(50000));
        // ignore: avoid_print
        print(
          'Original GIF station/history comparisons: $stationFrames; native queries exported no full windows',
        );
      } finally {
        for (final history in histories.values) {
          history.disposeStorage();
        }
        driver.dispose();
        tracker.resetNied();
        detector.reset(detachStations: true);
        image.stop();
        NiedReplayLogger.instance.resetForTest();
      }
      expect(NativeObservationHistory.diagnostics['sessions'], sessions);
    },
    skip: !NativeObservationHistory.supported,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'ABI boundaries preserve missing evidence, duplicates, empty windows and frozen results',
    () {
      // Controlled API boundary cases, separate from the untouched replay above.
      final origin = DateTime.utc(2026, 10, 18);
      for (final retention in [
        const Duration(seconds: 60),
        Duration.zero,
        const Duration(microseconds: -1),
      ]) {
        final dart = StationObservationHistory(retention: retention);
        final native = StationObservationHistory.native(retention: retention);
        final record = SeismicStationEventRecord(
          descriptor: const SeismicStationDescriptor(
            stationId: 'edge',
            code: 'edge',
            sourceId: 'nied',
            network: '',
            coordinate: LatLng(35, 135),
          ),
          firstObservedAt: origin,
          observationHistory: dart,
          lastAscend: -3,
        );
        try {
          verify(record, native, origin);
          StationObservationHistory.batchUpdates(() {
            for (var index = 0; index < 140; index++) {
              final time = origin.add(
                Duration(microseconds: (index ~/ 2) * 1000000 + index % 2),
              );
              final frame = SeismicStationObservationFrame(
                dataTime: index.isEven ? time : time.toLocal(),
                receivedAt: time,
                value: switch (index % 5) {
                  0 => -0.0,
                  1 => double.nan,
                  2 => double.infinity,
                  3 => null,
                  _ => 1 / 7,
                },
                rawLevel: index % 3 == 0 ? null : index - 30,
                detectLevel: index % 7 == 0 ? null : 10,
                isTriggered: index % 4 == 0,
                qualityFlags: switch (index % 11) {
                  0 => const {'missing_observation'},
                  1 => const {'stale_observation'},
                  2 => const {'pixel_undecodable'},
                  _ => const {'中文', '日本語'},
                },
              );
              dart.add(frame);
              native.add(frame);
              verify(record, native, time);
            }
          });
          final saved = native.niedSummary(origin)!;
          native.clear();
          dart.clear();
          verify(record, native, origin);
          // The returned summary owns its bytes and survives clear/disposal.
          expect(saved.values.length, 9);
        } finally {
          native.disposeStorage();
        }
      }
    },
    skip: !NativeObservationHistory.supported,
  );
}

class _NoEstimate implements SourceEstimator {
  @override
  String get methodId => 'query-reference-only';
  @override
  bool supports(SourceEstimationRequest request) => false;
  @override
  SourceEstimate? estimate(SourceEstimationRequest request) => null;
}
