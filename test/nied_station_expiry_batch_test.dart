import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/shake_detection_service.dart';

List<NiedStation> stations() => [
  for (var index = 0; index < 192; index++)
    NiedStation(
        id: index,
        code: 'expiry-$index',
        name: 'expiry-$index',
        coordinate: LatLng(34 + index * .0001, 135),
        network: 'test',
        prefecture: 'test',
      expireSeconds: NiedStation.kaExpireSeconds,
      )
      ..level = 11
      ..activity = 20
      ..ascend = 3
      ..triggerStamp = 100
      ..lastDataTime = DateTime.utc(2026, 10, 13, 11, 44, 15),
];

void main() {
  test('simultaneous station hold expiry publishes one combined snapshot', () {
    fakeAsync((clock) {
      final service = ShakeDetectionService.forSource('expiry-test');
      final input = stations();
      final snapshots = <ShakeDetectionSnapshot>[];
      var expired = 0;
      service.onDetectionSnapshotChanged = snapshots.add;
      service.onShakeExpired = () => expired++;
      service.setStations(input);
      service.processUpdate();
      expect(input.every((station) => station.isActive), isTrue);
      expect(snapshots, hasLength(1));
      expect(snapshots.single.detectedStations, hasLength(192));

      clock.elapse(const Duration(milliseconds: 10500));
      // The actual hold deadline is unchanged. Only publication is batched.
      expect(input.every((station) => !station.isActive), isTrue);
      expect(snapshots, hasLength(1));
      clock.elapse(const Duration(milliseconds: 16));
      expect(snapshots, hasLength(2));
      expect(snapshots.last.stage, ShakeDetectStage.idle);
      expect(snapshots.last.detectedStations, isEmpty);
      expect(expired, 1);
      expect(input.every((station) => station.level == 11), isTrue);
      expect(
        input.every(
          (station) =>
              station.lastDataTime == DateTime.utc(2026, 10, 13, 11, 44, 15),
        ),
        isTrue,
      );
      service.reset(detachStations: true, emitSnapshot: false);
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('a real frame cancels a pending expiry publication', () {
    fakeAsync((clock) {
      final service = ShakeDetectionService.forSource('expiry-test');
      final input = stations();
      var publications = 0;
      service.onDetectionSnapshotChanged = (_) => publications++;
      service.setStations(input);
      service.processUpdate();
      clock.elapse(const Duration(milliseconds: 10500));
      service.processUpdate();
      final afterFrame = publications;
      expect(input.every((station) => station.isActive), isTrue);
      clock.elapse(const Duration(milliseconds: 16));
      expect(publications, afterFrame);
      service.reset(detachStations: true, emitSnapshot: false);
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('reset cancels pending expiry work and its timer', () {
    fakeAsync((clock) {
      final service = ShakeDetectionService.forSource('expiry-test');
      final input = stations();
      var publications = 0;
      service.onDetectionSnapshotChanged = (_) => publications++;
      service.setStations(input);
      service.processUpdate();
      clock.elapse(const Duration(milliseconds: 10500));
      service.reset(detachStations: true, emitSnapshot: false);
      final afterReset = publications;
      clock.elapse(const Duration(seconds: 1));
      expect(publications, afterReset);
      expect(clock.pendingTimers, isEmpty);
    });
  });
}
