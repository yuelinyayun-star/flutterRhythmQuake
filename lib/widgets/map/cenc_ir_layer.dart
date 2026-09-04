import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/cenc_ir_data.dart';
import '../../core/intensity_calculator.dart';
import '../../core/utils/world_wrap.dart';

@visibleForTesting
double cencIrStationRadiusForZoom(double zoom) {
  final overview = ((zoom - 3.2) / 3.8).clamp(0.0, 1.0).toDouble();
  return 8.0 + overview * 2.0;
}

@visibleForTesting
double cencIrRomanFontSize(double radius, int length) {
  final scale = switch (length) {
    <= 1 => 1.34,
    2 => 1.08,
    3 => 0.90,
    _ => 0.70,
  };
  return (radius * scale).clamp(6.4, 12.0).toDouble();
}

@visibleForTesting
bool cencIrLayerDataChanged(CencIrData previous, CencIrData current) {
  return !identical(previous, current);
}

class CencIrLayer extends StatelessWidget {
  final CencIrData? data;

  const CencIrLayer({super.key, this.data});

  @override
  Widget build(BuildContext context) {
    if (data == null) return const SizedBox.shrink();
    final mediaSize = MediaQuery.of(context).size;
    final compact =
        mediaSize.shortestSide < 700 ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;

    return CustomPaint(
      painter: CencIrPainter(
        data: data!,
        camera: MapCamera.of(context),
        compact: compact,
      ),
      size: Size.infinite,
      isComplex: true,
      willChange: false,
    );
  }
}

class CencIrPainter extends CustomPainter {
  final CencIrData data;
  final MapCamera camera;
  final bool compact;

  CencIrPainter({
    required this.data,
    required this.camera,
    required this.compact,
  });

  static const int _maxVisibleStations = 900;
  static const int _maxStationLabels = 120;
  static const int _maxCompactStations = 900;
  static const List<String> _csisRomanLabels = [
    'N',
    'I',
    'II',
    'III',
    'IV',
    'V',
    'VI',
    'VII',
    'VIII',
    'IX',
    'X',
    'XI',
    'XII',
  ];
  static final _CencContourPathCache _contourPathCache = _CencContourPathCache(
    maxEntries: 10,
  );

  @override
  void paint(Canvas canvas, Size size) {
    _drawContours(canvas, size);
    _drawEpicenter(canvas, size);
    _drawStationIntensities(canvas, size);
  }

  /// 绘制光晕效果（与 history_marker_layer 统一 UI 震中红叉一致）
  void _drawCrosshairGlow(Canvas canvas, Offset center) {
    final glowPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.round;

    const s = 16.0;
    canvas.drawLine(
      Offset(center.dx - s, center.dy - s),
      Offset(center.dx + s, center.dy + s),
      glowPaint,
    );
    canvas.drawLine(
      Offset(center.dx + s, center.dy - s),
      Offset(center.dx - s, center.dy + s),
      glowPaint,
    );
  }

  /// 绘制十字标记（与 history_marker_layer 统一 UI 震中红叉一致）
  void _drawCrosshair(Canvas canvas, Offset center) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    const s = 14.0;
    canvas.drawLine(
      Offset(center.dx - s, center.dy - s),
      Offset(center.dx + s, center.dy + s),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx + s, center.dy - s),
      Offset(center.dx - s, center.dy + s),
      paint,
    );

    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 3.0, dotPaint);
  }

  void _drawEpicenter(Canvas canvas, Size size) {
    final epicenter = WorldWrap.latLngClosestToCamera(
      LatLng(data.epiLat, data.epiLon),
      camera,
    );
    final offset = camera.getOffsetFromOrigin(epicenter);
    if (offset.dx < -100 ||
        offset.dx > size.width + 100 ||
        offset.dy < -100 ||
        offset.dy > size.height + 100) {
      return;
    }

    // 与 history_marker_layer 中统一 UI 传入的震中红叉样式保持一致
    _drawCrosshairGlow(canvas, offset);
    _drawCrosshair(canvas, offset);

    if (compact) return;

    final tp = TextPainter(
      text: TextSpan(
        text: data.locName.isNotEmpty ? data.locName : '震中',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(
      canvas,
      Offset(offset.dx - tp.width / 2, offset.dy - 26 - tp.height),
    );
  }

  void _drawContours(Canvas canvas, Size size) {
    final geojson = data.contourGeojson;
    if (geojson == null) return;

    final cacheKey = _CencContourCacheKey(
      eventId: data.uniEventId,
      geojsonIdentity: identityHashCode(geojson),
      zoomKey: (camera.zoom * 1000).round(),
      compact: compact,
    );
    final contours = _contourPathCache.getOrBuild(
      cacheKey,
      () => _buildContourPaths(geojson),
    );

    if (contours.pathsByIntensity.isEmpty) return;

    final origin = camera.pixelOrigin;
    final clipRect = Offset.zero & size;
    final visibleGlobal = Rect.fromLTWH(
      origin.dx,
      origin.dy,
      size.width,
      size.height,
    ).inflate(4);

    canvas.save();
    canvas.clipRect(clipRect);
    canvas.translate(-origin.dx, -origin.dy);

    for (final entry in contours.pathsByIntensity.entries) {
      final intensity = entry.key;
      final contourPath = entry.value;
      if (contourPath.bounds.isEmpty ||
          !contourPath.bounds.overlaps(visibleGlobal)) {
        continue;
      }

      final color = _getIntensityColor(intensity);
      final fillPaint = Paint()
        ..color = color.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill;
      canvas.drawPath(contourPath.path, fillPaint);

      final strokePaint = Paint()
        ..color = color.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawPath(contourPath.path, strokePaint);
    }

    canvas.restore();
  }

  _CachedCencContours _buildContourPaths(Map<String, dynamic> geojson) {
    final features = geojson['features'];
    if (features is! List) return const _CachedCencContours.empty();

    final pathBuilders = <int, ui.Path>{};

    for (final feature in features) {
      if (feature is! Map) continue;
      final properties = feature['properties'];
      final geometry = feature['geometry'];

      if (geometry is! Map) continue;
      final geomType = geometry['type']?.toString();
      final coordinates = geometry['coordinates'];

      double intensity = 0;
      if (properties is Map) {
        intensity =
            double.tryParse(properties['intensity']?.toString() ?? '') ?? 0;
      }

      if (intensity <= 0) continue;
      final intensityKey = intensity.round().clamp(1, 12);
      final path = pathBuilders.putIfAbsent(
        intensityKey,
        () => ui.Path()..fillType = ui.PathFillType.evenOdd,
      );

      if (geomType == 'Polygon' &&
          coordinates is List &&
          coordinates.isNotEmpty) {
        _addPolygon(path, coordinates);
      } else if (geomType == 'MultiPolygon' && coordinates is List) {
        for (final polygon in coordinates) {
          if (polygon is List && polygon.isNotEmpty) {
            _addPolygon(path, polygon);
          }
        }
      }
    }

    if (pathBuilders.isEmpty) return const _CachedCencContours.empty();

    final pathsByIntensity = <int, _CachedCencContourPath>{};
    final intensities = pathBuilders.keys.toList()..sort();
    for (final intensity in intensities) {
      final path = pathBuilders[intensity]!;
      pathsByIntensity[intensity] = _CachedCencContourPath(
        path: path,
        bounds: path.getBounds(),
      );
    }
    return _CachedCencContours(pathsByIntensity);
  }

  void _addPolygon(ui.Path path, List coordinates) {
    for (final ring in coordinates) {
      if (ring is! List || ring.length < 3) continue;
      _addRing(path, ring);
    }
  }

  void _addRing(ui.Path path, List ring) {
    var first = true;
    var validPoints = 0;
    final stride = _ringPointStride(ring.length);

    for (var i = 0; i < ring.length; i += stride) {
      final point = ring[i];
      final latLng = _parseGeoJsonPoint(point);
      if (latLng == null) continue;
      final offset = camera.projectAtZoom(latLng);

      if (!offset.dx.isFinite || !offset.dy.isFinite) continue;

      if (first) {
        path.moveTo(offset.dx, offset.dy);
        first = false;
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
      validPoints++;
    }

    if (stride > 1 && (ring.length - 1) % stride != 0) {
      final latLng = _parseGeoJsonPoint(ring.last);
      if (latLng != null) {
        final offset = camera.projectAtZoom(latLng);
        if (offset.dx.isFinite && offset.dy.isFinite) {
          path.lineTo(offset.dx, offset.dy);
          validPoints++;
        }
      }
    }

    if (validPoints >= 3) {
      path.close();
    }
  }

  int _ringPointStride(int pointCount) {
    final budget = switch (camera.zoom) {
      < 4.0 => compact ? 60 : 120,
      < 5.0 => compact ? 100 : 220,
      < 6.0 => compact ? 160 : 360,
      < 8.0 => compact ? 260 : 700,
      _ => compact ? 420 : 1200,
    };
    return math.max(1, (pointCount / budget).ceil());
  }

  LatLng? _parseGeoJsonPoint(Object? point) {
    if (point is! List || point.length < 2) return null;
    final lon = double.tryParse(point[0].toString());
    final lat = double.tryParse(point[1].toString());
    if (lon == null || lat == null) return null;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
    return LatLng(lat, lon);
  }

  void _drawStationIntensities(Canvas canvas, Size size) {
    final visibleStations = _visibleStations(size);
    final drawLabels =
        !compact &&
        camera.zoom >= 6.2 &&
        visibleStations.length <= _maxStationLabels;

    var drawn = 0;
    final maxToDraw = _stationDrawLimit();
    final stationCount = math.min(visibleStations.length, maxToDraw);
    final radius = _stationRadius();
    final styles = <int, _CencStationStyle>{};
    final buckets = <int, List<_CencStationDrawItem>>{};
    for (var index = 0; index < stationCount; index++) {
      final station = visibleStations[index];
      final level = _csisLevel(station.intensity);
      final offset = camera.getOffsetFromOrigin(
        LatLng(station.latitude, station.longitude),
      );
      (buckets[level] ??= []).add(_CencStationDrawItem(offset, station));
      drawn++;
    }

    for (var level = 0; level <= 12; level++) {
      final items = buckets[level];
      if (items == null) continue;
      final style = _stationStyle(level, radius, styles);
      for (final item in items) {
        _drawStationDot(canvas, item, drawLabels, style);
      }
    }

    if (!compact && drawn < visibleStations.length && camera.zoom >= 5.5) {
      _drawOverflowHint(canvas, size, visibleStations.length - drawn);
    }
  }

  List<InstrumentIntensity> _visibleStations(Size size) {
    final visible = <InstrumentIntensity>[];
    for (final station in data.instrumentIntensities) {
      if (!station.hasUsableCoordinate) continue;
      final offset = camera.getOffsetFromOrigin(
        LatLng(station.latitude, station.longitude),
      );
      if (offset.dx < -50 ||
          offset.dx > size.width + 50 ||
          offset.dy < -50 ||
          offset.dy > size.height + 50) {
        continue;
      }
      visible.add(station);
    }
    visible.sort((a, b) => b.intensity.compareTo(a.intensity));
    return visible;
  }

  int _stationDrawLimit() {
    if (compact) {
      if (camera.zoom < 4.5) return 260;
      if (camera.zoom < 5.5) return 450;
      if (camera.zoom < 6.5) return 650;
      return _maxCompactStations;
    }
    if (camera.zoom < 4.5) return 260;
    if (camera.zoom < 5.5) return 450;
    if (camera.zoom < 6.5) return 650;
    return _maxVisibleStations;
  }

  void _drawStationDot(
    Canvas canvas,
    _CencStationDrawItem item,
    bool drawLabels,
    _CencStationStyle style,
  ) {
    final offset = item.offset;
    final station = item.station;

    canvas.drawCircle(offset, style.radius, style.fillPaint);
    canvas.drawCircle(offset, style.radius, style.borderPaint);

    style.textPainter.paint(
      canvas,
      Offset(
        offset.dx - style.textPainter.width / 2,
        offset.dy + style.textTopOffset,
      ),
    );

    if (!drawLabels) return;

    final lines = <String>[];
    if (station.stationName.isNotEmpty) {
      lines.add(station.stationName);
    }
    if (station.pga != null || station.pgv != null) {
      final parts = <String>[];
      if (station.pga != null) {
        parts.add('PGA:${station.pga!.toStringAsFixed(1)}');
      }
      if (station.pgv != null) {
        parts.add('PGV:${station.pgv!.toStringAsFixed(1)}');
      }
      if (parts.isNotEmpty) lines.add(parts.join(' '));
    }
    if (lines.isEmpty) return;

    final labelY = offset.dy + style.radius + 4;
    for (var i = 0; i < lines.length; i++) {
      final lp = TextPainter(
        text: TextSpan(
          text: lines[i],
          style: TextStyle(
            color: Colors.white.withValues(alpha: i == 0 ? 1.0 : 0.75),
            fontSize: i == 0 ? 11 : 9.5,
            fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
            shadows: const [Shadow(color: Colors.black87, blurRadius: 2.5)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      lp.paint(canvas, Offset(offset.dx - lp.width / 2, labelY + i * 14));
    }
  }

  void _drawOverflowHint(Canvas canvas, Size size, int hiddenCount) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: '+$hiddenCount',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.72),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(size.width - textPainter.width - 12, size.height - 28),
    );
  }

  int _csisLevel(double intensity) {
    if (!intensity.isFinite) return 0;
    return intensity.round().clamp(0, 12).toInt();
  }

  String _csisRomanLabel(int level) {
    return _csisRomanLabels[level.clamp(0, _csisRomanLabels.length - 1)];
  }

  double _romanFontSize(double radius, int length) {
    return cencIrRomanFontSize(radius, length);
  }

  Color _getIntensityColor(int level) {
    return Color(IntensityCalculator.getCsisColor(level));
  }

  _CencStationStyle _stationStyle(
    int level,
    double radius,
    Map<int, _CencStationStyle> styles,
  ) {
    return styles.putIfAbsent(level, () {
      final color = _getIntensityColor(level);
      final intText = _csisRomanLabel(level);
      final labelColor = _labelColor(color);
      final fontSize = _romanFontSize(radius, intText.length);
      final textPainter = TextPainter(
        text: TextSpan(
          text: intText,
          style: TextStyle(
            color: labelColor,
            fontFamily: 'JetBrainsMono',
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      final textTopOffset = -textPainter.height / 2 + fontSize * 0.06;
      return _CencStationStyle(
        radius: radius,
        fillPaint: Paint()
          ..color = color
          ..style = PaintingStyle.fill,
        borderPaint: Paint()
          ..color = Colors.white.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (radius * 0.19).clamp(1.5, 1.9),
        textPainter: textPainter,
        textTopOffset: textTopOffset,
      );
    });
  }

  double _stationRadius() {
    return cencIrStationRadiusForZoom(camera.zoom);
  }

  Color _labelColor(Color background) {
    return background.computeLuminance() > 0.42 ? Colors.black : Colors.white;
  }

  @override
  bool shouldRepaint(covariant CencIrPainter oldDelegate) {
    return cencIrLayerDataChanged(oldDelegate.data, data) ||
        oldDelegate.camera != camera ||
        oldDelegate.compact != compact;
  }
}

class _CencStationDrawItem {
  final Offset offset;
  final InstrumentIntensity station;

  const _CencStationDrawItem(this.offset, this.station);
}

class _CencStationStyle {
  final double radius;
  final Paint fillPaint;
  final Paint borderPaint;
  final TextPainter textPainter;
  final double textTopOffset;

  const _CencStationStyle({
    required this.radius,
    required this.fillPaint,
    required this.borderPaint,
    required this.textPainter,
    required this.textTopOffset,
  });
}

class _CencContourPathCache {
  final int maxEntries;
  final LinkedHashMap<_CencContourCacheKey, _CachedCencContours> _entries =
      LinkedHashMap<_CencContourCacheKey, _CachedCencContours>();

  _CencContourPathCache({required this.maxEntries});

  _CachedCencContours getOrBuild(
    _CencContourCacheKey key,
    _CachedCencContours Function() builder,
  ) {
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return cached;
    }

    final built = builder();
    _entries[key] = built;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    return built;
  }
}

class _CencContourCacheKey {
  final String eventId;
  final int geojsonIdentity;
  final int zoomKey;
  final bool compact;

  const _CencContourCacheKey({
    required this.eventId,
    required this.geojsonIdentity,
    required this.zoomKey,
    required this.compact,
  });

  @override
  bool operator ==(Object other) {
    return other is _CencContourCacheKey &&
        other.eventId == eventId &&
        other.geojsonIdentity == geojsonIdentity &&
        other.zoomKey == zoomKey &&
        other.compact == compact;
  }

  @override
  int get hashCode => Object.hash(eventId, geojsonIdentity, zoomKey, compact);
}

class _CachedCencContours {
  final Map<int, _CachedCencContourPath> pathsByIntensity;

  const _CachedCencContours(this.pathsByIntensity);

  const _CachedCencContours.empty() : pathsByIntensity = const {};
}

class _CachedCencContourPath {
  final ui.Path path;
  final Rect bounds;

  const _CachedCencContourPath({required this.path, required this.bounds});
}
