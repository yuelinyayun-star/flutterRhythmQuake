import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../services/sources/fdsn_station_service.dart';
import 'station_dot_painter_layer.dart';

class FdsnStationLayer extends StatelessWidget {
  final List<FdsnStation> stations;

  const FdsnStationLayer({super.key, required this.stations});

  static const int _maxVisibleDots = 1200;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final visibleStations = _visibleActiveStations(camera);
    final dots = [
      for (final station in visibleStations)
        StationDot(
          coordinate: station.coordinate,
          color: _colorForStation(station),
          radius: _radiusForZoom(camera.zoom),
          fillOpacity: 0.48,
          borderOpacity: 0.56,
          borderWidth: 0.8,
        ),
    ];
    if (dots.isEmpty) return const SizedBox.shrink();
    return StationDotPainterLayer(dots: dots);
  }

  List<FdsnStation> _visibleActiveStations(MapCamera camera) {
    final visible = camera.pixelBounds.inflate(36);
    final selected = <FdsnStation>[];

    for (final station in stations) {
      if (!station.hasActiveMotionMeasurement) continue;
      final projected = camera.projectAtZoom(station.coordinate);
      if (!_isVisible(projected, visible, camera.getWorldWidthAtZoom())) {
        continue;
      }
      selected.add(station);
    }

    if (selected.length <= _maxVisibleDots) return selected;

    selected.sort((a, b) => _motionRank(b).compareTo(_motionRank(a)));
    return selected.take(_maxVisibleDots).toList(growable: false);
  }

  double _motionRank(FdsnStation station) {
    final intensity = station.intensity;
    if (intensity != null) return intensity * 1000;
    final pga = station.pga ?? 0;
    final pgv = station.pgv ?? 0;
    return pga * 10 + pgv * 100;
  }

  double _radiusForZoom(double zoom) {
    if (zoom < 4.5) return 3.2;
    if (zoom < 6.0) return 4.0;
    return 5.0;
  }

  bool _isVisible(Offset projected, Rect visible, double worldWidth) {
    if (visible.contains(projected)) return true;
    if (worldWidth == 0) return false;

    for (
      double shift = -worldWidth;
      shift >= -worldWidth * 2;
      shift -= worldWidth
    ) {
      if (visible.contains(Offset(projected.dx + shift, projected.dy))) {
        return true;
      }
    }
    for (
      double shift = worldWidth;
      shift <= worldWidth * 2;
      shift += worldWidth
    ) {
      if (visible.contains(Offset(projected.dx + shift, projected.dy))) {
        return true;
      }
    }
    return false;
  }

  Color _colorForStation(FdsnStation station) {
    final mmi = station.intensity;
    if (mmi != null) {
      if (mmi >= 10.0) return const Color(0xFFC800A0);
      if (mmi >= 9.0) return const Color(0xFFC80000);
      if (mmi >= 8.0) return const Color(0xFFFF0000);
      if (mmi >= 7.0) return const Color(0xFFFF9600);
      if (mmi >= 6.0) return const Color(0xFFFFD200);
      if (mmi >= 5.0) return const Color(0xFFFFFF00);
      if (mmi >= 4.0) return const Color(0xFFB9F26C);
      if (mmi >= 3.0) return const Color(0xFF7BE1F1);
      if (mmi >= 2.0) return const Color(0xFFACD8E9);
      return const Color(0xFFE8F6FF);
    }
    if (_hasElevatedMotion(station)) {
      return const Color(0xFF00E676);
    }

    return const Color(0xFF2F80ED);
  }

  bool _hasElevatedMotion(FdsnStation station) {
    final pga = station.pga;
    if (pga != null && pga >= 0.8) return true;
    final pgv = station.pgv;
    if (pgv != null && pgv >= 0.08) return true;
    return false;
  }
}
