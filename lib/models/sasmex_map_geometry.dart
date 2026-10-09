import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../core/utils/quake_time.dart';
import 'unified_quake_data.dart';

/// Display model used by the reference website, never source measurements.
class SasmexMapAnimation {
  final LatLng center;
  final double elapsedSeconds;
  final bool severe;

  const SasmexMapAnimation(this.center, this.elapsedSeconds, this.severe);

  // Same propagation rule as our SASMEX wave layer, not a depth estimate.
  static const sWaveSpeedKmPerSecond = 5.0;
  static double sArrivalSeconds(double distanceKm) =>
      distanceKm / sWaveSpeedKmPerSecond;

  // The website stops updating at 2000 km and retains the last wave geometry.
  double get waveSeconds => math.min(elapsedSeconds, 243);
  double get pRadiusMeters => math.max(500, (waveSeconds + 7) * 8000);
  double get sRadiusMeters =>
      math.max(500, waveSeconds * sWaveSpeedKmPerSecond * 1000);

  static double cameraRadiusKm(double elapsedSeconds, {required bool severe}) {
    if (elapsedSeconds < 0 || elapsedSeconds >= (severe ? 300 : 180)) return 0;
    return math.max(.5, (math.min(elapsedSeconds, 243) + 7) * 8);
  }

  static SasmexMapAnimation? at(UnifiedQuakeData event, DateTime now) {
    final lat = event.lat;
    final lng = event.lng;
    if (event.source != 'sasmex' ||
        !event.isEew ||
        event.isHistory ||
        event.isCanceled ||
        event.originTime == null ||
        lat == null ||
        lng == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180) {
      return null;
    }
    final elapsed =
        now
            .toUtc()
            .subtract(event.replayClockOffset)
            .difference(QuakeTime.unifiedInstantUtc(event))
            .inMilliseconds /
        1000;
    final severe = event.sourcePayload?['severity'] == 'Severe';
    // Reference website: five minutes for Severe, three for detection.
    if (elapsed < 0 || elapsed >= (severe ? 300 : 180)) return null;
    return SasmexMapAnimation(LatLng(lat, lng), elapsed, severe);
  }
}

class SasmexStateGeometry {
  final String name;

  /// Each polygon holds its exterior ring followed by its holes.
  final List<List<List<LatLng>>> polygons;
  const SasmexStateGeometry(this.name, this.polygons);

  bool contains(LatLng point) => polygons.any(
    (rings) =>
        _inside(point, rings.first) &&
        !rings.skip(1).any((hole) => _inside(point, hole)),
  );

  static bool _inside(LatLng point, List<LatLng> ring) {
    var inside = false;
    for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i], b = ring[j];
      if ((a.latitude > point.latitude) != (b.latitude > point.latitude) &&
          point.longitude <
              (b.longitude - a.longitude) *
                      (point.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude) {
        inside = !inside;
      }
    }
    return inside;
  }
}

/// State geometry from the reference website.
/// No online status, intensity, default hypocenter or event values are added.
class SasmexMapCatalog {
  final List<SasmexStateGeometry> states;
  const SasmexMapCatalog(this.states);

  static Future<SasmexMapCatalog>? _cached;
  static Future<SasmexMapCatalog> load() => _cached ??= _load();
  static Future<SasmexMapCatalog> _load() async {
    return decode(
      await rootBundle.loadString('assets/maps/mexico_states.geojson'),
    );
  }

  static SasmexMapCatalog decode(String geojson) {
    final data = jsonDecode(geojson) as Map<String, dynamic>;
    final states = <SasmexStateGeometry>[];
    for (final feature in data['features'] as List) {
      final geometry = feature['geometry'] as Map;
      final coordinates = geometry['coordinates'] as List;
      final polygons = geometry['type'] == 'Polygon'
          ? [coordinates]
          : coordinates;
      states.add(
        SasmexStateGeometry(feature['properties']['name'] as String, [
          for (final polygon in polygons)
            [
              for (final ring in polygon as List)
                [
                  for (final point in ring as List)
                    LatLng(
                      (point[1] as num).toDouble(),
                      (point[0] as num).toDouble(),
                    ),
                ],
            ],
        ]),
      );
    }
    return SasmexMapCatalog(states);
  }

  SasmexStateGeometry? stateFor(UnifiedQuakeData event) {
    final raw = event.sourcePayload;
    final name = _normalize(
      (raw?['region'] ?? raw?['place'] ?? raw?['location'] ?? '')
          .toString()
          .split(',')
          .first,
    );
    if (name.isNotEmpty) {
      for (final state in states) {
        final candidate = _normalize(state.name);
        if (candidate == name ||
            candidate.contains(name) ||
            name.contains(candidate)) {
          return state;
        }
      }
    }
    final lat = event.lat, lng = event.lng;
    if (lat == null ||
        lng == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180) {
      return null;
    }
    for (final state in states) {
      if (state.contains(LatLng(lat, lng))) return state;
    }
    return null;
  }

  static String _normalize(String name) {
    var result = name.toLowerCase().trim().replaceAll(
      RegExp(r'[\u0300-\u036f]'),
      '',
    );
    const accents = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    accents.forEach((from, to) => result = result.replaceAll(from, to));
    return result;
  }
}
