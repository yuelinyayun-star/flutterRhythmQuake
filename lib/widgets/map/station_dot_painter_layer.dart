import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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

  const StationDotPainterLayer({super.key, required this.dots});

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
          painter: _StationDotPainter(camera: camera, dots: dots),
        ),
      ),
    );
  }
}

class _StationDotPainter extends CustomPainter {
  final MapCamera camera;
  final List<StationDot> dots;

  _StationDotPainter({required this.camera, required this.dots});

  @override
  void paint(Canvas canvas, Size size) {
    final worldWidth = camera.getWorldWidthAtZoom();
    final origin = camera.pixelOrigin;
    final visible = camera.pixelBounds.inflate(12);
    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()..style = PaintingStyle.stroke;

    for (final dot in dots) {
      final projected = camera.projectAtZoom(dot.coordinate);
      _drawAt(canvas, projected, origin, visible, fill, stroke, dot);
      if (worldWidth == 0) continue;

      for (double shift = -worldWidth; ; shift -= worldWidth) {
        final shifted = Offset(projected.dx + shift, projected.dy);
        if (!_isVisible(shifted, visible, dot.radius)) break;
        _drawAt(canvas, shifted, origin, visible, fill, stroke, dot);
      }
      for (double shift = worldWidth; ; shift += worldWidth) {
        final shifted = Offset(projected.dx + shift, projected.dy);
        if (!_isVisible(shifted, visible, dot.radius)) break;
        _drawAt(canvas, shifted, origin, visible, fill, stroke, dot);
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
  ) {
    if (!_isVisible(projected, visible, dot.radius)) return;
    final local = projected - origin;
    final fillOpacity = dot.fillOpacity.clamp(0.0, 1.0);
    if (fillOpacity > 0) {
      fill.color = dot.color.withValues(alpha: fillOpacity);
      canvas.drawCircle(local, dot.radius, fill);
    }
    final borderOpacity = dot.borderOpacity.clamp(0.0, 1.0);
    if (borderOpacity > 0 && dot.borderWidth > 0) {
      stroke
        ..color = dot.color.withValues(alpha: borderOpacity)
        ..strokeWidth = dot.borderWidth;
      canvas.drawCircle(local, dot.radius, stroke);
    }
  }

  bool _isVisible(Offset projected, Rect visible, double radius) {
    return visible.overlaps(Rect.fromCircle(center: projected, radius: radius));
  }

  @override
  bool shouldRepaint(covariant _StationDotPainter oldDelegate) {
    return oldDelegate.camera != camera || oldDelegate.dots != dots;
  }
}
