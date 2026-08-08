import 'dart:math' as math;

import '../../../calculator.dart';

abstract final class Matsuzaki2006PointSourceGeometry {
  static double hypocentralDistanceFromEpicentral({
    required double epicentralDistanceKm,
    required double depthKm,
  }) {
    _validateNonNegativeFinite(epicentralDistanceKm, 'epicentralDistanceKm');
    _validateNonNegativeFinite(depthKm, 'depthKm');
    return math.sqrt(
      epicentralDistanceKm * epicentralDistanceKm + depthKm * depthKm,
    );
  }

  static double hypocentralDistanceBetween({
    required double sourceLatitude,
    required double sourceLongitude,
    required double stationLatitude,
    required double stationLongitude,
    required double depthKm,
  }) {
    _validateCoordinate(sourceLatitude, sourceLongitude, 'source');
    _validateCoordinate(stationLatitude, stationLongitude, 'station');
    _validateNonNegativeFinite(depthKm, 'depthKm');
    final epicentralDistanceKm = QuakeCalculator.haversineDistance(
      sourceLatitude,
      sourceLongitude,
      stationLatitude,
      stationLongitude,
    );
    return hypocentralDistanceFromEpicentral(
      epicentralDistanceKm: epicentralDistanceKm,
      depthKm: depthKm,
    );
  }

  static void _validateCoordinate(
    double latitude,
    double longitude,
    String name,
  ) {
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      throw RangeError.value(
        latitude,
        '${name}Latitude',
        'Must be a finite latitude within -90..90.',
      );
    }
    if (!longitude.isFinite || longitude < -180 || longitude > 180) {
      throw RangeError.value(
        longitude,
        '${name}Longitude',
        'Must be a finite longitude within -180..180.',
      );
    }
  }

  static void _validateNonNegativeFinite(double value, String name) {
    if (!value.isFinite || value < 0) {
      throw ArgumentError.value(
        value,
        name,
        'Must be finite and non-negative.',
      );
    }
  }
}
