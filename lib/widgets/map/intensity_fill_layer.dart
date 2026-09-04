import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../core/utils/topojson_loader.dart';
import '../../core/intensity_calculator.dart';
import '../../core/utils/seis_int_loc.dart';
import '../../core/utils/jma_seis_int_loc.dart';

enum IntensityFillMode { jma, csis }

bool _sameDoubleValue(double a, double b) => a == b || (a.isNaN && b.isNaN);

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
  Map<String, String> _regionClassNames = {};
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
    final dataChanged =
        !_sameDoubleValue(oldWidget.magnitude, widget.magnitude) ||
        !_sameDoubleValue(oldWidget.depth, widget.depth) ||
        !_sameDoubleValue(oldWidget.hypoLat, widget.hypoLat) ||
        !_sameDoubleValue(oldWidget.hypoLng, widget.hypoLng);
    final warnAreaChanged = oldWidget.warnAreaJson != widget.warnAreaJson;

    if (sourceChanged) {
      _loadData();
    } else if ((dataChanged || warnAreaChanged) &&
        _topoData != null &&
        !_loading) {
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
    if (_sameDoubleValue(widget.magnitude, _lastMag) &&
        _sameDoubleValue(widget.depth, _lastDepth) &&
        _sameDoubleValue(widget.hypoLat, _lastLat) &&
        _sameDoubleValue(widget.hypoLng, _lastLng) &&
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
    final classNames = <String, String>{};

    if (widget.mode == IntensityFillMode.jma &&
        widget.warnAreaJson.isNotEmpty) {
      _applyJmaWarnArea(intensities, classNames);
      setState(() {
        _regionIntensities = intensities;
        _regionClassNames = classNames;
      });
      return;
    }

    for (final region in _topoData!.regions) {
      if (intensities.containsKey(region.name)) continue;

      if (widget.mode == IntensityFillMode.jma) {
        final sectStations = JmaSeisIntLoc.getStationsForSect(region.name);
        if (sectStations != null && sectStations.isNotEmpty) {
          double maxShindo = -3.0;
          for (final station in sectStations) {
            final shindo = IntensityCalculator.calcJmaShindo(
              widget.magnitude,
              widget.depth,
              widget.hypoLat,
              widget.hypoLng,
              station.lat,
              station.lng,
              arv: station.arv,
            );
            if (shindo > maxShindo) maxShindo = shindo;
          }
          intensities[region.name] = maxShindo;
        } else {
          final shindo = IntensityCalculator.calcJmaShindo(
            widget.magnitude,
            widget.depth,
            widget.hypoLat,
            widget.hypoLng,
            region.center?.latitude ?? 0,
            region.center?.longitude ?? 0,
          );
          intensities[region.name] = shindo;
        }
      } else {
        final intLocPoints = SeisIntLoc.getPoints(widget.source, region.name);
        final dist = IntensityCalculator.pointDistToArea(
          widget.hypoLat,
          widget.hypoLng,
          region.polygons,
          intLocPoints,
        );
        intensities[region.name] = IntensityCalculator.calcCsis(
          widget.magnitude,
          widget.depth,
          dist,
        );
      }
    }

    setState(() {
      _regionIntensities = intensities;
      _regionClassNames = const {};
    });
  }

  void _applyJmaWarnArea(
    Map<String, double> intensities,
    Map<String, String> classNames,
  ) {
    try {
      final List<dynamic> warnList = json.decode(widget.warnAreaJson);
      final classLevels = <String, int>{};
      for (final item in warnList) {
        if (item is! Map<String, dynamic>) continue;
        final name = item['name'] as String? ?? '';
        final intensity = item['intensity'] as String? ?? '';
        final className = item['className'] as String? ?? '';
        if (name.isEmpty) continue;

        final classLevel = _jmaClassLevel(className);
        final shindoValue = classLevel >= 0
            ? _jmaValueFromClassName(className)
            : _jmaShindoToValue(intensity, className);
        if (shindoValue >= 0) {
          final rank = classLevel >= 0
              ? classLevel
              : _jmaValueToClassLevel(shindoValue);
          final previousRank = classLevels[name];
          if (previousRank == null || rank > previousRank) {
            classLevels[name] = rank;
            intensities[name] = shindoValue;
            if (classLevel >= 0) {
              classNames[name] = className;
            } else {
              classNames.remove(name);
            }
          }
        }
      }
    } catch (_) {}
  }

  static int _jmaClassLevel(String className) {
    switch (className) {
      case 'dark-gray':
        return 0;
      case 'gray':
        return 1;
      case 'sky-blue':
        return 2;
      case 'blue':
        return 3;
      case 'green':
        return 4;
      case 'yellow':
        return 5;
      case 'orange':
        return 6;
      case 'dark-orange':
        return 7;
      case 'red':
        return 8;
      case 'dark-red':
        return 9;
      case 'purple':
        return 10;
      default:
        return -1;
    }
  }

  static int _jmaValueToClassLevel(double value) {
    if (value >= 7.0) return 10;
    if (value >= 6.0) return 9;
    if (value >= 5.5) return 8;
    if (value >= 5.0) return 7;
    if (value >= 4.5) return 6;
    if (value >= 4.0) return 5;
    if (value >= 3.0) return 4;
    if (value >= 2.0) return 3;
    if (value >= 1.0) return 1;
    if (value >= 0) return 0;
    return -1;
  }

  static double _jmaValueFromClassName(String className) {
    switch (className) {
      case 'gray':
        return 1.0;
      case 'sky-blue':
      case 'blue':
        return 2.0;
      case 'green':
        return 3.0;
      case 'yellow':
        return 4.0;
      case 'orange':
        return 4.5;
      case 'dark-orange':
        return 5.0;
      case 'red':
        return 5.5;
      case 'dark-red':
        return 6.0;
      case 'purple':
        return 7.0;
      case 'dark-gray':
        return 0.5;
      default:
        return -1;
    }
  }

  static double _jmaShindoToValue(String intensity, String className) {
    const map = {
      '0': 0.0,
      '1': 1.0,
      '2': 2.0,
      '3': 3.0,
      '4': 4.0,
      '5-': 4.5,
      '5弱': 4.5,
      '5+': 5.0,
      '5強': 5.0,
      '6-': 5.5,
      '6弱': 5.5,
      '6+': 6.0,
      '6強': 6.0,
      '7': 7.0,
    };
    if (map.containsKey(intensity)) return map[intensity]!;

    const classMap = {
      'dark-gray': 0.5,
      'gray': 1.0,
      'sky-blue': 2.0,
      'blue': 2.0,
      'green': 3.0,
      'yellow': 4.0,
      'orange': 4.5,
      'dark-orange': 5.0,
      'red': 5.5,
      'dark-red': 6.0,
      'purple': 7.0,
    };
    if (classMap.containsKey(className)) return classMap[className]!;
    return -1;
  }

  static Color? _jmaClassColor(String className) {
    switch (className) {
      case 'purple':
        return const Color(0xFF991199);
      case 'dark-red':
        return const Color(0xFFBB2222);
      case 'red':
        return const Color(0xFFCC3333);
      case 'dark-orange':
        return const Color(0xFFEE4444);
      case 'orange':
        return const Color(0xFFEE6644);
      case 'yellow':
        return const Color(0xFFEE9944);
      case 'green':
        return const Color(0xFFDDDD00);
      case 'blue':
      case 'sky-blue':
        return const Color(0xFF44BB66);
      case 'gray':
        return const Color(0xFF4499FF);
      case 'dark-gray':
        return const Color(0xFF888888);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _topoData == null || _loading) {
      return const SizedBox.shrink();
    }

    final polygons = <Polygon>[];

    for (final region in _topoData!.regions) {
      final intensity = _regionIntensities[region.name] ?? 0;
      final className = _regionClassNames[region.name];
      if (className == null && intensity < widget.minIntensity) continue;

      final color = className != null
          ? _jmaClassColor(className) ??
                Color(IntensityCalculator.getJmaShindoColor(intensity))
          : widget.mode == IntensityFillMode.jma
          ? Color(IntensityCalculator.getJmaShindoColor(intensity))
          : Color(IntensityCalculator.getCsisColor(intensity.round()));

      for (final polygonPoints in region.polygons) {
        if (polygonPoints.length < 3) continue;

        polygons.add(
          Polygon(
            points: polygonPoints,
            color: color.withValues(alpha: widget.opacity),
            borderColor: widget.showBorder ? color : Colors.transparent,
            borderStrokeWidth: widget.showBorder ? 1.0 : 0,
          ),
        );
      }
    }

    if (polygons.isEmpty) {
      return const SizedBox.shrink();
    }

    return PolygonLayer(polygons: polygons);
  }
}
