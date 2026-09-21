import 'package:latlong2/latlong.dart';

import '../../core/calculator.dart';
import '../../models/volcano_event_data.dart';

List<LatLng> volcanoInfoFocusPoints(VolcanoEventData volcano, {DateTime? now}) {
  final points = <LatLng>[];
  void add(double? latitude, double? longitude) {
    if (latitude != null &&
        longitude != null &&
        QuakeCalculator.isUsableMapCoordinate(latitude, longitude)) {
      points.add(LatLng(latitude, longitude));
    }
  }

  add(volcano.latitude, volcano.longitude);
  final window = volcano.mapAshfallWindow(now: now);
  if (window != null) {
    for (final item in window.items) {
      for (final polygon in item.polygons) {
        for (final point in polygon) {
          add(point.latitude, point.longitude);
        }
      }
    }
  }
  return points;
}
