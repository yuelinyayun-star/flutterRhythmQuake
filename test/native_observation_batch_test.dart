import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/source_estimation/native_observation_history.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_observation_history.dart';
import 'native_observation_history_test.dart'
    show values, snapshotAcrossIsolate;

SeismicStationObservationFrame frame(int tick) {
  final time = DateTime.utc(2026, 6, 10).add(Duration(seconds: tick ~/ 2));
  return SeismicStationObservationFrame(
    dataTime: tick.isEven ? time : time.toLocal(),
    receivedAt: time.add(const Duration(microseconds: 137)).toLocal(),
    value: switch (tick % 4) {
      0 => -0.0,
      1 => double.nan,
      2 => null,
      _ => 1 / 7,
    },
    rawLevel: tick,
    detectLevel: -tick,
    isTriggered: tick.isOdd,
    qualityFlags: tick % 7 == 0 ? const {'中文', '日本語'} : const {},
  );
}

void main() {
  test(
    'native batch failure preserves committed prefix and releases its scope',
    () {
      final history = NativeObservationHistory();
      final receiver = _CommitProbe();
      Int64List row(int time) =>
          Int64List.fromList([time, time, 0, 1, 1, 7, time]);
      try {
        expect(
          () => NativeObservationHistory.batchUpdates(() {
            history.appendDeferred(row(100), 0, receiver);
            history.appendDeferred(row(99), 0, receiver);
            history.appendDeferred(row(101), 0, receiver);
          }),
          throwsStateError,
        );
        expect(receiver.committed, [100]);
        expect(receiver.failures, 1);
        expect(history.length, 1);
        history.append(row(101), 0);
        expect(history.length, 2);
      } finally {
        history.dispose();
      }
    },
    skip: !NativeObservationHistory.supported,
  );
  test(
    'batch preserves duplicate history order, latest, pruning and ownership',
    () async {
      final sessions = NativeObservationHistory.diagnostics['sessions'];
      final calls = NativeObservationHistory.diagnostics['batchCalls']!;
      for (final retention in [
        const Duration(seconds: 60),
        Duration.zero,
        const Duration(microseconds: -1),
      ]) {
        final native = List.generate(
          2,
          (_) => StationObservationHistory.native(retention: retention),
        );
        final dart = List.generate(
          2,
          (_) => StationObservationHistory(retention: retention),
        );
        try {
          List<SeismicStationObservationFrame>? saved;
          Object? savedValues;
          StationObservationHistory.batchUpdates(() {
            // Cross the 2,048-row bound; repeated handles remain sequential.
            for (var index = 0; index < 2500; index++) {
              final slot = index % 2;
              final row = frame(index);
              dart[slot].add(row);
              native[slot].add(row);
              expect(values(native[slot].latest), values(dart[slot].latest));
              if (index == 10) {
                saved =
                    native[slot].frames; // Explicit read is a commit barrier.
                savedValues = [for (final row in saved!) values(row)];
              }
            }
          });
          expect([for (final row in saved!) values(row)], savedValues);
          for (var index = 0; index < 2; index++) {
            expect(
              [for (final row in native[index].frames) values(row)],
              [for (final row in dart[index].frames) values(row)],
            );
            expect(
              await snapshotAcrossIsolate(native[index].detachedSnapshot()),
              [for (final row in dart[index].frames) values(row)],
            );
          }
        } finally {
          for (final history in native) {
            history.disposeStorage();
          }
        }
      }
      expect(NativeObservationHistory.diagnostics['sessions'], sessions);
      expect(
        NativeObservationHistory.diagnostics['batchCalls']! - calls,
        allOf(greaterThan(0), lessThan(20)),
      );
    },
    skip: !NativeObservationHistory.supported,
  );

  test(
    'nested scopes, read barriers, clear and dispose keep earlier snapshots',
    () {
      final native = StationObservationHistory.native();
      try {
        StationObservationHistory.batchUpdates(() {
          native.add(frame(0));
          final saved = native.frames;
          StationObservationHistory.batchUpdates(() {
            native.add(frame(1));
          });
          expect(native.length, 2);
          native.add(frame(2));
          native.clear();
          expect(native.latest, isNull);
          native.add(frame(3));
          native.disposeStorage();
          expect(native.length, 1);
          expect(values(native.latest), values(frame(3)));
          expect(saved.length, 1);
          expect(values(saved.single), values(frame(0)));
        });
      } finally {
        native.disposeStorage();
      }
    },
    skip: !NativeObservationHistory.supported,
  );

  test(
    'body error commits earlier accepted rows and propagates original error',
    () {
      final native = StationObservationHistory.native();
      final error = StateError('controlled batch scope error');
      try {
        expect(
          () => StationObservationHistory.batchUpdates(() {
            native.add(frame(0));
            native.add(frame(2));
            throw error;
          }),
          throwsA(same(error)),
        );
        expect(native.length, 2);
        expect(values(native.latest), values(frame(2)));
        expect(
          () => StationObservationHistory.batchUpdates(() {
            native.add(frame(4));
            native.add(frame(0));
          }),
          throwsArgumentError,
        );
        expect(native.length, 3);
        expect(values(native.latest), values(frame(4)));
      } finally {
        native.disposeStorage();
      }
    },
    skip: !NativeObservationHistory.supported,
  );

  test(
    'cutoff DateTime overflow still appends before throwing inside batch',
    () {
      final native = StationObservationHistory.native(
        retention: const Duration(microseconds: -1),
      );
      final time = DateTime.fromMicrosecondsSinceEpoch(
        8640000000000000000,
        isUtc: true,
      );
      final row = SeismicStationObservationFrame(
        dataTime: time,
        receivedAt: time,
        value: -0.0,
        rawLevel: 1,
        detectLevel: 1,
        isTriggered: false,
        qualityFlags: const {},
      );
      try {
        expect(
          () => StationObservationHistory.batchUpdates(() {
            native.add(row);
          }),
          throwsArgumentError,
        );
        expect(native.length, 1);
        expect(values(native.latest), values(row));
      } finally {
        native.disposeStorage();
      }
    },
    skip: !NativeObservationHistory.supported,
  );
}

class _CommitProbe implements NativeObservationCommit {
  final List<int> committed = [];
  int failures = 0;
  @override
  void observationCommitted(int oldestMetadataId, int appendedMetadataId) =>
      committed.add(appendedMetadataId);
  @override
  void observationBatchFailed() {
    failures++;
  }
}
