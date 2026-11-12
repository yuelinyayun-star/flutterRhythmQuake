import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/nied_replay_logger.dart';
import 'package:flutterrhythmquake/core/event_detection/event_detection_models.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/native_nied_detection_owner.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_observation.dart';
import 'package:flutterrhythmquake/services/sources/shake_detection_service.dart';
import 'package:latlong2/latlong.dart';
import 'support/nied_replay_fixture.dart';
import 'support/shake_detection_before_20261019.dart' as frozen;

Object view(dynamic s) => [
  s.stage.index,
  s.weakCount,
  s.detectedCount,
  s.strongCount,
  s.maxShindo,
  [
    for (final e in s.detectedStations)
      [
        e.code,
        e.prefecture,
        e.level,
        e.jmaShindo,
        e.detectState,
        e.detectReason,
      ],
  ],
  [
    for (final e in s.gridCells.entries)
      [
        e.key,
        e.value.center.latitude,
        e.value.center.longitude,
        e.value.level,
        e.value.shindo,
      ],
  ],
];
Object event(EventDetection e) => [
  e.detectorId,
  e.sourceId,
  e.eventId,
  e.state.index,
  e.observedAt,
  e.startedAt,
  e.updatedAt,
  e.endedAt,
  e.memberStationIds,
  e.detectionScore,
  e.maxIntensity,
  e.reasonCodes.toList(),
  e.metadata,
];
Object raw(NiedStation s) => [
  s.code,
  s.coordinate.latitude,
  s.coordinate.longitude,
  s.level,
  s.activity,
  s.ascend,
  s.continuousShindo,
  s.triggerStamp,
  s.lastDataTime,
  s.lastUpdate,
];
Object stationView(NiedStation s) => [
  s.isActive,
  s.detectState,
  s.detectReason,
];

// Frozen display signature contract from the pre-migration pipeline.
String referenceLayerSignature(
  frozen.ShakeDetectionSnapshot detection,
  List<NiedStation> stations,
) {
  final cells = detection.gridCells.entries.toList()
    ..sort(
      (dynamic a, dynamic b) => (a.key as String).compareTo(b.key as String),
    );
  final buffer = StringBuffer()
    ..write(stations.length)
    ..write('|')
    ..write(detection.stage.name)
    ..write(':')
    ..write(detection.weakCount)
    ..write(':')
    ..write(detection.detectedCount)
    ..write(':')
    ..write(detection.strongCount)
    ..write(':')
    ..write(detection.maxShindo);
  for (final cell in cells) {
    buffer
      ..write(':')
      ..write(cell.key)
      ..write('=')
      ..write(cell.value.level);
  }
  for (final station in stations) {
    buffer
      ..write('|')
      ..write(station.id)
      ..write(':')
      ..write(station.level)
      ..write(':')
      ..write(station.detectState);
    if (station.isRealtimeObservationMissing) buffer.write(':missing');
  }
  return buffer.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'missing quality invalidates native layer even when held level is unchanged without activating a station',
    () {
      final input = [
        NiedStation(
          id: 0,
          code: 'quality',
          name: '',
          coordinate: const LatLng(35, 139),
          network: '',
          prefecture: '',
          expireSeconds: 10,
          level: 3,
        ),
      ];
      final owner = NativeNiedDetectionOwner(
        input,
        manualClock: true,
        onUpdate: (_) {},
      );
      try {
        owner.process(input, 2);
        final valid = owner.layerSignature;
        input.single.clearGifObservation(
          NiedGifLayer.realtimeShindo,
          qualityFlag: 'pixel_transparent',
        );
        owner.process(input, 2, clock: 1000);
        owner.rebind(input);
        expect(owner.layerSignature, contains(':missing'));
        expect(owner.layerSignature, isNot(valid));
        expect(input.single.isActive, isFalse);
        expect(input.single.level, 3);
        input.single.updateGifObservation(
          const NiedGifObservation(shindo: -1.96),
        );
        owner.process(input, 2, clock: 2000);
        expect(owner.layerSignature, valid);
      } finally {
        owner.dispose();
      }
    },
    skip: !NativeNiedDetectionOwner.supported,
  );
  test(
    'unaltered original 51 GIF frames preserve detection, grids, lifecycle and effects',
    () async {
      final directory = Directory('tmp/captures/20260610_180130_jst_nara_m36');
      expect(
        directory.existsSync(),
        isTrue,
        reason: 'Original GIF capture required',
      );
      final baseline = NativeNiedDetectionOwner.diagnostics['sessions'];
      final image = LmoniImageService()..start();
      final reference = frozen.FrozenShakeDetectionService.forSource(
        'nied',
        nativeOwner: true,
      );
      final actual = ShakeDetectionService.forSource('nied', nativeOwner: true);
      final expectedViews = <Object>[], actualViews = <Object>[];
      final expectedEvents = <Object>[], actualEvents = <Object>[];
      final expectedActions = <Object>[], actualActions = <Object>[];
      late frozen.ShakeDetectionSnapshot referenceSnapshot;
      reference.onDetectionSnapshotChanged = (v) {
        referenceSnapshot = v;
        expectedViews.add(view(v));
      };
      actual.onDetectionSnapshotChanged = (v) => actualViews.add(view(v));
      reference.onEventDetectionChanged = (v) => expectedEvents.add(event(v));
      actual.onEventDetectionChanged = (v) => actualEvents.add(event(v));
      reference.onShakeDetected = (v) => expectedActions.add(['shake', v]);
      actual.onShakeDetected = (v) => actualActions.add(['shake', v]);
      reference.onShakeExpired = () => expectedActions.add(['expired']);
      actual.onShakeExpired = () => actualActions.add(['expired']);
      reference.onNotification = (a, b) => expectedActions.add([a, b]);
      actual.onNotification = (a, b) => actualActions.add([a, b]);
      reference.onFocusWindow = () => expectedActions.add(['focus']);
      actual.onFocusWindow = () => actualActions.add(['focus']);
      var stationComparisons = 0;
      final legacyTime = Stopwatch(), nativeTime = Stopwatch();
      try {
        for (var second = 20; second <= 70; second++) {
          final time = DateTime(2026, 6, 10, 18, 1, second);
          final file = File(
            '${directory.path}/${formatNiedTimeKey(time)}.lmoni.jma_s.gif',
          );
          final original = file.readAsBytesSync(),
              digest = sha256.convert(file.readAsBytesSync());
          final decoded = (await decodeNiedGifFile(file))!;
          final ready = image.stationStream.firstWhere((v) => v != null);
          image.processPixels(
            decoded.packedRgb,
            surfaceGifBytes: original,
            dataTime: time,
            receivedAt: time,
          );
          final input = (await ready)!;
          final expectedStations = input
              .map(NiedStation.detachedSnapshot)
              .toList();
          final actualStations = input
              .map(NiedStation.detachedSnapshot)
              .toList();
          final rawBefore = actualStations.map(raw).toList();
          reference.setStations(expectedStations);
          actual.setStations(actualStations);
          legacyTime.start();
          reference.processUpdate();
          legacyTime.stop();
          nativeTime.start();
          actual.processUpdate();
          nativeTime.stop();
          expect(
            actualStations.map(raw),
            rawBefore,
            reason: '$time raw columns',
          );
          expect(
            actualStations.map(stationView),
            expectedStations.map(stationView),
            reason: '$time station state',
          );
          expect(actualStations.every((s) => s.activeTimer == null), isTrue);
          expect(actualViews, expectedViews, reason: '$time UI projections');
          expect(
            actual.preparedLayerSignature,
            referenceLayerSignature(referenceSnapshot, expectedStations),
            reason: '$time complete native map refresh signature',
          );
          expect(actualEvents, expectedEvents, reason: '$time event lifecycle');
          expect(
            actualActions,
            expectedActions,
            reason: '$time notification/focus',
          );
          expect(sha256.convert(file.readAsBytesSync()), digest);
          stationComparisons += input.length;
        }
        expect(stationComparisons, 83334);
        expect(actualViews.length, greaterThan(1));
        expect(actualActions, isNotEmpty);
        // ignore: avoid_print
        print(
          'NIED_NATIVE_DETECTION originalFrames=51 stationComparisons=$stationComparisons projections=${actualViews.length} actions=${actualActions.length} legacyProcessUs=${legacyTime.elapsedMicroseconds} nativeProcessUs=${nativeTime.elapsedMicroseconds}',
        );
      } finally {
        reference.reset(detachStations: true, emitSnapshot: false);
        actual.reset(detachStations: true, emitSnapshot: false);
        image.stop();
        NiedReplayLogger.instance.resetForTest();
      }
      expect(NativeNiedDetectionOwner.diagnostics['sessions'], baseline);
    },
    skip: !NativeNiedDetectionOwner.supported,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'native deadline owns expiry without Dart timers and reset discards pending work',
    () {
      // Lifecycle boundary inputs only; not a measured earthquake sample.
      fakeAsync((clock) {
        final input = [
          NiedStation(
              id: 0,
              code: '期限',
              name: '',
              coordinate: const LatLng(35, 140),
              network: '',
              prefecture: '',
              expireSeconds: 10,
            )
            ..level = 10
            ..activity = 30
            ..ascend = 4
            ..lastDataTime = DateTime.utc(2026, 10, 19),
        ];
        final before = input.map(raw).toList();
        final output = <List<dynamic>>[];
        final owner = NativeNiedDetectionOwner(
          input,
          manualClock: true,
          onUpdate: output.add,
        );
        try {
          owner.process(input, 2);
          owner.rebind(input);
          expect(input.single.isActive, isTrue);
          expect(clock.pendingTimers, isEmpty);
          final count = output.length;
          owner.tick(10499);
          expect(output, hasLength(count));
          owner.tick(10500);
          owner.rebind(input);
          expect(input.single.isActive, isFalse);
          expect(output.last[2], isNull);
          owner.tick(10516);
          expect(output.last[2][10], EventDetectionState.ended.index);
          expect(output.last[1], [
            [3],
          ]);
          expect(input.map(raw), before);
          owner.process(input, 2, clock: 20000);
          owner.tick(30500);
          owner.reset(clearHolds: true);
          final afterReset = output.length;
          owner.tick(40000);
          expect(output, hasLength(afterReset));
          owner.rebind(input);
          expect(input.single.isActive, isFalse);
        } finally {
          owner.dispose();
        }
        expect(clock.pendingTimers, isEmpty);
      });
    },
    skip: !NativeNiedDetectionOwner.supported,
  );

  test(
    'live native worker publishes expiration and joins on disposal',
    () async {
      final baseline = NativeNiedDetectionOwner.diagnostics;
      final input = [
        NiedStation(
            id: 0,
            code: '期限',
            name: '',
            coordinate: const LatLng(35, 140),
            network: '',
            prefecture: '',
            expireSeconds: 10,
          )
          ..level = 10
          ..activity = 30
          ..ascend = 4
          ..lastDataTime = DateTime.utc(2026, 10, 19),
      ];
      final expired = Completer<void>();
      var updates = 0;
      final owner = NativeNiedDetectionOwner(
        input,
        onUpdate: (result) {
          updates++;
          for (final row in result[1] as List) {
            if (row[0] == 3 && !expired.isCompleted) expired.complete();
          }
        },
      );
      try {
        owner.process(input, 2);
        await expired.future.timeout(const Duration(seconds: 13));
        owner.rebind(input);
        expect(input.single.isActive, isFalse);
        expect(updates, 3);
      } finally {
        owner.dispose();
      }
      expect(
        NativeNiedDetectionOwner.diagnostics['sessions'],
        baseline['sessions'],
      );
      expect(
        NativeNiedDetectionOwner.diagnostics['workers'],
        baseline['workers'],
      );
    },
    skip: !NativeNiedDetectionOwner.supported,
  );

  test(
    'hosted background mode promotes the shared singleton to the native owner',
    () {
      // The shared singleton has nativeOwner=false; hosted Android must still
      // reach the Rust detector through the dynamic promotion in setStations.
      final service = ShakeDetectionService();
      final baseline = NativeNiedDetectionOwner.diagnostics['sessions'];
      try {
        final input = [
          NiedStation(
            id: 0,
            code: 'hosted',
            name: '',
            coordinate: const LatLng(35, 139),
            network: '',
            prefecture: '',
            expireSeconds: 10,
            level: 10,
          )..lastDataTime = DateTime.utc(2026, 11, 12),
        ];
        service.setStations(input, background: true);
        service.processUpdate(background: true);
        expect(
          NativeNiedDetectionOwner.diagnostics['sessions'],
          greaterThan(baseline!),
          reason: 'hosted background must create a native Rust session',
        );
        // Holds/expiry are owned by Rust; no Dart hold timer is installed.
        expect(input.single.activeTimer, isNull);

        // Returning to the foreground path must release the session again.
        service.setStations(input, background: false);
        service.processUpdate(background: false);
        expect(
          NativeNiedDetectionOwner.diagnostics['sessions'],
          baseline,
          reason: 'leaving hosted mode must release the native session',
        );

        // Re-entering hosted mode recreates it exactly once (no leaks).
        service.setStations(input, background: true);
        service.processUpdate(background: true);
        expect(
          NativeNiedDetectionOwner.diagnostics['sessions'],
          baseline! + 1,
        );
      } finally {
        service.reset(detachStations: true, emitSnapshot: false);
      }
      expect(NativeNiedDetectionOwner.diagnostics['sessions'], baseline);
    },
    skip: !NativeNiedDetectionOwner.supported,
  );
}
