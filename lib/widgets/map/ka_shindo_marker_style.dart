import 'package:flutter/material.dart';

class KaShindoMarkerStyle {
  KaShindoMarkerStyle._();

  static const int minimumMarkerLevel = 8;
  static const double minimumMarkerZoom = 4.0;

  // KA shindoColorBand, indexed by the original -1..20 station level.
  static const List<Color> _colors = [
    Color(0xFF9F9F9F),
    Color(0xFF9F9F9F),
    Color(0xFF9F9F9F),
    Color(0xFF9F9F9F),
    Color(0xFF9F9F9F),
    Color(0xFF9F9F9F),
    Color(0xFF9F9F9F),
    Color(0xFF9F9F9F),
    Color(0xFFCFCFCF),
    Color(0xFFCFCFCF),
    Color(0xFF3FAFFF),
    Color(0xFF3FAFFF),
    Color(0xFF5FDF8F),
    Color(0xFF5FDF8F),
    Color(0xFFF7E757),
    Color(0xFFF7E757),
    Color(0xFFFF8F00),
    Color(0xFFFF4F00),
    Color(0xFFDF0F0F),
    Color(0xFFAF0000),
    Color(0xFF7F007F),
  ];

  static bool shouldShowMarker({
    required int level,
    required double zoom,
    bool displayShindo0 = false,
  }) {
    final threshold = displayShindo0 ? 6 : minimumMarkerLevel;
    return level >= threshold && zoom >= minimumMarkerZoom;
  }

  static Color colorForLevel(int level) {
    return _colors[level.clamp(0, _colors.length - 1)];
  }

  static Color foregroundForLevel(int level) {
    return level >= 17 ? Colors.white : Colors.black;
  }

  static String labelForLevel(int level) {
    if (level < 0) return '--';
    if (level <= 7) return '0';
    if (level <= 9) return '1';
    if (level <= 11) return '2';
    if (level <= 13) return '3';
    if (level <= 15) return '4';
    if (level == 16) return '5弱';
    if (level == 17) return '5強';
    if (level == 18) return '6弱';
    if (level == 19) return '6強';
    return '7';
  }
}
