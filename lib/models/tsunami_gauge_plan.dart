/// Passive native presentation data. No unit conversion or aggregation in Dart.
class TsunamiGaugeData {
  const TsunamiGaugeData({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.forecastText,
    required this.forecastUnit,
    required this.forecastLabel,
    required this.observationText,
    required this.observationUnit,
    required this.observationLabel,
    this.forecastFraction,
    this.observedFraction,
    this.members = const [],
  });
  final String id, name, forecastText, forecastUnit, forecastLabel;
  final String observationText, observationUnit, observationLabel;
  final double latitude, longitude;
  final double? forecastFraction, observedFraction;
  final List<int> members;

  factory TsunamiGaugeData.fromMap(Map map) => TsunamiGaugeData(
    id: map['id'] as String,
    name: map['name'] as String,
    latitude: (map['latitude'] as num).toDouble(),
    longitude: (map['longitude'] as num).toDouble(),
    forecastText: map['forecastText'] as String,
    forecastUnit: map['forecastUnit'] as String,
    forecastLabel: map['forecastLabel'] as String,
    observationText: map['observationText'] as String,
    observationUnit: map['observationUnit'] as String,
    observationLabel: map['observationLabel'] as String,
    forecastFraction: (map['forecastFraction'] as num?)?.toDouble(),
    observedFraction: (map['observedFraction'] as num?)?.toDouble(),
    members: (map['members'] as List).cast<int>(),
  );
}

class TsunamiGaugePlan {
  const TsunamiGaugePlan({
    this.markers = const [],
    this.levels = const [],
    this.entries = const [],
    this.scaleMetres,
    this.expiresUtcMs,
  });
  final List<TsunamiGaugeData> markers;
  final List<List<int>> levels;
  final List<Map<String, dynamic>> entries;
  final double? scaleMetres;
  final int? expiresUtcMs;
  factory TsunamiGaugePlan.fromMap(Map map) => TsunamiGaugePlan(
    markers: [
      for (final row in map['markers'] as List)
        TsunamiGaugeData.fromMap(row as Map),
    ],
    levels: [
      for (final row in map['levels'] as List) (row as List).cast<int>(),
    ],
    entries: [
      for (final row in map['entries'] as List)
        Map<String, dynamic>.from(row as Map),
    ],
    scaleMetres: (map['scaleMetres'] as num?)?.toDouble(),
    expiresUtcMs: (map['expiresUtcMs'] as num?)?.toInt(),
  );
  Iterable<TsunamiGaugeData> atZoom(double zoom) => levels.isEmpty
      ? const []
      : levels[zoom.floor().clamp(0, levels.length - 1)].map(
          (index) => markers[index],
        );
}
