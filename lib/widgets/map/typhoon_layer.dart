import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/typhoon_data.dart';

const Color _wind7Color = Color(0xFF00E060);
const Color _wind10Color = Color(0xFFFFC845);
const Color _wind12Color = Color(0xFFFF5A52);

class TyphoonLayer extends StatelessWidget {
  final List<TyphoonData> typhoons;

  const TyphoonLayer({super.key, required this.typhoons});

  @override
  Widget build(BuildContext context) {
    if (typhoons.isEmpty) return const SizedBox.shrink();

    final camera = MapCamera.of(context);
    final zoom = camera.zoom;
    final scale = _scaleForZoom(zoom);
    final windPolygons = <Polygon>[];
    final polylines = <Polyline>[];
    final historyMarkers = <Marker>[];
    final visibleTyphoons = <TyphoonData>[];

    for (final typhoon in typhoons) {
      final latest = typhoon.latestPoint;
      if (latest == null || !latest.hasLocation) continue;
      visibleTyphoons.add(typhoon);

      final historyPoints = typhoon.points
          .where((point) => point.hasLocation)
          .toList();
      final color = _colorForTyphoon(latest);
      _addHistoryPolylines(polylines, historyPoints);

      _addWindFieldPolygon(windPolygons, latest, latest.radius7, _wind7Color);
      _addWindFieldPolygon(windPolygons, latest, latest.radius10, _wind10Color);
      _addWindFieldPolygon(windPolygons, latest, latest.radius12, _wind12Color);
      _addForecastPolyline(polylines, latest, color);
      historyMarkers.addAll(_historyMarkers(historyPoints, scale));
      historyMarkers.addAll(_forecastMarkers(latest, color, scale));
    }

    if (windPolygons.isEmpty &&
        polylines.isEmpty &&
        historyMarkers.isEmpty &&
        visibleTyphoons.isEmpty) {
      return const SizedBox.shrink();
    }

    return RepaintBoundary(
      child: Stack(
        children: [
          if (windPolygons.isNotEmpty) PolygonLayer(polygons: windPolygons),
          if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
          if (historyMarkers.isNotEmpty) MarkerLayer(markers: historyMarkers),
          if (visibleTyphoons.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _TyphoonAnnotationPainter(
                    typhoons: visibleTyphoons,
                    camera: camera,
                    scale: scale,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static double _scaleForZoom(double zoom) {
    if (zoom <= 3.2) return 0.50;
    if (zoom <= 4.0) return 0.58;
    if (zoom <= 5.0) return 0.68;
    if (zoom <= 6.0) return 0.82;
    if (zoom <= 7.0) return 0.94;
    return 1.0;
  }

  static void _addForecastPolyline(
    List<Polyline> polylines,
    TyphoonPoint latest,
    Color color,
  ) {
    final forecast = _preferredForecast(latest.forecast);
    if (forecast == null) return;
    final forecastPoints = forecast.points.where((point) => point.hasLocation);
    if (forecastPoints.isEmpty) return;

    var previous = LatLng(latest.lat!, latest.lng!);
    for (final point in forecastPoints) {
      final current = LatLng(point.lat!, point.lng!);
      final segmentColor = _colorForForecastPoint(point, fallback: color);
      polylines.add(
        Polyline(
          points: [previous, current],
          color: segmentColor.withValues(alpha: 0.52),
          strokeWidth: 1.8,
          pattern: StrokePattern.dashed(segments: const [10, 8]),
          borderColor: Colors.black.withValues(alpha: 0.24),
          borderStrokeWidth: 0.8,
        ),
      );
      previous = current;
    }
  }

  static void _addHistoryPolylines(
    List<Polyline> polylines,
    List<TyphoonPoint> points,
  ) {
    if (points.length < 2) return;

    Color? segmentColor;
    final segmentPoints = <LatLng>[];

    void flushSegment() {
      if (segmentColor == null || segmentPoints.length < 2) return;
      polylines.add(
        Polyline(
          points: List<LatLng>.from(segmentPoints),
          color: segmentColor.withValues(alpha: 0.78),
          strokeWidth: 2.4,
          borderColor: Colors.black.withValues(alpha: 0.38),
          borderStrokeWidth: 1.0,
        ),
      );
    }

    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final color = _colorForTyphoon(current);
      final previousLatLng = LatLng(previous.lat!, previous.lng!);
      final currentLatLng = LatLng(current.lat!, current.lng!);

      if (segmentColor == null || segmentColor.toARGB32() != color.toARGB32()) {
        flushSegment();
        segmentColor = color;
        segmentPoints
          ..clear()
          ..add(previousLatLng);
      }
      segmentPoints.add(currentLatLng);
    }

    flushSegment();
  }

  static List<Marker> _historyMarkers(List<TyphoonPoint> points, double scale) {
    if (points.length <= 2) return const [];
    final step = math.max(1, (points.length / 80).ceil());
    final size = (7 * scale).clamp(3.5, 7.0).toDouble();
    final markers = <Marker>[];
    for (var i = 0; i < points.length - 1; i += step) {
      final point = points[i];
      final color = _colorForTyphoon(point);
      markers.add(
        Marker(
          point: LatLng(point.lat!, point.lng!),
          width: size,
          height: size,
          alignment: Alignment.center,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.82),
                border: Border.all(
                  color: Colors.black.withValues(alpha: 0.42),
                  width: math.max(0.6, scale),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  static List<Marker> _forecastMarkers(
    TyphoonPoint latest,
    Color fallbackColor,
    double scale,
  ) {
    final forecast = _preferredForecast(latest.forecast);
    if (forecast == null || forecast.points.isEmpty) return const [];

    final size = (6.5 * scale).clamp(3.5, 6.5).toDouble();
    final markers = <Marker>[];
    for (final point in forecast.points.where((point) => point.hasLocation)) {
      final color = _colorForForecastPoint(point, fallback: fallbackColor);
      markers.add(
        Marker(
          point: LatLng(point.lat!, point.lng!),
          width: size,
          height: size,
          alignment: Alignment.center,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.70),
                border: Border.all(
                  color: Colors.black.withValues(alpha: 0.36),
                  width: math.max(0.6, scale * 0.9),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  static void _addWindFieldPolygon(
    List<Polygon> polygons,
    TyphoonPoint point,
    List<double> rawRadii,
    Color color,
  ) {
    if (!point.hasLocation || rawRadii.length < 4) return;
    final radii = _displayRadii(rawRadii);
    if (radii.every((radius) => radius <= 0)) return;

    final center = LatLng(point.lat!, point.lng!);
    final points = <LatLng>[];
    const stepDegrees = 4;
    for (var bearing = 0; bearing < 360; bearing += stepDegrees) {
      final radiusKm = _radiusForBearing(radii, bearing.toDouble());
      if (radiusKm <= 0) continue;
      points.add(_destinationPoint(center, bearing.toDouble(), radiusKm));
    }
    if (points.length < 3) return;

    polygons.add(
      Polygon(
        points: points,
        color: color.withValues(alpha: 0.14),
        borderColor: color.withValues(alpha: 0.88),
        borderStrokeWidth: 1.1,
      ),
    );
  }

  static double _radiusForBearing(List<double> radiiNeSeSwNw, double bearing) {
    final normalized = bearing % 360;
    if (normalized < 90) return radiiNeSeSwNw[0];
    if (normalized < 180) return radiiNeSeSwNw[1];
    if (normalized < 270) return radiiNeSeSwNw[2];
    return radiiNeSeSwNw[3];
  }

  static List<double> _displayRadii(List<double> rawRadii) {
    if (rawRadii.length < 4) return rawRadii;
    // FAN returns NE, SE, NW, SW. Draw and display as NE, SE, SW, NW.
    return [rawRadii[0], rawRadii[1], rawRadii[3], rawRadii[2]];
  }

  static LatLng _destinationPoint(
    LatLng origin,
    double bearingDegrees,
    double distanceKm,
  ) {
    const earthRadiusKm = 6371.0088;
    final angularDistance = distanceKm / earthRadiusKm;
    final bearing = _degToRad(bearingDegrees);
    final lat1 = _degToRad(origin.latitude);
    final lon1 = _degToRad(origin.longitude);

    final sinLat1 = math.sin(lat1);
    final cosLat1 = math.cos(lat1);
    final sinDistance = math.sin(angularDistance);
    final cosDistance = math.cos(angularDistance);

    final lat2 = math.asin(
      sinLat1 * cosDistance + cosLat1 * sinDistance * math.cos(bearing),
    );
    final lon2 =
        lon1 +
        math.atan2(
          math.sin(bearing) * sinDistance * cosLat1,
          cosDistance - sinLat1 * math.sin(lat2),
        );

    return LatLng(_radToDeg(lat2), _normalizeLongitude(_radToDeg(lon2)));
  }

  static double _degToRad(double degrees) => degrees * math.pi / 180;
  static double _radToDeg(double radians) => radians * 180 / math.pi;

  static double _normalizeLongitude(double longitude) {
    return ((longitude + 540) % 360) - 180;
  }

  static TyphoonForecast? _preferredForecast(List<TyphoonForecast> forecasts) {
    for (final forecast in forecasts) {
      if (forecast.agency == '\u4e2d\u56fd' && forecast.points.isNotEmpty) {
        return forecast;
      }
    }
    for (final forecast in forecasts) {
      if (forecast.points.isNotEmpty) return forecast;
    }
    return null;
  }
}

class _TyphoonAnnotationPainter extends CustomPainter {
  static const double _baseLabelWidth = 164;
  static const double _baseFontSize = 10.5;

  final List<TyphoonData> typhoons;
  final MapCamera camera;
  final double scale;

  _TyphoonAnnotationPainter({
    required this.typhoons,
    required this.camera,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final origin = camera.pixelOrigin;
    final visible = Offset.zero & size;
    final occupiedLabels = <Rect>[];
    final annotations = <_VisibleTyphoonAnnotation>[];

    for (var i = 0; i < typhoons.length; i++) {
      final typhoon = typhoons[i];
      final point = typhoon.latestPoint;
      if (point == null || !point.hasLocation) continue;

      final projected = camera.projectAtZoom(LatLng(point.lat!, point.lng!));
      final center = projected - origin;
      if (!visible.inflate(700).contains(center)) continue;

      annotations.add(
        _VisibleTyphoonAnnotation(
          typhoon: typhoon,
          point: point,
          center: center,
          index: i,
        ),
      );
    }

    for (final annotation in annotations) {
      _drawCenter(
        canvas,
        annotation.center,
        _colorForTyphoon(annotation.point),
      );
    }

    for (final annotation in annotations) {
      final preferLeft = _preferLabelOnLeft(annotation.center, annotations);
      final labelRect = _drawLabel(
        canvas,
        annotation.center,
        annotation.typhoon,
        annotation.point,
        annotation.index,
        size,
        origin,
        occupiedLabels,
        preferLeft,
      );
      occupiedLabels.add(labelRect.inflate(4 * scale));
    }
  }

  void _drawCenter(Canvas canvas, Offset center, Color color) {
    final innerRadius = 7 * scale;
    canvas.drawCircle(
      center,
      innerRadius,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      innerRadius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.82)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, 1.2 * scale),
    );
  }

  Rect _drawLabel(
    Canvas canvas,
    Offset center,
    TyphoonData typhoon,
    TyphoonPoint point,
    int index,
    Size size,
    Offset origin,
    List<Rect> occupiedLabels,
    bool preferredLeft,
  ) {
    final text = _labelText(typhoon, point);
    final labelScale = (scale * 1.18).clamp(0.68, 1.22).toDouble();
    final fontSize = _baseFontSize * labelScale;
    final width = _baseLabelWidth * labelScale;
    final measurePainter = _textPainter(text, fontSize)
      ..layout(maxWidth: width);
    final windRadius = _windFieldPixelRadius(point, center, origin);
    final gap = (windRadius + 6 * labelScale).clamp(
      18 * labelScale,
      62 * labelScale,
    );

    final sideOptions = preferredLeft ? [true, false] : [false, true];
    final verticalOptions = [
      (index.isEven ? -24 : 10) * labelScale,
      (index.isEven ? 10 : -24) * labelScale,
      -54 * labelScale,
      34 * labelScale,
    ];
    var best = _LabelPlacement(
      topLeft: Offset.zero,
      anchor: Offset.zero,
      rect: Rect.zero,
      score: double.infinity,
      labelOnLeft: preferredLeft,
    );

    for (final labelOnLeft in sideOptions) {
      final horizontalOffset = labelOnLeft ? -(width + gap) : gap;
      for (final verticalOffset in verticalOptions) {
        final topLeft = _clampLabelTopLeft(
          Offset(center.dx + horizontalOffset, center.dy + verticalOffset),
          Size(width, measurePainter.height),
          size,
          labelScale,
        );
        final rect = topLeft & Size(width, measurePainter.height);
        final anchor = Offset(
          labelOnLeft ? rect.right : rect.left,
          rect.top + 8 * labelScale,
        );
        final score =
            _labelOverlapScore(rect.inflate(3 * labelScale), occupiedLabels) +
            _offscreenPenalty(rect, size) +
            (labelOnLeft == preferredLeft ? 0 : 500);
        if (score < best.score) {
          best = _LabelPlacement(
            topLeft: topLeft,
            anchor: anchor,
            rect: rect,
            score: score,
            labelOnLeft: labelOnLeft,
          );
        }
      }
    }

    canvas.drawLine(
      center,
      best.anchor,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.42)
        ..strokeWidth = math.max(0.9, labelScale),
    );

    final textAlign = best.labelOnLeft ? TextAlign.right : TextAlign.left;
    final strokePainter = _textPainter(
      text,
      fontSize,
      stroke: true,
      textAlign: textAlign,
    )..layout(maxWidth: width);
    final fillPainter = _textPainter(text, fontSize, textAlign: textAlign)
      ..layout(maxWidth: width);
    strokePainter.paint(canvas, best.topLeft);
    fillPainter.paint(canvas, best.topLeft);
    return best.rect;
  }

  static double _labelOverlapScore(Rect rect, List<Rect> occupiedLabels) {
    var score = 0.0;
    for (final occupied in occupiedLabels) {
      score += _rectOverlapArea(rect, occupied) * 12;
    }
    return score;
  }

  static Offset _clampLabelTopLeft(
    Offset topLeft,
    Size labelSize,
    Size canvasSize,
    double labelScale,
  ) {
    final padding = 4 * labelScale;
    final maxX = math.max(
      padding,
      canvasSize.width - labelSize.width - padding,
    );
    final maxY = math.max(
      padding,
      canvasSize.height - labelSize.height - padding,
    );
    return Offset(
      topLeft.dx.clamp(padding, maxX).toDouble(),
      topLeft.dy.clamp(padding, maxY).toDouble(),
    );
  }

  static bool _preferLabelOnLeft(
    Offset center,
    List<_VisibleTyphoonAnnotation> annotations,
  ) {
    var leftCount = 0;
    var rightCount = 0;
    for (final annotation in annotations) {
      final dx = annotation.center.dx - center.dx;
      if (dx.abs() < 1) continue;
      if (dx > 0) {
        rightCount++;
      } else {
        leftCount++;
      }
    }
    if (rightCount != leftCount) return rightCount > leftCount;

    final averageX =
        annotations.fold<double>(0, (sum, item) => sum + item.center.dx) /
        annotations.length;
    return center.dx <= averageX;
  }

  static double _offscreenPenalty(Rect rect, Size size) {
    final overflow =
        math.max(0.0, -rect.left) +
        math.max(0.0, -rect.top) +
        math.max(0.0, rect.right - size.width) +
        math.max(0.0, rect.bottom - size.height);
    return overflow * 80;
  }

  static double _rectOverlapArea(Rect a, Rect b) {
    final width = math.max(
      0.0,
      math.min(a.right, b.right) - math.max(a.left, b.left),
    );
    final height = math.max(
      0.0,
      math.min(a.bottom, b.bottom) - math.max(a.top, b.top),
    );
    return width * height;
  }

  double _windFieldPixelRadius(
    TyphoonPoint point,
    Offset center,
    Offset origin,
  ) {
    var radiusKm = 0.0;
    for (final radii in [point.radius7, point.radius10, point.radius12]) {
      if (radii.isEmpty) continue;
      for (final radius in TyphoonLayer._displayRadii(radii)) {
        radiusKm = math.max(radiusKm, radius);
      }
    }
    if (radiusKm <= 0 || !point.hasLocation) return 0;

    final latLng = LatLng(point.lat!, point.lng!);
    var radiusPx = 0.0;
    for (final bearing in const [0.0, 90.0, 180.0, 270.0]) {
      final edge = TyphoonLayer._destinationPoint(latLng, bearing, radiusKm);
      final projected = camera.projectAtZoom(edge) - origin;
      radiusPx = math.max(radiusPx, (projected - center).distance);
    }
    return radiusPx;
  }

  static TextPainter _textPainter(
    String text,
    double fontSize, {
    bool stroke = false,
    TextAlign textAlign = TextAlign.left,
  }) {
    return TextPainter(
      textAlign: textAlign,
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: stroke ? null : Colors.white,
          fontSize: fontSize,
          height: 1.12,
          fontWeight: FontWeight.w800,
          foreground: stroke
              ? (ui.Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = math.max(1.1, fontSize * 0.23)
                  ..color = Colors.black.withValues(alpha: 0.86))
              : null,
        ),
      ),
      maxLines: 6,
      ellipsis: '',
      textDirection: TextDirection.ltr,
    );
  }

  static String _labelText(TyphoonData typhoon, TyphoonPoint point) {
    final level = point.strong.trim();
    final lines = <String>[
      '${typhoon.displayName} ${typhoon.tfid}',
      [
        if (level.isNotEmpty) level,
        '\u4e2d\u5fc3 ${_fmt(point.lat)} / ${_fmt(point.lng)}',
      ].join('  '),
    ];
    final wind = <String>[];
    if (point.speed != null) wind.add('${_fmt(point.speed)}m/s');
    if (point.power != null) wind.add('${point.power}\u7ea7');
    final windPressure = [
      if (wind.isNotEmpty) '\u98ce ${wind.join(' ')}',
      if (point.pressure != null) '\u538b ${point.pressure}hPa',
    ].join('  ');
    if (windPressure.isNotEmpty) lines.add(windPressure);

    final moving = [
      if (point.movedirection.isNotEmpty) point.movedirection,
      if (point.movespeed != null) '${_fmt(point.movespeed)}km/h',
    ].join(' ');
    if (moving.isNotEmpty) lines.add('\u79fb $moving');

    final radii = _radiusText(point);
    if (radii.isNotEmpty) lines.add(radii);
    if (point.time.isNotEmpty) lines.add(_shortTime(point.time));
    return lines.join('\n');
  }

  static String _radiusText(TyphoonPoint point) {
    if (point.radius7.isNotEmpty) {
      return '7\u7ea7 ${_radiusList(TyphoonLayer._displayRadii(point.radius7))}km';
    }
    if (point.radius10.isNotEmpty) {
      return '10\u7ea7 ${_radiusList(TyphoonLayer._displayRadii(point.radius10))}km';
    }
    if (point.radius12.isNotEmpty) {
      return '12\u7ea7 ${_radiusList(TyphoonLayer._displayRadii(point.radius12))}km';
    }
    return '';
  }

  static String _radiusList(List<double> values) {
    return values.map(_fmt).join('/');
  }

  static String _shortTime(String time) {
    if (time.length >= 16) return time.substring(0, 16);
    return time;
  }

  static String _fmt(num? value) {
    if (value == null) return '--';
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(2);
  }

  @override
  bool shouldRepaint(covariant _TyphoonAnnotationPainter oldDelegate) {
    return oldDelegate.typhoons != typhoons ||
        oldDelegate.camera != camera ||
        oldDelegate.scale != scale;
  }
}

class _LabelPlacement {
  final Offset topLeft;
  final Offset anchor;
  final Rect rect;
  final double score;
  final bool labelOnLeft;

  const _LabelPlacement({
    required this.topLeft,
    required this.anchor,
    required this.rect,
    required this.score,
    required this.labelOnLeft,
  });
}

class _VisibleTyphoonAnnotation {
  final TyphoonData typhoon;
  final TyphoonPoint point;
  final Offset center;
  final int index;

  const _VisibleTyphoonAnnotation({
    required this.typhoon,
    required this.point,
    required this.center,
    required this.index,
  });
}

Color _colorForTyphoon(TyphoonPoint point) {
  return _colorForPowerAndStrong(point.power, point.strong);
}

Color _colorForForecastPoint(
  TyphoonForecastPoint point, {
  required Color fallback,
}) {
  if (point.power == null && point.strong.trim().isEmpty) return fallback;
  return _colorForPowerAndStrong(point.power, point.strong);
}

Color _colorForPowerAndStrong(int? rawPower, String strong) {
  final power = rawPower ?? _powerFromStrong(strong);
  if (power >= 16) return const Color(0xFFD64BFF);
  if (power >= 14) return const Color(0xFFFF3B5C);
  if (power >= 12) return const Color(0xFFFF8A2A);
  if (power >= 10) return const Color(0xFFFFD24A);
  return const Color(0xFF62D6FF);
}

int _powerFromStrong(String strong) {
  final text = strong.trim();
  if (text.contains('\u8d85\u5f3a\u53f0\u98ce')) return 16;
  if (text.contains('\u5f3a\u53f0\u98ce')) return 14;
  if (text.contains('\u53f0\u98ce')) return 12;
  if (text.contains('\u5f3a\u70ed\u5e26\u98ce\u66b4')) return 10;
  if (text.contains('\u70ed\u5e26\u98ce\u66b4')) return 8;
  return 0;
}
