import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/sources/kma_monitor.dart';
import 'ka_kma_marker_style.dart';
import 'map_style_zoom.dart';
import 'station_dot_painter_layer.dart';

class KmaIntensityLayer extends StatefulWidget {
  final List<KmaStation>? stations;
  final bool hideGrid;
  final bool blinkOn;
  final bool displayShindo0;
  final void Function(List<LatLng> centers)? onGridCellsChanged;

  const KmaIntensityLayer({
    super.key,
    this.stations,
    this.hideGrid = false,
    this.blinkOn = true,
    this.displayShindo0 = false,
    this.onGridCellsChanged,
  });

  @override
  State<KmaIntensityLayer> createState() => _KmaIntensityLayerState();
}

class _KmaIntensityLayerState extends State<KmaIntensityLayer>
    with GridCentersEmitMixin {
  bool _hadActiveStations = false;
  List<double> _gridDecimal = const [0.0, 0.0];
  final Map<String, _KmaGridCell> _heldGridCells = {};

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
    final dotSize = KaKmaMarkerStyle.dotSizeForZoom(zoom);
    final dotBorderWidth = KaKmaMarkerStyle.borderWidthForZoom(zoom);

    final activeStations = data.where((s) => s.isActive).toList();
    _syncHeldGridCells(activeStations);
    final showGrids = _heldGridCells.isNotEmpty && !widget.hideGrid;

    emitGridCentersIfChanged(
      _heldGridCells.values.map((c) => c.center).toList(growable: false),
      widget.onGridCellsChanged,
    );

    final dots = <StationDot>[];
    final iconMarkers = <Marker>[];

    for (var station in data) {
      final level = station.holdLevel;
      final active = level >= 0;
      final showLabel = KaKmaMarkerStyle.shouldShowMarker(
        holdLevel: level,
        zoom: zoom,
        displayShindo0: widget.displayShindo0,
      );

      if (!active) {
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
      } else if (showLabel) {
        iconMarkers.add(
          Marker(
            width: KaKmaMarkerStyle.labeledMarkerSize,
            height: KaKmaMarkerStyle.labeledMarkerSize,
            point: station.coordinate,
            child: _KmaLabeledMarker(
              color: KaKmaMarkerStyle.markerColorForLevel(level),
              level: level,
            ),
          ),
        );
      } else {
        final color = KaKmaMarkerStyle.stationColorForLevel(level);
        dots.add(
          StationDot(
            coordinate: station.coordinate,
            color: color,
            radius: dotSize / 2,
            fillOpacity: 0.14 + overview * 0.22,
            borderOpacity: 0.45 + overview * 0.45,
            borderWidth: dotBorderWidth,
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

  void _syncHeldGridCells(List<KmaStation> activeStations) {
    if (activeStations.isEmpty) {
      _heldGridCells.clear();
      if (_hadActiveStations) {
        _hadActiveStations = false;
        _gridDecimal = const [0.0, 0.0];
      }
      return;
    }

    if (!_hadActiveStations) {
      final strongest = activeStations.reduce(
        (a, b) => a.activityLevel >= b.activityLevel ? a : b,
      );
      _gridDecimal = [
        _gridDecimalPart(strongest.coordinate.latitude),
        _gridDecimalPart(strongest.coordinate.longitude),
      ];
      _hadActiveStations = true;
    }

    for (final station in activeStations) {
      final latRounded = _roundCoord(
        station.coordinate.latitude,
        _gridDecimal[0],
      );
      final lngRounded = _roundCoord(
        station.coordinate.longitude,
        _gridDecimal[1],
      );
      final key = '$latRounded,$lngRounded';
      final level = station.activityLevel;
      if (level < 0) continue;
      final existing = _heldGridCells[key];
      if (existing == null || level > existing.level) {
        _heldGridCells[key] = _KmaGridCell(
          LatLng(latRounded, lngRounded),
          level,
        );
      }
    }
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
    if (level <= 3) return colorGreen;
    if (level <= 7) return colorYellow;
    return colorRed;
  }

  double _roundCoord(double val, double decimal) {
    return (val - decimal).roundToDouble() + decimal;
  }

  static double _gridDecimalPart(double val) {
    final fraction = (val + 180) % 1;
    return (fraction * 10).roundToDouble() / 10;
  }

  static double _overviewFactor(double zoom) {
    return ((zoom - 3.2) / 3.8).clamp(0.0, 1.0).toDouble();
  }
}

class _KmaLabeledMarker extends StatelessWidget {
  final Color color;
  final int level;

  const _KmaLabeledMarker({required this.color, required this.level});

  @override
  Widget build(BuildContext context) {
    final isHigh = level >= 7;
    final displayValue = KaKmaMarkerStyle.mmiForLevel(level).toString();

    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: isHigh ? 2.0 : 1.0),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          displayValue,
          style: TextStyle(
            color: KaKmaMarkerStyle.foregroundForLevel(level),
            fontSize: KaKmaMarkerStyle.labelFontSizeForLevel(level),
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _KmaGridCell {
  final LatLng center;
  final int level;

  _KmaGridCell(this.center, this.level);
}
