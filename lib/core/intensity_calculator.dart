import 'dart:math';
import 'package:latlong2/latlong.dart';

class IntensityLevel {
  final String label;
  final String description;
  final int colorHex;

  IntensityLevel(this.label, this.description, this.colorHex);
}

class JmaShindoLevel {
  final String symbol;
  final String kanji;
  final int colorHex;
  final int level;

  const JmaShindoLevel(this.symbol, this.kanji, this.colorHex, this.level);
}

class IntensityCalculator {
  static const double _earthRadius = 6371.0;

  static bool pointInPolygon(double lat, double lng, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final yi = polygon[i].latitude;
      final xi = polygon[i].longitude;
      final yj = polygon[j].latitude;
      final xj = polygon[j].longitude;
      if (((yi > lat) != (yj > lat)) &&
          (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi)) {
        inside = !inside;
      }
    }
    return inside;
  }

  static bool pointInAnyPolygon(
    double lat,
    double lng,
    List<List<LatLng>> polygons,
  ) {
    for (final polygon in polygons) {
      if (pointInPolygon(lat, lng, polygon)) return true;
    }
    return false;
  }

  static double pointDistToArea(
    double hypoLat,
    double hypoLng,
    List<List<LatLng>> polygons,
    List<(double, double)>? intLocPoints,
  ) {
    if (pointInAnyPolygon(hypoLat, hypoLng, polygons)) {
      return 0;
    }
    if (intLocPoints != null && intLocPoints.isNotEmpty) {
      double minDist = double.infinity;
      for (final (lng, lat) in intLocPoints) {
        final d = haversineDistance(hypoLat, hypoLng, lat, lng);
        if (d < minDist) minDist = d;
      }
      return minDist;
    }
    double sumLat = 0, sumLng = 0;
    int count = 0;
    for (final polygon in polygons) {
      for (final p in polygon) {
        sumLat += p.latitude;
        sumLng += p.longitude;
        count++;
      }
    }
    if (count == 0) return 0;
    return haversineDistance(hypoLat, hypoLng, sumLat / count, sumLng / count);
  }

  static double calculate({required double mag, required double distance}) {
    if (mag.isNaN || mag.isInfinite) return 0.0;
    if (distance.isNaN || distance.isInfinite) return 0.0;
    if (distance < 1) distance = 1;

    double intensity = 0.92 + (1.63 * mag) - (3.49 * log(distance + 7) / ln10);

    if (intensity.isNaN || intensity.isInfinite) return 0.0;
    return max(0, intensity);
  }

  static int calcCsisLevel(double magnitude, double depth, double distance) {
    final csis = _calcCsis(magnitude, depth, distance);
    return csis.clamp(0, 12).round();
  }

  static double calcCsis(double magnitude, double depth, double distance) {
    return _calcCsis(magnitude, depth, distance);
  }

  static double _calcCsis(double m, double dep, double dis) {
    if (m.isNaN || dis.isNaN) return 0;
    if (dis > 10000) return 0;
    if (dep.isNaN || dep < 10) dep = 10;

    final lineDis = _calcLineDis(dep, dis);
    final long = pow(10, (m - 3.821) / 1.86).toDouble();
    final hypoDis = [
      lineDis - 10 - long,
      dis - long,
      0.2 * (lineDis - 10),
      0,
    ].reduce((a, b) => a > b ? a : b).toDouble();

    final ceaCsis1 = _calcCeaCsis(m, dis);
    final ceaCsis2 = _calcCeaCsis(m, hypoDis);
    return (ceaCsis1 + ceaCsis2) / 2;
  }

  static double _calcLineDis(double dep, double dis) {
    final theta = dis / _earthRadius;
    final a = _earthRadius - dep;
    return sqrt(
      a * a + _earthRadius * _earthRadius - 2 * a * _earthRadius * cos(theta),
    );
  }

  static double _calcCeaCsis(double m, double dis) {
    return 1.297 * m - 4.368 * log(dis + 15) / ln10 + 5.363;
  }

  static IntensityLevel getLevel(double intensity) {
    if (intensity < 1.0) return IntensityLevel("I", "无感", 0xFF999999);
    if (intensity < 3.0) return IntensityLevel("II-III", "轻微震感", 0xFF4CAF50);
    if (intensity < 5.0) return IntensityLevel("IV-V", "强震感", 0xFFFFEB3B);
    if (intensity < 7.0) return IntensityLevel("VI-VII", "部分建筑受损", 0xFFFF9800);
    if (intensity < 9.0) return IntensityLevel("VIII-IX", "严重破坏", 0xFFF44336);
    return IntensityLevel("X+", "毁灭性破坏", 0xFFB71C1C);
  }

  static int calcCwbLevel(double magnitude, double depth, double distance) {
    if (magnitude.isNaN || distance.isNaN) return 0;
    if (distance < 1) distance = 1;

    double intensity = magnitude * 0.8 - log(distance) / ln10 * 1.2 + 1.0;

    if (intensity.isNaN || intensity.isInfinite) return 0;

    return intensity.clamp(0, 7).round();
  }

  static double calcJmaShindo(
    double mj,
    double dep,
    double hypoLat,
    double hypoLng,
    double locLat,
    double locLng, {
    double arv = 1.0,
  }) {
    if (mj.isNaN || dep.isNaN) return -3.0;
    if (mj < 0 || dep < 0) return -3.0;

    final mw = mj - 0.171;
    final faultLength = pow(10, 0.5 * mw - 1.85) / 2;

    final surfaceDist = haversineDistance(hypoLat, hypoLng, locLat, locLng);
    final lineDis = _calcLineDis(dep, surfaceDist);
    final hypoDist = lineDis - faultLength;

    final x = max(hypoDist, 3);

    final pgv600 = pow(
      10,
      0.58 * mw +
          0.0038 * dep -
          1.29 -
          log(x + 0.0028 * pow(10, 0.5 * mw)) / ln10 -
          0.002 * x,
    ).toDouble();

    final pgv400 = pgv600 * 1.307;
    final pgv = pgv400 * arv;

    if (pgv <= 0) return -3.0;

    final instShindo = 2.68 + 1.72 * log(pgv) / ln10;
    return instShindo;
  }

  static String getJmaShindoLevel(double instShindo, {bool useSymbol = true}) {
    final s = (instShindo * 100).roundToDouble() / 10;
    final s1 = s.floorToDouble() / 10;
    if (s1 < 0.5) return "0";
    if (s1 < 1.5) return "1";
    if (s1 < 2.5) return "2";
    if (s1 < 3.5) return "3";
    if (s1 < 4.5) return "4";
    if (s1 < 5.0) return useSymbol ? "5-" : "5弱";
    if (s1 < 5.5) return useSymbol ? "5+" : "5強";
    if (s1 < 6.0) return useSymbol ? "6-" : "6弱";
    if (s1 < 6.5) return useSymbol ? "6+" : "6強";
    return "7";
  }

  static int getJmaShindoNumericLevel(double instShindo) {
    if (instShindo < -3.0) return -1;
    if (instShindo == -3.0) return 0;
    if (instShindo >= 6.5) return 10;
    return (instShindo * 2 + 7).floor();
  }

  static double getJmaShindoFromLevel(int level) {
    if (level < 0) return -3.0;
    if (level > 10) return 7.0;
    if (level <= 7) return 0;
    return (level - 7) / 2.0;
  }

  static JmaShindoLevel getJmaShindoInfo(
    double instShindo, {
    bool useSymbol = true,
  }) {
    final level = getJmaShindoLevel(instShindo, useSymbol: useSymbol);
    return _jmaShindoMap[level] ?? JmaShindoLevel("?", "不明", 0xFF666666, -1);
  }

  static JmaShindoLevel getJmaShindoInfoByLevel(String level) {
    return _jmaShindoMap[level] ?? JmaShindoLevel("?", "不明", 0xFF666666, -1);
  }

  static const Map<String, JmaShindoLevel> _jmaShindoMap = {
    "0": JmaShindoLevel("0", "0", 0xFF888888, 0),
    "1": JmaShindoLevel("1", "1", 0xFF4499FF, 1),
    "2": JmaShindoLevel("2", "2", 0xFF44BB66, 2),
    "3": JmaShindoLevel("3", "3", 0xFFDDDD00, 3),
    "4": JmaShindoLevel("4", "4", 0xFFEE9944, 4),
    "5-": JmaShindoLevel("5-", "5弱", 0xFFEE6644, 5),
    "5弱": JmaShindoLevel("5-", "5弱", 0xFFEE6644, 5),
    "5+": JmaShindoLevel("5+", "5強", 0xFFEE4444, 6),
    "5強": JmaShindoLevel("5+", "5強", 0xFFEE4444, 6),
    "6-": JmaShindoLevel("6-", "6弱", 0xFFCC3333, 7),
    "6弱": JmaShindoLevel("6-", "6弱", 0xFFCC3333, 7),
    "6+": JmaShindoLevel("6+", "6強", 0xFFBB2222, 8),
    "6強": JmaShindoLevel("6+", "6強", 0xFFBB2222, 8),
    "7": JmaShindoLevel("7", "7", 0xFF991199, 9),
  };

  static int getCsisColor(int csisLevel) {
    return _csisColorMap[csisLevel.clamp(0, 12)];
  }

  static const List<int> _csisColorMap = [
    0xFF888888,
    0xFF888888,
    0xFFAAAAAA,
    0xFF66AACC,
    0xFF4499FF,
    0xFF44BB66,
    0xFFDDDD00,
    0xFFEE9944,
    0xFFEE6644,
    0xFFCC3333,
    0xFF991199,
    0xFF991199,
    0xFF991199,
  ];

  static int getJmaShindoColor(double instShindo) {
    final level = getJmaShindoLevel(instShindo);
    final info = _jmaShindoMap[level];
    return info?.colorHex ?? 0xFF666666;
  }

  static int getJmaShindoColorByLevel(String level) {
    final info = _jmaShindoMap[level];
    return info?.colorHex ?? 0xFF666666;
  }

  static double haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return _earthRadius * c;
  }

  static double calcMaxJmaShindo(
    double mj,
    double dep,
    double hypoLat,
    double hypoLng,
    List<Map<String, dynamic>> locations,
  ) {
    double maxShindo = -3.0;
    for (final loc in locations) {
      final lat = loc['lat'] as double?;
      final lng = loc['lng'] as double?;
      final arv = (loc['arv'] as double?) ?? 1.0;
      if (lat == null || lng == null) continue;

      final shindo = calcJmaShindo(
        mj,
        dep,
        hypoLat,
        hypoLng,
        lat,
        lng,
        arv: arv,
      );
      if (shindo > maxShindo) maxShindo = shindo;
    }
    return maxShindo;
  }

  static String calcMaxJmaShindoLevel(
    double mj,
    double dep,
    double hypoLat,
    double hypoLng,
    List<Map<String, dynamic>> locations, {
    bool useSymbol = true,
  }) {
    final maxShindo = calcMaxJmaShindo(mj, dep, hypoLat, hypoLng, locations);
    return getJmaShindoLevel(maxShindo, useSymbol: useSymbol);
  }

  static Map<String, double> calcRegionIntensities({
    required double magnitude,
    required double depth,
    required double hypoLat,
    required double hypoLng,
    required Map<String, (double lat, double lng)> regionCenters,
    bool useJma = false,
  }) {
    final result = <String, double>{};

    for (final entry in regionCenters.entries) {
      final name = entry.key;
      final (lat, lng) = entry.value;

      if (useJma) {
        result[name] = calcJmaShindo(
          magnitude,
          depth,
          hypoLat,
          hypoLng,
          lat,
          lng,
        );
      } else {
        final dist = haversineDistance(hypoLat, hypoLng, lat, lng);
        result[name] = calcCsis(magnitude, depth, dist);
      }
    }

    return result;
  }

  static Map<String, String> calcRegionShindoLevels({
    required double magnitude,
    required double depth,
    required double hypoLat,
    required double hypoLng,
    required Map<String, (double lat, double lng)> regionCenters,
    bool useSymbol = true,
  }) {
    final intensities = calcRegionIntensities(
      magnitude: magnitude,
      depth: depth,
      hypoLat: hypoLat,
      hypoLng: hypoLng,
      regionCenters: regionCenters,
      useJma: true,
    );

    return intensities.map(
      (name, shindo) =>
          MapEntry(name, getJmaShindoLevel(shindo, useSymbol: useSymbol)),
    );
  }

  static Map<String, int> calcRegionCsisLevels({
    required double magnitude,
    required double depth,
    required double hypoLat,
    required double hypoLng,
    required Map<String, (double lat, double lng)> regionCenters,
  }) {
    final intensities = calcRegionIntensities(
      magnitude: magnitude,
      depth: depth,
      hypoLat: hypoLat,
      hypoLng: hypoLng,
      regionCenters: regionCenters,
      useJma: false,
    );

    return intensities.map(
      (name, csis) => MapEntry(name, csis.clamp(0, 12).round()),
    );
  }
}
