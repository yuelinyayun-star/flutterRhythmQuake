import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../../core/calculator.dart';
import '../../core/utils/jma_seis_int_loc.dart';

List<LatLng> jmaInfoFocusPoints({
  required String warnAreaJson,
  double? epicenterLatitude,
  double? epicenterLongitude,
}) {
  final points = <LatLng>[];
  if (epicenterLatitude != null &&
      epicenterLongitude != null &&
      QuakeCalculator.isUsableMapCoordinate(
        epicenterLatitude,
        epicenterLongitude,
      )) {
    points.add(LatLng(epicenterLatitude, epicenterLongitude));
  }

  final names = <String>{};
  try {
    final decoded = json.decode(warnAreaJson);
    if (decoded is List) {
      for (final item in decoded) {
        if (item is! Map) continue;
        final name = item['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) names.add(name);
      }
    }
  } catch (_) {
    return points;
  }
  if (names.isEmpty) return points;

  final stationsBySect = JmaSeisIntLoc.getStationsBySect();
  var minLat = double.infinity;
  var maxLat = double.negativeInfinity;
  var minLng = double.infinity;
  var maxLng = double.negativeInfinity;
  for (final name in names) {
    final stations = stationsBySect[name];
    if (stations == null) continue;
    for (final station in stations) {
      minLat = station.lat < minLat ? station.lat : minLat;
      maxLat = station.lat > maxLat ? station.lat : maxLat;
      minLng = station.lng < minLng ? station.lng : minLng;
      maxLng = station.lng > maxLng ? station.lng : maxLng;
    }
  }

  if (minLat.isFinite && minLng.isFinite) {
    points.add(LatLng(minLat, minLng));
    if (maxLat != minLat || maxLng != minLng) {
      points.add(LatLng(maxLat, maxLng));
    }
  }
  return points;
}
