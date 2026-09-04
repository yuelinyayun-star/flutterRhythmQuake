import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../core/intensity_calculator.dart';
import '../../services/sources/seisjs_service.dart';
import 'map_style_zoom.dart';
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

@visibleForTesting
double seisJsMarkerDotSizeForZoom(double zoom) {
  // SeisJS is sparse community sensors, not a dense NIED-style grid.
  // Keep a readable floor and only grow a little when zoomed in.
  return (16.0 + (zoom - 4) * 1.4).clamp(16.0, 24.0);
}

@visibleForTesting
Size seisJsMarkerSizeForLabel(String label, double zoom) {
  final dotSize = seisJsMarkerDotSizeForZoom(zoom);
  // Keep one stable square for every intensity. FittedBox handles 10-12
  // inside the same marker instead of changing the marker's map footprint.
  return Size.square(dotSize);
}

@visibleForTesting
double seisJsIdleDotRadiusForZoom(double zoom) {
  return (5.0 + (zoom - 3) * 0.8).clamp(5.0, 9.0);
}

@visibleForTesting
double seisJsOverviewFactorForZoom(double zoom) {
  return ((zoom - 3.2) / 3.8).clamp(0.0, 1.0).toDouble();
}

class SeisJsLayer extends StatelessWidget {
  final List<SeisJsStation>? stations;

  const SeisJsLayer({super.key, this.stations});

  static const Color _idleColor = Color(0x804466AA);

  @override
  Widget build(BuildContext context) {
    final data = stations;
    if (data == null || data.isEmpty) return const SizedBox.shrink();

    final zoom = MapCamera.maybeOf(context)?.zoom ?? mapStyleZoomOf(context);
    final overview = seisJsOverviewFactorForZoom(zoom);
    final idleRadius = seisJsIdleDotRadiusForZoom(zoom);
    final idleBorderWidth = (1.1 + overview * 0.5).clamp(1.1, 1.6);

    final dots = <StationDot>[];
    final iconMarkers = <Marker>[];

    for (var station in data) {
      final intensity = seisJsMapIntensityLevel(station.intensity);
      final active = station.intensity.isFinite && station.intensity >= 0;

      if (active) {
        final label = intensity.toString();
        final markerSize = seisJsMarkerSizeForLabel(label, zoom);
        iconMarkers.add(
          Marker(
            width: markerSize.width,
            height: markerSize.height,
            point: station.coordinate,
            child: _IntensityMarker(
              color: _getColor(intensity),
              label: label,
              intensity: intensity,
              markerSize: markerSize,
            ),
          ),
        );
      } else {
        dots.add(
          StationDot(
            coordinate: station.coordinate,
            color: _idleColor,
            radius: idleRadius,
            fillOpacity: 0.32 + overview * 0.22,
            borderOpacity: 0.62 + overview * 0.28,
            borderWidth: idleBorderWidth,
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
}

class _IntensityMarker extends StatelessWidget {
  final Color color;
  final String label;
  final int intensity;
  final Size markerSize;

  const _IntensityMarker({
    required this.color,
    required this.label,
    required this.intensity,
    required this.markerSize,
  });

  @override
  Widget build(BuildContext context) {
    // Scale typography and chrome from the original 14px-tall marker design.
    final scale = markerSize.height / 14.0;
    final isHigh = intensity >= 5;

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.75),
        shape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(3 * scale),
        border: Border.all(
          color: isHigh ? Colors.white : Colors.white.withValues(alpha: 0.4),
          width: (isHigh ? 1.5 : 0.8) * scale,
        ),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: (label.length >= 2 ? 2 : 1) * scale,
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color.computeLuminance() > 0.42
                    ? Colors.black
                    : Colors.white,
                fontSize: (intensity >= 5 ? 8 : 6.5) * scale,
                fontWeight: FontWeight.bold,
                height: 1.0,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
