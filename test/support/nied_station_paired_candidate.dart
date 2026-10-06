import 'dart:math' as math;

import 'package:flutterrhythmquake/core/source_estimation/srev_kaizou_magnitude.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';

final _stationCoordinates = {
  for (final station in NiedStationDb.stations)
    station['code'] as String: (
      latitude: (station['lat'] as num).toDouble(),
      longitude: (station['lng'] as num).toDouble(),
    ),
};

/// Shadow candidate only: pair each strongest observation with its own distance.
Map<String, Object?> calculateNiedStationPairedCandidate({
  required double latitude,
  required double longitude,
  required double? intensity,
  required List<String> strongestCodes,
  required bool multipleSources,
}) {
  final base = <String, Object?>{
    'feedsProduction': false,
    'readyForProduction': false,
    'labelsUsedInInference': false,
    'model': 'event_peak_strongest_station_distance_shadow_v1',
    'tiePolicy': 'median_of_equal_intensity_strongest_station_magnitudes',
    'depthCorrectionApplied': false,
    'stationDbVersion': NiedStationDb.stationDbVersion,
  };
  if (!latitude.isFinite ||
      !longitude.isFinite ||
      intensity == null ||
      !intensity.isFinite ||
      strongestCodes.isEmpty) {
    return {...base, 'supported': false, 'reason': 'invalid_geometry_or_peak'};
  }
  final missing = strongestCodes
      .where((code) => !_stationCoordinates.containsKey(code))
      .toList();
  if (missing.isNotEmpty) {
    return {
      ...base,
      'supported': false,
      'reason': 'unknown_strongest_station',
      'missingCodes': missing,
    };
  }
  final rows = <Map<String, Object?>>[];
  final magnitudes = <double>[];
  for (final code in strongestCodes) {
    final station = _stationCoordinates[code]!;
    final distance = srevKaizouStationDistanceKm(
      roundedSourceLatitude: srevKaizouRoundCoordinate(latitude),
      roundedSourceLongitude: srevKaizouRoundCoordinate(longitude),
      stationLatitude: station.latitude,
      stationLongitude: station.longitude,
    );
    final clamped = math.max(srevKaizouMinimumStationDistanceKm, distance);
    final magnitude = srevKaizouMagnitudeFromDistanceAndIntensity(
      stationDistanceKm: clamped,
      inputIntensity: intensity,
      multipleSources: multipleSources,
    );
    if (magnitude == null) {
      return {
        ...base,
        'supported': false,
        'reason': 'nonfinite_station_magnitude',
        'code': code,
      };
    }
    magnitudes.add(magnitude);
    rows.add({
      'code': code,
      'intensity': intensity,
      'epicentralDistanceKm': distance,
      'clampedDistanceKm': clamped,
      'magnitude': magnitude,
    });
  }
  magnitudes.sort();
  final middle = magnitudes.length ~/ 2;
  final median = magnitudes.length.isOdd
      ? magnitudes[middle]
      : (magnitudes[middle - 1] + magnitudes[middle]) / 2;
  return {
    ...base,
    'supported': true,
    'magnitude': median,
    'minimum': magnitudes.first,
    'maximum': magnitudes.last,
    'stations': rows,
  };
}
