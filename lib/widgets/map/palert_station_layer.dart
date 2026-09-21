import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/sources/palert_detection_grid.dart';
import '../../services/sources/palert_service.dart';
import 'ka_shindo_marker_style.dart';
import 'map_style_zoom.dart';
import 'station_dot_painter_layer.dart';

class PAlertStationLayer extends StatelessWidget {
  final List<PAlertStation> stations;
  final bool displayShindo0;
  final List<PAlertDetectionGridCell> detectionGridCells;
  final bool hideGrid;
  final bool blinkOn;

  const PAlertStationLayer({
    super.key,
    required this.stations,
    this.displayShindo0 = false,
    this.detectionGridCells = const [],
    this.hideGrid = false,
    this.blinkOn = true,
  });

  static const Color _idleColor = Color(0x804466AA);
  static const Duration _realtimeHold = Duration(seconds: 12);

  @override
  Widget build(BuildContext context) {
    if (stations.isEmpty) return const SizedBox.shrink();

    final zoom = mapStyleZoomOf(context);

    final overview = _overviewFactor(zoom);
    final idleDotSize = (0.9 + (zoom - 3) * 0.95).clamp(0.9, 7.5);
    final idleBorderWidth = (0.35 + overview * 0.55).clamp(0.35, 0.9);
    final nowUtc = DateTime.now().toUtc();

    final dots = <StationDot>[];
    final markers = <Marker>[];

    for (final station in stations) {
      final recent =
          station.receivedAt != null &&
          nowUtc.difference(station.receivedAt!.toUtc()) <= _realtimeHold;
      final level = station.gridLevel;
      final showMarker =
          recent &&
          level >= 0 &&
          (displayShindo0 || station.displayCwaIntensityIndex != 0) &&
          KaShindoMarkerStyle.shouldShowMarker(
            // Eligibility uses current PGA; labels/colors keep held CWA levels.
            level: station.detectionLevel,
            zoom: zoom,
            displayShindo0: displayShindo0,
          );
      if (showMarker) {
        markers.add(
          Marker(
            width: _markerSize(level),
            height: _markerSize(level),
            point: station.coordinate,
            child: _PAlertIntensityMarker(
              color: KaShindoMarkerStyle.colorForLevel(level),
              label: KaShindoMarkerStyle.labelForLevel(level),
              level: level,
            ),
          ),
        );
      } else if (level >= 0) {
        final dotColor = KaShindoMarkerStyle.colorForLevel(level);
        dots.add(
          StationDot(
            coordinate: station.coordinate,
            color: dotColor,
            radius: idleDotSize / 2,
            fillOpacity: 0.14 + overview * 0.22,
            borderOpacity: 0.45 + overview * 0.45,
            borderWidth: idleBorderWidth,
          ),
        );
      } else {
        dots.add(
          StationDot(
            coordinate: station.coordinate,
            color: _idleColor,
            radius: idleDotSize / 2,
            fillOpacity: 0.08 + overview * 0.10,
            borderOpacity: 0.22 + overview * 0.38,
            borderWidth: idleBorderWidth,
          ),
        );
      }
    }

    return Stack(
      children: [
        if (detectionGridCells.isNotEmpty && !hideGrid)
          PolygonLayer(polygons: _buildGridPolygons()),
        StationDotPainterLayer(dots: dots, sizeWithCameraZoom: true),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
      ],
    );
  }

  List<Polygon> _buildGridPolygons() {
    const halfStep = 0.99 / 2;
    return detectionGridCells
        .map((cell) {
          final center = cell.center;
          final color = cell.level <= 7
              ? const Color(0xFF008000)
              : cell.level <= 13
              ? const Color(0xFFFFFF00)
              : const Color(0xFFFF0000);
          return Polygon(
            points: [
              LatLng(center.latitude - halfStep, center.longitude - halfStep),
              LatLng(center.latitude + halfStep, center.longitude - halfStep),
              LatLng(center.latitude + halfStep, center.longitude + halfStep),
              LatLng(center.latitude - halfStep, center.longitude + halfStep),
            ],
            borderStrokeWidth: 2.0,
            borderColor: blinkOn ? color : color.withValues(alpha: 0),
            color: Colors.transparent,
          );
        })
        .toList(growable: false);
  }

  static double _markerSize(int level) => 14.0;

  static double _overviewFactor(double zoom) {
    return ((zoom - 3.2) / 3.8).clamp(0.0, 1.0).toDouble();
  }
}

class _PAlertIntensityMarker extends StatelessWidget {
  final Color color;
  final String label;
  final int level;

  const _PAlertIntensityMarker({
    required this.color,
    required this.label,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    final isHigh = level >= 17;

    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: isHigh ? Colors.white : Colors.white.withValues(alpha: 0.5),
          width: isHigh ? 2.0 : 1.0,
        ),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(
              color: KaShindoMarkerStyle.foregroundForLevel(level),
              fontSize: level >= 16 ? 8 : 7,
              fontWeight: FontWeight.bold,
              height: 1.0,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
