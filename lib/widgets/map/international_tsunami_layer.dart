import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/tsunami_message.dart';
import 'nmefc_tsunami_layer.dart';

class InternationalTsunamiLayer extends StatelessWidget {
  final TsunamiMessage? tsunami;

  const InternationalTsunamiLayer({super.key, required this.tsunami});

  @override
  Widget build(BuildContext context) {
    final data = tsunami;
    if (data == null ||
        !data.source.isBulletinSource ||
        !data.isDisplayableAt(DateTime.now())) {
      return const SizedBox.shrink();
    }
    final lat = data.epicenterLat;
    final lng = data.epicenterLng;
    final isInformation = data.isInformation;
    final color = isInformation
        ? const Color(0xFF4AA3FF)
        : _gradeColor(data.className);
    final markers = <Marker>[
      if (lat != null &&
          lng != null &&
          lat.isFinite &&
          lng.isFinite &&
          lat.abs() <= 90 &&
          lng.abs() <= 180)
        Marker(
          point: LatLng(lat, lng),
          width: 28,
          height: 28,
          child: Tooltip(
            message: [
              data.source.displayLabel,
              if (data.title.isNotEmpty) data.title,
              if (data.epicenterName.isNotEmpty) data.epicenterName,
            ].join('\n'),
            child: Container(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.85),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(
                isInformation ? Icons.info_outline : Icons.waves,
                color: Colors.white,
                size: 14,
              ),
            ),
          ),
        ),
      for (final station in data.observations.where((e) => e.hasValidPosition))
        Marker(
          point: LatLng(station.latitude, station.longitude),
          width: 78,
          height: 42,
          child: Tooltip(
            message: [
              data.source.displayLabel,
              if (station.stationName.isNotEmpty) station.stationName,
              if (station.stationId.isNotEmpty) station.stationId,
              if (station.maxWaveHeight.isNotEmpty)
                '波高：${station.maxWaveHeight}',
              if (station.time.isNotEmpty)
                '到达：${data.formatLocalTime(station.time)}',
              if (station.condition.isNotEmpty) station.condition,
            ].join('\n'),
            child: TsunamiObservationMarker(
              color: color,
              size: 14,
              label: station.maxWaveHeight.isEmpty
                  ? null
                  : station.maxWaveHeight,
            ),
          ),
        ),
    ];
    return markers.isEmpty
        ? const SizedBox.shrink()
        : MarkerLayer(markers: markers);
  }

  static Color _gradeColor(String className) {
    return switch (className) {
      'purple' => const Color(0xFF991199),
      'red' => const Color(0xFFCC3333),
      'yellow' => const Color(0xFFEECC00),
      _ => const Color(0xFF888888),
    };
  }
}
