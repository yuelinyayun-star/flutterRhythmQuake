import 'dart:convert';
import 'dart:math' as math;

import 'cwa_prediction_towns.dart';

class CwaIntensityForecast {
  const CwaIntensityForecast(
    this.townRanks,
    this.countyRanks,
    this.maximumRank,
  );

  final Map<String, int> townRanks;
  final Map<String, int> countyRanks;
  final int maximumRank;
}

/// Local Taiwan PGA prediction. R is hypocentral distance in km; PGA is Gal.
class CwaIntensityPrediction {
  static const labels = ['0', '1', '2', '3', '4', '5-', '5+', '6-', '6+', '7'];
  static const pgaThresholds = [
    0.8,
    2.5,
    8.0,
    25.0,
    80.0,
    140.0,
    250.0,
    440.0,
    800.0,
  ];
  static const markerLevels = [7, 9, 11, 13, 15, 16, 17, 18, 19, 20];
  static const countyAliases = <String, String>{
    '台北市': '臺北市',
    '台中市': '臺中市',
    '台南市': '臺南市',
    '宜兰县': '宜蘭縣',
    '桃园市': '桃園市',
    '嘉义市': '嘉義市',
    '新竹县': '新竹縣',
    '苗栗县': '苗栗縣',
    '南投县': '南投縣',
    '彰化县': '彰化縣',
    '云林县': '雲林縣',
    '嘉义县': '嘉義縣',
    '屏东县': '屏東縣',
    '花莲县': '花蓮縣',
    '台东县': '臺東縣',
    '澎湖县': '澎湖縣',
    '金门县': '金門縣',
    '连江县': '連江縣',
  };
  static final counties = cwaPredictionTowns.map((t) => t.county).toSet();
  static final Map<Object, CwaIntensityForecast> _cache = {};
  static const cacheLimit = 24;

  static String canonicalCounty(String name) => countyAliases[name] ?? name;

  static int? parseRank(Object? value) {
    final text = value
        ?.toString()
        .trim()
        .replaceAll('弱', '-')
        .replaceAll('強', '+')
        .replaceAll('强', '+');
    if (text == null) return null;
    final rank = labels.indexOf(text);
    if (rank >= 0) return rank;
    if (text == '5') return 5;
    if (text == '6') return 7;
    final number = double.tryParse(text);
    if (number != null && number.isFinite && number == number.roundToDouble()) {
      final integer = number.toInt();
      if (integer == 5) return 5;
      if (integer == 6) return 7;
      final index = labels.indexOf(integer.toString());
      return index >= 0 ? index : null;
    }
    return null;
  }

  static int rankForPga(double pga) {
    if (pga.isNaN || pga < 0) throw ArgumentError.value(pga, 'pga');
    for (var rank = 0; rank < pgaThresholds.length; rank++) {
      if (pga < pgaThresholds[rank]) return rank;
    }
    return pgaThresholds.length;
  }

  static double surfaceDistanceKm(
    double lat,
    double lng,
    double targetLat,
    double targetLng,
  ) {
    final meanLat = (lat + targetLat) / 2;
    final latScale =
        ((-0.000003885162 * meanLat + 0.0005279958) * meanLat - 0.004162794) *
            meanLat +
        110.60424;
    final lngScale =
        ((0.0000614022 * meanLat - 0.0204) * meanLat + 0.091614) * meanLat +
        110.44248;
    final dy = (lat - targetLat) * latScale;
    final dx = (lng - targetLng) * lngScale;
    return math.sqrt(dx * dx + dy * dy);
  }

  static double pgaAt({
    required double magnitude,
    required double depth,
    required double lat,
    required double lng,
    required double targetLat,
    required double targetLng,
    required double siteFactor,
    required double adjustment,
  }) {
    final surface = surfaceDistanceKm(lat, lng, targetLat, targetLng);
    final distance = math.sqrt(surface * surface + depth * depth);
    return 1.657 *
        math.exp(1.533 * magnitude) *
        math.pow(distance, -1.607) *
        siteFactor *
        adjustment;
  }

  static CwaIntensityForecast? predict({
    required double magnitude,
    required double depth,
    required double lat,
    required double lng,
    required double adjustment,
    String warnAreaJson = '',
  }) {
    if (!magnitude.isFinite ||
        magnitude <= 0 ||
        !depth.isFinite ||
        depth < 0 ||
        !lat.isFinite ||
        lat.abs() > 90 ||
        !lng.isFinite ||
        lng.abs() > 180 ||
        (lat == 0 && lng == 0) ||
        !adjustment.isFinite ||
        adjustment <= 0) {
      return null;
    }
    final key = (magnitude, depth, lat, lng, adjustment, warnAreaJson);
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    final reported = _reportedAreas(warnAreaJson);
    final towns = <String, int>{};
    final countyRanks = <String, int>{};
    var maximum = 0;
    final amplitude = 1.657 * math.exp(1.533 * magnitude) * adjustment;
    final depthSquared = depth * depth;
    for (final town in cwaPredictionTowns) {
      final name = '${town.county}${town.town}';
      final surface = surfaceDistanceKm(lat, lng, town.lat, town.lng);
      final distance = math.sqrt(surface * surface + depthSquared);
      // No measured site factor is present for these offshore reference points.
      final predicted = rankForPga(
        amplitude * math.pow(distance, -1.607) * (town.site ?? 1),
      );
      final rank =
          reported[name] ??
          reported[town.area] ??
          reported[town.county] ??
          predicted;
      towns[name] = rank;
      countyRanks[town.county] = math.max(countyRanks[town.county] ?? 0, rank);
      maximum = math.max(maximum, rank);
    }
    final result = CwaIntensityForecast(
      Map.unmodifiable(towns),
      Map.unmodifiable(countyRanks),
      maximum,
    );
    _cache[key] = result;
    if (_cache.length > cacheLimit) _cache.remove(_cache.keys.first);
    return result;
  }

  static Map<String, int> _reportedAreas(String text) {
    if (text.isEmpty) return const {};
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return const {};
    }
    if (decoded is! List) return const {};
    final result = <String, int>{};
    for (final area in decoded.whereType<Map>()) {
      final name = area['name'];
      final rank = parseRank(area['intensityTo'] ?? area['intensity']);
      if (name is! String || rank == null) continue;
      final canonical = canonicalCounty(name);
      result[canonical] = math.max(result[canonical] ?? 0, rank);
    }
    return result;
  }
}
