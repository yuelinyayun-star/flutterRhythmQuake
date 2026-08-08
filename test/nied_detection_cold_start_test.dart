import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/shake_detection_service.dart';

NiedStation _station(int id, double lat, double lng) {
  return NiedStation(
    id: id,
    code: 'SIM$id',
    name: 'Sim $id',
    coordinate: LatLng(lat, lng),
    network: 'KNET',
    prefecture: 'TEST',
    expireSeconds: 30,
  );
}

List<NiedStation> _cluster({
  required int count,
  int baseId = 0,
  double lat = 35.0,
  double lng = 139.0,
  double step = 0.03,
}) {
  return List.generate(
    count,
    (i) => _station(baseId + i, lat + i * step, lng + i * step),
  );
}

void _feedFrame(List<NiedStation> stations, List<int> levels) {
  for (var i = 0; i < stations.length; i++) {
    stations[i].update(levels[i]);
  }
}

ShakeDetectionSnapshot _runDetection(List<NiedStation> stations) {
  var snapshot = const ShakeDetectionSnapshot(
    stage: ShakeDetectStage.idle,
    weakCount: 0,
    detectedCount: 0,
    strongCount: 0,
    maxShindo: -1,
  );
  final detector = ShakeDetectionService();
  detector.setSensitivity(2);
  detector.setStations(stations);
  detector.onDetectionSnapshotChanged = (value) => snapshot = value;
  detector.processUpdate();
  return snapshot;
}

void main() {
  test(
    'kanameishi-style clustered rise is detected after a baseline frame',
    () {
      final stations = _cluster(count: 6, baseId: 100);
      _feedFrame(stations, List.filled(stations.length, 0));
      _runDetection(stations);

      _feedFrame(stations, List.filled(stations.length, 20));
      final snapshot = _runDetection(stations);

      expect(snapshot.stage, isNot(ShakeDetectStage.idle));
      expect(stations.where((s) => s.isActive).length, stations.length);
      expect(snapshot.hypoLat, isNull);
      expect(snapshot.hypoLng, isNull);
    },
  );

  test(
    'M2.0 deep-source style weak clustered rise stays as shindo 0 detection',
    () {
      final stations = _cluster(count: 6, baseId: 200);
      _feedFrame(stations, List.filled(stations.length, 5));
      _runDetection(stations);

      _feedFrame(stations, List.filled(stations.length, 7));
      final snapshot = _runDetection(stations);

      expect(snapshot.stage, ShakeDetectStage.weak);
      expect(snapshot.maxShindo, 0);
      expect(snapshot.weakCount, stations.length);
      expect(snapshot.detectedCount, 0);
    },
  );

  test(
    'urban multi-noise isolated spikes do not satisfy nearby count gate',
    () {
      final stations = <NiedStation>[
        ..._cluster(count: 6, baseId: 300, lat: 35.0, lng: 139.0),
        ..._cluster(count: 6, baseId: 400, lat: 35.8, lng: 139.7),
        ..._cluster(count: 6, baseId: 500, lat: 34.7, lng: 135.5),
      ];
      _feedFrame(stations, List.filled(stations.length, 0));
      _runDetection(stations);

      final noisy = List.filled(stations.length, 0);
      noisy[0] = 20;
      noisy[6] = 20;
      noisy[12] = 20;
      _feedFrame(stations, noisy);
      final snapshot = _runDetection(stations);

      expect(snapshot.stage, ShakeDetectStage.idle);
      expect(stations.where((s) => s.isActive), isEmpty);
    },
  );
}
