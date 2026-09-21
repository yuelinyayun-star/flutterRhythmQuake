import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/typhoon_data.dart';

const Color _wind7Color = Color(0xFF00E060);
const Color _wind10Color = Color(0xFFFFC845);
const Color _wind12Color = Color(0xFFFF5A52);
const Color _typhoonWarningLineColor = Color(0xFFF9D805);

class TyphoonLayer extends StatelessWidget {
  final List<TyphoonData> typhoons;

  const TyphoonLayer({super.key, required this.typhoons});

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final zoom = camera.zoom;
    final scale = _scaleForZoom(zoom);
    final windPolygons = <Polygon>[];
    final polylines = <Polyline>[];
    final historyMarkers = <Marker>[];
    final visibleTyphoons = <TyphoonData>[];

    _addWarningLines(polylines);
    historyMarkers.addAll(_warningLineLabels(scale));

    for (final typhoon in typhoons) {
      if (!typhoon.isActive) continue;
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

  static const List<LatLng> _warning48Line = [
    LatLng(0, 105),
    LatLng(0, 120),
    LatLng(15, 132),
    LatLng(34, 132),
  ];

  static const List<LatLng> _warning24Line = [
    LatLng(0, 105),
    LatLng(4.5, 113),
    LatLng(11, 119),
    LatLng(18, 119),
    LatLng(22, 127),
    LatLng(34, 127),
  ];

  static void _addWarningLines(List<Polyline> polylines) {
    polylines
      ..add(
        Polyline(
          points: _warning48Line,
          color: _typhoonWarningLineColor,
          strokeWidth: 1.0,
          pattern: StrokePattern.dashed(segments: const [8, 6]),
        ),
      )
      ..add(
        Polyline(
          points: _warning24Line,
          color: _typhoonWarningLineColor,
          strokeWidth: 1.0,
        ),
      );
  }

  static List<Marker> _warningLineLabels(double scale) {
    final labelScale = scale.clamp(0.78, 1.0).toDouble();
    return [
      _warningLabel(
        point: const LatLng(30, 132),
        text: '48\n小\n时\n警\n戒\n线',
        scale: labelScale,
      ),
      _warningLabel(
        point: const LatLng(30, 127),
        text: '24\n小\n时\n警\n戒\n线',
        scale: labelScale,
      ),
    ];
  }

  static Marker _warningLabel({
    required LatLng point,
    required String text,
    required double scale,
  }) {
    return Marker(
      point: point,
      width: 24 * scale,
      height: 104 * scale,
      alignment: Alignment.center,
      child: IgnorePointer(
        child: Text(
          text,
          textAlign: TextAlign.center,
          overflow: TextOverflow.visible,
          style: TextStyle(
            color: _typhoonWarningLineColor,
            fontSize: 12 * scale,
            height: 1.0,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
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
    // Zhejiang returns NE, SE, NW, SW. Draw and display as NE, SE, SW, NW.
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
  static const double _baseLabelWidth = 230;
  static const double _baseFontSize = 10.2;

  /// Design reference: label looks "normal" around this map scale.
  static const double _labelReferencePxPerKm = 1.15;

  /// Keep the leader attached just outside the center marker, in map space.
  static const double _labelGapKm = 28;

  /// Text stays readable when zoomed out; capped when zoomed in.
  static const double _labelScaleMin = 0.78;
  static const double _labelScaleMax = 1.05;

  final List<TyphoonData> typhoons;
  final MapCamera camera;

  _TyphoonAnnotationPainter({required this.typhoons, required this.camera});

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

      final latLng = LatLng(point.lat!, point.lng!);
      final projected = camera.projectAtZoom(latLng);
      final center = projected - origin;
      // Once the eye leaves the viewport, drop the annotation. Keeping it and
      // clamping onto the screen stretches the leader across the map.
      if (!visible.inflate(56).contains(center)) continue;

      annotations.add(
        _VisibleTyphoonAnnotation(
          typhoon: typhoon,
          point: point,
          latLng: latLng,
          center: center,
          index: i,
        ),
      );
    }

    for (final annotation in annotations) {
      _drawCenter(
        canvas,
        annotation.center,
        annotation.latLng,
        _colorForTyphoon(annotation.point),
      );
    }

    for (final annotation in annotations) {
      final preferLeft = _preferLabelOnLeft(annotation.center, annotations);
      final labelRect = _drawLabel(
        canvas,
        annotation.center,
        annotation.latLng,
        annotation.typhoon,
        annotation.point,
        annotation.index,
        size,
        occupiedLabels,
        preferLeft,
      );
      occupiedLabels.add(labelRect.inflate(4));
    }
  }

  void _drawCenter(Canvas canvas, Offset center, LatLng latLng, Color color) {
    // Scale the eye with the map so it shrinks/grows like the track.
    final innerRadius = _kmToPixels(latLng, 12).clamp(3.5, 10.0).toDouble();
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
        ..strokeWidth = math.max(0.8, innerRadius * 0.18),
    );
  }

  Rect _drawLabel(
    Canvas canvas,
    Offset center,
    LatLng latLng,
    TyphoonData typhoon,
    TyphoonPoint point,
    int index,
    Size size,
    List<Rect> occupiedLabels,
    bool preferredLeft,
  ) {
    final text = _labelText(typhoon, point);
    final pxPerKm = _pixelsPerKm(latLng);
    // Gap + column width follow map scale so the block stays near the eye.
    // Font uses a compressed curve so zoom-out stays readable.
    final mapFactor = (pxPerKm / _labelReferencePxPerKm).clamp(0.15, 1.3);
    final labelScale = _compressedLabelScale(mapFactor);
    final fontSize = _baseFontSize * labelScale;
    final width = (_baseLabelWidth * mapFactor.clamp(0.42, 1.0))
        .clamp(120.0, _baseLabelWidth)
        .toDouble();
    final measurePainter = _textPainter(text, fontSize)
      ..layout(maxWidth: width);
    final centerMarkerRadius = _kmToPixels(latLng, 12).clamp(3.5, 10.0);
    final gap = (_kmToPixels(latLng, _labelGapKm) + centerMarkerRadius * 0.35)
        .clamp(3.0, 40.0)
        .toDouble();

    final sideOptions = preferredLeft ? [true, false] : [false, true];
    final verticalOptions = [
      (index.isEven ? -16 : 6) * labelScale,
      (index.isEven ? 6 : -16) * labelScale,
      -36 * labelScale,
      22 * labelScale,
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
        ..strokeWidth = math.max(0.7, labelScale),
    );

    final textAlign = best.labelOnLeft ? TextAlign.right : TextAlign.left;
    final strokePainter = _textPainter(
      text,
      fontSize,
      stroke: true,
      textAlign: textAlign,
    )..layout(maxWidth: width);
    final fillPainter = textAlign == TextAlign.left
        ? measurePainter
        : (_textPainter(text, fontSize, textAlign: textAlign)
            ..layout(maxWidth: width));
    strokePainter.paint(canvas, best.topLeft);
    fillPainter.paint(canvas, best.topLeft);
    strokePainter.dispose();
    if (fillPainter != measurePainter) {
      fillPainter.dispose();
    }
    measurePainter.dispose();
    return best.rect;
  }

  double _pixelsPerKm(LatLng at) {
    final origin = camera.projectAtZoom(at);
    final east = TyphoonLayer._destinationPoint(at, 90, 1);
    final distance = (camera.projectAtZoom(east) - origin).distance;
    return distance <= 0 ? 0.01 : distance;
  }

  double _kmToPixels(LatLng at, double km) => _pixelsPerKm(at) * km;

  /// Soften map scale for typography only (gap stays geographic).
  static double _compressedLabelScale(double mapFactor) {
    // sqrt compresses both ends: tiny mapFactor → still near min, large → near max.
    final t = math.sqrt(((mapFactor - 0.15) / (1.3 - 0.15)).clamp(0.0, 1.0));
    return _labelScaleMin + (_labelScaleMax - _labelScaleMin) * t;
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
      maxLines: 16,
      ellipsis: '',
      textDirection: TextDirection.ltr,
    );
  }

  static String _labelText(TyphoonData typhoon, TyphoonPoint point) {
    final lines = <String>[
      _agencyLine(point.forecast),
      '${_nameLine(typhoon)} ${_shortCmaTime(point.time)}',
      '',
      '编号：${_displayTfid(typhoon.tfid)}',
      '等级：${point.strong.trim().isEmpty ? '--' : point.strong.trim()}',
      '中心位置：(${_coord(point.lat, isLat: true)}, ${_coord(point.lng, isLat: false)})',
      '最大风速：${_windSpeedText(point)}',
      '中心气压：${point.pressure == null ? '--' : '${point.pressure} hPa'}',
      '移动速度：${_movementText(point)}',
    ];

    final radiusLines = _radiusLines(point);
    if (radiusLines.isNotEmpty) {
      lines
        ..add('')
        ..add('风圈半径 (NE, SE, SW, NW)')
        ..addAll(radiusLines);
    }
    return lines.join('\n');
  }

  static String _agencyLine(List<TyphoonForecast> forecasts) {
    final preferred = TyphoonLayer._preferredForecast(forecasts);
    final agency = preferred?.agency.trim().isNotEmpty == true
        ? preferred!.agency.trim()
        : _firstAgency(forecasts);
    return _agencyDisplayName(agency);
  }

  static String _firstAgency(List<TyphoonForecast> forecasts) {
    for (final forecast in forecasts) {
      final agency = forecast.agency.trim();
      if (agency.isNotEmpty) return agency;
    }
    return '';
  }

  static String _agencyDisplayName(String agency) {
    final text = agency.trim();
    if (text.isEmpty) return '--';
    switch (text) {
      case '中国':
        return '中国气象局';
      case '中国台湾':
      case '台湾':
        return '台湾中央气象署';
      case '中国香港':
      case '香港':
        return '香港天文台';
      case '日本':
        return '日本气象厅';
      case '美国':
        return '美国';
      default:
        return text;
    }
  }

  static String _nameLine(TyphoonData typhoon) {
    final cn = typhoon.name.trim();
    final en = typhoon.enname.trim();
    if (cn.isEmpty) return en.isEmpty ? '--' : en;
    if (en.isEmpty) return cn;
    return '$cn（$en）';
  }

  static String _displayTfid(String tfid) {
    final text = tfid.trim();
    if (text.length <= 4) return text.isEmpty ? '--' : text;
    return text.substring(text.length - 4);
  }

  static String _shortCmaTime(String time) {
    final text = time.trim();
    if (text.isEmpty) return '--';
    final parsed = DateTime.tryParse(text.replaceFirst(' ', 'T'));
    if (parsed != null) return '${parsed.day}日${parsed.hour}时';
    final match = RegExp(r'(\d{1,2})[^\d]+(\d{1,2})(?::\d{1,2})?').firstMatch(
      text.length >= 5 ? text.substring(math.max(0, text.length - 8)) : text,
    );
    if (match != null) return '${match.group(1)}日${match.group(2)}时';
    return text.length >= 16 ? text.substring(5, 16) : text;
  }

  static String _coord(num? value, {required bool isLat}) {
    if (value == null) return '--';
    final hemi = isLat ? (value >= 0 ? 'N' : 'S') : (value >= 0 ? 'E' : 'W');
    return '${value.abs().toStringAsFixed(1)}°$hemi';
  }

  static String _windSpeedText(TyphoonPoint point) {
    final speed = point.speed == null ? '--' : '${_fmt(point.speed)} m/s';
    final power = point.power == null ? '' : ' (${point.power}级)';
    return '$speed$power';
  }

  static String _movementText(TyphoonPoint point) {
    final direction = point.movedirection.trim().isEmpty
        ? '--'
        : point.movedirection.trim();
    final speed = point.movespeed == null
        ? ''
        : ' (${_fmt(point.movespeed)} KM/H)';
    return '$direction$speed';
  }

  static List<String> _radiusLines(TyphoonPoint point) {
    final lines = <String>[];
    void addLine(String label, List<double> radii) {
      if (radii.isEmpty) return;
      lines.add(
        '$label：${_radiusList(TyphoonLayer._displayRadii(radii))} (KM)',
      );
    }

    addLine('7  级', point.radius7);
    addLine('10级', point.radius10);
    addLine('12级', point.radius12);
    return lines;
  }

  static String _radiusList(List<double> values) {
    return values.map(_fmt).join(', ');
  }

  static String _fmt(num? value) {
    if (value == null) return '--';
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(2);
  }

  @override
  bool shouldRepaint(covariant _TyphoonAnnotationPainter oldDelegate) {
    return oldDelegate.typhoons != typhoons || oldDelegate.camera != camera;
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
  final LatLng latLng;
  final Offset center;
  final int index;

  const _VisibleTyphoonAnnotation({
    required this.typhoon,
    required this.point,
    required this.latLng,
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
