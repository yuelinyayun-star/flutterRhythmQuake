import 'dart:isolate';
import 'dart:typed_data';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/core/source_estimation/seismic_source_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/source_estimation/native_observation_history.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_observation_history.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';

int bits(double v) => (ByteData(8)..setFloat64(0, v)).getUint64(0);
Object? values(SeismicStationObservationFrame? f) => f == null
    ? null
    : [
        f.dataTime.microsecondsSinceEpoch,
        f.dataTime.isUtc,
        f.receivedAt.microsecondsSinceEpoch,
        f.receivedAt.isUtc,
        if (f.value == null) null else bits(f.value!),
        f.rawLevel,
        f.detectLevel,
        f.isTriggered,
        f.qualityFlags.toList(),
        f.isMissing,
        f.isStale,
        f.isDecodable,
        {
          for (final e in f.physicalObservations.entries)
            e.key.index: [
              e.value.quantity.index,
              e.value.layerId,
              bits(e.value.value),
              e.value.colorPosition,
              e.value.dataTime.microsecondsSinceEpoch,
              e.value.dataTime.isUtc,
              e.value.receivedAt.microsecondsSinceEpoch,
              e.value.receivedAt.isUtc,
              e.value.qualityFlags.toList(),
            ],
        },
      ];
Future<Object?> snapshotAcrossIsolate(StationObservationHistory history) =>
    Isolate.run(() => [for (final f in history.frames) values(f)]);
void main() {
  test(
    'native history preserves raw bits, UTC flags, cutoff and snapshots',
    () async {
      final baseline = NativeObservationHistory.diagnostics['sessions'];
      for (final retention in [
        const Duration(seconds: 60),
        Duration.zero,
        const Duration(microseconds: -1),
      ]) {
        final dart = StationObservationHistory(retention: retention),
            native = StationObservationHistory.native(retention: retention);
        try {
          final start = DateTime.utc(2026, 6, 10, 9, 1, 20, 0, 137);
          final flags = <String>{'missing_observation', '日本語', '中文'};
          List<SeismicStationObservationFrame>? saved;
          Object? savedValues;
          for (var i = 0; i < 150; i++) {
            // Controlled edge cases, separate from unmodified real-frame replay.
            final time = start.add(
              Duration(seconds: i ~/ 2 + (i >= 100 ? 100 : 0)),
            );
            final frame = SeismicStationObservationFrame(
              dataTime: i.isEven ? time : time.toLocal(),
              receivedAt: time.add(const Duration(microseconds: 17)).toLocal(),
              value: i % 5 == 0
                  ? null
                  : i % 5 == 1
                  ? -0.0
                  : i % 5 == 2
                  ? double.nan
                  : i % 5 == 3
                  ? double.infinity
                  : i / 7,
              rawLevel: i % 3 == 0 ? null : -i,
              detectLevel: i % 4 == 0 ? null : i,
              isTriggered: i.isOdd,
              qualityFlags: i % 7 == 0 ? flags : const {},
              physicalObservations: i % 9 == 0
                  ? {
                      StationValueType.pgv: SeismicPhysicalObservation(
                        quantity: StationValueType.pgv,
                        layerId: '原始-PGV',
                        value: -0.0,
                        colorPosition: 0.125,
                        dataTime: time,
                        receivedAt: time.toLocal(),
                        qualityFlags: const {'raw'},
                      ),
                    }
                  : const {},
            );
            dart.add(frame);
            native.add(frame);
            expect(native.length, dart.length);
            expect(values(native.latest), values(dart.latest));
            expect(
              [for (final f in native.frames) values(f)],
              [for (final f in dart.frames) values(f)],
            );
            expect(native.frames, same(native.frames));
            if (i == 45) {
              saved = native.frames;
              savedValues = [for (final f in saved) values(f)];
            }
          }
          expect([for (final f in saved!) values(f)], savedValues);
          final transferred = native.detachedSnapshot();
          expect(await snapshotAcrossIsolate(transferred), [
            for (final f in dart.frames) values(f),
          ]);
          final finalValues = [for (final f in native.frames) values(f)];
          native.disposeStorage();
          native.disposeStorage();
          expect([for (final f in native.frames) values(f)], finalValues);
          native.clear();
          dart.clear();
          expect(native.frames, isEmpty);
          expect(native.latest, isNull);
        } finally {
          native.disposeStorage();
        }
      }
      expect(NativeObservationHistory.diagnostics['sessions'], baseline);
    },
    skip: !NativeObservationHistory.supported,
  );
  test(
    'out of order rejection leaves original rows and metadata intact',
    () {
      final history = StationObservationHistory.native();
      final frame = SeismicStationObservationFrame(
        dataTime: DateTime.utc(2026),
        receivedAt: DateTime.utc(2026),
        value: 1,
        rawLevel: 1,
        detectLevel: 1,
        isTriggered: false,
        qualityFlags: const {},
      );
      try {
        history.add(frame);
        final before = history.frames;
        expect(
          () => history.add(
            SeismicStationObservationFrame(
              dataTime: DateTime.utc(2025),
              receivedAt: frame.receivedAt,
              value: null,
              rawLevel: null,
              detectLevel: null,
              isTriggered: false,
              qualityFlags: const {'earlier'},
            ),
          ),
          throwsArgumentError,
        );
        expect(history.frames, same(before));
        expect(values(history.latest), values(frame));
        final transfer = history.detachedSnapshot();
        expect(() => transfer.frames.clear(), throwsUnsupportedError);
        transfer.add(frame);
        expect(transfer.length, 2);
        expect(history.length, 1);
        history.clear();
        expect(before.length, 1);
        expect(transfer.length, 2);
      } finally {
        history.disposeStorage();
      }
    },
    skip: !NativeObservationHistory.supported,
  );
  test(
    'DateTime cutoff overflow preserves append-before-error behavior',
    () {
      final native = StationObservationHistory.native(
        retention: const Duration(microseconds: -1),
      );
      final dart = StationObservationHistory(
        retention: const Duration(microseconds: -1),
      );
      final time = DateTime.fromMicrosecondsSinceEpoch(
        8640000000000000000,
        isUtc: true,
      );
      final frame = SeismicStationObservationFrame(
        dataTime: time,
        receivedAt: time,
        value: 1,
        rawLevel: 1,
        detectLevel: 1,
        isTriggered: false,
        qualityFlags: const {},
      );
      try {
        Object? dartError, nativeError;
        try {
          dart.add(frame);
        } catch (e) {
          dartError = e;
        }
        try {
          native.add(frame);
        } catch (e) {
          nativeError = e;
        }
        expect(dartError, isNotNull);
        expect(nativeError.runtimeType, dartError.runtimeType);
        expect(
          [for (final f in native.frames) values(f)],
          [for (final f in dart.frames) values(f)],
        );
      } finally {
        native.disposeStorage();
      }
    },
    skip: !NativeObservationHistory.supported,
  );
  test(
    'archive and reset release native windows while retained records stay readable',
    () {
      final baseline = NativeObservationHistory.diagnostics['sessions'];
      final tracker = SeismicSourceTracker();
      tracker.setObservationHistoryFactory(
        'edge',
        StationObservationHistory.native,
      );
      final start = DateTime.utc(2026);
      void ingest(int second, String stage) {
        final at = start.add(Duration(seconds: second));
        tracker.ingestFrame(
          sourceId: 'edge',
          observedAt: at,
          stageName: stage,
          maxShindo: 1,
          samples: [
            SeismicStationSample(
              descriptor: const SeismicStationDescriptor(
                stationId: 'edge',
                code: 'edge',
                sourceId: 'edge',
                network: 'controlled-test',
                coordinate: LatLng(0, 0),
              ),
              observedAt: at,
              valueType: StationValueType.jmaShindo,
              value: 1,
              rawLevel: 1,
              detectLevel: 1,
              activity: 0,
              ascend: 0,
              isTriggered: stage != 'idle',
              qualityFlags: const {'controlled-edge'},
            ),
          ],
        );
      }

      try {
        ingest(0, 'detected');
        final first = tracker.currentEvent('edge')!.records.single;
        expect(NativeObservationHistory.diagnostics['sessions'], baseline! + 1);
        ingest(1, 'idle');
        expect(tracker.currentEvent('edge'), isNull);
        expect(tracker.history('edge').single.records, isEmpty);
        expect(NativeObservationHistory.diagnostics['sessions'], baseline);
        expect(first.observationHistory.length, 2);
        expect(
          first.observationHistory.frames.last.dataTime,
          start.add(const Duration(seconds: 1)),
        );
        ingest(2, 'detected');
        final second = tracker.currentEvent('edge')!.records.single;
        final before = values(second.observationHistory.latest);
        tracker.resetSource('edge');
        expect(values(second.observationHistory.latest), before);
        expect(NativeObservationHistory.diagnostics['sessions'], baseline);
      } finally {
        tracker.resetAll();
      }
    },
    skip: !NativeObservationHistory.supported,
  );
}
