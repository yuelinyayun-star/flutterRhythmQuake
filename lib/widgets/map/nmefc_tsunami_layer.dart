import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/tsunami_message.dart';

class NmefcTsunamiLayer extends StatelessWidget {
  final TsunamiMessage? tsunami;

  const NmefcTsunamiLayer({super.key, required this.tsunami});

  @override
  Widget build(BuildContext context) {
    final data = tsunami;
    if (data == null || data.source != TsunamiSource.nmefc) {
      return const SizedBox.shrink();
    }

    final markers = <Marker>[
      ..._buildEpicenterMarkers(data),
      ..._buildObservationMarkers(context, data),
    ];

    if (markers.isEmpty) {
      return const SizedBox.shrink();
    }

    return MarkerLayer(markers: markers);
  }

  List<Marker> _buildEpicenterMarkers(TsunamiMessage data) {
    final lat = data.epicenterLat;
    final lng = data.epicenterLng;
    if (!_isValidLatLng(lat, lng)) return const [];

    final color = _classColor(data.className);
    return [
      Marker(
        point: LatLng(lat!, lng!),
        width: 92,
        height: 72,
        child: Tooltip(
          message: _epicenterTooltip(data),
          child: _NmefcEpicenterMarker(color: color, magnitude: data.magnitude),
        ),
      ),
    ];
  }

  List<Marker> _buildObservationMarkers(
    BuildContext context,
    TsunamiMessage data,
  ) {
    double zoom = 5.0;
    final camera = MapCamera.maybeOf(context);
    if (camera != null) zoom = camera.zoom;
    final size = (zoom * 1.9).clamp(9.5, 17.0);
    final showLabel = zoom >= 6.2;

    return data.observations.map((station) {
      final color = _waveHeightColor(station.maxWaveHeightMeters);
      return Marker(
        point: LatLng(station.latitude, station.longitude),
        width: showLabel ? 78 : 28,
        height: showLabel ? 42 : 28,
        child: Tooltip(
          message: _observationTooltip(station),
          child: _NmefcObservationMarker(
            color: color,
            size: size,
            label: showLabel ? station.maxWaveHeight : null,
          ),
        ),
      );
    }).toList();
  }

  static bool _isValidLatLng(double? lat, double? lng) {
    return lat != null &&
        lng != null &&
        lat.isFinite &&
        lng.isFinite &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180;
  }

  static String _epicenterTooltip(TsunamiMessage data) {
    final lines = <String>[
      data.title.isEmpty ? 'NMEFC 海啸信息' : data.title,
      if (data.epicenterName.isNotEmpty) data.epicenterName,
      if (data.originTime.isNotEmpty) '发震时刻: ${data.originTime}',
      if (data.magnitude != null) '震级: M${data.magnitude!.toStringAsFixed(1)}',
      if (data.depth != null) '深度: ${data.depth!.toStringAsFixed(0)}km',
    ];
    return lines.join('\n');
  }

  static String _observationTooltip(TsunamiObservationInfo station) {
    final lines = <String>[
      station.stationName.isEmpty ? '水位监测站' : station.stationName,
      if (station.location.isNotEmpty) station.location,
      if (station.maxWaveHeight.isNotEmpty) '最大波高: ${station.maxWaveHeight}cm',
      if (station.time.isNotEmpty) '观测时刻: ${station.time}',
    ];
    return lines.join('\n');
  }

  static Color _classColor(String className) {
    switch (className) {
      case 'blue':
        return const Color(0xFF4AA3FF);
      case 'yellow':
        return const Color(0xFFF4D44D);
      case 'red':
        return const Color(0xFFFF4F4F);
      case 'purple':
        return const Color(0xFFB56AFF);
      case 'gray':
      default:
        return const Color(0xFF9EA9B7);
    }
  }

  static Color _waveHeightColor(double? meters) {
    if (meters == null || meters <= 0) return const Color(0xFF97A6B9);
    if (meters >= 3.0) return const Color(0xFFB56AFF);
    if (meters >= 1.0) return const Color(0xFFFF4F4F);
    if (meters >= 0.3) return const Color(0xFFF4D44D);
    return const Color(0xFF4AA3FF);
  }
}

class _NmefcEpicenterMarker extends StatelessWidget {
  final Color color;
  final double? magnitude;

  const _NmefcEpicenterMarker({required this.color, required this.magnitude});

  @override
  Widget build(BuildContext context) {
    final magText = magnitude == null
        ? '海啸'
        : 'M${magnitude!.toStringAsFixed(1)}';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xE61A2230),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.72)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              magText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 2),
          CustomPaint(
            size: const Size.square(34),
            painter: _NmefcEpicenterPainter(color),
          ),
        ],
      ),
    );
  }
}

class _NmefcEpicenterPainter extends CustomPainter {
  final Color color;

  _NmefcEpicenterPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 2;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.3
      ..color = color.withValues(alpha: 0.82);
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: 0.18);
    final cross = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.1
      ..strokeCap = StrokeCap.round
      ..color = color;
    final shadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.4
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x99000000);

    canvas.drawCircle(center, radius, fill);
    canvas.drawCircle(center, radius, ring);

    final inset = radius * 0.48;
    canvas.drawLine(
      Offset(center.dx - inset, center.dy - inset),
      Offset(center.dx + inset, center.dy + inset),
      shadow,
    );
    canvas.drawLine(
      Offset(center.dx + inset, center.dy - inset),
      Offset(center.dx - inset, center.dy + inset),
      shadow,
    );
    canvas.drawLine(
      Offset(center.dx - inset, center.dy - inset),
      Offset(center.dx + inset, center.dy + inset),
      cross,
    );
    canvas.drawLine(
      Offset(center.dx + inset, center.dy - inset),
      Offset(center.dx - inset, center.dy + inset),
      cross,
    );
  }

  @override
  bool shouldRepaint(covariant _NmefcEpicenterPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _NmefcObservationMarker extends StatelessWidget {
  final Color color;
  final double size;
  final String? label;

  const _NmefcObservationMarker({
    required this.color,
    required this.size,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final marker = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.34),
        border: Border.all(color: color.withValues(alpha: 0.95), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
      ),
    );

    if (label == null || label!.isEmpty) {
      return Center(child: marker);
    }

    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          marker,
          const SizedBox(width: 3),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xD91A2230),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: color.withValues(alpha: 0.55)),
              ),
              child: Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
