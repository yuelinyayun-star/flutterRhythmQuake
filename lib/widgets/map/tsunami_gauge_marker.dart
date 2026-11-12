import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/tsunami_gauge_plan.dart';

/// Narrow map label. Fill fractions and all readings arrive from Rust.
class TsunamiGaugeMarker extends StatelessWidget {
  const TsunamiGaugeMarker({super.key, required this.data, this.onTap});
  final TsunamiGaugeData data;
  final VoidCallback? onTap;
  static const markerWidth = 108.0;
  static const markerHeight = 140.0;
  static const bodyWidth = 28.0;
  static const bodyHeight = 64.0;
  // SREV scales its bar pen size by 4 + sqrt(camera magnification).
  // Normalize that curve to our existing ~50px column at zoom 5.
  static double scaleAtZoom(double zoom) =>
      (.78 * (4 + 10 * math.pow(2, (zoom - 5) / 2)) / 14)
          .clamp(.30, 1.60)
          .toDouble();
  static const borderColor = Color(0xFFCBD0D5);
  static const _textColor = Color(0xFFF5F6F7);
  static const _mutedColor = Color(0xFFB4BBC3);

  Widget _text(
    String value,
    double size, {
    Color color = _textColor,
    FontWeight weight = FontWeight.w500,
  }) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(
      value,
      maxLines: 1,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: weight,
        height: 1.05,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    label:
        '${data.name}，${data.forecastLabel} ${data.forecastText}${data.forecastUnit}，'
        '${data.observationLabel} ${data.observationText}${data.observationUnit}',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: markerWidth,
        height: markerHeight,
        child: Column(
          children: [
            SizedBox(
              height: 32,
              child: Column(
                children: [
                  SizedBox(
                    height: 13,
                    child: _text(data.forecastLabel, 11, color: _mutedColor),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    height: 17,
                    child: _text(
                      '${data.forecastText}${data.forecastUnit}',
                      13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            RepaintBoundary(
              child: CustomPaint(
                key: ValueKey('tsunami_gauge_body_${data.id}'),
                painter: TsunamiGaugePainter(
                  forecastFraction: data.forecastFraction,
                  observedFraction: data.observedFraction,
                ),
                child: SizedBox(
                  width: bodyWidth,
                  height: bodyHeight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(
                          height: 22,
                          child: _text(data.observationText, 15),
                        ),
                        SizedBox(
                          height: 13,
                          child: _text(
                            data.observationUnit,
                            11,
                            color: _mutedColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 13,
              child: _text(data.observationLabel, 11, color: _mutedColor),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 15,
              child: Text(
                data.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.05,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class TsunamiGaugePainter extends CustomPainter {
  const TsunamiGaugePainter({this.forecastFraction, this.observedFraction});
  final double? forecastFraction, observedFraction;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(15),
    );
    canvas.drawRRect(body, Paint()..color = const Color(0xEB181A1E));
    canvas.save();
    canvas.clipRRect(body.deflate(3));
    final observed = observedFraction;
    if (observed != null) {
      final level = size.height - 3 - (size.height - 6) * observed;
      final water = Rect.fromLTRB(3, level, size.width - 3, size.height - 3);
      if (water.height > 0) {
        canvas.drawRect(
          water,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xA32C596C), Color(0xAE4DA9C8)],
            ).createShader(water),
        );
      }
      canvas.drawLine(
        Offset(3, level),
        Offset(size.width - 3, level),
        Paint()
          ..color = const Color(0xFF65ADC4)
          ..strokeWidth = 1,
      );
    }
    canvas.restore();
    canvas.drawRRect(
      body.deflate(.5),
      Paint()
        ..color = TsunamiGaugeMarker.borderColor.withValues(alpha: .8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final ticks = Paint()
      ..color = const Color(0x779FAAB5)
      ..strokeWidth = 1;
    for (var y = 18.0; y < size.height - 10; y += 15) {
      canvas.drawLine(Offset(-5, y), Offset(-2, y), ticks);
    }
    final forecast = forecastFraction;
    if (forecast != null) {
      final y = size.height - 3 - (size.height - 6) * forecast;
      final paint = Paint()
        ..color = const Color(0xC0D5DCE2)
        ..strokeWidth = 1;
      for (var x = -3.0; x < size.width + 3; x += 6) {
        canvas.drawLine(Offset(x, y), Offset(x + 3, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant TsunamiGaugePainter oldDelegate) =>
      forecastFraction != oldDelegate.forecastFraction ||
      observedFraction != oldDelegate.observedFraction;
}
