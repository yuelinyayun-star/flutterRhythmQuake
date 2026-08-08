import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/quake_message.dart';
import '../../models/cmt_moment_tensor.dart';
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
  final String? nodalPlane1;
  final String? nodalPlane2;
  final CmtMomentTensor? momentTensor;
  final String location;
  final double magnitude;

  /// 矩心深度（km），CMT 反演产出，显示在 beachball 下方第二行
  final double? centroidDepth;

  const FssnCmtMarker({
    required this.latitude,
    required this.longitude,
    this.nodalPlane1,
    this.nodalPlane2,
    this.momentTensor,
    required this.location,
    required this.magnitude,
    this.centroidDepth,
  });

  factory FssnCmtMarker.fromQuakeMessage(QuakeMessage event) {
    return FssnCmtMarker(
      latitude: event.latitude,
      longitude: event.longitude,
      nodalPlane1: event.nodalPlane1,
      nodalPlane2: event.nodalPlane2,
      momentTensor: event.momentTensor,
      location: event.location,
      magnitude: event.magnitude,
      centroidDepth: event.centroidDepth,
    );
  }
}

/// Reusable focal-sphere widget using the same renderer as the map layer.
///
/// The marker layer below calls the shared canvas routine directly, while
/// panels can use this widget without recreating or approximating a beachball.
class CmtBeachball extends StatelessWidget {
  final double diameter;
  final CmtMomentTensor? momentTensor;
  final String? nodalPlane;
  final String? nodalPlane2;

  const CmtBeachball({
    super.key,
    required this.diameter,
    this.momentTensor,
    this.nodalPlane,
    this.nodalPlane2,
  });

  static bool hasRenderableMechanism({
    CmtMomentTensor? momentTensor,
    String? nodalPlane,
    String? nodalPlane2,
  }) {
    return momentTensor != null ||
        _StrikeDipRake.tryParse(nodalPlane) != null ||
        _StrikeDipRake.tryParse(nodalPlane2) != null;
  }

  @override
  Widget build(BuildContext context) {
    if (!hasRenderableMechanism(
      momentTensor: momentTensor,
      nodalPlane: nodalPlane,
      nodalPlane2: nodalPlane2,
    )) {
      return SizedBox.square(dimension: diameter);
    }
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(diameter),
        painter: _CmtBeachballPainter(
          momentTensor: momentTensor,
          nodalPlane: nodalPlane,
          nodalPlane2: nodalPlane2,
        ),
      ),
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

      _drawBeachball(
        canvas,
        offset,
        18.0,
        momentTensor: marker.momentTensor,
        nodalPlane: marker.nodalPlane1,
        nodalPlane2: marker.nodalPlane2,
      );

      // 矩心深度标注（beachball 下方，黄色区分）
      if (marker.centroidDepth != null && marker.centroidDepth! > 0) {
        final cdTp = TextPainter(
          text: TextSpan(
            text: 'Cd: ${marker.centroidDepth!.toInt()}km',
            style: const TextStyle(
              color: Colors.yellow,
              fontSize: 9,
              fontWeight: FontWeight.w500,
              shadows: [Shadow(color: Colors.black87, blurRadius: 3)],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        cdTp.paint(canvas, Offset(offset.dx - cdTp.width / 2, offset.dy + 22));
      }
    }
  }

  void _drawBeachball(
    Canvas canvas,
    Offset center,
    double r, {
    required CmtMomentTensor? momentTensor,
    required String? nodalPlane,
    required String? nodalPlane2,
  }) {
    _paintCmtBeachball(
      canvas,
      center,
      r,
      momentTensor: momentTensor,
      nodalPlane: nodalPlane,
      nodalPlane2: nodalPlane2,
    );
  }

  @override
  bool shouldRepaint(covariant _CmtPainter oldDelegate) => true;
}

class _CmtBeachballPainter extends CustomPainter {
  final CmtMomentTensor? momentTensor;
  final String? nodalPlane;
  final String? nodalPlane2;

  const _CmtBeachballPainter({
    this.momentTensor,
    this.nodalPlane,
    this.nodalPlane2,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintCmtBeachball(
      canvas,
      Offset(size.width / 2, size.height / 2),
      size.shortestSide / 2,
      momentTensor: momentTensor,
      nodalPlane: nodalPlane,
      nodalPlane2: nodalPlane2,
    );
  }

  @override
  bool shouldRepaint(covariant _CmtBeachballPainter oldDelegate) =>
      oldDelegate.momentTensor != momentTensor ||
      oldDelegate.nodalPlane != nodalPlane ||
      oldDelegate.nodalPlane2 != nodalPlane2;
}

void _paintCmtBeachball(
  Canvas canvas,
  Offset center,
  double r, {
  required CmtMomentTensor? momentTensor,
  required String? nodalPlane,
  required String? nodalPlane2,
}) {
  final mechanism = momentTensor != null
      ? _FocalMechanism.fromMomentTensor(momentTensor)
      : _FocalMechanism.tryParse(nodalPlane) ??
            _FocalMechanism.tryParse(nodalPlane2);
  if (mechanism == null || r <= 0) return;

  final circlePaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.85)
    ..style = PaintingStyle.fill;
  canvas.drawCircle(center, r, circlePaint);

  final fillDark = Paint()
    ..color = const Color(0xFFE53935)
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
          Rect.fromCenter(center: Offset(px, py), width: cellW, height: cellW),
          fillDark,
        );
      }
    }
  }

  final borderPaint = Paint()
    ..color = Colors.black54
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  canvas.drawCircle(center, r, borderPaint);

  // The tensor fill remains authoritative. These lines are the two official
  // double-couple nodal planes, overlaid only when the source supplied them.
  _drawDoubleCoupleNodalLines(canvas, center, r, <String?>[
    nodalPlane,
    nodalPlane2,
  ]);
}

void _drawDoubleCoupleNodalLines(
  Canvas canvas,
  Offset center,
  double r,
  List<String?> planes,
) {
  final line = Paint()
    ..color = Colors.black
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = max(1.0, r * 0.055);

  for (final plane in planes) {
    for (final path in _projectNodalPlanePaths(plane, center, r)) {
      canvas.drawPath(path, line);
    }
  }
}

List<ui.Path> _projectNodalPlanePaths(String? plane, Offset center, double r) {
  final parsed = _StrikeDipRake.tryParse(plane);
  if (parsed == null || r <= 0) return const <ui.Path>[];

  final strike = parsed.strike * pi / 180.0;
  final dip = parsed.dip * pi / 180.0;

  // A horizontal strike vector and a perpendicular vector in the same plane
  // form an orthonormal basis for the great circle of this nodal plane.
  final strikeNorth = cos(strike);
  final strikeEast = sin(strike);
  final strikeDown = 0.0;
  final normalNorth = -sin(dip) * sin(strike);
  final normalEast = sin(dip) * cos(strike);
  final normalDown = -cos(dip);
  var planeNorth = normalEast * strikeDown - normalDown * strikeEast;
  var planeEast = normalDown * strikeNorth - normalNorth * strikeDown;
  var planeDown = normalNorth * strikeEast - normalEast * strikeNorth;
  final planeLength = sqrt(
    planeNorth * planeNorth + planeEast * planeEast + planeDown * planeDown,
  );
  if (planeLength <= 1e-9) return const <ui.Path>[];
  planeNorth /= planeLength;
  planeEast /= planeLength;
  planeDown /= planeLength;

  final paths = <ui.Path>[];
  ui.Path? current;
  const samples = 720;
  for (var index = 0; index <= samples; index++) {
    final angle = 2.0 * pi * index / samples;
    final north = cos(angle) * strikeNorth + sin(angle) * planeNorth;
    final east = cos(angle) * strikeEast + sin(angle) * planeEast;
    final down = cos(angle) * strikeDown + sin(angle) * planeDown;
    if (down < -1e-6) {
      if (current != null) {
        paths.add(current);
        current = null;
      }
      continue;
    }

    final denominator = 1.0 + down;
    if (denominator <= 1e-9) continue;
    final point = Offset(
      center.dx + r * east / denominator,
      center.dy - r * north / denominator,
    );
    if (current == null) {
      current = ui.Path()..moveTo(point.dx, point.dy);
    } else {
      current.lineTo(point.dx, point.dy);
    }
  }
  if (current != null) paths.add(current);
  return paths;
}

class _StrikeDipRake {
  final double strike;
  final double dip;
  final double rake;

  const _StrikeDipRake(this.strike, this.dip, this.rake);

  static _StrikeDipRake? tryParse(String? value) {
    if (value == null) return null;
    final parts = value.split('/');
    if (parts.length != 3) return null;
    final strike = double.tryParse(parts[0].trim());
    final dip = double.tryParse(parts[1].trim());
    final rake = double.tryParse(parts[2].trim());
    if (strike == null || dip == null || rake == null) return null;
    if (!strike.isFinite || !dip.isFinite || !rake.isFinite) return null;
    if (dip < 0 || dip > 90) return null;
    return _StrikeDipRake(strike % 360, dip, rake);
  }
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

  static _FocalMechanism? tryParse(String? plane) {
    final parsed = _StrikeDipRake.tryParse(plane);
    if (parsed == null) return null;
    return fromStrikeDipRake(parsed.strike, parsed.dip, parsed.rake);
  }

  factory _FocalMechanism.fromMomentTensor(CmtMomentTensor tensor) {
    return _FocalMechanism(
      mnn: tensor.mnn,
      mee: tensor.mee,
      mdd: tensor.mdd,
      mne: tensor.mne,
      mnd: tensor.mnd,
      med: tensor.med,
    );
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
