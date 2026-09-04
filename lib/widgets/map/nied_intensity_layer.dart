import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/sources/jp_shindo_scale.dart';
import '../../services/sources/nied_monitor.dart';
import '../../services/sources/shake_detection_service.dart';
import 'map_style_zoom.dart';
import 'station_dot_painter_layer.dart';

class NiedIntensityLayer extends StatefulWidget {
  final List<NiedStation>? stations;
  final bool hideGrid;
  final bool blinkOn;
  final bool displayShindo0;
  final Map<String, NiedDetectionGridCell>? detectionGridCells;
  final void Function(List<LatLng> centers)? onGridCellsChanged;

  const NiedIntensityLayer({
    super.key,
    this.stations,
    this.hideGrid = false,
    this.blinkOn = true,
    this.displayShindo0 = false,
    this.detectionGridCells,
    this.onGridCellsChanged,
  });

  @override
  State<NiedIntensityLayer> createState() => _NiedIntensityLayerState();
}

class _NiedIntensityLayerState extends State<NiedIntensityLayer>
    with GridCentersEmitMixin {
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

    // Avoid MapCamera InheritedWidget — continuous EEW follow would otherwise
    // rebuild hundreds of station dots on every camera tick.
    final zoom = mapStyleZoomOf(context);

    final overview = _overviewFactor(zoom);
    final dotSize = (0.9 + (zoom - 3) * 0.95).clamp(0.9, 7.5);
    final dotBorderWidth = (0.35 + overview * 0.55).clamp(0.35, 0.9);

    final detectionCells = widget.detectionGridCells;
    final hasDetectionCells =
        detectionCells != null && detectionCells.isNotEmpty;
    if (hasDetectionCells) {
      _replaceGridCellsFromDetection(detectionCells);
    } else {
      _gridCells.clear();
    }

    emitGridCentersIfChanged(
      _gridCells.values.map((c) => c.center).toList(growable: false),
      widget.onGridCellsChanged,
    );

    final dots = <StationDot>[];
    final iconMarkers = <Marker>[];

    for (final station in data) {
      final level = station.level;

      if (level < 0) {
        dots.add(
          StationDot(
            coordinate: station.coordinate,
            color: _idleColor,
            radius: dotSize / 2,
            fillOpacity: 0.08 + overview * 0.10,
            borderOpacity: 0.22 + overview * 0.38,
            borderWidth: dotBorderWidth,
          ),
        );
      } else if (level < (widget.displayShindo0 ? 6 : 8) || zoom < 4) {
        final dotColor =
            _niedDotColors[level.clamp(0, _niedDotColors.length - 1)];
        dots.add(
          StationDot(
            coordinate: station.coordinate,
            color: dotColor,
            radius: dotSize / 2,
            fillOpacity: 0.14 + overview * 0.22,
            borderOpacity: 0.45 + overview * 0.45,
            borderWidth: dotBorderWidth,
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
        StationDotPainterLayer(dots: dots, sizeWithCameraZoom: true),
        if (iconMarkers.isNotEmpty) MarkerLayer(markers: iconMarkers),
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
    return JpShindoScale.jmaIndexFromKanameishiLevel(level);
  }

  static double _overviewFactor(double zoom) {
    return ((zoom - 3.2) / 3.8).clamp(0.0, 1.0).toDouble();
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
    final isHigh = JpShindoScale.jmaIndexFromKanameishiLevel(level) >= 7;

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
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
              color: JpShindoScale.jmaIndexFromKanameishiLevel(level) >= 4
                  ? Colors.black
                  : Colors.white,
              fontSize: isHigh ? 8 : 7,
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
