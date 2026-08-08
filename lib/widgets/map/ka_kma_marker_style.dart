import 'package:flutter/material.dart';

class KaKmaMarkerStyle {
  KaKmaMarkerStyle._();

  static const double minimumMarkerZoom = 4.0;
  static const double labeledMarkerSize = 14.0;

  /// Keep KMA station dots the same size as the NIED station layer.
  static double dotSizeForZoom(double zoom) {
    return (0.9 + (zoom - 3) * 0.95).clamp(0.9, 7.5).toDouble();
  }

  static double borderWidthForZoom(double zoom) {
    final overview = ((zoom - 3.2) / 3.8).clamp(0.0, 1.0).toDouble();
    return (0.35 + overview * 0.55).clamp(0.35, 0.9).toDouble();
  }

  static double labelFontSizeForLevel(int level) => level >= 7 ? 8.0 : 7.0;

  // KA kmaColorBand.nied, used by ordinary station dots.
  static const List<Color> stationColors = [
    Color(0xFF0003CF),
    Color(0xFF004FF4),
    Color(0xFF05D384),
    Color(0xFF50FB30),
    Color(0xFFCCFF09),
    Color(0xFFFDFC00),
    Color(0xFFFFCA00),
    Color(0xFFFF7900),
    Color(0xFFFF4700),
    Color(0xFFF91900),
    Color(0xFFE10000),
    Color(0xFFAF0000),
    Color(0xFFAE0000),
    Color(0xFFAD0000),
  ];

  // KA kmaIntColorBand, used by labeled intensity markers.
  static const List<Color> markerColors = [
    Color(0xFF9F9F9F),
    Color(0xFF9F9F9F),
    Color(0xFF9F9F9F),
    Color(0xFF9F9F9F),
    Color(0xFFCFCFCF),
    Color(0xFF5FCFFF),
    Color(0xFF3FAFFF),
    Color(0xFF5FDF8F),
    Color(0xFFF7E757),
    Color(0xFFFF8F00),
    Color(0xFFFF4F00),
    Color(0xFFDF0F0F),
    Color(0xFF7F007F),
    Color(0xFF7F007F),
  ];

  static bool shouldShowMarker({
    required int holdLevel,
    required double zoom,
    bool displayShindo0 = false,
  }) {
    final threshold = displayShindo0 ? 3 : 4;
    return holdLevel >= threshold && zoom >= minimumMarkerZoom;
  }

  static Color stationColorForLevel(int level) {
    return stationColors[level.clamp(0, stationColors.length - 1)];
  }

  static Color markerColorForLevel(int level) {
    return markerColors[level.clamp(0, markerColors.length - 1)];
  }

  static int mmiForLevel(int level) {
    if (level < 0) return -1;
    return (level - 2).clamp(0, 11);
  }

  static Color foregroundForLevel(int level) {
    return level >= 10 ? Colors.white : Colors.black;
  }
}
