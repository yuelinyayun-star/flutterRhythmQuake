import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/sources/cwa_station_service.dart';
import 'ka_shindo_marker_style.dart';
import 'map_style_zoom.dart';
import 'station_dot_painter_layer.dart';

class CwaStationLayer extends StatefulWidget {
  final List<CwaStation>? stations;
  final bool hideGrid;
  final bool blinkOn;
  final bool displayShindo0;
  final void Function(List<LatLng> centers)? onGridCellsChanged;

  const CwaStationLayer({
    super.key,
    this.stations,
    this.hideGrid = false,
    this.blinkOn = true,
    this.displayShindo0 = false,
    this.onGridCellsChanged,
  });

  @override
  State<CwaStationLayer> createState() => _CwaStationLayerState();
}

class _CwaStationLayerState extends State<CwaStationLayer>
    with GridCentersEmitMixin {
  bool _hadAlertStations = false;
  List<double> _gridDecimal = const [0.0, 0.0];
  final Map<String, _CwaGridCell> _heldGridCells = {};

  static const Color _idleColor = Color(0x804466AA);

  @override
  void dispose() {
    _heldGridCells.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.stations;
    if (data == null || data.isEmpty) return const SizedBox.shrink();

    final zoom = mapStyleZoomOf(context);

    final overview = _overviewFactor(zoom);
    final idleDotSize = (0.9 + (zoom - 3) * 0.95).clamp(0.9, 7.5);
    final idleBorderWidth = (0.35 + overview * 0.55).clamp(0.35, 0.9);

    final alertStations = data.where((s) => s.hasAlert).toList();
    _syncHeldGridCells(alertStations);
    final showGrids = _heldGridCells.isNotEmpty && !widget.hideGrid;

    emitGridCentersIfChanged(
      _heldGridCells.values.map((c) => c.center).toList(growable: false),
      widget.onGridCellsChanged,
    );

    final dots = <StationDot>[];
    final iconMarkers = <Marker>[];

    for (var station in data) {
      final intensity = station.currentIntensity;
      final level = CwaStationService.gridLevelFromInstShindo(intensity);
      final showMarker = KaShindoMarkerStyle.shouldShowMarker(
        level: level,
        zoom: zoom,
        displayShindo0: widget.displayShindo0,
      );

      if (showMarker) {
        iconMarkers.add(
          Marker(
            width: _getSize(level),
            height: _getSize(level),
            point: station.coordinate,
            child: _CwaIntensityMarker(
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
        if (showGrids)
          PolygonLayer(polygons: _buildGridPolygons(widget.blinkOn)),
        StationDotPainterLayer(dots: dots, sizeWithCameraZoom: true),
        if (iconMarkers.isNotEmpty) MarkerLayer(markers: iconMarkers),
      ],
    );
  }

  void _syncHeldGridCells(List<CwaStation> alertStations) {
    if (alertStations.isEmpty) {
      _heldGridCells.clear();
      if (_hadAlertStations) {
        _hadAlertStations = false;
        _gridDecimal = const [0.0, 0.0];
      }
      return;
    }

    if (!_hadAlertStations) {
      final strongest = alertStations.reduce(
        (a, b) => a.alertIntensity >= b.alertIntensity ? a : b,
      );
      _gridDecimal = [
        _gridDecimalPart(strongest.coordinate.latitude),
        _gridDecimalPart(strongest.coordinate.longitude),
      ];
      _hadAlertStations = true;
    }

    final currentGridCells = <String, _CwaGridCell>{};
    for (final station in alertStations) {
      final latRounded = _roundCoord(
        station.coordinate.latitude,
        _gridDecimal[0],
      );
      final lngRounded = _roundCoord(
        station.coordinate.longitude,
        _gridDecimal[1],
      );
      final key = '$latRounded,$lngRounded';
      final level = CwaStationService.gridLevelFromInstShindo(
        station.alertIntensity,
      );
      final existing = currentGridCells[key];
      if (existing == null || level > existing.level) {
        currentGridCells[key] = _CwaGridCell(
          LatLng(latRounded, lngRounded),
          level,
        );
      }
    }

    _heldGridCells
      ..clear()
      ..addAll(currentGridCells);
  }

  List<Polygon> _buildGridPolygons(bool blinkOn) {
    final grids = _heldGridCells.values.toList(growable: false);
    final polygons = <Polygon>[];
    if (grids.isEmpty) return polygons;
    const step = 0.99;
    final blinkAlpha = blinkOn ? 1.0 : 0.0;
    for (final cell in grids) {
      final center = cell.center;
      final color = _gridColor(cell.level);
      polygons.add(
        Polygon(
          points: [
            LatLng(center.latitude - step / 2, center.longitude - step / 2),
            LatLng(center.latitude + step / 2, center.longitude - step / 2),
            LatLng(center.latitude + step / 2, center.longitude + step / 2),
            LatLng(center.latitude - step / 2, center.longitude + step / 2),
          ],
          borderStrokeWidth: 2.0,
          borderColor: color.withValues(alpha: 0.8 * blinkAlpha),
          color: Colors.transparent,
        ),
      );
    }
    return polygons;
  }

  Color _gridColor(int level) {
    const colorGreen = Color(0xFF3DAA7E);
    const colorYellow = Color(0xFFEBC033);
    const colorRed = Color(0xFFE74C3C);
    if (level <= 7) return colorGreen;
    if (level <= 13) return colorYellow;
    return colorRed;
  }

  double _roundCoord(double val, double decimal) {
    return (val - decimal).roundToDouble() + decimal;
  }

  static double _gridDecimalPart(double val) {
    final fraction = (val + 180) % 1;
    return (fraction * 10).roundToDouble() / 10;
  }

  double _getSize(int level) {
    return 14.0;
  }

  static double _overviewFactor(double zoom) {
    return ((zoom - 3.2) / 3.8).clamp(0.0, 1.0).toDouble();
  }
}

class _CwaIntensityMarker extends StatelessWidget {
  final Color color;
  final String label;
  final int level;

  const _CwaIntensityMarker({
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

class _CwaGridCell {
  final LatLng center;
  final int level;

  _CwaGridCell(this.center, this.level);
}
