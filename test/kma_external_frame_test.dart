import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/kma_monitor.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('external KMA frames reuse the PEWS history and gap pipeline', () async {
    final service = KmaMonitorService();
    service.disconnect();
    service.setExternalInputEnabled(true);
    service.setIntensityHoldFrames(3);

    final emitted = <List<KmaStation>>[];
    final subscription = service.stationStream.listen(emitted.add);
    final coordinates = <LatLng>[
      const LatLng(37.5, 127.0),
      const LatLng(35.1, 129.0),
    ];
    final firstTime = DateTime.parse('2026-08-10T12:00:00+09:00');

    service.ingestExternalFrame(
      timestamp: firstTime,
      coordinates: coordinates,
      values: const [1, 2],
    );
    await Future<void>.delayed(Duration.zero);

    expect(emitted, hasLength(1));
    final firstStations = emitted.single;
    expect(firstStations.map((station) => station.intensity), [1, 2]);
    expect(firstStations.first.recentLevel, [3]);

    service.ingestExternalFrame(
      timestamp: firstTime.add(const Duration(seconds: 3)),
      coordinates: coordinates,
      values: const [4, 5],
    );
    await Future<void>.delayed(Duration.zero);

    expect(emitted, hasLength(2));
    final secondStations = emitted.last;
    expect(identical(firstStations.first, secondStations.first), isTrue);
    expect(secondStations.first.recentLevel, [6, -1, -1, 3]);
    expect(secondStations.first.heldIntensity, 4);
    expect(
      service.dataTimeNotifier.value,
      firstTime.add(const Duration(seconds: 3)),
    );

    service.ingestExternalFrame(
      timestamp: firstTime.add(const Duration(seconds: 2)),
      coordinates: coordinates,
      values: const [7, 7],
    );
    await Future<void>.delayed(Duration.zero);
    expect(emitted, hasLength(2));

    await subscription.cancel();
    service.setExternalInputEnabled(false);
    service.resetRealtimeState();
  });
}
