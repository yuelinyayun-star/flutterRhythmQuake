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
  final String nodalPlane2;
  final String location;
  final double magnitude;

  const FssnCmtMarker({
    required this.latitude,
    required this.longitude,
    required this.nodalPlane1,
    required this.nodalPlane2,
    required this.location,
    required this.magnitude,
  });

  factory FssnCmtMarker.fromQuakeMessage(QuakeMessage event) {
    return FssnCmtMarker(
      latitude: event.latitude,
      longitude: event.longitude,
      nodalPlane1: event.nodalPlane1 ?? '0/90/0',
      nodalPlane2: event.nodalPlane2 ?? '',
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
    final mechanism = _FocalMechanism.tryParse(plane1);
    if (mechanism == null) return;

    final circlePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, r, circlePaint);

    // Fill quadrants by sampling points
    final fillDark = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    const int n = 96;
    final cellW = 2.0 * r / n + 1;
    for (int i = 0; i < n; i++) {
      final px = center.dx - r + (2 * r * i) / n;
      for (int j = 0; j < n; j++) {
        final py = center.dy - r + (2 * r * j) / n;
        final dx = (px - center.dx) / r;
        final dy = (py - center.dy) / r;
        final r2 = dx * dx + dy * dy;
        if (r2 > 1.0) continue;

        final denom = 1.0 + r2;
        final east = 2.0 * dx / denom;
        final north = -2.0 * dy / denom;
        final down = (1.0 - r2) / denom;

        if (mechanism.amplitude(north, east, down) > 0) {
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

class _FocalMechanism {
  final double mnn;
  final double mee;
  final double mdd;
  final double mne;
  final double mnd;
  final double med;

  const _FocalMechanism({
    required this.mnn,
    required this.mee,
    required this.mdd,
    required this.mne,
    required this.mnd,
    required this.med,
  });

  static _FocalMechanism? tryParse(String plane) {
    final parts = plane.split('/');
    if (parts.length != 3) return null;
    final strike = double.tryParse(parts[0].trim());
    final dip = double.tryParse(parts[1].trim());
    final rake = double.tryParse(parts[2].trim());
    if (strike == null || dip == null || rake == null) return null;
    return fromStrikeDipRake(strike, dip, rake);
  }

  static _FocalMechanism fromStrikeDipRake(
    double strike,
    double dip,
    double rake,
  ) {
    final strikeRad = strike * pi / 180.0;
    final dipRad = dip * pi / 180.0;
    final rakeRad = rake * pi / 180.0;

    final normalN = -sin(dipRad) * sin(strikeRad);
    final normalE = sin(dipRad) * cos(strikeRad);
    final normalD = -cos(dipRad);

    final slipN =
        cos(rakeRad) * cos(strikeRad) +
        sin(rakeRad) * cos(dipRad) * sin(strikeRad);
    final slipE =
        cos(rakeRad) * sin(strikeRad) -
        sin(rakeRad) * cos(dipRad) * cos(strikeRad);
    final slipD = -sin(rakeRad) * sin(dipRad);

    return _FocalMechanism(
      mnn: 2.0 * slipN * normalN,
      mee: 2.0 * slipE * normalE,
      mdd: 2.0 * slipD * normalD,
      mne: slipN * normalE + normalN * slipE,
      mnd: slipN * normalD + normalN * slipD,
      med: slipE * normalD + normalE * slipD,
    );
  }

  double amplitude(double north, double east, double down) {
    return mnn * north * north +
        mee * east * east +
        mdd * down * down +
        2.0 * mne * north * east +
        2.0 * mnd * north * down +
        2.0 * med * east * down;
  }
}
