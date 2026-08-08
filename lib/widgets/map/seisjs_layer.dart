import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../core/intensity_calculator.dart';
import '../../services/sources/seisjs_service.dart';
import 'station_dot_painter_layer.dart';

@visibleForTesting
int seisJsMapIntensityLevel(double intensity) {
  if (!intensity.isFinite) return 0;
  return intensity.round().clamp(0, 12);
}

@visibleForTesting
Color seisJsMapIntensityColor(double intensity) {
  return Color(
    IntensityCalculator.getCsisColor(seisJsMapIntensityLevel(intensity)),
  );
}

class SeisJsLayer extends StatelessWidget {
  final List<SeisJsStation>? stations;

  const SeisJsLayer({super.key, this.stations});

  static const Color _idleColor = Color(0x804466AA);

  @override
  Widget build(BuildContext context) {
    final data = stations;
    if (data == null || data.isEmpty) return const SizedBox.shrink();

    final dots = <StationDot>[];
    final iconMarkers = <Marker>[];

    for (var station in data) {
      final intensity = seisJsMapIntensityLevel(station.intensity);
      final active = station.intensity.isFinite && station.intensity >= 0;

      if (active) {
        iconMarkers.add(
          Marker(
            width: _getSize(intensity) * 0.75,
            height: _getSize(intensity) * 0.75,
            point: station.coordinate,
            child: _IntensityMarker(
              color: _getColor(intensity),
              label: intensity.toString(),
              intensity: intensity,
            ),
          ),
        );
      } else {
        dots.add(
          StationDot(
            coordinate: station.coordinate,
            color: _idleColor,
            radius: 1.25,
            fillOpacity: 1.0,
            borderOpacity: 0.0,
            borderWidth: 0.0,
          ),
        );
      }
    }

    return Stack(
      children: [
        StationDotPainterLayer(dots: dots),
        if (iconMarkers.isNotEmpty) MarkerLayer(markers: iconMarkers),
      ],
    );
  }

  Color _getColor(int intensity) {
    return seisJsMapIntensityColor(intensity.toDouble());
  }

  double _getSize(int intensity) {
    return 14.0;
  }
}

class _IntensityMarker extends StatelessWidget {
  final Color color;
  final String label;
  final int intensity;

  const _IntensityMarker({
    required this.color,
    required this.label,
    required this.intensity,
  });

  @override
  Widget build(BuildContext context) {
    final isHigh = intensity >= 5;

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.75),
        shape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: isHigh ? Colors.white : Colors.white.withValues(alpha: 0.4),
          width: isHigh ? 1.5 : 0.8,
        ),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: color.computeLuminance() > 0.42
                ? Colors.black
                : Colors.white,
            fontSize: intensity >= 5 ? 8 : 6.5,
            fontWeight: FontWeight.bold,
            height: 1.0,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
