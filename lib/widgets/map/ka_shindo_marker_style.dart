import 'package:flutter/material.dart';
import '../../core/source_estimation/palert_source_profile.dart';

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

  static String labelForLevel(int level) =>
      PAlertSourceProfile.intensityLabelFromLevel(level);
}
