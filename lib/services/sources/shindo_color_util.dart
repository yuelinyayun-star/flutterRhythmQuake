import 'dart:developer' as developer;
import 'dart:math';

import 'jp_shindo_scale.dart';

enum ShindoMatchType {
  palette,
  greenAlias,
  hsvAccepted,
  hsvRejected,
  lowSatVal,
  zeroPosition,
  noPaletteEntry,
  blackPixel,
}

class ShindoColorUtil {
  ShindoColorUtil._();

  static const int _strictPaletteDistanceSquared = 55 * 55;

  static ShindoMatchType? lastMatchType;
  static int _logCount = 0;
  static const int _logLimit = 30;

  static void resetFrameLog() {
    _logCount = 0;
  }

  static double? rgbaToShindo(int r, int g, int b) {
    final p = rgbaToPosition(r, g, b);
    if (p != null) return 10.0 * p - 3.0;

    final ct = _colorTable;
    final rMap = ct[r];
    if (rMap != null) {
      final gMap = rMap[g];
      if (gMap != null) {
        final v = gMap[b];
        if (v != null) return v;
      }
    }
    return null;
  }

  static double? rgbaToPosition(int r, int g, int b) {
    if (r == 0 && g == 0 && b == 0) {
      lastMatchType = ShindoMatchType.blackPixel;
      return null;
    }
    final hsv = _rgbToHsv(r, g, b);
    final p = _color2position(hsv[0], hsv[1], hsv[2]);
    if (p > 0) return p;

    final ct = _colorTable;
    final rMap = ct[r];
    if (rMap != null) {
      final gMap = rMap[g];
      if (gMap != null) {
        final v = gMap[b];
        if (v != null) return ((v + 3.0) / 10.0).clamp(0.0, 1.0);
      }
    }
    return null;
  }

  static double? rgbaToShindoStrict(int r, int g, int b) {
    _logCount++;
    final shouldLog = _logCount <= _logLimit;

    if (r == 0 && g == 0 && b == 0) {
      lastMatchType = ShindoMatchType.blackPixel;
      if (shouldLog) {
        _debugPrint(
          '[ShindoColor] #$_logCount RGB($r,$g,$b) -> black pixel -> no data',
        );
      }
      return null;
    }

    final nearest = _nearestColorTableValue(r, g, b);
    if (nearest != null) {
      lastMatchType = ShindoMatchType.palette;
      if (shouldLog && nearest > -1.5) {
        _debugPrint(
          '[ShindoColor] #$_logCount RGB($r,$g,$b) 鈫?palette match 鈫?shindo=$nearest',
        );
      }
      return nearest;
    }

    final greenAlias = _greenAliasValue(r, g, b);
    if (greenAlias != null) {
      lastMatchType = ShindoMatchType.greenAlias;
      if (shouldLog && greenAlias > -1.5) {
        _debugPrint(
          '[ShindoColor] #$_logCount RGB($r,$g,$b) 鈫?green alias 鈫?shindo=$greenAlias',
        );
      }
      return greenAlias;
    }

    final hsv = _rgbToHsv(r, g, b);
    if (hsv[1] <= 0.85 || hsv[2] <= 0.2) {
      lastMatchType = ShindoMatchType.lowSatVal;
      if (shouldLog) {
        _debugPrint(
          '[ShindoColor] #$_logCount RGB($r,$g,$b) 鈫?HSV(${hsv[0].toStringAsFixed(3)}, ${hsv[1].toStringAsFixed(3)}, ${hsv[2].toStringAsFixed(3)}) 鈫?saturation/value too low, skipped',
        );
      }
      return null;
    }

    final p = _color2position(hsv[0], hsv[1], hsv[2]);
    if (p <= 0) {
      lastMatchType = ShindoMatchType.zeroPosition;
      if (shouldLog) {
        _debugPrint(
          '[ShindoColor] #$_logCount RGB($r,$g,$b) 鈫?HSV(${hsv[0].toStringAsFixed(3)}, ${hsv[1].toStringAsFixed(3)}, ${hsv[2].toStringAsFixed(3)}) 鈫?position=${p.toStringAsFixed(4)} (鈮?), skipped',
        );
      }
      return null;
    }

    final shindo = 10.0 * p - 3.0;
    final expected = _nearestPaletteEntryForShindo(shindo);
    if (expected == null) {
      lastMatchType = ShindoMatchType.noPaletteEntry;
      if (shouldLog) {
        _debugPrint(
          '[ShindoColor] #$_logCount RGB($r,$g,$b) 鈫?HSV(${hsv[0].toStringAsFixed(3)}, ${hsv[1].toStringAsFixed(3)}, ${hsv[2].toStringAsFixed(3)}) 鈫?p=${p.toStringAsFixed(4)} 鈫?shindo=${shindo.toStringAsFixed(1)} 鈫?no palette entry, skipped',
        );
      }
      return null;
    }

    final dr = r - expected.$1;
    final dg = g - expected.$2;
    final db = b - expected.$3;
    final distSq = dr * dr + dg * dg + db * db;
    final passed = distSq <= _strictPaletteDistanceSquared;
    lastMatchType = passed
        ? ShindoMatchType.hsvAccepted
        : ShindoMatchType.hsvRejected;
    if (shouldLog) {
      _debugPrint(
        '[ShindoColor] #$_logCount RGB($r,$g,$b) 鈫?HSV(${hsv[0].toStringAsFixed(3)}, ${hsv[1].toStringAsFixed(3)}, ${hsv[2].toStringAsFixed(3)}) 鈫?p=${p.toStringAsFixed(4)} 鈫?shindo=${shindo.toStringAsFixed(1)} 鈫?palette(${expected.$1},${expected.$2},${expected.$3},${expected.$4}) distSq=$distSq threshold=$_strictPaletteDistanceSquared 鈫?${passed ? "ACCEPTED 鈫?level=${shindoToRawLevel(shindo)}" : "REJECTED (distSq too large)"}',
      );
    }
    return passed ? shindo : null;
  }

  static double? _greenAliasValue(int r, int g, int b) {
    if (g < 220 || r > 90 || b > 100) return null;
    if (g - r < 140 || g - b < 140) return null;

    final earlyGreenEntries = _paletteEntries.where((entry) {
      return entry.$4 >= -1.2 && entry.$4 <= -0.8;
    });
    (int, int, int, double)? best;
    var bestDistSq = 1 << 30;
    for (final entry in earlyGreenEntries) {
      final dr = r - entry.$1;
      final dg = g - entry.$2;
      final db = b - entry.$3;
      final distSq = dr * dr + dg * dg + db * db;
      if (distSq < bestDistSq) {
        bestDistSq = distSq;
        best = entry;
      }
    }
    return bestDistSq <= 75 * 75 ? best?.$4 : null;
  }

  static int shindoToRawLevel(double shindo) {
    return JpShindoScale.levelFromShindo(shindo);
  }

  static double levelToShindo(int lvl) {
    return JpShindoScale.displayShindoFromLevel(lvl);
  }

  static List<double> _rgbToHsv(int r, int g, int b) {
    final rn = r / 255.0, gn = g / 255.0, bn = b / 255.0;
    final cmax = max(rn, max(gn, bn));
    final cmin = min(rn, min(gn, bn));
    final delta = cmax - cmin;
    double h = 0;
    if (delta != 0) {
      if (cmax == rn) {
        h = 60 * (((gn - bn) / delta) % 6);
      } else if (cmax == gn) {
        h = 60 * (((bn - rn) / delta) + 2);
      } else {
        h = 60 * (((rn - gn) / delta) + 4);
      }
    }
    if (h < 0) h += 360;
    return [h / 360.0, cmax == 0 ? 0.0 : delta / cmax, cmax];
  }

  static double? _nearestColorTableValue(int r, int g, int b) {
    double? bestValue;
    var bestDistSq = 1 << 30;
    for (final entry in _paletteEntries) {
      final dr = r - entry.$1;
      final dg = g - entry.$2;
      final db = b - entry.$3;
      final distSq = dr * dr + dg * dg + db * db;
      if (distSq < bestDistSq) {
        bestDistSq = distSq;
        bestValue = entry.$4;
      }
    }
    return bestDistSq <= _strictPaletteDistanceSquared ? bestValue : null;
  }

  static (int, int, int, double)? _nearestPaletteEntryForShindo(double shindo) {
    if (_paletteEntries.isEmpty) return null;
    var best = _paletteEntries.first;
    var bestDiff = (shindo - best.$4).abs();
    for (final entry in _paletteEntries.skip(1)) {
      final diff = (shindo - entry.$4).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = entry;
      }
    }
    return best;
  }

  static double _color2position(double h, double s, double v) {
    double p = 0;
    if (v <= 0.1 || s <= 0.75) return 0;
    if (h > 0.1476) {
      p =
          280.31 * pow(h, 6) -
          916.05 * pow(h, 5) +
          1142.6 * pow(h, 4) -
          709.95 * pow(h, 3) +
          234.65 * pow(h, 2) -
          40.27 * h +
          3.2217;
    } else if (h > 0.001) {
      p =
          151.4 * pow(h, 4) -
          49.32 * pow(h, 3) +
          6.753 * pow(h, 2) -
          2.481 * h +
          0.9033;
    } else {
      p = -0.005171 * pow(v, 2) - 0.3282 * v + 1.2236;
    }
    return p.clamp(0.0, 1.0);
  }

  static void _debugPrint(String message) {
    developer.log(message, name: 'ShindoColor');
  }

  static final List<(int, int, int, double)> _paletteEntries =
      _buildPaletteEntries();
  static final Map<int, Map<int, Map<int, double>>> _colorTable =
      _buildColorTable();

  static List<(int, int, int, double)> _buildPaletteEntries() {
    final entries = <(int, int, int, double)>[];
    for (int i = 0; i < _colorPairs.length; i += 4) {
      entries.add((
        _colorPairs[i].toInt(),
        _colorPairs[i + 1].toInt(),
        _colorPairs[i + 2].toInt(),
        _colorPairs[i + 3].toDouble(),
      ));
    }
    return entries;
  }

  static Map<int, Map<int, Map<int, double>>> _buildColorTable() {
    final t = <int, Map<int, Map<int, double>>>{};
    for (int i = 0; i < _colorPairs.length; i += 4) {
      final r = _colorPairs[i].toInt();
      final g = _colorPairs[i + 1].toInt();
      final b = _colorPairs[i + 2].toInt();
      (t[r] ??= {})[g] ??= {};
      t[r]![g]![b] = _colorPairs[i + 3].toDouble();
    }
    return t;
  }

  static const List<num> _colorPairs = [
    0,
    0,
    0,
    -3.0,
    0,
    0,
    26,
    -3.0,
    0,
    0,
    77,
    -3.0,
    0,
    0,
    103,
    -3.0,
    0,
    0,
    128,
    -3.0,
    0,
    0,
    154,
    -3.0,
    0,
    0,
    179,
    -3.0,
    0,
    0,
    205,
    -3.0,
    0,
    7,
    209,
    -2.9,
    0,
    18,
    213,
    -2.8,
    0,
    36,
    214,
    -2.7,
    0,
    55,
    213,
    -2.6,
    0,
    73,
    211,
    -2.5,
    0,
    91,
    210,
    -2.4,
    0,
    110,
    210,
    -2.3,
    0,
    128,
    212,
    -2.2,
    0,
    146,
    215,
    -2.1,
    0,
    165,
    214,
    -2.0,
    0,
    183,
    207,
    -1.9,
    0,
    201,
    201,
    -1.8,
    0,
    220,
    193,
    -1.7,
    0,
    238,
    167,
    -1.6,
    0,
    255,
    134,
    -1.5,
    0,
    255,
    96,
    -1.4,
    0,
    255,
    57,
    -1.3,
    0,
    255,
    19,
    -1.2,
    22,
    255,
    0,
    -1.1,
    67,
    255,
    0,
    -1.0,
    121,
    255,
    0,
    -0.9,
    170,
    255,
    0,
    -0.8,
    219,
    255,
    0,
    -0.7,
    255,
    244,
    0,
    -0.6,
    255,
    225,
    0,
    -0.5,
    255,
    206,
    0,
    -0.4,
    255,
    187,
    0,
    -0.3,
    255,
    168,
    0,
    -0.2,
    255,
    149,
    0,
    -0.1,
    255,
    130,
    0,
    0.0,
    255,
    111,
    0,
    0.1,
    255,
    92,
    0,
    0.2,
    255,
    73,
    0,
    0.3,
    255,
    54,
    0,
    0.4,
    255,
    35,
    0,
    0.5,
    255,
    16,
    0,
    0.6,
    249,
    0,
    0,
    0.7,
    230,
    0,
    0,
    0.8,
    211,
    0,
    0,
    0.9,
    192,
    0,
    0,
    1.0,
    173,
    0,
    0,
    1.1,
    154,
    0,
    0,
    1.2,
    135,
    0,
    0,
    1.3,
    116,
    0,
    0,
    1.4,
    97,
    0,
    0,
    1.5,
    78,
    0,
    0,
    1.6,
    59,
    0,
    0,
    1.7,
    40,
    0,
    0,
    1.8,
    21,
    0,
    0,
    1.9,
    13,
    0,
    11,
    2.0,
    18,
    0,
    25,
    2.1,
    22,
    0,
    40,
    2.2,
    27,
    0,
    54,
    2.3,
    31,
    0,
    69,
    2.4,
    36,
    0,
    84,
    2.5,
    40,
    0,
    98,
    2.6,
    45,
    0,
    113,
    2.7,
    49,
    0,
    127,
    2.8,
    54,
    0,
    142,
    2.9,
    58,
    0,
    156,
    3.0,
    63,
    0,
    171,
    3.1,
    67,
    0,
    185,
    3.2,
    72,
    0,
    200,
    3.3,
    76,
    0,
    214,
    3.4,
    81,
    0,
    229,
    3.5,
    85,
    0,
    243,
    3.6,
    90,
    0,
    255,
    3.7,
    95,
    0,
    255,
    3.8,
    100,
    0,
    255,
    3.9,
    105,
    0,
    255,
    4.0,
    110,
    0,
    255,
    4.1,
    115,
    0,
    255,
    4.2,
    120,
    0,
    255,
    4.3,
    125,
    0,
    255,
    4.4,
    130,
    0,
    255,
    4.5,
    135,
    0,
    255,
    4.6,
    140,
    0,
    255,
    4.7,
    145,
    0,
    255,
    4.8,
    150,
    0,
    255,
    4.9,
    155,
    0,
    255,
    5.0,
    160,
    0,
    255,
    5.1,
    165,
    0,
    255,
    5.2,
    170,
    0,
    255,
    5.3,
    175,
    0,
    255,
    5.4,
    180,
    0,
    255,
    5.5,
    185,
    0,
    255,
    5.6,
    190,
    0,
    255,
    5.7,
    195,
    0,
    255,
    5.8,
    200,
    0,
    255,
    5.9,
    205,
    0,
    255,
    6.0,
    210,
    0,
    255,
    6.1,
    215,
    0,
    255,
    6.2,
    220,
    0,
    255,
    6.3,
    225,
    0,
    255,
    6.4,
    230,
    0,
    255,
    6.5,
    235,
    0,
    255,
    6.6,
    240,
    0,
    255,
    6.7,
    245,
    0,
    255,
    6.8,
    250,
    0,
    255,
    6.9,
    255,
    0,
    255,
    7.0,
  ];
}
