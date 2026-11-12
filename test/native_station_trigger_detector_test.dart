import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutterrhythmquake/core/event_detection/event_detection_models.dart';
import 'package:flutterrhythmquake/core/event_detection/native_station_trigger_detector.dart';
import 'package:flutterrhythmquake/core/event_detection/robust_station_trigger_detector.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_station_observation_adapter.dart';
import 'support/nied_replay_fixture.dart';
import 'support/station_trigger_comparison.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final enabled = NativeStationTriggerDetector.supported;
  for (final config in [
    const RobustStationTriggerConfig(),
    const RobustStationTriggerConfig(
      historySeconds: 2,
      minimumBaselineSamples: 1,
    ),
    const RobustStationTriggerConfig(
      historySeconds: 0,
      minimumBaselineSamples: 0,
      risingFrames: 0,
      triggeredFrames: 0,
      decayFrames: 0,
      missingFramesToEnd: 0,
    ),
  ]) {
    test(
      'native states, times, missing, disorder and reset match Dart: ${config.historySeconds}/${config.risingFrames}',
      () {
        final old = RobustStationTriggerDetector(config: config);
        final native = NativeStationTriggerDetector(config: config);
        addTearDown(native.dispose);
        final start = DateTime.utc(2026, 6, 20);
        final values = <int?>[
          5,
          5,
          5,
          5,
          5,
          7,
          7,
          8,
          8,
          8,
          14,
          14,
          14,
          5,
          5,
          5,
          null,
          null,
          null,
          5,
        ];
        for (var i = 0; i < 400; i++) {
          final index = i % values.length;
          final micros =
              start.microsecondsSinceEpoch + (i % 31 == 0 ? i - 7 : i) * 100000;
          final time = DateTime.fromMicrosecondsSinceEpoch(
            micros,
            isUtc: i.isEven,
          );
          final frames = [
            for (var station = 0; station < 3; station++)
              StationObservationFrame(
                stationId: '站$station',
                code: 'CODE$station',
                sourceId: 'nied_test',
                observedAt: time,
                latitude: 34.0 + station,
                longitude: 135.0,
                intensity: station == 0
                    ? null
                    : (station == 1 ? index / 3 : -index / 3),
                detectLevel: station == 0 ? values[index] : null,
                rawLevel: station == 0 ? values[index] : null,
                qualityFlags: const {'original_quality'},
              ),
          ];
          // Repeated station IDs in a batch must retain serial update semantics.
          if (i % 37 == 0) frames.add(frames.first);
          final expected = frames
              .map(old.update)
              .map(stationTriggerValues)
              .toList();
          expect(
            native.updateBatch(frames).map(stationTriggerValues).toList(),
            expected,
            reason: 'frame $i',
          );
          if (i % 53 == 0) {
            old.resetStation('站1');
            native.resetStation('站1');
          }
          if (i % 107 == 0) {
            old.reset();
            native.reset();
          }
        }
        native.reset();
        expect(native.diagnostics['stationCount'], 0);
        expect(native.diagnostics['bufferCapacityBytes'], 0);
        expect(native.diagnostics['rustCurrentBytes'], 0);
        native.dispose();
        native.dispose();
        expect(() => native.updateBatch(const []), throwsStateError);
      },
      skip: !enabled,
    );
  }
  test(
    'original 51 Nara GIF frames retain all 1634 station trigger outputs',
    () async {
      final directory = Directory('tmp/captures/20260610_180130_jst_nara_m36');
      if (!directory.existsSync()) {
        markTestSkipped('Requires original local Nara capture');
        return;
      }
      final native = NativeStationTriggerDetector(),
          old = RobustStationTriggerDetector();
      final images = LmoniImageService()..start();
      addTearDown(() {
        native.dispose();
        images.stop();
      });
      const adapter = NiedStationObservationAdapter();
      var count = 0;
      final states = <StationTriggerState>{};
      for (var second = 20; second <= 70; second++) {
        final time = DateTime(2026, 6, 10, 18, 1, second);
        final file = File(
          '${directory.path}/${formatNiedTimeKey(time)}.lmoni.jma_s.gif',
        );
        final hash = sha256.convert(file.readAsBytesSync());
        final pixels = (await decodeNiedGifFile(file))!;
        final next = images.stationStream.firstWhere((s) => s != null);
        images.processPixels(
          pixels.packedRgb,
          surfaceGifBytes: pixels.gifBytes,
          dataTime: time,
          receivedAt: time,
        );
        final stations = (await next)!;
        expect(stations.length, 1634);
        final observations = adapter.fromStations(stations, observedAt: time);
        final expected = observations.map(old.update).toList();
        final actual = native.updateBatch(observations);
        expect(
          actual.map(stationTriggerValues).toList(),
          expected.map(stationTriggerValues).toList(),
          reason: file.path,
        );
        states.addAll(actual.map((s) => s.state));
        count += actual.length;
        expect(sha256.convert(file.readAsBytesSync()), hash);
      }
      expect(count, 83334);
      // Report actual coverage; never modify observations to manufacture triggers.
      debugPrint(
        'NATIVE_TRIGGER_ORIGINAL values=$count states=$states stats=${native.diagnostics}',
      );
      images.stop();
      native.dispose();
      expect(
        NativeStationTriggerDetector.globalDiagnostics['triggerSessions'],
        0,
      );
      expect(
        NativeStationTriggerDetector.globalDiagnostics['rustCurrentBytes'],
        0,
      );
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
