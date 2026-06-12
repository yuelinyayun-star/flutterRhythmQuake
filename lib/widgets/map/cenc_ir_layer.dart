import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/cenc_ir_data.dart';
import '../../core/intensity_calculator.dart';

class CencIrLayer extends StatelessWidget {
  final CencIrData? data;

  const CencIrLayer({super.key, this.data});

  @override
  Widget build(BuildContext context) {
    if (data == null) return const SizedBox.shrink();

    return CustomPaint(
      painter: CencIrPainter(data: data!, camera: MapCamera.of(context)),
      size: Size.infinite,
    );
  }
}

class CencIrPainter extends CustomPainter {
  final CencIrData data;
  final MapCamera camera;

  CencIrPainter({required this.data, required this.camera});

  static const double _baseStationRadius = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    _drawContours(canvas, size);
    _drawEpicenter(canvas, size);
    _drawStationIntensities(canvas, size);
  }

  void _drawEpicenter(Canvas canvas, Size size) {
    final offset = camera.getOffsetFromOrigin(LatLng(data.epiLat, data.epiLon));
    if (offset.dx < -100 ||
        offset.dx > size.width + 100 ||
        offset.dy < -100 ||
        offset.dy > size.height + 100) {
      return;
    }

    final outerPaint = Paint()
      ..color = const Color(0xFFFF4500).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(offset, 14, outerPaint);

    final midPaint = Paint()
      ..color = const Color(0xFFFF4500).withValues(alpha: 0.4)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(offset, 8, midPaint);

    final ringPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(offset, 7, ringPaint);

    final centerPaint = Paint()
      ..color = const Color(0xFFFF4500)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(offset, 4, centerPaint);

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

    final features = geojson['features'];
    if (features is! List) return;

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

      final color = _getIntensityColor(intensity);

      if (geomType == 'Polygon' &&
          coordinates is List &&
          coordinates.isNotEmpty) {
        _drawPolygon(canvas, coordinates, color, size);
      } else if (geomType == 'MultiPolygon' && coordinates is List) {
        for (final polygon in coordinates) {
          if (polygon is List && polygon.isNotEmpty) {
            _drawPolygon(canvas, polygon, color, size);
          }
        }
      }
    }
  }

  void _drawPolygon(Canvas canvas, List coordinates, Color color, Size size) {
    final outerRing = coordinates.isNotEmpty ? coordinates[0] : null;
    if (outerRing is! List || outerRing.length < 3) return;

    final path = ui.Path();
    bool first = true;

    for (final point in outerRing) {
      if (point is! List || point.length < 2) continue;
      final lon = double.tryParse(point[0].toString()) ?? 0;
      final lat = double.tryParse(point[1].toString()) ?? 0;
      final offset = camera.getOffsetFromOrigin(LatLng(lat, lon));

      if (offset.dx < -100 ||
          offset.dx > size.width + 100 ||
          offset.dy < -100 ||
          offset.dy > size.height + 100) {
        first = true;
        continue;
      }

      if (first) {
        path.moveTo(offset.dx, offset.dy);
        first = false;
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }

    path.close();

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final strokePaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, strokePaint);
  }

  void _drawStationIntensities(Canvas canvas, Size size) {
    for (final station in data.instrumentIntensities) {
      final offset = camera.getOffsetFromOrigin(
        LatLng(station.latitude, station.longitude),
      );

      if (offset.dx < -50 ||
          offset.dx > size.width + 50 ||
          offset.dy < -50 ||
          offset.dy > size.height + 50) {
        continue;
      }

      final color = _getIntensityColor(station.intensity);
      final radius = _stationRadius();

      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(offset, radius + 5, glowPaint);

      final fillPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(offset, radius, fillPaint);

      final borderPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      canvas.drawCircle(offset, radius, borderPaint);

      final intText = station.intensity.toStringAsFixed(1);
      final intPainter = TextPainter(
        text: TextSpan(
          text: intText,
          style: TextStyle(
            color: _labelColor(color),
            fontSize: (radius * 0.62).clamp(7.5, 9.5),
            fontWeight: FontWeight.w900,
            shadows: [
              Shadow(
                color: _labelColor(color) == Colors.black
                    ? Colors.white.withValues(alpha: 0.75)
                    : Colors.black.withValues(alpha: 0.85),
                blurRadius: 2.5,
              ),
              Shadow(
                color: _labelColor(color) == Colors.black
                    ? Colors.white.withValues(alpha: 0.55)
                    : Colors.black.withValues(alpha: 0.65),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      intPainter.paint(
        canvas,
        Offset(
          offset.dx - intPainter.width / 2,
          offset.dy - intPainter.height / 2,
        ),
      );

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
      if (lines.isEmpty) continue;

      final labelY = offset.dy + radius + 4;
      for (var i = 0; i < lines.length; i++) {
        final lp = TextPainter(
          text: TextSpan(
            text: lines[i],
            style: TextStyle(
              color: Colors.white.withValues(alpha: i == 0 ? 1.0 : 0.75),
              fontSize: i == 0 ? 10 : 8.5,
              fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
              shadows: const [Shadow(color: Colors.black87, blurRadius: 3)],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        lp.paint(canvas, Offset(offset.dx - lp.width / 2, labelY + i * 12));
      }
    }
  }

  Color _getIntensityColor(double intensity) {
    return Color(IntensityCalculator.getCsisColor(intensity.round()));
  }

  double _stationRadius() {
    return (_baseStationRadius + (camera.zoom - 5.0) * 0.8).clamp(7.0, 12.0);
  }

  Color _labelColor(Color background) {
    return background.computeLuminance() > 0.42 ? Colors.black : Colors.white;
  }

  @override
  bool shouldRepaint(covariant CencIrPainter oldDelegate) {
    return oldDelegate.data.uniEventId != data.uniEventId ||
        oldDelegate.camera != camera;
  }
}
