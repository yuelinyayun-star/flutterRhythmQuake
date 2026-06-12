import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../core/intensity_calculator.dart';
import '../../services/sources/fdsn_station_service.dart';

class FdsnStationLayer extends StatelessWidget {
  final List<FdsnStation> stations;

  const FdsnStationLayer({super.key, required this.stations});

  @override
  Widget build(BuildContext context) {
    if (stations.isEmpty) return const SizedBox.shrink();

    const size = 6.0;
    const opacity = 0.46;
    const borderOpacity = 0.72;

    return MarkerLayer(
      markers: [
        for (final station in stations)
          Marker(
            width: size,
            height: size,
            point: station.coordinate,
            child: _FdsnDot(
              color: _colorForStation(station),
              opacity: opacity,
              borderOpacity: borderOpacity,
            ),
          ),
      ],
    );
  }

  Color _colorForStation(FdsnStation station) {
    final intensity = station.intensity;
    if (intensity != null && station.isMotionActive) {
      return Color(IntensityCalculator.getJmaShindoColor(intensity));
    }
    if (station.isMotionActive) {
      return const Color(0xFF00E5FF);
    }

    switch (_stationLevel(station)) {
      case 3:
        return const Color(0xFFFFD166);
      case 2:
        return const Color(0xFF5DADE2);
      default:
        return const Color(0xFF58D68D);
    }
  }

  int _stationLevel(FdsnStation station) {
    const globalNetworks = {'IU', 'II', 'IC', 'GE'};
    const nationalNetworks = {'CU', 'US', 'AK', 'CI', 'NC', 'NN', 'PN', 'PB'};
    if (globalNetworks.contains(station.network)) return 3;
    if (nationalNetworks.contains(station.network)) return 2;
    return 1;
  }
}

class _FdsnDot extends StatelessWidget {
  final Color color;
  final double opacity;
  final double borderOpacity;

  const _FdsnDot({
    required this.color,
    required this.opacity,
    required this.borderOpacity,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: opacity),
        border: Border.all(
          color: color.withValues(alpha: borderOpacity),
          width: 0.6,
        ),
      ),
    );
  }
}
