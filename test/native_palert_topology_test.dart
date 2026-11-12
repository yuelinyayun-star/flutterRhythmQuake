import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/native_palert_topology.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'palert_live_source_driver_test.dart' show fixture, originalFrames;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native WGS84 preserves every neighbor for 787 original P-Alert stations',
    () {
      final stations = ForegroundStationPayload.decodePAlert(
        originalFrames().first.snapshot['stations'],
      );
      final coordinates = [
        for (final station in stations) ...[
          station.coordinate.latitude,
          station.coordinate.longitude,
        ],
      ];
      final before = List<double>.of(coordinates);
      final expected = jsonDecode(
        File(
          '$fixture/golden_neighbors.derived.json',
        ).readAsStringSync(encoding: utf8),
      );
      expect(stations, hasLength(787));
      expect(NativePAlertTopology.build(coordinates), expected);
      expect(coordinates, before);
      expect(NativePAlertTopology.build([]), isEmpty);
      expect(() => NativePAlertTopology.build([1]), throwsArgumentError);
    },
    skip: !NativePAlertTopology.supported,
  );
}
