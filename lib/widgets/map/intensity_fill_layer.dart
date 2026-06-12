import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../core/utils/topojson_loader.dart';
import '../../core/intensity_calculator.dart';
import '../../core/utils/seis_int_loc.dart';
import '../../core/utils/jma_seis_int_loc.dart';

enum IntensityFillMode { jma, csis }

class IntensityFillLayer extends StatefulWidget {
  final double magnitude;
  final double depth;
  final double hypoLat;
  final double hypoLng;
  final String source;
  final IntensityFillMode mode;
  final double minIntensity;
  final double opacity;
  final bool showBorder;
  final bool enabled;
  final String warnAreaJson;

  const IntensityFillLayer({
    super.key,
    required this.magnitude,
    required this.depth,
    required this.hypoLat,
    required this.hypoLng,
    this.source = 'cn',
    this.mode = IntensityFillMode.csis,
    this.minIntensity = 1.0,
    this.opacity = 0.4,
    this.showBorder = true,
    this.enabled = true,
    this.warnAreaJson = '',
  });

  @override
  State<IntensityFillLayer> createState() => _IntensityFillLayerState();
}

class _IntensityFillLayerState extends State<IntensityFillLayer> {
  TopoJsonData? _topoData;
  Map<String, double> _regionIntensities = {};
  bool _loading = false;
  double _lastMag = -1;
  double _lastDepth = -1;
  double _lastLat = -1;
  double _lastLng = -1;
  String _lastSource = '';
  String _lastWarnArea = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant IntensityFillLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged = oldWidget.source != widget.source;
    final dataChanged = oldWidget.magnitude != widget.magnitude ||
        oldWidget.depth != widget.depth ||
        oldWidget.hypoLat != widget.hypoLat ||
        oldWidget.hypoLng != widget.hypoLng;
    final warnAreaChanged = oldWidget.warnAreaJson != widget.warnAreaJson;

    if (sourceChanged) {
      _loadData();
    } else if ((dataChanged || warnAreaChanged) && _topoData != null && !_loading) {
      _calculateIntensities();
    }
  }

  Future<void> _loadData() async {
    if (_loading) return;
    setState(() => _loading = true);

    TopoJsonData? data;
    switch (widget.source) {
      case 'cn':
        data = await TopoJsonLoader.loadCnEew();
        break;
      case 'jp':
        data = await TopoJsonLoader.loadJpEew();
        break;
      case 'kr':
        data = await TopoJsonLoader.loadKrEew();
        break;
      case 'tw':
        data = await TopoJsonLoader.loadTwEew();
        break;
    }

    if (mounted) {
      setState(() {
        _topoData = data;
        _loading = false;
      });
      if (data != null) {
        _calculateIntensities();
      }
    }
  }

  void _calculateIntensities() {
    if (_topoData == null) return;
    if (widget.magnitude == _lastMag &&
        widget.depth == _lastDepth &&
        widget.hypoLat == _lastLat &&
        widget.hypoLng == _lastLng &&
        widget.source == _lastSource &&
        widget.warnAreaJson == _lastWarnArea) {
      return;
    }

    _lastMag = widget.magnitude;
    _lastDepth = widget.depth;
    _lastLat = widget.hypoLat;
    _lastLng = widget.hypoLng;
    _lastSource = widget.source;
    _lastWarnArea = widget.warnAreaJson;

    final intensities = <String, double>{};

    if (widget.mode == IntensityFillMode.jma && widget.warnAreaJson.isNotEmpty) {
      _applyJmaWarnArea(intensities);
    }

    for (final region in _topoData!.regions) {
      if (intensities.containsKey(region.name)) continue;

      if (widget.mode == IntensityFillMode.jma) {
        final sectStations = JmaSeisIntLoc.getStationsForSect(region.name);
        if (sectStations != null && sectStations.isNotEmpty) {
          double maxShindo = -3.0;
          for (final station in sectStations) {
            final shindo = IntensityCalculator.calcJmaShindo(
              widget.magnitude, widget.depth,
              widget.hypoLat, widget.hypoLng,
              station.lat, station.lng,
              arv: station.arv,
            );
            if (shindo > maxShindo) maxShindo = shindo;
          }
          intensities[region.name] = maxShindo;
        } else {
          final shindo = IntensityCalculator.calcJmaShindo(
            widget.magnitude, widget.depth,
            widget.hypoLat, widget.hypoLng,
            region.center?.latitude ?? 0, region.center?.longitude ?? 0,
          );
          intensities[region.name] = shindo;
        }
      } else {
        final intLocPoints = SeisIntLoc.getPoints(widget.source, region.name);
        final dist = IntensityCalculator.pointDistToArea(
          widget.hypoLat, widget.hypoLng,
          region.polygons,
          intLocPoints,
        );
        intensities[region.name] = IntensityCalculator.calcCsis(
          widget.magnitude, widget.depth, dist,
        );
      }
    }

    setState(() => _regionIntensities = intensities);
  }

  void _applyJmaWarnArea(Map<String, double> intensities) {
    try {
      final List<dynamic> warnList = json.decode(widget.warnAreaJson);
      for (final item in warnList) {
        if (item is! Map<String, dynamic>) continue;
        final name = item['name'] as String? ?? '';
        final intensity = item['intensity'] as String? ?? '';
        final className = item['className'] as String? ?? '';
        if (name.isEmpty) continue;

        double shindoValue = _jmaShindoToValue(intensity, className);
        if (shindoValue >= 0) {
          intensities[name] = shindoValue;
        }
      }
    } catch (_) {}
  }

  static double _jmaShindoToValue(String intensity, String className) {
    const map = {
      '0': 0.0, '1': 1.0, '2': 2.0, '3': 3.0, '4': 4.0,
      '5-': 4.5, '5弱': 4.5, '5+': 5.0, '5強': 5.0,
      '6-': 5.5, '6弱': 5.5, '6+': 6.0, '6強': 6.0,
      '7': 7.0,
    };
    if (map.containsKey(intensity)) return map[intensity]!;

    const classMap = {
      'dark-gray': 0.5, 'gray': 1.0, 'sky-blue': 2.0, 'blue': 2.0,
      'green': 3.0, 'yellow': 4.0,
      'orange': 4.5, 'dark-orange': 5.0, 'red': 5.5,
      'dark-red': 6.0, 'purple': 7.0,
    };
    if (classMap.containsKey(className)) return classMap[className]!;
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _topoData == null || _loading) {
      return const SizedBox.shrink();
    }

    final polygons = <Polygon>[];

    for (final region in _topoData!.regions) {
      final intensity = _regionIntensities[region.name] ?? 0;
      if (intensity < widget.minIntensity) continue;

      final color = widget.mode == IntensityFillMode.jma
          ? Color(IntensityCalculator.getJmaShindoColor(intensity))
          : Color(IntensityCalculator.getCsisColor(intensity.round()));

      for (final polygonPoints in region.polygons) {
        if (polygonPoints.length < 3) continue;

        polygons.add(Polygon(
          points: polygonPoints,
          color: color.withValues(alpha: widget.opacity),
          borderColor: widget.showBorder ? color : Colors.transparent,
          borderStrokeWidth: widget.showBorder ? 1.0 : 0,
        ));
      }
    }

    if (polygons.isEmpty) {
      return const SizedBox.shrink();
    }

    return PolygonLayer(polygons: polygons);
  }
}
