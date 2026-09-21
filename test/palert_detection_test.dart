import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/palert_detection.dart';
import 'package:flutterrhythmquake/services/sources/palert_detection_grid.dart';
import 'package:flutterrhythmquake/services/sources/palert_service.dart';
import 'package:flutterrhythmquake/services/sources/shake_detection_service.dart';

// Controlled boundary-test inputs, not an earthquake replay or live records.
List<PAlertStation> frame(DateTime time, List<int> levels, {int? held}) => [
  for (var i = 0; i < levels.length; i++)
    PAlertStation(
      id: 'SIM$i',
      network: 'P-Alert',
      name: 'SIM$i',
      area: 'TEST',
      coordinate: LatLng(23.5 + i * 0.02, 121 + i * 0.02),
      pgaGal: const [0.02, 1.5, 6.0, 15.0, 50.0][levels[i]],
      cwaIntensityIndex: levels[i],
      heldCwaIntensityIndex: held,
      dataTime: time,
      receivedAt: time,
    ),
];

List<PAlertStation> pgaFrame(DateTime time, double? pga, {double? pgv}) => [
  for (final station in frame(time, List.filled(6, 0)))
    PAlertStation(
      id: station.id,
      network: station.network,
      name: station.name,
      area: station.area,
      coordinate: station.coordinate,
      pgaGal: pga,
      pgvCms: pgv,
      cwaIntensityIndex: PAlertService.cwaIntensityIndexFromPgaPgv(
        pgaGal: pga,
        pgvCms: pgv,
      ),
      dataTime: time,
      receivedAt: time,
    ),
];

void main() {
  final start = DateTime.utc(2026, 9, 21);
  late PAlertDetector detector;
  setUp(() => detector = PAlertDetector());
  tearDown(() => detector.dispose());

  test('joint PGA rise inside CWA zero reaches the NIED weak stage', () {
    detector.update(pgaFrame(start, 0.02), now: start);
    final time = start.add(const Duration(seconds: 1));
    final raw = pgaFrame(time, 0.6);
    final gate = PAlertDetectionGate();
    final signals = <PAlertDetectionSignal>[];
    detector.onCwaIntensityChanged = (value) => signals.add(gate.update(value));
    detector.update(raw, now: time);
    expect(detector.snapshot.stage, ShakeDetectStage.weak);
    expect(detector.snapshot.gridCells, isNotEmpty);
    expect(detector.confirmedCwaMaxShindo, 0);
    expect(signals, [PAlertDetectionSignal.none]);
    expect(raw.every((s) => s.cwaIntensityIndex == 0), isTrue);
    expect(raw.every((s) => s.pgaGal == 0.6), isTrue);
    expect(raw.first.estimatedContinuousShindo, closeTo(0.2563025, 1e-6));
  });

  test('steady subzero PGA does not invent an observed rise', () {
    for (var i = 0; i < 65; i++) {
      final time = start.add(Duration(seconds: i));
      detector.update(pgaFrame(time, 0.1), now: time);
      expect(detector.snapshot.gridCells, isEmpty);
      expect(detector.confirmedCwaMaxShindo, -1);
    }
  });

  test('CWA sound boundary updates even without a new engine snapshot', () {
    final gate = PAlertDetectionGate();
    final alerts = <int>[];
    detector.onCwaIntensityChanged = (value) {
      if (gate.update(value) == PAlertDetectionSignal.detected) {
        alerts.add(value);
      }
    };
    detector.update(pgaFrame(start, 0.02), now: start);
    final time = start.add(const Duration(seconds: 1));
    detector.update(pgaFrame(time, 24.99), now: time);
    expect(alerts, [3]);
    var snapshots = 0;
    detector.onSnapshot = (_) => snapshots++;
    for (var i = 1; i <= 3; i++) {
      final next = time.add(Duration(seconds: i));
      detector.update(pgaFrame(next, 25), now: next);
    }
    expect(snapshots, 0);
    expect(alerts, [3, 4]);
    expect(detector.snapshot.maxShindo, 3);
    expect(detector.confirmedCwaMaxShindo, 4);
  });

  test('high PGA does not replace CWA PGV-based sound intensity', () {
    detector.update(pgaFrame(start, 0.02), now: start);
    final time = start.add(const Duration(seconds: 1));
    detector.update(pgaFrame(time, 1000, pgv: 5), now: time);
    expect(detector.snapshot.maxShindo, 7);
    expect(detector.confirmedCwaMaxShindo, 4);
    final next = time.add(const Duration(seconds: 1));
    detector.update(pgaFrame(next, 1000, pgv: 100), now: next);
    expect(detector.confirmedCwaMaxShindo, 6);
  });

  test('missing PGV does not block PGA detection or invent CWA sound', () {
    detector.update(pgaFrame(start, 0.02), now: start);
    final time = start.add(const Duration(seconds: 1));
    detector.update(pgaFrame(time, 1000), now: time);
    expect(detector.snapshot.gridCells, isNotEmpty);
    expect(detector.confirmedCwaMaxShindo, 0);
  });

  test('missing PGA cannot use a display hold or old CWA value', () {
    detector.update(pgaFrame(start, 0.02), now: start);
    final time = start.add(const Duration(seconds: 1));
    detector.update(pgaFrame(time, 6), now: time);
    final next = time.add(const Duration(seconds: 1));
    detector.update([
      for (final station in pgaFrame(next, null))
        station.copyWith(cwaIntensityIndex: 4, heldCwaIntensityIndex: 4),
    ], now: next);
    expect(detector.snapshot.gridCells, isEmpty);
    expect(detector.confirmedCwaMaxShindo, -1);
  });

  test('sound tiers survive quiet holds and rearm only after expiry', () {
    final gate = PAlertDetectionGate();
    final alerts = <int>[];
    var expired = 0;
    detector.onCwaIntensityChanged = (value) {
      final signal = gate.update(value);
      if (signal == PAlertDetectionSignal.detected) {
        alerts.add(value);
      }
      if (signal == PAlertDetectionSignal.expired) {
        expired++;
      }
    };
    final pgas = [0.02, 1.5, 0.02, 1.5, 50.0, 50.0];
    for (var i = 0; i < pgas.length; i++) {
      final time = start.add(Duration(seconds: i));
      detector.update(pgaFrame(time, pgas[i]), now: time);
    }
    expect(alerts, [1, 4]);
    expect(expired, 0);
    detector.expireStale(start.add(const Duration(seconds: 12)));
    expect(expired, 1);
    for (var i = 0; i < 2; i++) {
      final time = start.add(Duration(seconds: 13 + i));
      detector.update(pgaFrame(time, pgas[i]), now: time);
    }
    expect(alerts, [1, 4, 1]);
  });

  test('invalid PGA breaks history instead of becoming a quiet baseline', () {
    for (final invalid in <double?>[null, 0, -1, double.nan, double.infinity]) {
      detector.reset();
      detector.update(pgaFrame(start, 0.02), now: start);
      final invalidTime = start.add(const Duration(seconds: 1));
      detector.update(pgaFrame(invalidTime, invalid), now: invalidTime);
      final next = start.add(const Duration(seconds: 2));
      detector.update(pgaFrame(next, 50), now: next);
      expect(detector.snapshot.gridCells, isEmpty);
      expect(detector.confirmedCwaMaxShindo, -1);
    }
  });

  test('cold high frame is not an observed rise', () {
    detector.update(frame(start, List.filled(6, 4)), now: start);
    expect(detector.snapshot.stage, ShakeDetectStage.idle);
    expect(detector.snapshot.gridCells, isEmpty);
  });

  test(
    'single high station among quiet neighbors does not pass count gate',
    () {
      detector.update(frame(start, List.filled(6, 0)), now: start);
      final time = start.add(const Duration(seconds: 1));
      detector.update(frame(time, [4, 0, 0, 0, 0, 0]), now: time);
      expect(detector.snapshot.stage, ShakeDetectStage.idle);
      expect(detector.snapshot.gridCells, isEmpty);
    },
  );

  test('nearby joint rise produces shared station and grid results', () {
    detector.update(frame(start, List.filled(6, 0)), now: start);
    final time = start.add(const Duration(seconds: 1));
    final raw = frame(time, List.filled(6, 1));
    detector.update(raw, now: time);
    expect(detector.snapshot.stage, ShakeDetectStage.detected);
    expect(detector.snapshot.detectedStations, hasLength(6));
    expect(detector.snapshot.maxShindo, 1);
    expect(detector.snapshot.gridCells, isNotEmpty);
    expect(raw.every((s) => s.cwaIntensityIndex == 1), isTrue);
    expect(raw.every((s) => s.heldCwaIntensityIndex == null), isTrue);
  });

  test(
    'display peak holds cannot trigger detection from quiet current data',
    () {
      detector.update(frame(start, List.filled(6, 0)), now: start);
      final time = start.add(const Duration(seconds: 1));
      detector.update(frame(time, List.filled(6, 0), held: 4), now: time);
      expect(detector.snapshot.stage, ShakeDetectStage.idle);
      expect(detector.snapshot.gridCells, isEmpty);
    },
  );

  test('duplicate and backwards samples cannot invent a rising frame', () {
    detector.update(frame(start, List.filled(6, 0)), now: start);
    detector.update(frame(start, List.filled(6, 4)), now: start);
    detector.update(
      frame(start.subtract(const Duration(seconds: 1)), List.filled(6, 4)),
      now: start,
    );
    expect(detector.snapshot.stage, ShakeDetectStage.idle);
  });

  test(
    'stale per-station frames cannot vote while other stations keep updating',
    () {
      detector.update(frame(start, List.filled(6, 0)), now: start);
      final time = start.add(const Duration(seconds: 1));
      final rise = frame(time, List.filled(6, 2));
      detector.update(rise, now: time);
      expect(detector.snapshot.gridCells, isNotEmpty);
      final later = time.add(const Duration(seconds: 7));
      detector.update([
        frame(later, [0]).first,
        ...rise.skip(1),
      ], now: later);
      expect(detector.snapshot.stage, ShakeDetectStage.idle);
      expect(detector.snapshot.gridCells, isEmpty);
    },
  );

  test('watchdog expires all grids even with no new source frames', () {
    detector.update(frame(start, List.filled(6, 0)), now: start);
    final time = start.add(const Duration(seconds: 1));
    detector.update(frame(time, List.filled(6, 2)), now: time);
    detector.expireStale(time.add(const Duration(seconds: 7)));
    expect(detector.snapshot.stage, ShakeDetectStage.idle);
    expect(detector.snapshot.gridCells, isEmpty);
  });

  testWidgets(
    'quiet frames retain NIED hold then expire without extending it',
    (tester) async {
      detector.update(frame(start, List.filled(6, 0)), now: start);
      final riseTime = start.add(const Duration(seconds: 1));
      detector.update(frame(riseTime, List.filled(6, 2)), now: riseTime);
      for (var i = 1; i <= 11; i++) {
        await tester.pump(const Duration(seconds: 1));
        final time = riseTime.add(Duration(seconds: i));
        detector.update(frame(time, List.filled(6, 0)), now: time);
        if (i == 1) expect(detector.snapshot.gridCells, isNotEmpty);
      }
      expect(detector.snapshot.stage, ShakeDetectStage.idle);
      expect(detector.snapshot.gridCells, isEmpty);
      detector.dispose();
    },
  );

  test('P-Alert equals direct NIED engine results for each sensitivity', () {
    for (var sensitivity = 1; sensitivity <= 3; sensitivity++) {
      detector.reset();
      detector.setSensitivity(sensitivity);
      final reference = ShakeDetectionService.forSource('reference');
      reference.setSensitivity(sensitivity);
      final stations = [
        for (final s in frame(start, List.filled(6, 0)))
          NiedStation(
            id: int.parse(s.id.substring(3)),
            code: s.id,
            name: s.name,
            coordinate: s.coordinate,
            network: 'TEST',
            prefecture: 'TEST',
            expireSeconds: NiedStation.kaExpireSeconds,
          ),
      ];
      reference.setStations(stations);
      var expected = ShakeDetectionService.idleSnapshot;
      reference.onDetectionSnapshotChanged = (s) => expected = s;
      final frames = [
        [0, 0, 0, 0, 0, 0],
        [1, 1, 0, 0, 0, 0],
        [1, 1, 1, 1, 0, 0],
        [4, 4, 4, 4, 4, 4],
        [0, 0, 0, 0, 0, 0],
      ];
      try {
        for (var t = 0; t < frames.length; t++) {
          final time = start.add(Duration(seconds: t));
          final input = frame(time, frames[t]);
          for (var i = 0; i < stations.length; i++) {
            stations[i].lastDataTime = time;
            stations[i].lastReceivedAt = time;
            stations[i].update(input[i].detectionLevel);
          }
          reference.processUpdate();
          detector.update(input, now: time);
          expect(detector.snapshot.stage, expected.stage);
          expect(detector.snapshot.maxShindo, expected.maxShindo);
          expect(
            detector.snapshot.detectedStations.map((s) => s.code),
            expected.detectedStations.map((s) => s.code),
          );
          expect(detector.snapshot.gridCells.keys, expected.gridCells.keys);
        }
      } finally {
        reference.reset(detachStations: true);
      }
    }
  });

  test('three rising stations use the configured NIED sensitivity', () {
    for (final sensitivity in [1, 2, 3]) {
      detector.reset();
      detector.setSensitivity(sensitivity);
      detector.update(frame(start, List.filled(6, 0)), now: start);
      final time = start.add(const Duration(seconds: 1));
      detector.update(frame(time, [1, 1, 1, 0, 0, 0]), now: time);
      expect(detector.snapshot.gridCells.isNotEmpty, sensitivity != 1);
    }
  });

  test('an observation gap does not become an invented rise on reconnect', () {
    detector.update(frame(start, List.filled(6, 0)), now: start);
    final time = start.add(const Duration(seconds: 10));
    detector.update(frame(time, List.filled(6, 4)), now: time);
    expect(detector.snapshot.stage, ShakeDetectStage.idle);
    expect(detector.snapshot.gridCells, isEmpty);
  });

  test('P-Alert reset cannot reset the shared NIED singleton', () {
    final nied = ShakeDetectionService();
    var niedUpdates = 0;
    final oldCallback = nied.onDetectionSnapshotChanged;
    nied.onDetectionSnapshotChanged = (_) => niedUpdates++;
    try {
      detector.update(frame(start, List.filled(6, 0)), now: start);
      detector.reset();
      expect(niedUpdates, 0);
    } finally {
      nied.onDetectionSnapshotChanged = oldCallback;
    }
  });

  test(
    'hosted JSON transports confirmed grids and never derives them from stations',
    () {
      final time = start.add(const Duration(seconds: 1));
      final raw = frame(time, List.filled(6, 2));
      final noDetection = ForegroundStationPayload.palert(
        raw,
        receivedTime: time,
      );
      expect(
        ForegroundStationPayload.decodePAlertDetection(noDetection, now: time),
        isEmpty,
      );
      detector.update(frame(start, List.filled(6, 0)), now: start);
      detector.update(raw, now: time);
      final decoded = ForegroundStationPayload.decodePAlert(
        jsonDecode(
          jsonEncode(ForegroundStationPayload.palert(raw)),
        )['stations'],
      );
      expect(decoded.map((s) => s.pgaGal), raw.map((s) => s.pgaGal));
      expect(
        decoded.map((s) => s.detectionLevel),
        raw.map((s) => s.detectionLevel),
      );
      final payload =
          jsonDecode(
                jsonEncode(
                  ForegroundStationPayload.palert(
                    raw,
                    dataTime: time,
                    receivedTime: time,
                    detection: detector.snapshot,
                  ),
                ),
              )
              as Map<String, dynamic>;
      final grid = PAlertDetectionGrid()
        ..update(
          ForegroundStationPayload.decodePAlertDetection(payload, now: time),
        );
      expect(
        grid.centers.toSet(),
        detector.snapshot.gridCells.values.map((s) => s.center).toSet(),
      );
      expect(
        ForegroundStationPayload.decodePAlertDetection(
          payload,
          now: time.add(const Duration(seconds: 7)),
        ),
        isEmpty,
      );
      detector.reset();
      final ended = ForegroundStationPayload.palert(
        raw,
        receivedTime: time,
        detection: detector.snapshot,
      );
      expect(
        ForegroundStationPayload.decodePAlertDetection(ended, now: time),
        isEmpty,
      );
    },
  );
}
