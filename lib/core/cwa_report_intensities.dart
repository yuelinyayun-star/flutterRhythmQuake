import 'dart:convert';

import '../models/unified_quake_data.dart';
import 'cwa_intensity_prediction.dart';

/// Observed report grades only. Never infer regions from the event maximum.
class CwaReportIntensities {
  static bool isObservedRevision(UnifiedQuakeData old, UnifiedQuakeData next) =>
      !old.isEew &&
      !next.isEew &&
      !next.isCanceled &&
      old.source == 'cwaEqlist' &&
      next.source == old.source &&
      old.eventId.isNotEmpty &&
      old.eventId == next.eventId &&
      old.origin == next.origin &&
      old.originTime == next.originTime &&
      old.reportTime == next.reportTime &&
      old.lat == next.lat &&
      old.lng == next.lng &&
      old.depth == next.depth &&
      old.magnitude == next.magnitude &&
      old.warnArea != next.warnArea &&
      fromWarnArea(next.warnArea).isNotEmpty;

  static int? encodedRank(Object? value) {
    final number = num.tryParse(value?.toString() ?? '');
    if (number == null ||
        !number.isFinite ||
        number != number.roundToDouble()) {
      return null;
    }
    final rank = number.toInt();
    return rank >= 0 && rank < CwaIntensityPrediction.labels.length
        ? rank
        : null;
  }

  static Map<String, int> countyRanks(Map<dynamic, dynamic> raw) {
    final ranks = <String, int>{};
    void add(Object? name, int? rank) {
      if (name is! String || rank == null) return;
      final county = CwaIntensityPrediction.canonicalCounty(name.trim());
      if (!CwaIntensityPrediction.counties.contains(county)) return;
      if (rank > (ranks[county] ?? -1)) ranks[county] = rank;
    }

    // ExpTech's int is an ordinal 0..9, not the displayed numeral (6 = 5+).
    final list = raw['list'];
    if (list is Map) {
      for (final entry in list.entries) {
        final county = entry.value;
        if (county is! Map) continue;
        add(entry.key, encodedRank(county['int']));
        final towns = county['town'];
        if (towns is Map) {
          for (final station in towns.values.whereType<Map>()) {
            add(entry.key, encodedRank(station['int']));
          }
        }
      }
    }

    // WHEWS: pref -> areas -> stations, with literal 5-/5+/6-/6+/7 labels.
    final intensities = raw['intensities'];
    if (intensities is List) {
      for (final pref in intensities.whereType<Map>()) {
        add(
          pref['pref'],
          CwaIntensityPrediction.parseRank(pref['maxIntensity']),
        );
        final areas = pref['areas'];
        if (areas is! List) continue;
        for (final area in areas.whereType<Map>()) {
          final name = pref['pref'] ?? area['area'];
          add(name, CwaIntensityPrediction.parseRank(area['maxIntensity']));
          final stations = area['stations'];
          if (stations is! List) continue;
          for (final station in stations.whereType<Map>()) {
            add(name, CwaIntensityPrediction.parseRank(station['intensity']));
          }
        }
      }
    }

    final areas = raw['intensityAreas'];
    if (areas is List) {
      for (final area in areas.whereType<Map>()) {
        add(area['name'], CwaIntensityPrediction.parseRank(area['intensity']));
      }
    }
    return Map.unmodifiable(ranks);
  }

  static String toWarnArea(Map<dynamic, dynamic> raw) {
    final ranks = countyRanks(raw);
    if (ranks.isEmpty) return '';
    final names = ranks.keys.toList()..sort();
    return jsonEncode([
      for (final name in names)
        {
          'name': name,
          'intensity': CwaIntensityPrediction.labels[ranks[name]!],
          'rank': ranks[name],
          'kind': 'observed',
        },
    ]);
  }

  static Map<String, int> fromWarnArea(String text) {
    if (text.isEmpty) return const {};
    try {
      final areas = jsonDecode(text);
      if (areas is! List) return const {};
      return countyRanks({
        'intensityAreas': [
          for (final area in areas.whereType<Map>())
            if (area['kind'] == 'observed') area,
        ],
      });
    } on FormatException {
      return const {};
    }
  }
}
