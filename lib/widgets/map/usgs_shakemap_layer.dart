import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:latlong2/latlong.dart' show LatLng;

import '../../core/utils/quake_time.dart';
import '../../core/utils/world_wrap.dart';
import '../../models/usgs_shakemap.dart';

class UsgsShakeMapLayer extends StatelessWidget {
  const UsgsShakeMapLayer({super.key, this.frame, this.status});
  final UsgsShakeMapFrame? frame;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final data = frame;
    if (data == null && status == null) return const SizedBox.shrink();
    final product = data?.product;
    final camera = MapCamera.of(context);
    return Stack(
      children: [
        if (data != null && product != null)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: UsgsMmiContourPainter(frame: data, camera: camera),
                  isComplex: true,
                  willChange: false,
                ),
              ),
            ),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18, left: 12, right: 12),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xDD171717),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (data != null && product != null) ...[
                    Text(
                      'USGS ShakeMap · MMI 等烈度线${product.version.isEmpty ? '' : ' · 第${product.version}版'}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    Text(
                      '${data.event.location} · ${DateFormat('MM-dd HH:mm:ss').format(product.updated.toLocal())} (${QuakeTime.systemZoneLabel})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                    if (data.contours.isNotEmpty)
                      Wrap(
                        spacing: 12,
                        runSpacing: 2,
                        children: [
                          for (final contour in data.contours)
                            if (contour.value == contour.value.roundToDouble())
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 14,
                                    height: 2,
                                    color: Color(contour.colorArgb),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    contour.value.toStringAsFixed(0),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                        ],
                      ),
                  ],
                  if (status != null)
                    Text(
                      status!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class UsgsMmiContourPainter extends CustomPainter {
  const UsgsMmiContourPainter({required this.frame, required this.camera});
  final UsgsShakeMapFrame frame;
  final MapCamera camera;

  /// World-copy selection applies only to projection, leaving USGS coordinates
  /// intact. Consecutive points unwrap relative to each other at the date line.
  static List<Offset> projectLine(List<LatLng> line, MapCamera camera) {
    var reference = camera.center.longitude;
    return [
      for (final point in line)
        camera.latLngToScreenOffset(
          LatLng(
            point.latitude,
            reference = WorldWrap.longitudeClosestTo(
              point.longitude,
              reference,
            ),
          ),
        ),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final visible = Offset.zero & size;
    final occupied = <Rect>[];
    canvas.save();
    canvas.clipRect(visible);
    for (final contour in frame.contours) {
      Offset? label;
      var bestLength = 70.0;
      for (final line in contour.lines) {
        final points = projectLine(line, camera);
        final path = Path()..moveTo(points.first.dx, points.first.dy);
        var lineLength = 0.0;
        var longestVisible = 0.0;
        Offset? candidate;
        for (var i = 1; i < points.length; i++) {
          path.lineTo(points[i].dx, points[i].dy);
          final length = (points[i] - points[i - 1]).distance;
          final middle = (points[i] + points[i - 1]) / 2;
          lineLength += length;
          if (length > longestVisible && visible.deflate(25).contains(middle)) {
            longestVisible = length;
            candidate = middle;
          }
        }
        if (candidate != null && lineLength > bestLength) {
          bestLength = lineLength;
          label = candidate;
        }
        if (!path.getBounds().inflate(contour.weight).overlaps(visible)) {
          continue;
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0x88000000)
            ..style = PaintingStyle.stroke
            ..strokeWidth = contour.weight + 1
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = Color(contour.colorArgb)
            ..style = PaintingStyle.stroke
            ..strokeWidth = contour.weight
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round,
        );
      }
      if (label == null) continue;
      final text = TextPainter(
        text: TextSpan(
          text:
              'MMI ${contour.value.toStringAsFixed(contour.value == contour.value.roundToDouble() ? 0 : 1)}',
          style: TextStyle(
            color: Color(contour.colorArgb),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final rect = Rect.fromCenter(
        center: label,
        width: text.width + 8,
        height: text.height + 4,
      );
      if (occupied.any((r) => r.overlaps(rect.inflate(5)))) {
        text.dispose();
        continue;
      }
      occupied.add(rect);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = const Color(0xCC171717),
      );
      text.paint(canvas, rect.topLeft + const Offset(4, 2));
      text.dispose();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant UsgsMmiContourPainter oldDelegate) =>
      !identical(frame, oldDelegate.frame) ||
      camera.center != oldDelegate.camera.center ||
      camera.zoom != oldDelegate.camera.zoom ||
      camera.rotation != oldDelegate.camera.rotation ||
      camera.nonRotatedSize != oldDelegate.camera.nonRotatedSize;
}
