import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/quake_message.dart';
import '../../core/calculator.dart';
import '../../core/travel_time_service.dart';
import '../../core/utils/world_wrap.dart';
import '../../services/ntp_service.dart';
import '../../core/utils/quake_time.dart';
import '../../core/event_animation_clock.dart';

enum SWaveColorMode { alert, magnitude, intensity }

class QuakeWaveLayer extends StatefulWidget {
  final QuakeMessage event;
  final bool showWaves;
  final LatLng? userPosition;
  final SWaveColorMode colorMode;
  final double frameRate;
  final bool blinkOn;
  final Color? pWaveColor;
  final Color? sWaveColor;
  final bool showCrosshair;
  final bool showEpicenterLabel;

  const QuakeWaveLayer({
    super.key,
    required this.event,
    this.showWaves = true,
    this.userPosition,
    this.colorMode = SWaveColorMode.alert,
    this.frameRate = 4,
    this.blinkOn = true,
    this.pWaveColor,
    this.sWaveColor,
    this.showCrosshair = true,
    this.showEpicenterLabel = true,
  });

  @override
  State<QuakeWaveLayer> createState() => _QuakeWaveLayerState();
}

class _QuakeWaveLayerState extends State<QuakeWaveLayer> {
  EventAnimationLease? _clockLease;

  @override
  void initState() {
    super.initState();
    _syncClock();
  }

  @override
  void didUpdateWidget(covariant QuakeWaveLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showWaves != widget.showWaves ||
        oldWidget.frameRate != widget.frameRate) {
      _syncClock();
    }
  }

  @override
  void dispose() {
    _clockLease?.dispose();
    super.dispose();
  }

  void _syncClock() {
    if (widget.showWaves) {
      _clockLease ??= EventAnimationClock.instance.acquire();
    } else {
      _clockLease?.dispose();
      _clockLease = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildPaint(context);
  }

  Widget _buildPaint(BuildContext context) {
    return Builder(
      builder: (innerContext) {
        final camera = MapCamera.of(innerContext);
        final repaint = widget.showWaves
            ? EventAnimationClock.instance.listenableForFrameRate(
                widget.frameRate,
              )
            : null;
        return CustomPaint(
          painter: WavePainter(
            event: widget.event,
            camera: camera,
            showWaves: widget.showWaves,
            userPosition: widget.userPosition,
            colorMode: widget.colorMode,
            blinkOn: widget.blinkOn,
            pWaveColor: widget.pWaveColor,
            sWaveColor: widget.sWaveColor,
            showCrosshair: widget.showCrosshair,
            showEpicenterLabel: widget.showEpicenterLabel,
            repaint: repaint,
          ),
          size: Size.infinite,
          isComplex: true,
          willChange: widget.showWaves,
        );
      },
    );
  }
}

class WavePainter extends CustomPainter {
  final QuakeMessage event;
  final MapCamera camera;
  final bool showWaves;
  final LatLng? userPosition;
  final SWaveColorMode colorMode;
  final bool blinkOn;
  final Color? pWaveColor;
  final Color? sWaveColor;
  final bool showCrosshair;
  final bool showEpicenterLabel;

  static const double _maxRadius1 = 2000;
  static const double _maxRadius2 = 10000;

  WavePainter({
    required this.event,
    required this.camera,
    this.showWaves = true,
    this.userPosition,
    this.colorMode = SWaveColorMode.alert,
    this.blinkOn = true,
    this.pWaveColor,
    this.sWaveColor,
    this.showCrosshair = true,
    this.showEpicenterLabel = true,
    super.repaint,
  });

  double _calcMaxWaveRadius() {
    final m = event.magnitude;
    return min(max(50 * m * m, 200), 2000);
  }

  double _calcOpacity(
    double radius,
    double minRadius,
    double maxRadius, [
    double minOpacity = 0,
    double maxOpacity = 1,
  ]) {
    if (radius <= minRadius * 0.2 + maxRadius * 0.8) return maxOpacity;
    if (radius >= maxRadius) return minOpacity;
    final k = 5 * (minOpacity - maxOpacity) / (maxRadius - minRadius);
    final b =
        (5 * maxOpacity * maxRadius -
            4 * minOpacity * maxRadius -
            minOpacity * minRadius) /
        (maxRadius - minRadius);
    return (k * radius + b).clamp(minOpacity, maxOpacity);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final normalizedOrigin = QuakeTime.normalizedOriginLocal(event);
    final currentTime = NtpService().now;
    final double elapsed = QuakeCalculator.getElapsedSeconds(
      normalizedOrigin,
      currentTime,
    );

    final isValidHypo = event.latitude != 0.0 || event.longitude != 0.0;
    if (!isValidHypo) return;

    final centerLatLng = WorldWrap.latLngClosestToCamera(
      LatLng(event.latitude, event.longitude),
      camera,
    );
    final centerPos = camera.getOffsetFromOrigin(centerLatLng);

    if (centerPos.dx < -200 ||
        centerPos.dx > size.width + 200 ||
        centerPos.dy < -200 ||
        centerPos.dy > size.height + 200) {
      return;
    }

    if (elapsed < 0) {
      _drawEpicenter(canvas, centerPos);
      return;
    }

    final tts = TravelTimeService();
    final maxWaveRadius = _calcMaxWaveRadius();

    double pRadiusKm = 0;
    double sRadiusKm = 0;

    if (tts.isLoaded) {
      var pInfo = tts.calcWaveDistance('jma2001', true, event.depth, elapsed);
      if (pInfo.radius > _maxRadius1) {
        pInfo = tts.calcWaveDistance('jb', true, event.depth, elapsed);
      }
      pRadiusKm = pInfo.radius;

      var sInfo = tts.calcWaveDistance('jma2001', false, event.depth, elapsed);
      if (sInfo.radius > _maxRadius1) {
        sInfo = tts.calcWaveDistance('jb', false, event.depth, elapsed);
      }
      sRadiusKm = sInfo.radius;
    } else {
      final depthFactor = event.depth > 0
          ? (1.0 - (event.depth / 700) * 0.15).clamp(0.85, 1.0)
          : 1.0;
      pRadiusKm = elapsed * QuakeCalculator.pWaveSpeed * depthFactor;
      sRadiusKm = elapsed * QuakeCalculator.sWaveSpeed * depthFactor;
    }

    final double pRadiusPx = _getPixelRadius(pRadiusKm, centerLatLng.latitude);
    final double sRadiusPx = _getPixelRadius(sRadiusKm, centerLatLng.latitude);

    if (showWaves) {
      if (sRadiusPx > 0 && sRadiusKm <= _maxRadius2) {
        final opacity = sRadiusKm <= maxWaveRadius
            ? _calcOpacity(sRadiusKm, 0, maxWaveRadius, 0.25, 1.0)
            : _calcOpacity(sRadiusKm, maxWaveRadius, _maxRadius2, 0, 0.25);
        _drawSWaveFill(
          canvas,
          centerPos,
          sRadiusPx,
          centerLatLng.latitude,
          opacity,
          sRadiusKm <= maxWaveRadius,
          sRadiusKm,
        );
      }
      if (pRadiusPx > 0 && pRadiusKm <= _maxRadius2) {
        final opacity = pRadiusKm <= maxWaveRadius
            ? _calcOpacity(pRadiusKm, 0, maxWaveRadius, 0.25, 1.0)
            : _calcOpacity(pRadiusKm, maxWaveRadius, _maxRadius2, 0, 0.25);
        _drawPWave(canvas, centerPos, pRadiusPx, opacity);
      }
      if (sRadiusPx > 0 && sRadiusKm <= _maxRadius2) {
        final opacity = sRadiusKm <= maxWaveRadius
            ? _calcOpacity(sRadiusKm, 0, maxWaveRadius, 0.25, 1.0)
            : _calcOpacity(sRadiusKm, maxWaveRadius, _maxRadius2, 0, 0.25);
        _drawSWave(canvas, centerPos, sRadiusPx, opacity);
      }
    }

    if (showWaves && userPosition != null) {
      _drawUserLocationIndicator(canvas, centerLatLng, elapsed, size);
    }

    _drawEpicenter(canvas, centerPos);
  }

  void _drawEpicenter(Canvas canvas, Offset center) {
    if (blinkOn && showCrosshair) {
      _drawCrosshair(canvas, center);
    }

    if (blinkOn && showEpicenterLabel) {
      _drawEpicenterLabel(canvas, center);
    }
  }

  void _drawPWave(
    Canvas canvas,
    Offset center,
    double radiusPx,
    double opacity,
  ) {
    final pPaint = Paint()
      ..color = (pWaveColor ?? Colors.white).withValues(
        alpha: opacity.clamp(0.0, 1.0),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radiusPx, pPaint);
  }

  Color _getSWaveColor() {
    switch (colorMode) {
      case SWaveColorMode.alert:
        if (event.isWarn) return Colors.red;
        if (event.isCanceled) return Colors.grey;
        return const Color(0xFFFF9800);
      case SWaveColorMode.magnitude:
        final mag = event.magnitude;
        if (mag >= 7) return const Color(0xFF9C27B0);
        if (mag >= 6) return Colors.red;
        if (mag >= 5) return Colors.orange;
        if (mag >= 4) return Colors.yellow;
        if (mag >= 3) return Colors.green;
        if (mag >= 2) return Colors.blue;
        return Colors.grey;
      case SWaveColorMode.intensity:
        final intensity = event.maxIntensity;
        if (intensity == null) return Colors.orange;
        if (intensity <= 0) return Colors.grey;
        if (intensity <= 2) return const Color(0xFF5FCFFF);
        if (intensity <= 4) return const Color(0xFF3FAFFF);
        if (intensity <= 5) return const Color(0xFF5FDF8F);
        if (intensity <= 6) return const Color(0xFFF7E757);
        if (intensity <= 7) return const Color(0xFFFF8F00);
        if (intensity <= 8) return const Color(0xFFFF4F00);
        if (intensity <= 9) return const Color(0xFFDF0F0F);
        return const Color(0xFF7F007F);
    }
  }

  void _drawSWave(
    Canvas canvas,
    Offset center,
    double radiusPx,
    double opacity,
  ) {
    final Color waveColor = sWaveColor ?? _getSWaveColor();
    final sPaint = Paint()
      ..color = waveColor.withValues(alpha: opacity.clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radiusPx, sPaint);
  }

  void _drawSWaveFill(
    Canvas canvas,
    Offset center,
    double radiusPx,
    double latitude,
    double opacity,
    bool showFill,
    double sRadiusKm,
  ) {
    if (!showFill) return;
    final Color waveColor = sWaveColor ?? _getSWaveColor();
    final fillOpacity = _calcOpacity(sRadiusKm, 0, _calcMaxWaveRadius()) * 0.25;
    final gradient = RadialGradient(
      center: Alignment.center,
      radius: 1.0,
      colors: [
        waveColor.withValues(alpha: 0),
        waveColor.withValues(alpha: fillOpacity.clamp(0.0, 1.0)),
      ],
      stops: const [0.0, 1.0],
    );

    final shaderRect = Rect.fromCircle(center: center, radius: radiusPx);
    final sFill = Paint()
      ..shader = gradient.createShader(shaderRect)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radiusPx, sFill);
  }

  void _drawUserLocationIndicator(
    Canvas canvas,
    LatLng epicenter,
    double elapsed,
    Size size,
  ) {
    final rawUserLatLng = userPosition!;
    final userLatLng = WorldWrap.latLngClosestToCamera(rawUserLatLng, camera);
    final userPos = camera.getOffsetFromOrigin(userLatLng);

    if (userPos.dx < -100 ||
        userPos.dx > size.width + 100 ||
        userPos.dy < -100 ||
        userPos.dy > size.height + 100) {
      return;
    }

    final distanceKm = QuakeCalculator.haversineDistance(
      epicenter.latitude,
      epicenter.longitude,
      rawUserLatLng.latitude,
      rawUserLatLng.longitude,
    );

    if (distanceKm <= 0) return;

    final tts = TravelTimeService();
    double pArrivalTime;
    double sArrivalTime;

    if (tts.isLoaded) {
      final tableName = distanceKm <= _maxRadius1 ? 'jma2001' : 'jb';
      pArrivalTime = tts.calcReachTime(
        tableName,
        true,
        event.depth,
        distanceKm,
      );
      sArrivalTime = tts.calcReachTime(
        tableName,
        false,
        event.depth,
        distanceKm,
      );
    } else {
      final depthFactor = event.depth > 0
          ? (1.0 - (event.depth / 700) * 0.15).clamp(0.85, 1.0)
          : 1.0;
      pArrivalTime = distanceKm / (QuakeCalculator.pWaveSpeed * depthFactor);
      sArrivalTime = distanceKm / (QuakeCalculator.sWaveSpeed * depthFactor);
    }

    final double pProgress = elapsed >= pArrivalTime
        ? 1.0
        : (elapsed / pArrivalTime).clamp(0.0, 1.0);
    final double sProgress = elapsed >= sArrivalTime
        ? 1.0
        : (elapsed / sArrivalTime).clamp(0.0, 1.0);

    final sColor = _getSWaveColor();

    final outerGlow = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(userPos, 16, outerGlow);

    final outerRing = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(userPos, 14, outerRing);

    if (pProgress > 0 && pProgress < 1.0) {
      final pArcPaint = Paint()
        ..color = Colors.cyanAccent.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      final arcRect = Rect.fromCircle(center: userPos, radius: 14);
      canvas.drawArc(arcRect, -pi / 2, 2 * pi * pProgress, false, pArcPaint);
    }

    if (sProgress > 0 && sProgress < 1.0) {
      final sArcPaint = Paint()
        ..color = sColor.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      final arcRect = Rect.fromCircle(center: userPos, radius: 9);
      canvas.drawArc(arcRect, -pi / 2, 2 * pi * sProgress, false, sArcPaint);
    }

    if (sProgress >= 1.0) {
      final arrivedPaint = Paint()
        ..color = Colors.red.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawCircle(userPos, 12, arrivedPaint);
    }

    final centerDot = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(userPos, 3.5, centerDot);

    final centerBorder = Paint()
      ..color = Colors.black.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(userPos, 3.5, centerBorder);

    if (sProgress < 1.0 && pProgress > 0) {
      final dirPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;
      final epicenterPos = camera.getOffsetFromOrigin(epicenter);
      canvas.drawLine(epicenterPos, userPos, dirPaint);
    }
  }

  double _getPixelRadius(double km, double latitude) {
    final double zoom = camera.zoom;
    return km * (pow(2, zoom) / (40075.017 * cos(latitude * pi / 180) / 256));
  }

  void _drawCrosshair(Canvas canvas, Offset center) {
    final crossSize = 14.0;

    final glowPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(center.dx - crossSize, center.dy - crossSize),
      Offset(center.dx + crossSize, center.dy + crossSize),
      glowPaint,
    );
    canvas.drawLine(
      Offset(center.dx + crossSize, center.dy - crossSize),
      Offset(center.dx - crossSize, center.dy + crossSize),
      glowPaint,
    );

    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(center.dx - crossSize, center.dy - crossSize),
      Offset(center.dx + crossSize, center.dy + crossSize),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx + crossSize, center.dy - crossSize),
      Offset(center.dx - crossSize, center.dy + crossSize),
      paint,
    );
  }

  void _drawEpicenterLabel(Canvas canvas, Offset center) {
    String label;
    if (event.isCanceled) {
      label = '已取消';
    } else if (event.isAssumption) {
      label = '假定震源';
    } else {
      label = 'M${event.magnitude.toStringAsFixed(1)}';
    }

    final bgPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final labelX = center.dx - textPainter.width / 2;
    final labelY = center.dy - 30;

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        labelX - 4,
        labelY - 2,
        textPainter.width + 8,
        textPainter.height + 4,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(bgRect, bgPaint);

    textPainter.paint(canvas, Offset(labelX, labelY));
  }

  @override
  bool shouldRepaint(covariant WavePainter oldDelegate) {
    if (!showWaves && !oldDelegate.showWaves) {
      return oldDelegate.event.eventId != event.eventId ||
          oldDelegate.camera != camera ||
          oldDelegate.userPosition != userPosition ||
          oldDelegate.blinkOn != blinkOn;
    }
    return oldDelegate.event != event ||
        oldDelegate.camera != camera ||
        oldDelegate.userPosition != userPosition ||
        oldDelegate.colorMode != colorMode ||
        oldDelegate.blinkOn != blinkOn ||
        oldDelegate.pWaveColor != pWaveColor ||
        oldDelegate.sWaveColor != sWaveColor ||
        oldDelegate.showCrosshair != showCrosshair ||
        oldDelegate.showEpicenterLabel != showEpicenterLabel;
  }
}
