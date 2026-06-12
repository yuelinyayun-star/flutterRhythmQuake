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
}
