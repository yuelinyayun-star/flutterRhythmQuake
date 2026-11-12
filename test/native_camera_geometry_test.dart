import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/native_camera_focus.dart';
import 'package:flutterrhythmquake/services/native_camera_focus_portable.dart'
    as portable;

// Frozen previous normal-range calculation: mathematical camera inputs, not
// fabricated earthquake reports. Keep ordering and latitude/longitude math.
Map<String, double> frozenView(List<List<double>> points) {
  var south = double.infinity, north = double.negativeInfinity;
  final longitudes = <double>[];
  for (final p in points) {
    south = math.min(south, p[0]);
    north = math.max(north, p[0]);
    var lng = p[1];
    while (lng <= -180) {
      lng += 360;
    }
    while (lng > 180) {
      lng -= 360;
    }
    longitudes.add(lng < 0 ? lng + 360 : lng);
  }
  longitudes.sort();
  var gap = -1.0, index = 0;
  for (var i = 0; i < longitudes.length; i++) {
    final next = i == longitudes.length - 1
        ? longitudes.first + 360
        : longitudes[i + 1];
    if (next - longitudes[i] > gap) {
      gap = next - longitudes[i];
      index = i;
    }
  }
  final startIndex = (index + 1) % longitudes.length;
  final start = longitudes[startIndex];
  final end = startIndex == 0 ? longitudes[index] : longitudes[index] + 360;
  return {
    'latitude': (south + north) / 2,
    'longitude': (start + end) / 2,
    'latDiff': north - south,
    'lngDiff': end - start,
  };
}

void main() {
  test(
    'range selection runs Rust on unchanged raw float64 including nonfinite values',
    () {
      expect(
        NativeCameraFocus.supported,
        isTrue,
        reason: 'Actual Rust DLL is required',
      );
      final coordinates = Float64List.fromList([
        51.707,
        178.854,
        49.867,
        176.083,
        53.483,
        181.883,
        double.nan,
        1,
        10,
        double.infinity,
        91,
        100,
        0,
        0,
      ]);
      final bytes = Uint8List.fromList(coordinates.buffer.asUint8List());
      final calls = NativeCameraFocus.calls;
      final result = NativeCameraFocus.prepareGeometry(coordinates);
      expect(result['indices'], [0, 1, 2, 6]);
      expect(coordinates.buffer.asUint8List(), bytes);
      expect(NativeCameraFocus.calls, calls + 1);
      expect(NativeCameraFocus.outputs, 0);
      expect(result, portable.NativeCameraFocus.prepareGeometry(coordinates));
    },
  );

  test('normal-range geometry retains frozen pre-fix circular bounds', () {
    expect(NativeCameraFocus.supported, isTrue);
    for (final points in <List<List<double>>>[
      [
        [0, 0],
      ],
      [
        [35.6, 139.7],
        [36.2, 140.3],
        [34.8, 138.5],
      ],
      [
        [10, 179.9],
        [11, -179.8],
      ],
      [
        [10, -180],
        [10, 180],
      ],
      [
        [-90, -170],
        [90, 170],
      ],
      [
        [10, -90],
        [20, 0],
        [30, 90],
        [40, 180],
      ],
    ]) {
      final coordinates = Float64List.fromList(
        points.expand((p) => p).toList(),
      );
      final result = NativeCameraFocus.prepareGeometry(coordinates);
      expect(result['indices'], List.generate(points.length, (i) => i));
      expect(result['view'], frozenView(points));
    }
    expect(NativeCameraFocus.outputs, 0);
  });

  test(
    'range FFI frees repeated outputs and rejects malformed pair counts',
    () {
      expect(NativeCameraFocus.supported, isTrue);
      for (var i = 0; i < 300; i++) {
        final result = NativeCameraFocus.prepareGeometry(
          Float64List.fromList([0, 179, 0, 181, 0, -179, 0, 541]),
        );
        expect(result['view']['lngDiff'], 2.0);
        expect(NativeCameraFocus.outputs, 0);
      }
      final empty = NativeCameraFocus.prepareGeometry(Float64List(0));
      expect(empty['indices'], isEmpty);
      expect(empty['view'], isNull);
      final invalid = NativeCameraFocus.prepareGeometry(
        Float64List.fromList([double.nan, 0, 0, double.negativeInfinity]),
      );
      expect(invalid['view'], isNull);
      expect(
        () => NativeCameraFocus.prepareGeometry(Float64List(1)),
        throwsArgumentError,
      );
      expect(NativeCameraFocus.outputs, 0);
    },
  );
}
