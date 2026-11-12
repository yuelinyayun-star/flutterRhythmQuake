import 'package:latlong2/latlong.dart';

import '../../models/cenc_ir_data.dart';
import '../intensity_calculator.dart';
import 'topojson_loader.dart';

/// Match original station observations to the same administrative geometry
/// used by the intensity fill layer. Unobserved areas receive no value.
class CencIrRegionIntensities {
  static final _indexes = Expando<List<_RegionBounds>>();
  static final _projections = Expando<_StationRegions>();

  static bool isFilled(double intensity, {double minIntensity = 1}) =>
      intensity.isFinite && intensity.round().clamp(0, 12) >= minIntensity;

  static Map<String, double> fromStations(
    TopoJsonData geography,
    List<InstrumentIntensity> stations,
  ) => _project(geography, stations).values;

  /// Four extent corners enclose all painted polygons beyond the stations.
  static List<LatLng> filledBounds(
    TopoJsonData geography,
    List<InstrumentIntensity> stations,
  ) => _project(geography, stations).bounds;

  static _StationRegions _project(
    TopoJsonData geography,
    List<InstrumentIntensity> stations,
  ) {
    final cached = _projections[stations];
    if (cached != null && identical(cached.geography, geography)) return cached;
    final index = _indexes[geography] ??= [
      for (final region in geography.regions)
        for (final polygon in region.polygons)
          if (polygon.length >= 3) _RegionBounds(region.name, polygon),
    ];
    final values = <String, double>{};
    for (final station in stations) {
      if (!station.hasUsableCoordinate || !station.intensity.isFinite) {
        continue;
      }
      for (final area in index) {
        if (!area.contains(station)) continue;
        final previous = values[area.name];
        if (previous == null || station.intensity > previous) {
          values[area.name] = station.intensity;
        }
      }
    }
    var south = double.infinity, north = double.negativeInfinity;
    var west = double.infinity, east = double.negativeInfinity;
    for (final area in index) {
      final value = values[area.name];
      if (value == null || !isFilled(value)) continue;
      if (area.south < south) south = area.south;
      if (area.north > north) north = area.north;
      if (area.west < west) west = area.west;
      if (area.east > east) east = area.east;
    }
    return _projections[stations] = _StationRegions(
      geography,
      Map.unmodifiable(values),
      List.unmodifiable(
        south.isFinite
            ? [
                LatLng(south, west),
                LatLng(south, east),
                LatLng(north, west),
                LatLng(north, east),
              ]
            : <LatLng>[],
      ),
    );
  }
}

class _StationRegions {
  const _StationRegions(this.geography, this.values, this.bounds);
  final TopoJsonData geography;
  final Map<String, double> values;
  final List<LatLng> bounds;
}

class _RegionBounds {
  _RegionBounds(this.name, this.polygon) {
    for (final point in polygon) {
      if (point.latitude < south) south = point.latitude;
      if (point.latitude > north) north = point.latitude;
      if (point.longitude < west) west = point.longitude;
      if (point.longitude > east) east = point.longitude;
    }
  }

  final String name;
  final List<LatLng> polygon;
  double south = double.infinity;
  double north = double.negativeInfinity;
  double west = double.infinity;
  double east = double.negativeInfinity;

  bool contains(InstrumentIntensity station) =>
      station.latitude >= south &&
      station.latitude <= north &&
      station.longitude >= west &&
      station.longitude <= east &&
      IntensityCalculator.pointInPolygon(
        station.latitude,
        station.longitude,
        polygon,
      );
}
