import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/sources/cwa_station_service.dart';

class CwaStationLayer extends StatefulWidget {
  final List<CwaStation>? stations;
  final bool hideGrid;
  final bool blinkOn;
  final void Function(List<LatLng> centers)? onGridCellsChanged;

  const CwaStationLayer({
    super.key,
    this.stations,
    this.hideGrid = false,
    this.blinkOn = true,
    this.onGridCellsChanged,
  });

  @override
  State<CwaStationLayer> createState() => _CwaStationLayerState();
}

class _CwaStationLayerState extends State<CwaStationLayer> {
  bool _hadAlertStations = false;
  List<double> _gridDecimal = const [0.0, 0.0];
  final Map<String, _CwaGridCell> _heldGridCells = {};

  static const List<Color> _cwaColors = [
    Color(0xFF0005D0),
    Color(0xFF004BF8),
    Color(0xFF009EF8),
    Color(0xFF79E5FD),
    Color(0xFF49E9AD),
    Color(0xFF44FA34),
    Color(0xFFBEFF0C),
    Color(0xFFFFF000),
    Color(0xFFFF9300),
    Color(0xFFFC5235),
    Color(0xFFB720E9),
  ];

  static const List<String> _cwaLabels = [
    '0',
    '0',
    '0',
    '0',
    '1',
    '2',
    '3',
    '4',
    '5弱',
    '5強',
    '7',
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
    final idleBorderWidth = (0.35 + overview * 0.55).clamp(0.35, 0.9);

    final alertStations = data
        .where((s) => s.hasAlert && s.alertIntensity >= 0)
        .toList();
    _syncHeldGridCells(alertStations);
    final showGrids = _heldGridCells.isNotEmpty && !widget.hideGrid;

    final callback = widget.onGridCellsChanged;
    if (callback != null) {
      final centers = _heldGridCells.values.map((c) => c.center).toList();
      callback(centers);
    }

    final dotMarkers = <Marker>[];
    final iconMarkers = <Marker>[];

    final sorted = List<CwaStation>.from(data)
      ..sort((a, b) => a.alertIntensity.compareTo(b.alertIntensity));

    for (var station in sorted) {
      final I = station.alertIntensity;
      final active = station.work && I >= 0;

      if (active) {
        iconMarkers.add(
          Marker(
            width: _getSize(I),
            height: _getSize(I),
            point: station.coordinate,
            child: _CwaIntensityMarker(
              color: _getColor(I),
              label: _getLabel(I),
              intensity: I,
            ),
          ),
        );
      } else {
        dotMarkers.add(
          Marker(
            width: idleDotSize,
            height: idleDotSize,
            point: station.coordinate,
            child: _SoftStationDot(
              color: _idleColor,
              fillOpacity: 0.08 + overview * 0.10,
              borderOpacity: 0.22 + overview * 0.38,
              borderWidth: idleBorderWidth,
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
      final level = (station.alertIntensity + 3) * 2;
      final existing = _heldGridCells[key];
      if (existing == null || level > existing.level) {
        _heldGridCells[key] = _CwaGridCell(
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

  Color _getColor(int I) {
    final idx = (I + 3).clamp(0, _cwaColors.length - 1);
    return _cwaColors[idx];
  }

  String _getLabel(int I) {
    final idx = (I + 3).clamp(0, _cwaLabels.length - 1);
    return _cwaLabels[idx];
  }

  double _getSize(int I) {
    return 14.0;
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

class _CwaIntensityMarker extends StatelessWidget {
  final Color color;
  final String label;
  final int intensity;

  const _CwaIntensityMarker({
    required this.color,
    required this.label,
    required this.intensity,
  });

  @override
  Widget build(BuildContext context) {
    final isHigh = intensity >= 5;

    return Container(
      decoration: BoxDecoration(
        color: color,
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
            color: intensity >= 4 ? Colors.black : Colors.white,
            fontSize: intensity >= 5 ? 8 : 7,
            fontWeight: FontWeight.bold,
            height: 1.0,
          ),
          textAlign: TextAlign.center,
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
