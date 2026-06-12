import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/sources/kma_monitor.dart';

class KmaIntensityLayer extends StatefulWidget {
  final List<KmaStation>? stations;
  final bool hideGrid;
  final bool blinkOn;
  final void Function(List<LatLng> centers)? onGridCellsChanged;

  const KmaIntensityLayer({
    super.key,
    this.stations,
    this.hideGrid = false,
    this.blinkOn = true,
    this.onGridCellsChanged,
  });

  @override
  State<KmaIntensityLayer> createState() => _KmaIntensityLayerState();
}

class _KmaIntensityLayerState extends State<KmaIntensityLayer> {
  bool _hadActiveStations = false;
  List<double> _gridDecimal = const [0.0, 0.0];
  final Map<String, _KmaGridCell> _heldGridCells = {};

  static const List<Color> _kmaColors = [
    Color(0xFF0003CF),
    Color(0xFF004FF4),
    Color(0xFF05D384),
    Color(0xFF50FB30),
    Color(0xFFCCFF09),
    Color(0xFFFDFC00),
    Color(0xFFFFCA00),
    Color(0xFFFF7900),
    Color(0xFFFF4700),
    Color(0xFFF91900),
    Color(0xFFE10000),
    Color(0xFFAF0000),
    Color(0xFFAD0000),
  ];

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

    double zoom = 4.0;
    final camera = MapCamera.maybeOf(context);
    if (camera != null) zoom = camera.zoom;

    final overview = _overviewFactor(zoom);
    final idleDotSize = (1.0 + overview * 4.0).clamp(1.0, 5.0);
    final smallMarkerSize = (4.5 + overview * 9.5).clamp(4.5, 14.0);
    final smallBorderWidth = (0.35 + overview * 0.65).clamp(0.35, 1.0);

    final activeStations = data.where((s) => s.isActive).toList();
    _syncHeldGridCells(activeStations);
    final showGrids = _heldGridCells.isNotEmpty && !widget.hideGrid;

    // kanameishi: 通知网格中心点变化 (用于相机视角和测站焦点)
    final callback = widget.onGridCellsChanged;
    if (callback != null) {
      final centers = _heldGridCells.values.map((c) => c.center).toList();
      callback(centers);
    }

    final dotMarkers = <Marker>[];
    final iconMarkers = <Marker>[];

    final sorted = List<KmaStation>.from(data)
      ..sort((a, b) => a.intensity.compareTo(b.intensity));

    for (var station in sorted) {
      final active = station.intensity >= 0;
      final level = (station.intensity + 2).clamp(0, 12);
      final showLabel = active && level >= 4;

      if (!active) {
        dotMarkers.add(
          Marker(
            width: idleDotSize,
            height: idleDotSize,
            point: station.coordinate,
            child: _SoftStationDot(
              color: _idleColor,
              fillOpacity: 0.08 + overview * 0.10,
              borderOpacity: 0.22 + overview * 0.38,
              borderWidth: smallBorderWidth,
            ),
          ),
        );
      } else if (showLabel) {
        iconMarkers.add(
          Marker(
            width: 22,
            height: 22,
            point: station.coordinate,
            child: _KmaLabeledMarker(
              color: _kmaColors[level],
              level: level,
              intensity: station.intensity,
            ),
          ),
        );
      } else {
        iconMarkers.add(
          Marker(
            width: smallMarkerSize,
            height: smallMarkerSize,
            point: station.coordinate,
            child: _KmaMarker(
              color: _kmaColors[level],
              level: level,
              fillOpacity: 0.14 + overview * 0.22,
              borderOpacity: 0.45 + overview * 0.45,
              borderWidth: smallBorderWidth,
            ),
          ),
        );
      }
    }

    return Stack(
      children: [
        if (showGrids)
          PolygonLayer(polygons: _buildGridPolygons(widget.blinkOn)),
        MarkerLayer(markers: [...dotMarkers, ...iconMarkers]),
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
        (a, b) => a.intensity >= b.intensity ? a : b,
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
      final level = station.intensity + 2;
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
          color: color.withValues(alpha: 0.25 * blinkAlpha),
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

  static double _overviewFactor(double zoom) {
    return ((zoom - 3.2) / 3.8).clamp(0.0, 1.0).toDouble();
  }
}

class _KmaMarker extends StatelessWidget {
  final Color color;
  final int level;
  final double fillOpacity;
  final double borderOpacity;
  final double borderWidth;

  const _KmaMarker({
    required this.color,
    required this.level,
    required this.fillOpacity,
    required this.borderOpacity,
    required this.borderWidth,
  });

  @override
  Widget build(BuildContext context) {
    final isHigh = level >= 7;

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: fillOpacity.clamp(0.0, 1.0)),
        shape: BoxShape.circle,
        border: Border.all(
          color: isHigh
              ? Colors.white
              : color.withValues(alpha: borderOpacity.clamp(0.0, 1.0)),
          width: isHigh ? 1.5 : borderWidth,
        ),
        boxShadow: isHigh
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : [
                BoxShadow(
                  color: color.withValues(alpha: 0.16),
                  blurRadius: 2,
                  spreadRadius: 0.4,
                ),
              ],
      ),
    );
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

class _KmaLabeledMarker extends StatelessWidget {
  final Color color;
  final int level;
  final int intensity;

  const _KmaLabeledMarker({
    required this.color,
    required this.level,
    required this.intensity,
  });

  @override
  Widget build(BuildContext context) {
    final isHigh = level >= 7;
    final displayValue = intensity.toString();

    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: isHigh ? 2.0 : 1.2),
        boxShadow: isHigh
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: 8,
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
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          displayValue,
          style: TextStyle(
            color: level >= 5 ? Colors.black : Colors.white,
            fontSize: 12,
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
