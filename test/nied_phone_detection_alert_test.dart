import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/shake_detection_service.dart';
import 'support/nied_replay_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'original Nara frames retain detection across phone object replacement',
    () async {
      final dir = Directory('tmp/captures/20260610_180130_jst_nara_m36');
      if (!dir.existsSync()) {
        markTestSkipped('Original local Nara GIF capture required.');
        return;
      }
      final images = LmoniImageService()..stop();
      images.start();
      final detector = ShakeDetectionService()..reset(detachStations: true);
      var snapshot = ShakeDetectionService.idleSnapshot;
      final alerts = <int>[];
      final expectedAlerts = <int>[];
      var previousShindo = -1;
      var notifications = 0;
      var focuses = 0;
      detector.onShakeDetected = alerts.add;
      detector.onNotification = (_, _) => notifications++;
      detector.onFocusWindow = () => focuses++;
      detector.onDetectionSnapshotChanged = (value) => snapshot = value;
      addTearDown(() {
        detector.reset(detachStations: true);
        detector.onShakeDetected = null;
        detector.onNotification = null;
        detector.onFocusWindow = null;
        detector.onDetectionSnapshotChanged = null;
        images.stop();
      });
      List<NiedStation>? activeFrame;
      for (var second = 20; second <= 70; second++) {
        final stamp = DateTime(2026, 6, 10, 18, 1, second);
        final decoded = await decodeNiedGifFile(
          File('${dir.path}/${formatNiedTimeKey(stamp)}.lmoni.jma_s.gif'),
        );
        expect(decoded, isNotNull);
        final pending = images.stationStream.firstWhere(
          (value) => value != null,
        );
        images.processPixels(
          decoded!.packedRgb,
          surfaceGifBytes: decoded.gifBytes,
          dataTime: stamp,
          receivedAt: stamp,
        );
        final source = (await pending)!;
        final raw = ForegroundStationPayload.nied(source);
        final frame = ForegroundStationPayload.decodeNied(raw['stations']);
        detector.setStations(frame);
        detector.processUpdate();
        if (snapshot.maxShindo >= 0 && snapshot.maxShindo > previousShindo) {
          expectedAlerts.add(snapshot.maxShindo);
        }
        previousShindo = snapshot.maxShindo;
        expect(alerts, expectedAlerts);
        expect(frame.map((s) => s.level), source.map((s) => s.level));
        expect(frame.map((s) => s.activity), source.map((s) => s.activity));
        if (snapshot.maxShindo >= 0) {
          activeFrame = frame;
          // Re-delivery of the exact original payload must not reset the session.
          final count = alerts.length;
          final notificationCount = notifications;
          final focusCount = focuses;
          for (var repeat = 0; repeat < 3; repeat++) {
            final replacement = ForegroundStationPayload.decodeNied(
              raw['stations'],
            );
            detector.setStations(replacement);
            detector.processUpdate();
            expect(alerts.length, count);
            expect(notifications, notificationCount);
            expect(focuses, focusCount);
            // Held stations may expire during replay; a fall is not an alert.
            expect(snapshot.maxShindo, lessThanOrEqualTo(previousShindo));
            previousShindo = snapshot.maxShindo;
            activeFrame = replacement;
          }
        }
      }
      expect(activeFrame, isNotNull);
      expect(alerts, isNotEmpty);
      // Match KA's rising transitions without imposing a session-peak limit.
      expect(alerts, expectedAlerts);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('transferring a station hold preserves its original expiry', () async {
    final row = NiedStationDb.stations.first;
    final station = NiedStation(
      id: 0,
      code: row['code'] as String,
      name: row['name'] as String,
      coordinate: LatLng(
        (row['lat'] as num).toDouble(),
        (row['lng'] as num).toDouble(),
      ),
      network: row['network'] as String? ?? 'K-NET',
      prefecture: row['pref'] as String? ?? '',
      expireSeconds: 10,
    );
    var expired = 0;
    station.setActive(() => expired++);
    await Future<void>.delayed(const Duration(seconds: 4));
    final replacement = ForegroundStationPayload.decodeNied(
      ForegroundStationPayload.nied([station])['stations'],
    ).single;
    replacement.adoptDetectionHold(station, () => expired++);
    expect(station.activeTimer!.isActive, isFalse);
    expect(replacement.isActive, isTrue);
    await Future<void>.delayed(const Duration(seconds: 6));
    expect(replacement.isActive, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(replacement.isActive, isFalse);
    expect(expired, 1);
    replacement.terminate();
  });
}
