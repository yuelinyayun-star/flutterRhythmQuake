import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/sources/jp_shindo_scale.dart';
import '../../services/sources/nied_monitor.dart';
import '../../services/sources/shake_detection_service.dart';

class NiedIntensityLayer extends StatefulWidget {
  final List<NiedStation>? stations;
  final bool hideGrid;
  final bool blinkOn;
  final Map<String, NiedDetectionGridCell>? detectionGridCells;
  final void Function(List<LatLng> centers)? onGridCellsChanged;

  const NiedIntensityLayer({
    super.key,
    this.stations,
    this.hideGrid = false,
    this.blinkOn = true,
    this.detectionGridCells,
    this.onGridCellsChanged,
  });

  @override
  State<NiedIntensityLayer> createState() => _NiedIntensityLayerState();
}

class _NiedIntensityLayerState extends State<NiedIntensityLayer> {
  final Map<String, _HeldGridCell> _gridCells = {};

  static const Color _idleColor = Color(0x4D0003CF);

  static const List<Color> _niedDotColors = [
    Color(0x4D0003CF),
    Color(0x4D0014DA),
    Color(0x4D0037F0),
    Color(0x4D006CDC),
    Color(0x4D00B3A2),
    Color(0x4D12DC72),
  ];

  static const List<Color> _jmaColors = [
    Color(0xFF888888),
    Color(0xFF8282FF),
    Color(0xFF46B4FF),
    Color(0xFF00DC8C),
    Color(0xFFFFFF00),
    Color(0xFFFFB400),
    Color(0xFFFF6400),
    Color(0xFFFF0000),
    Color(0xFFB40000),
    Color(0xFF640096),
  ];

  static const List<String> _jmaLabels = [
    '0',
    '1',
    '2',
    '3',
    '4',
    '5-',
    '5+',
    '6-',
    '6+',
    '7',
  ];

  @override
  Widget build(BuildContext context) {
    final data = widget.stations;
    if (data == null || data.isEmpty) return const SizedBox.shrink();

    double zoom = 4.0;
    final camera = MapCamera.maybeOf(context);
    if (camera != null) zoom = camera.zoom;

    final overview = _overviewFactor(zoom);
    final dotSize = (0.9 + (zoom - 3) * 0.95).clamp(0.9, 7.5);
    final dotOpacity = (0.08 + overview * 0.62).clamp(0.08, 0.78);
    final dotBorderWidth = (0.35 + overview * 0.55).clamp(0.35, 0.9);

    final detectionCells = widget.detectionGridCells;
    final hasDetectionCells =
        detectionCells != null && detectionCells.isNotEmpty;
    if (hasDetectionCells) {
      _replaceGridCellsFromDetection(detectionCells);
    } else {
      _gridCells.clear();
    }

    final callback = widget.onGridCellsChanged;
    if (callback != null) {
      callback(_gridCells.values.map((c) => c.center).toList(growable: false));
    }

    final dotMarkers = <Marker>[];
    final iconMarkers = <Marker>[];

    final sorted = List<NiedStation>.from(data)
      ..sort((a, b) => a.level.compareTo(b.level));

    for (final station in sorted) {
      final level = station.level;

      if (level < 0) {
        dotMarkers.add(
          Marker(
            width: dotSize,
            height: dotSize,
            point: station.coordinate,
            child: _SoftStationDot(
              color: _idleColor,
              fillOpacity: dotOpacity * 0.12,
              borderOpacity: dotOpacity * 0.32,
              borderWidth: dotBorderWidth,
            ),
          ),
        );
      } else if (level <= 5 || zoom < 4) {
        final dotColor =
            _niedDotColors[level.clamp(0, _niedDotColors.length - 1)];
        dotMarkers.add(
          Marker(
            width: dotSize,
            height: dotSize,
            point: station.coordinate,
            child: _SoftStationDot(
              color: dotColor,
              fillOpacity: dotOpacity * 0.22,
              borderOpacity: dotOpacity * 0.68,
              borderWidth: dotBorderWidth,
            ),
          ),
        );
      } else {
        final idx = _levelToJmaIndex(level);
        iconMarkers.add(
          Marker(
            width: 14.0,
            height: 14.0,
            point: station.coordinate,
            child: _IntensityMarker(
              color: _jmaColors[idx],
              label: _jmaLabels[idx],
              level: level,
            ),
          ),
        );
      }
    }

    return Stack(
      children: [
        if (_gridCells.isNotEmpty && !widget.hideGrid)
          PolygonLayer(polygons: _buildGridPolygons()),
        MarkerLayer(markers: [...dotMarkers, ...iconMarkers]),
      ],
    );
  }

  void _replaceGridCellsFromDetection(
    Map<String, NiedDetectionGridCell> detectionCells,
  ) {
    _gridCells
      ..clear()
      ..addEntries(
        detectionCells.entries.map(
          (entry) => MapEntry(
            entry.key,
            _HeldGridCell(
              center: entry.value.center,
              shindo: entry.value.shindo,
              level: entry.value.level,
            ),
          ),
        ),
      );
  }

  List<Polygon> _buildGridPolygons() {
    final polygons = <Polygon>[];
    const step = 0.99;

    for (final cell in _gridCells.values) {
      final color = _gridBorderColorFromKanameishiLevel(cell.level);
      final center = cell.center;
      polygons.add(
        Polygon(
          points: [
            LatLng(center.latitude - step / 2, center.longitude - step / 2),
            LatLng(center.latitude + step / 2, center.longitude - step / 2),
            LatLng(center.latitude + step / 2, center.longitude + step / 2),
            LatLng(center.latitude - step / 2, center.longitude + step / 2),
          ],
          borderStrokeWidth: 2.0,
          borderColor: widget.blinkOn ? color : color.withValues(alpha: 0),
          color: Colors.transparent,
        ),
      );
    }
    return polygons;
  }

  Color _gridBorderColorFromKanameishiLevel(int level) {
    if (level <= 7) return const Color(0xFF008000);
    if (level <= 13) return const Color(0xFFFFFF00);
    return const Color(0xFFFF0000);
  }

  static int _levelToJmaIndex(int level) {
    return JpShindoScale.jmaIndexFromLevel(level);
  }

  static double _overviewFactor(double zoom) {
    return ((zoom - 3.2) / 3.8).clamp(0.0, 1.0).toDouble();
  }
}

class _SoftStationDot extends StatelessWidget {
  final Color color;
  final double fillOpacity;
  final double borderOpacity;
  final double borderWidth;

  const _SoftStationDot({
    required this.color,
    required this.fillOpacity,
    required this.borderOpacity,
    required this.borderWidth,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: fillOpacity.clamp(0.0, 1.0)),
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: borderOpacity.clamp(0.0, 1.0)),
          width: borderWidth,
        ),
      ),
    );
  }
}

class _IntensityMarker extends StatelessWidget {
  final Color color;
  final String label;
  final int level;

  const _IntensityMarker({
    required this.color,
    required this.label,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    final isHigh = JpShindoScale.jmaIndexFromLevel(level) >= 7;

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        shape: BoxShape.circle,
        border: Border.all(
          color: isHigh ? Colors.white : Colors.white.withValues(alpha: 0.5),
          width: isHigh ? 2.0 : 1.0,
        ),
        boxShadow: isHigh
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ]
            : [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 3,
                  spreadRadius: 1,
                ),
              ],
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: JpShindoScale.jmaIndexFromLevel(level) >= 4
                ? Colors.black
                : Colors.white,
            fontSize: isHigh ? 8 : 7,
            fontWeight: FontWeight.bold,
            height: 1.0,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _HeldGridCell {
  final LatLng center;
  final double shindo;
  final int level;

  const _HeldGridCell({
    required this.center,
    required this.shindo,
    required this.level,
  });
}
