import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/tsunami_message.dart';

class InternationalTsunamiLayer extends StatelessWidget {
  final TsunamiMessage? tsunami;

  const InternationalTsunamiLayer({super.key, required this.tsunami});

  @override
  Widget build(BuildContext context) {
    final data = tsunami;
    if (data == null ||
        !_isInternationalSource(data.source) ||
        !data.isActive) {
      return const SizedBox.shrink();
    }
    final lat = data.epicenterLat;
    final lng = data.epicenterLng;
    if (lat == null ||
        lng == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lng < -180 ||
        lng > 180) {
      return const SizedBox.shrink();
    }

    final color = _gradeColor(data.className);
    return MarkerLayer(
      markers: [
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
              child: const Icon(Icons.waves, color: Colors.white, size: 14),
            ),
          ),
        ),
      ],
    );
  }

  static bool _isInternationalSource(TsunamiSource source) {
    return source == TsunamiSource.ptwc ||
        source == TsunamiSource.ntwc ||
        source == TsunamiSource.incois;
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
