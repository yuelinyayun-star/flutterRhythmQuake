import 'dart:typed_data';
import 'package:latlong2/latlong.dart';
import '../../services/native_camera_focus.dart';

/// UI adapter only: pack unchanged coordinates, then retain the original
/// points selected by the native range policy. Projection stays in Flutter.
class RangeCameraGeometry {
  RangeCameraGeometry._(this.points, this.view);
  final List<LatLng> points;
  final Map<String, dynamic>? view;

  factory RangeCameraGeometry.prepare(List<LatLng> points) {
    final coordinates = Float64List(points.length * 2);
    for (var i = 0; i < points.length; i++) {
      coordinates[i * 2] = points[i].latitude;
      coordinates[i * 2 + 1] = points[i].longitude;
    }
    final result = NativeCameraFocus.prepareGeometry(coordinates);
    return RangeCameraGeometry._([
      for (final index in result['indices'] as List) points[index as int],
    ], result['view'] as Map<String, dynamic>?);
  }
}
