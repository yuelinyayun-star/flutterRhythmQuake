import 'dart:ui';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class WorldWrap {
  WorldWrap._();

  static double normalizeLongitude(double longitude) {
    var value = longitude;
    while (value <= -180) {
      value += 360;
    }
    while (value > 180) {
      value -= 360;
    }
    return value;
  }

  static double longitudeClosestTo(double longitude, double reference) {
    var value = longitude;
    while (value - reference > 180) {
      value -= 360;
    }
    while (reference - value > 180) {
      value += 360;
    }
    return value;
  }

  static LatLng latLngClosestToCamera(LatLng point, MapCamera camera) {
    return LatLng(
      point.latitude,
      longitudeClosestTo(point.longitude, camera.center.longitude),
    );
  }

  /// Unproject in the base world before restoring the longitude world copy.
  /// Mercator's inverse projection clamps longitudes outside [-180, 180].
  static LatLng unprojectUnwrapped(
    MapCamera camera,
    Offset point, {
    double? zoom,
  }) {
    final targetZoom = zoom ?? camera.zoom;
    final worldWidth = camera.getWorldWidthAtZoom(targetZoom);
    if (worldWidth <= 0) return camera.unprojectAtZoom(point, targetZoom);
    final worldLeft = camera
        .projectAtZoom(const LatLng(0, -180), targetZoom)
        .dx;
    final world = ((point.dx - worldLeft) / worldWidth).floor();
    final position = camera.unprojectAtZoom(
      Offset(point.dx - world * worldWidth, point.dy),
      targetZoom,
    );
    return LatLng(position.latitude, position.longitude + world * 360);
  }
}
