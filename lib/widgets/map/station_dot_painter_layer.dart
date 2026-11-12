import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'ka_kma_marker_style.dart';

class StationDot {
  final LatLng coordinate;
  final Color color;
  final double radius;
  final double fillOpacity;
  final double borderOpacity;
  final double borderWidth;

  const StationDot({
    required this.coordinate,
    required this.color,
    required this.radius,
    required this.fillOpacity,
    required this.borderOpacity,
    required this.borderWidth,
  });
}

class StationDotPainterLayer extends StatefulWidget {
  final List<StationDot> dots;
  final bool sizeWithCameraZoom;

  const StationDotPainterLayer({
    super.key,
    required this.dots,
    this.sizeWithCameraZoom = false,
  });

  @override
  State<StationDotPainterLayer> createState() => _StationDotPainterLayerState();
}

class _StationDotPainterLayerState extends State<StationDotPainterLayer> {
  final _projected = <LatLng, Offset>{};
  List<Offset>? _projectedByIndex;
  List<StationDot>? _indexedDots;
  double? _zoom;
  Crs? _crs;
  List<StationDot> get dots => widget.dots;
  bool get sizeWithCameraZoom => widget.sizeWithCameraZoom;

  @override
  void didUpdateWidget(covariant StationDotPainterLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.dots, dots)) {
      _projectedByIndex = null;
      _indexedDots = null;
      final live = dots.map((dot) => dot.coordinate).toSet();
      _projected.removeWhere((coordinate, _) => !live.contains(coordinate));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (dots.isEmpty) {
      _projected.clear();
      _projectedByIndex = null;
      _indexedDots = null;
      return const SizedBox.shrink();
    }
    final camera = MapCamera.of(context);
    if (_zoom != camera.zoom || _crs != camera.crs) {
      _projected.clear();
      _projectedByIndex = null;
      _indexedDots = null;
      _zoom = camera.zoom;
      _crs = camera.crs;
    }
    var projectedByIndex = _projectedByIndex;
    if (projectedByIndex == null ||
        !identical(_indexedDots, dots) ||
        projectedByIndex.length != dots.length) {
      projectedByIndex = List<Offset>.generate(dots.length, (i) {
        final coord = dots[i].coordinate;
        return _projected.putIfAbsent(
          coord,
          () => camera.projectAtZoom(coord),
        );
      }, growable: false);
      _projectedByIndex = projectedByIndex;
      _indexedDots = dots;
      if (_projected.length > dots.length) {
        final live = dots.map((dot) => dot.coordinate).toSet();
        _projected.removeWhere((coordinate, _) => !live.contains(coordinate));
      }
    }
    final visible = camera.pixelBounds.inflate(12);
    final worldWidth = camera.getWorldWidthAtZoom();
    final zoomRadius = sizeWithCameraZoom
        ? KaKmaMarkerStyle.dotSizeForZoom(camera.zoom) / 2
        : null;
    // A hidden station changing color must not invalidate the whole map.
    // Keep the original observations; select only dots this camera can paint.
    final visibleDots = <({StationDot dot, Offset point})>[];
    for (var i = 0; i < dots.length; i++) {
      final dot = dots[i];
      final projected = projectedByIndex[i];
      final radius = zoomRadius ?? dot.radius;
      bool intersects(double shift) =>
          _intersects(projected.dx + shift, projected.dy, radius, visible);
      if (intersects(0) ||
          (worldWidth != 0 &&
              (intersects(-worldWidth) || intersects(worldWidth)))) {
        visibleDots.add((dot: dot, point: projected));
      }
    }
    if (visibleDots.isEmpty) return const SizedBox.shrink();
    return MobileLayerTransformer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: camera.size,
          isComplex: true,
          willChange: false,
          painter: _StationDotPainter(
            camera: camera,
            dots: visibleDots,
            sizeWithCameraZoom: sizeWithCameraZoom,
          ),
        ),
      ),
    );
  }
}

class _StationDotPainter extends CustomPainter {
  final MapCamera camera;
  final List<({StationDot dot, Offset point})> dots;
  final bool sizeWithCameraZoom;

  _StationDotPainter({
    required this.camera,
    required this.dots,
    required this.sizeWithCameraZoom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final worldWidth = camera.getWorldWidthAtZoom();
    final origin = camera.pixelOrigin;
    final visible = camera.pixelBounds.inflate(12);
    // Most stations share a few styles. Keep the same individual circle order,
    // without repeatedly sending identical colors and widths through dart:ui.
    // This palette lives for this paint only, so it cannot grow across frames.
    final styles = <(Color, double, double, double), _DotPaints>{};
    final zoomRadius = sizeWithCameraZoom
        ? KaKmaMarkerStyle.dotSizeForZoom(camera.zoom) / 2
        : null;
    final zoomBorder = sizeWithCameraZoom
        ? KaKmaMarkerStyle.borderWidthForZoom(camera.zoom)
        : null;

    for (final projectedDot in dots) {
      final dot = projectedDot.dot;
      final radius = zoomRadius ?? dot.radius;
      final borderWidth = zoomBorder ?? dot.borderWidth;
      final projected = projectedDot.point;
      final fillAlpha = dot.fillOpacity.clamp(0.0, 1.0);
      final borderAlpha = dot.borderOpacity.clamp(0.0, 1.0);
      final style = styles.putIfAbsent((
        dot.color,
        fillAlpha,
        borderAlpha,
        borderWidth,
      ), () => _DotPaints(dot.color, fillAlpha, borderAlpha, borderWidth));
      _drawAt(canvas, projected, origin, visible, style, radius);
      if (worldWidth == 0) continue;

      for (double shift = -worldWidth; ; shift -= worldWidth) {
        final x = projected.dx + shift;
        if (!_intersects(x, projected.dy, radius, visible)) break;
        final shifted = Offset(x, projected.dy);
        _drawAt(canvas, shifted, origin, visible, style, radius);
      }
      for (double shift = worldWidth; ; shift += worldWidth) {
        final x = projected.dx + shift;
        if (!_intersects(x, projected.dy, radius, visible)) break;
        final shifted = Offset(x, projected.dy);
        _drawAt(canvas, shifted, origin, visible, style, radius);
      }
    }
  }

  void _drawAt(
    Canvas canvas,
    Offset projected,
    Offset origin,
    Rect visible,
    _DotPaints style,
    double radius,
  ) {
    if (!_isVisible(projected, visible, radius)) return;
    final local = projected - origin;
    if (style.fill case final fill?) {
      canvas.drawCircle(local, radius, fill);
    }
    if (style.stroke case final stroke?) {
      canvas.drawCircle(local, radius, stroke);
    }
  }

  bool _isVisible(Offset projected, Rect visible, double radius) {
    return _intersects(projected.dx, projected.dy, radius, visible);
  }

  @override
  bool shouldRepaint(covariant _StationDotPainter oldDelegate) {
    if (oldDelegate.camera != camera ||
        oldDelegate.sizeWithCameraZoom != sizeWithCameraZoom ||
        oldDelegate.dots.length != dots.length) {
      return true;
    }
    if (identical(oldDelegate.dots, dots)) return false;
    for (var index = 0; index < dots.length; index++) {
      final previous = oldDelegate.dots[index].dot;
      final current = dots[index].dot;
      if (previous.coordinate != current.coordinate ||
          previous.color != current.color ||
          previous.radius != current.radius ||
          previous.fillOpacity != current.fillOpacity ||
          previous.borderOpacity != current.borderOpacity ||
          previous.borderWidth != current.borderWidth) {
        return true;
      }
    }
    return false;
  }
}

class _DotPaints {
  _DotPaints(Color color, double fillAlpha, double borderAlpha, double width)
    : fill = fillAlpha > 0
          ? (Paint()
              ..style = PaintingStyle.fill
              ..color = color.withValues(alpha: fillAlpha))
          : null,
      stroke = borderAlpha > 0 && width > 0
          ? (Paint()
              ..style = PaintingStyle.stroke
              ..color = color.withValues(alpha: borderAlpha)
              ..strokeWidth = width)
          : null;
  final Paint? fill, stroke;
}

bool _intersects(double x, double y, double radius, Rect visible) =>
    x + radius > visible.left &&
    x - radius < visible.right &&
    y + radius > visible.top &&
    y - radius < visible.bottom;
