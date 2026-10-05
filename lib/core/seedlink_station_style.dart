import 'package:flutter/foundation.dart';
import 'dart:math' as math;

enum SeedLinkSensorType {
  unknown,
  velocity,
  acceleration,
  displacement;

  static SeedLinkSensorType parse(String? value) =>
      values.firstWhere((type) => type.name == value, orElse: () => unknown);

  // Classify from the channel response input unit, never the provider name.
  static SeedLinkSensorType fromUnit(String unit) {
    final normalized = unit.toUpperCase().replaceAll(' ', '');
    return switch (normalized) {
      'M/S**2' ||
      'M/S^2' ||
      'M/S2' ||
      'M/S/S' ||
      'M/SEC**2' ||
      'M/SEC^2' ||
      'M/SEC/SEC' => acceleration,
      'M/S' || 'M/SEC' => velocity,
      'M' || 'METER' || 'METERS' => displacement,
      _ => unknown,
    };
  }
}

enum SeedLinkShapeMode { triangle, circle, sensorType }

enum SeedLinkMarkerShape { triangle, circle, invertedTriangle, square }

class SeedLinkStationStyle {
  static const preferenceKey = 'seedlink_station_shape';
  // Web-Mercator zoom, not GlobalQuake's globe-camera distance.
  static const labelMinZoom = 6.0;
  // Scale the cached sprite, not its texture; keep distant stations visible.
  static double markerScale(double zoom) =>
      math.pow(2, (zoom - 7) / 2).toDouble().clamp(.5, 1.0);
  static final shape = _initialize();

  static ValueNotifier<SeedLinkShapeMode> _initialize() {
    LicenseRegistry.addLicense(() async* {
      yield const LicenseEntryWithLineBreaks([
        'GlobalQuake 0.11.0',
      ], _gqLicense);
    });
    return ValueNotifier(SeedLinkShapeMode.circle);
  }

  // Extracted without interpolation from GQ 0.11.0 scales/pgaScale3.png.
  // GlobalQuake copyright/license: seedlink_signal_analysis.dart.
  static const colors = <int>[
    0xFF0008D2,
    0xFF0008D1,
    0xFF000CCF,
    0xFF001CCB,
    0xFF002FC6,
    0xFF0041C2,
    0xFF0053BD,
    0xFF0067B9,
    0xFF0078B5,
    0xFF008BB1,
    0xFF009DAC,
    0xFF03ACA2,
    0xFF0AB595,
    0xFF13BE87,
    0xFF1DC777,
    0xFF26D068,
    0xFF30DA59,
    0xFF39E34A,
    0xFF43EC3B,
    0xFF4CF52C,
    0xFF00FF00,
    0xFF0AFF00,
    0xFF1BFF00,
    0xFF2CFF00,
    0xFF3DFF00,
    0xFF4DFF00,
    0xFF5EFF00,
    0xFF6FFF00,
    0xFF80FF00,
    0xFF90FF00,
    0xFFA2FF00,
    0xFFABFF00,
    0xFFB4FF00,
    0xFFBEFF00,
    0xFFC8FF00,
    0xFFD1FF00,
    0xFFDBFF00,
    0xFFE5FF00,
    0xFFEEFF00,
    0xFFF8FF00,
    0xFFFFFF00,
    0xFFFFF600,
    0xFFFFE900,
    0xFFFFDB00,
    0xFFFFCE00,
    0xFFFFC100,
    0xFFFFB400,
    0xFFFFA700,
    0xFFFF9A00,
    0xFFFF8D00,
    0xFFFF7F00,
    0xFFFF7200,
    0xFFFF6500,
    0xFFFF5800,
    0xFFFF4B00,
    0xFFFF3E00,
    0xFFFF3100,
    0xFFFF2400,
    0xFFFF1600,
    0xFFFF0900,
    0xFFFF0000,
    0xFFFF0000,
    0xFFFB0000,
    0xFFF20000,
    0xFFEA0000,
    0xFFE10000,
    0xFFD60000,
    0xFFCE0000,
    0xFFC50000,
    0xFFBA0000,
    0xFFB20000,
    0xFFA90000,
    0xFFA00000,
    0xFF960000,
    0xFF8D0000,
    0xFF840000,
    0xFF7C0000,
    0xFF730000,
    0xFF680000,
    0xFF600000,
  ];
  static int colorIndex(double ratio) => ratio <= 1
      ? 0
      : (math.pow((ratio - 1) / 50000, .25) * 79).toInt().clamp(0, 79);
  static int ratioColor(double? ratio) =>
      ratio == null || !ratio.isFinite ? 0xFFC0C0C0 : colors[colorIndex(ratio)];
  static int eventColor(double ratio) => ratio >= 20000
      ? 0xFFFF0000
      : ratio >= 2000
      ? 0xFFFFFF00
      : 0xFF00FF00;

  static SeedLinkShapeMode parseMode(String? value) =>
      SeedLinkShapeMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => SeedLinkShapeMode.circle,
      );

  static SeedLinkMarkerShape resolve(
    SeedLinkShapeMode mode,
    SeedLinkSensorType type,
  ) => switch (mode) {
    SeedLinkShapeMode.triangle => SeedLinkMarkerShape.triangle,
    SeedLinkShapeMode.circle => SeedLinkMarkerShape.circle,
    SeedLinkShapeMode.sensorType => switch (type) {
      SeedLinkSensorType.velocity => SeedLinkMarkerShape.triangle,
      SeedLinkSensorType.acceleration => SeedLinkMarkerShape.invertedTriangle,
      SeedLinkSensorType.displacement => SeedLinkMarkerShape.square,
      SeedLinkSensorType.unknown => SeedLinkMarkerShape.circle,
    },
  };
}

const _gqLicense = '''
MIT License

Copyright (c) 2023 xspanger3770

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
''';
