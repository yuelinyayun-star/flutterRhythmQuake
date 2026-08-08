import 'dart:math' as math;

import '../../../calculator.dart';

class Matsuzaki2006RectangularFaultPlane {
  const Matsuzaki2006RectangularFaultPlane({
    required this.id,
    required double upperEdgeStartLatitude,
    required double upperEdgeStartLongitude,
    required double upperEdgeDepthKm,
    required this.lengthKm,
    required this.widthKm,
    required this.upperEdgeAzimuthDegrees,
    required this.downDipAzimuthDegrees,
    required this.dipDegrees,
  }) : referencePointRole = 'upper_edge_start',
       referenceLatitude = upperEdgeStartLatitude,
       referenceLongitude = upperEdgeStartLongitude,
       referenceDepthKm = upperEdgeDepthKm,
       referenceAlongLengthKm = 0,
       referenceDownDipKm = 0;

  const Matsuzaki2006RectangularFaultPlane.fromPointOnPlane({
    required this.id,
    required this.referencePointRole,
    required this.referenceLatitude,
    required this.referenceLongitude,
    required this.referenceDepthKm,
    required this.referenceAlongLengthKm,
    required this.referenceDownDipKm,
    required this.lengthKm,
    required this.widthKm,
    required this.upperEdgeAzimuthDegrees,
    required this.downDipAzimuthDegrees,
    required this.dipDegrees,
  });

  final String id;
  final String referencePointRole;
  final double referenceLatitude;
  final double referenceLongitude;
  final double referenceDepthKm;

  /// Distance from the upper-edge start to the reference point along strike.
  final double referenceAlongLengthKm;

  /// Distance from the upper edge to the reference point down dip.
  final double referenceDownDipKm;
  final double lengthKm;
  final double widthKm;

  /// Direction from the supplied upper-edge start point to its other endpoint.
  final double upperEdgeAzimuthDegrees;

  /// Horizontal azimuth of the down-dip direction.
  final double downDipAzimuthDegrees;
  final double dipDegrees;

  double shortestDistanceToSurfacePoint({
    required double latitude,
    required double longitude,
  }) {
    _validate();
    _validateCoordinate(latitude, longitude, 'station');
    final local = _surfaceOffsetFromReferencePoint(
      latitude: latitude,
      longitude: longitude,
    );
    final strikeRadians = _degreesToRadians(upperEdgeAzimuthDegrees);
    final dipAzimuthRadians = _degreesToRadians(downDipAzimuthDegrees);
    final dipRadians = _degreesToRadians(dipDegrees);
    final alongLength = _Vector3(
      east: math.sin(strikeRadians),
      north: math.cos(strikeRadians),
      down: 0,
    );
    final downDip = _Vector3(
      east: math.sin(dipAzimuthRadians) * math.cos(dipRadians),
      north: math.cos(dipAzimuthRadians) * math.cos(dipRadians),
      down: math.sin(dipRadians),
    );
    final relative = _Vector3(
      east: local.$1,
      north: local.$2,
      down: -referenceDepthKm,
    );
    final lengthProjection = _clamp(
      relative.dot(alongLength),
      -referenceAlongLengthKm,
      lengthKm - referenceAlongLengthKm,
    );
    final widthProjection = _clamp(
      relative.dot(downDip),
      -referenceDownDipKm,
      widthKm - referenceDownDipKm,
    );
    final closest =
        alongLength.scaled(lengthProjection) + downDip.scaled(widthProjection);
    return (relative - closest).length;
  }

  Map<String, Object> toJson() => {
    'id': id,
    'referencePoint': {
      'role': referencePointRole,
      'latitude': referenceLatitude,
      'longitude': referenceLongitude,
      'depthKm': referenceDepthKm,
      'alongLengthKm': referenceAlongLengthKm,
      'downDipKm': referenceDownDipKm,
    },
    'inferredUpperEdgeDepthKm':
        referenceDepthKm -
        referenceDownDipKm * math.sin(_degreesToRadians(dipDegrees)),
    'lengthKm': lengthKm,
    'widthKm': widthKm,
    'upperEdgeAzimuthDegrees': upperEdgeAzimuthDegrees,
    'downDipAzimuthDegrees': downDipAzimuthDegrees,
    'dipDegrees': dipDegrees,
    'distanceDefinition':
        'minimum_3d_distance_from_surface_station_to_finite_rectangle',
  };

  (double, double) _surfaceOffsetFromReferencePoint({
    required double latitude,
    required double longitude,
  }) {
    final distanceKm = QuakeCalculator.haversineDistance(
      referenceLatitude,
      referenceLongitude,
      latitude,
      longitude,
    );
    if (distanceKm == 0) return (0, 0);
    final startLatitudeRadians = _degreesToRadians(referenceLatitude);
    final stationLatitudeRadians = _degreesToRadians(latitude);
    final longitudeDeltaRadians = _degreesToRadians(
      longitude - referenceLongitude,
    );
    final bearing = math.atan2(
      math.sin(longitudeDeltaRadians) * math.cos(stationLatitudeRadians),
      math.cos(startLatitudeRadians) * math.sin(stationLatitudeRadians) -
          math.sin(startLatitudeRadians) *
              math.cos(stationLatitudeRadians) *
              math.cos(longitudeDeltaRadians),
    );
    return (distanceKm * math.sin(bearing), distanceKm * math.cos(bearing));
  }

  void _validate() {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be empty.');
    }
    if (referencePointRole.isEmpty) {
      throw ArgumentError.value(
        referencePointRole,
        'referencePointRole',
        'Must not be empty.',
      );
    }
    _validateCoordinate(referenceLatitude, referenceLongitude, 'reference');
    _validatePositive(referenceDepthKm, 'referenceDepthKm');
    _validatePositive(lengthKm, 'lengthKm');
    _validatePositive(widthKm, 'widthKm');
    _validateOffset(referenceAlongLengthKm, lengthKm, 'referenceAlongLengthKm');
    _validateOffset(referenceDownDipKm, widthKm, 'referenceDownDipKm');
    _validateAzimuth(upperEdgeAzimuthDegrees, 'upperEdgeAzimuthDegrees');
    _validateAzimuth(downDipAzimuthDegrees, 'downDipAzimuthDegrees');
    final azimuthDifference = _degreesToRadians(
      downDipAzimuthDegrees - upperEdgeAzimuthDegrees,
    );
    if (math.cos(azimuthDifference).abs() > 1e-10) {
      throw ArgumentError(
        'upperEdgeAzimuthDegrees and downDipAzimuthDegrees must be '
        'orthogonal.',
      );
    }
    if (!dipDegrees.isFinite || dipDegrees <= 0 || dipDegrees > 90) {
      throw RangeError.value(
        dipDegrees,
        'dipDegrees',
        'Must be finite and within (0, 90].',
      );
    }
    final upperEdgeDepthKm =
        referenceDepthKm -
        referenceDownDipKm * math.sin(_degreesToRadians(dipDegrees));
    if (upperEdgeDepthKm < 0) {
      throw RangeError.value(
        upperEdgeDepthKm,
        'inferredUpperEdgeDepthKm',
        'The supplied reference point places the upper edge above ground.',
      );
    }
  }

  static void _validateCoordinate(
    double latitude,
    double longitude,
    String name,
  ) {
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      throw RangeError.value(latitude, '${name}Latitude');
    }
    if (!longitude.isFinite || longitude < -180 || longitude > 180) {
      throw RangeError.value(longitude, '${name}Longitude');
    }
  }

  static void _validatePositive(double value, String name) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(value, name, 'Must be finite and positive.');
    }
  }

  static void _validateOffset(double value, double extent, String name) {
    if (!value.isFinite || value < 0 || value > extent) {
      throw RangeError.value(value, name, 'Must be within [0, $extent].');
    }
  }

  static void _validateAzimuth(double value, String name) {
    if (!value.isFinite || value < 0 || value >= 360) {
      throw RangeError.value(value, name, 'Must be within [0, 360).');
    }
  }

  static double _degreesToRadians(double value) => value * math.pi / 180;
  static double _clamp(double value, double minimum, double maximum) =>
      math.max(minimum, math.min(maximum, value));
}

abstract final class Matsuzaki2006FiniteFaultGeometry {
  static double shortestDistanceToFaultUnion({
    required List<Matsuzaki2006RectangularFaultPlane> faultPlanes,
    required double stationLatitude,
    required double stationLongitude,
  }) {
    if (faultPlanes.isEmpty) {
      throw ArgumentError.value(
        faultPlanes,
        'faultPlanes',
        'Must contain at least one finite rectangle.',
      );
    }
    return faultPlanes
        .map(
          (plane) => plane.shortestDistanceToSurfacePoint(
            latitude: stationLatitude,
            longitude: stationLongitude,
          ),
        )
        .reduce(math.min);
  }
}

class _Vector3 {
  const _Vector3({required this.east, required this.north, required this.down});

  final double east;
  final double north;
  final double down;

  double dot(_Vector3 other) =>
      east * other.east + north * other.north + down * other.down;

  double get length => math.sqrt(dot(this));

  _Vector3 scaled(double factor) =>
      _Vector3(east: east * factor, north: north * factor, down: down * factor);

  _Vector3 operator +(_Vector3 other) => _Vector3(
    east: east + other.east,
    north: north + other.north,
    down: down + other.down,
  );

  _Vector3 operator -(_Vector3 other) => _Vector3(
    east: east - other.east,
    north: north - other.north,
    down: down - other.down,
  );
}
