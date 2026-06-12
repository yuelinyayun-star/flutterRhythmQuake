import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/quake_message.dart';
import '../../core/utils/world_wrap.dart';

class FssnCmtLayer extends StatelessWidget {
  final List<FssnCmtMarker>? markers;

  const FssnCmtLayer({super.key, this.markers});

  @override
  Widget build(BuildContext context) {
    if (markers == null || markers!.isEmpty) return const SizedBox.shrink();

    return CustomPaint(
      painter: _CmtPainter(markers: markers!, camera: MapCamera.of(context)),
      size: Size.infinite,
    );
  }
}

class FssnCmtMarker {
  final double latitude;
  final double longitude;
  final String nodalPlane1;
  final String location;
  final double magnitude;

  const FssnCmtMarker({
    required this.latitude,
    required this.longitude,
    required this.nodalPlane1,
    required this.location,
    required this.magnitude,
  });

  factory FssnCmtMarker.fromQuakeMessage(QuakeMessage event) {
    return FssnCmtMarker(
      latitude: event.latitude,
      longitude: event.longitude,
      nodalPlane1: event.nodalPlane1 ?? '0/90/0',
      location: event.location,
      magnitude: event.magnitude,
    );
  }
}

class _CmtPainter extends CustomPainter {
  final List<FssnCmtMarker> markers;
  final MapCamera camera;

  _CmtPainter({required this.markers, required this.camera});

  @override
  void paint(Canvas canvas, Size size) {
    for (final marker in markers) {
      final offset = camera.getOffsetFromOrigin(
        WorldWrap.latLngClosestToCamera(
          LatLng(marker.latitude, marker.longitude),
          camera,
        ),
      );
      if (offset.dx < -60 ||
          offset.dx > size.width + 60 ||
          offset.dy < -60 ||
          offset.dy > size.height + 60) {
        continue;
      }

      _drawBeachball(canvas, offset, 18.0, marker.nodalPlane1);

      final tp = TextPainter(
        text: TextSpan(
          text: marker.location,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            shadows: [Shadow(color: Colors.black87, blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(offset.dx - tp.width / 2, offset.dy + 22));
    }
  }

  void _drawBeachball(Canvas canvas, Offset center, double r, String plane1) {
    final parts = plane1.split('/');
    if (parts.length != 3) return;
    final strike = double.tryParse(parts[0]) ?? 0;
    final dip = double.tryParse(parts[1]) ?? 90;
    final rake = double.tryParse(parts[2]) ?? 0;

    final strRad = strike * pi / 180.0;
    final dipRad = dip * pi / 180.0;
    final rakeRad = rake * pi / 180.0;

    // Normal vector to plane 1 (downward)
    final n1x = -sin(dipRad) * sin(strRad);
    final n1y = sin(dipRad) * cos(strRad);
    final n1z = -cos(dipRad);

    // Slip vector on plane 1
    final s1x =
        cos(rakeRad) * cos(strRad) + sin(rakeRad) * cos(dipRad) * sin(strRad);
    final s1y =
        cos(rakeRad) * sin(strRad) - sin(rakeRad) * cos(dipRad) * cos(strRad);
    final s1z = -sin(rakeRad) * sin(dipRad);

    final nMinus = n1x - s1x, nMinusy = n1y - s1y, nMinusz = n1z - s1z;
    double pLen = sqrt(nMinus * nMinus + nMinusy * nMinusy + nMinusz * nMinusz);
    if (pLen == 0) pLen = 1;
    final pax = (n1x - s1x) / pLen,
        pay = (n1y - s1y) / pLen,
        paz = (n1z - s1z) / pLen;

    // Draw circle background
    final circlePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, r, circlePaint);

    // Fill quadrants by sampling points
    final fillDark = Paint()
      ..color = const Color(0xFF444444)
      ..style = PaintingStyle.fill;

    const int n = 60;
    final cellW = 2.0 * r / n + 1;
    for (int i = 0; i < n; i++) {
      final px = center.dx - r + (2 * r * i) / n;
      for (int j = 0; j < n; j++) {
        final py = center.dy - r + (2 * r * j) / n;
        final dx = (px - center.dx) / r;
        final dy = (py - center.dy) / r;
        final r2 = dx * dx + dy * dy;
        if (r2 > 1.0) continue;

        // Inverse stereographic projection to lower sphere
        final denom = 1.0 + r2;
        final sx = 2.0 * dx / denom;
        final sy = 2.0 * dy / denom;
        final sz = -(1.0 - r2) / denom;

        final dotP = sx * pax + sy * pay + sz * paz;
        if (dotP > 0.01) {
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset(px, py),
              width: cellW,
              height: cellW,
            ),
            fillDark,
          );
        }
      }
    }

    // Circle border on top
    final borderPaint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, r, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _CmtPainter oldDelegate) => true;
}
