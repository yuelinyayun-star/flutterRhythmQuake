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
    if (data == null || data.source != TsunamiSource.nmefc || !data.isActive) {
      return const SizedBox.shrink();
    }

    final markers = _buildObservationMarkers(context, data);
    if (markers.isEmpty) return const SizedBox.shrink();

    return MarkerLayer(markers: markers);
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

  static String _observationTooltip(TsunamiObservationInfo station) {
    final lines = <String>[
      station.stationName.isEmpty ? '水位监测站' : station.stationName,
      if (station.location.isNotEmpty) station.location,
      if (station.maxWaveHeight.isNotEmpty) '最大波高: ${station.maxWaveHeight}cm',
      if (station.time.isNotEmpty) '观测时刻: ${station.time}',
    ];
    return lines.join('\n');
  }

  static Color _waveHeightColor(double? meters) {
    if (meters == null || meters <= 0) return const Color(0xFF97A6B9);
    if (meters >= 3.0) return const Color(0xFFB56AFF);
    if (meters >= 1.0) return const Color(0xFFFF4F4F);
    if (meters >= 0.3) return const Color(0xFFF4D44D);
    return const Color(0xFF4AA3FF);
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
