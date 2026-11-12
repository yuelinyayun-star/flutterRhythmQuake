import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/palert_service.dart';
import 'package:flutterrhythmquake/services/sources/palert_source_worker.dart';
import 'package:flutterrhythmquake/services/sources/native_station_runtime.dart';
import 'native_palert_runtime_test.dart' show earthquakeFrames, until;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native P-Alert complete source session matches untouched earthquake archive',
    () async {
      final saved = earthquakeFrames();
      final service = PAlertService.nativeForTesting(
        settings: {'testing': true, 'inference': true},
      );
      final reference = PAlertSourceWorker.dartReferenceForTesting();
      try {
        service.start();
        await until(() => service.nativeSummary != null);
        service.handleOriginalForTesting(
          utf8.encode(jsonEncode(saved.first.originalJson!['metadata'])),
          saved.first.receivedAt,
        );
        await until(() => service.stations.length == 787);
        var count = 0, sourceFrames = 0;
        for (final f in saved) {
          final raw = f.originalJson!['data'];
          final time = PAlertService.parseTimestamp(
            raw['data']['pga']['timestamp'],
          );
          if (time == service.dataTimeNotifier.value) continue;
          service.handleOriginalForTesting(
            utf8.encode(jsonEncode(raw)),
            f.receivedAt,
          );
          count++;
          await until(() => service.nativeFrameCount == count);
          final expected = await reference.process(service.stations, {
            for (final s in service.detectionSnapshot.detectedStations) s.code,
          }, now: f.receivedAt);
          final actual = service.nativeSourceEvents;
          expect(
            actual.length,
            expected!.length,
            reason: 'source count frame $count',
          );
          for (var i = 0; i < actual.length; i++) {
            final a = actual[i], b = expected[i];
            final x = a.estimate!, y = b.estimate!;
            expect(a.eventId, b.eventId, reason: 'event identity frame $count');
            expect(
              x.latitude,
              closeTo(y.latitude, 1e-10),
              reason: 'latitude frame $count',
            );
            expect(
              x.longitude,
              closeTo(y.longitude, 1e-10),
              reason: 'longitude frame $count',
            );
            expect(
              x.depthKm,
              closeTo(y.depthKm!, 1e-10),
              reason: 'depth frame $count',
            );
            expect(x.originTime, y.originTime, reason: 'origin frame $count');
            if (y.magnitude == null) {
              expect(x.magnitude, isNull);
            } else {
              expect(
                x.magnitude,
                closeTo(y.magnitude!, 1e-10),
                reason: 'magnitude frame $count',
              );
            }
            expect(x.confidence, y.confidence);
            expect(x.supportingStationCount, y.supportingStationCount);
            expect(a.metadata, b.metadata);
            for (final key in y.diagnostics.keys) {
              final value = y.diagnostics[key];
              if (value is double) {
                expect(
                  x.diagnostics[key],
                  closeTo(value, 1e-8),
                  reason: '$key frame $count',
                );
              } else {
                expect(x.diagnostics[key], value, reason: '$key frame $count');
              }
            }
          }
          if (actual.isNotEmpty) sourceFrames++;
        }
        expect(sourceFrames, greaterThan(0));
        debugPrint(
          'NATIVE_PALERT_INFERENCE originalFrames=$count sourceFrames=$sourceFrames',
        );
      } finally {
        service.stop();
        reference.dispose();
        await until(() => NativeStationRuntime.workers == 0);
      }
    },
    skip: !NativeStationRuntime.supported,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
