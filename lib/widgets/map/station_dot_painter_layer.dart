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

class StationDotPainterLayer extends StatelessWidget {
  final List<StationDot> dots;
  final bool sizeWithCameraZoom;

  const StationDotPainterLayer({
    super.key,
    required this.dots,
    this.sizeWithCameraZoom = false,
  });

  @override
  Widget build(BuildContext context) {
    if (dots.isEmpty) return const SizedBox.shrink();
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: camera.size,
          isComplex: true,
          willChange: false,
          painter: _StationDotPainter(
            camera: camera,
            dots: dots,
            sizeWithCameraZoom: sizeWithCameraZoom,
          ),
        ),
      ),
    );
  }
}

class _StationDotPainter extends CustomPainter {
  final MapCamera camera;
  final List<StationDot> dots;
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
    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()..style = PaintingStyle.stroke;
    final zoomRadius = sizeWithCameraZoom
        ? KaKmaMarkerStyle.dotSizeForZoom(camera.zoom) / 2
        : null;
    final zoomBorder = sizeWithCameraZoom
        ? KaKmaMarkerStyle.borderWidthForZoom(camera.zoom)
        : null;

    for (final dot in dots) {
      final radius = zoomRadius ?? dot.radius;
      final borderWidth = zoomBorder ?? dot.borderWidth;
      final projected = camera.projectAtZoom(dot.coordinate);
      _drawAt(
        canvas,
        projected,
        origin,
        visible,
        fill,
        stroke,
        dot,
        radius,
        borderWidth,
      );
      if (worldWidth == 0) continue;

      for (double shift = -worldWidth; ; shift -= worldWidth) {
        final shifted = Offset(projected.dx + shift, projected.dy);
        if (!_isVisible(shifted, visible, radius)) break;
        _drawAt(
          canvas,
          shifted,
          origin,
          visible,
          fill,
          stroke,
          dot,
          radius,
          borderWidth,
        );
      }
      for (double shift = worldWidth; ; shift += worldWidth) {
        final shifted = Offset(projected.dx + shift, projected.dy);
        if (!_isVisible(shifted, visible, radius)) break;
        _drawAt(
          canvas,
          shifted,
          origin,
          visible,
          fill,
          stroke,
          dot,
          radius,
          borderWidth,
        );
      }
    }
  }

  void _drawAt(
    Canvas canvas,
    Offset projected,
    Offset origin,
    Rect visible,
    Paint fill,
    Paint stroke,
    StationDot dot,
    double radius,
    double borderWidth,
  ) {
    if (!_isVisible(projected, visible, radius)) return;
    final local = projected - origin;
    final fillOpacity = dot.fillOpacity.clamp(0.0, 1.0);
    if (fillOpacity > 0) {
      fill.color = dot.color.withValues(alpha: fillOpacity);
      canvas.drawCircle(local, radius, fill);
    }
    final borderOpacity = dot.borderOpacity.clamp(0.0, 1.0);
    if (borderOpacity > 0 && borderWidth > 0) {
      stroke
        ..color = dot.color.withValues(alpha: borderOpacity)
        ..strokeWidth = borderWidth;
      canvas.drawCircle(local, radius, stroke);
    }
  }

  bool _isVisible(Offset projected, Rect visible, double radius) {
    return visible.overlaps(Rect.fromCircle(center: projected, radius: radius));
  }

  @override
  bool shouldRepaint(covariant _StationDotPainter oldDelegate) {
    return oldDelegate.camera != camera ||
        oldDelegate.dots != dots ||
        oldDelegate.sizeWithCameraZoom != sizeWithCameraZoom;
  }
}
