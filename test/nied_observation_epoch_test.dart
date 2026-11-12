import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/core/source_estimation/native_observation_history.dart';
import 'package:flutterrhythmquake/core/source_estimation/nied_hyp_input_snapshot.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_observation_history.dart';
import 'native_observation_history_test.dart' show values;

void main() {
  test(
    'numeric native cutoff preserves SDK values and errors at epoch bounds',
    () {
      const limit = 8640000000000000000;
      final sessionCount = NativeObservationHistory.diagnostics['sessions'];
      for (final isUtc in [false, true]) {
        for (final micros in [-limit, -limit + 1, -1, 0, 1, limit - 1, limit]) {
          for (final retention in [
            Duration.zero,
            const Duration(microseconds: 1),
            const Duration(microseconds: -1),
            const Duration(seconds: 60),
            const Duration(microseconds: 0x7fffffffffffffff),
            const Duration(microseconds: -0x8000000000000000),
          ]) {
            final native = StationObservationHistory.native(
              retention: retention,
            );
            final dart = StationObservationHistory(retention: retention);
            final at = DateTime.fromMicrosecondsSinceEpoch(
              micros,
              isUtc: isUtc,
            );
            final row = SeismicStationObservationFrame(
              dataTime: at,
              receivedAt: at,
              value: -0.0,
              rawLevel: 1,
              detectLevel: null,
              isTriggered: false,
              qualityFlags: const {'边界', '境界'},
            );
            try {
              Object? nativeError, dartError;
              try {
                dart.add(row);
              } catch (error) {
                dartError = error;
              }
              try {
                StationObservationHistory.batchUpdates(() {
                  native.add(row);
                });
              } catch (error) {
                nativeError = error;
              }
              expect(
                nativeError?.runtimeType,
                dartError?.runtimeType,
                reason: '$micros / ${retention.inMicroseconds} / UTC=$isUtc',
              );
              expect(nativeError?.toString(), dartError?.toString());
              expect(native.length, dart.length);
              expect(values(native.latest), values(dart.latest));
              expect(
                [for (final row in native.frames) values(row)],
                [for (final row in dart.frames) values(row)],
              );
            } finally {
              native.disposeStorage();
            }
          }
        }
      }
      expect(NativeObservationHistory.diagnostics['sessions'], sessionCount);
    },
    skip: !NativeObservationHistory.supported,
  );

  test(
    'HYP time presence agrees with materialized local time including invalid bounds',
    () {
      for (final stamp in [
        -8640000000000001,
        -1,
        0,
        1,
        1791522664003,
        8640000000000000,
        8640000000000001,
        0x7fffffffffffffff,
      ]) {
        final snapshot = NiedHypStationSnapshot(
          stationId: 1,
          code: 'time-contract',
          coordinate: const LatLng(35, 139),
          triggerStamp: 1,
          updateStamp: stamp,
          ascend: 2,
          level: 7,
          currentShindo: 0,
          active: false,
        );
        Object? oldError, newError;
        bool? oldPresence, newPresence;
        try {
          oldPresence = snapshot.updateAt != null;
        } catch (error) {
          oldError = error;
        }
        try {
          newPresence = snapshot.hasUpdateTime;
        } catch (error) {
          newError = error;
        }
        expect(newPresence, oldPresence);
        expect(newError?.runtimeType, oldError?.runtimeType);
        expect(newError?.toString(), oldError?.toString());
        if (oldPresence == true) {
          expect(snapshot.updateAt!.millisecondsSinceEpoch, stamp);
          expect(snapshot.updateAt!.isUtc, isFalse);
        }
      }
      final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final ordinary = NiedHypStationValues(
        id: '1',
        code: 'ordinary',
        coordinate: const LatLng(35, 139),
        triggerAt: null,
        updateAt: epoch,
        level: null,
        currentShindo: null,
        ascend: 0,
        active: false,
      );
      expect(ordinary.hasUpdateTime, isTrue);
    },
  );
}
