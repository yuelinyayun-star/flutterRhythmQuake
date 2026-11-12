import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../core/utils/topojson_loader.dart';
import '../../core/intensity_calculator.dart';
import '../../core/utils/seis_int_loc.dart';
import '../../core/utils/jma_seis_int_loc.dart';
import '../../core/cwa_intensity_prediction.dart';
import '../../core/cwa_report_intensities.dart';
import '../../core/utils/cenc_ir_region_intensities.dart';
import '../../models/cenc_ir_data.dart';
import 'ka_shindo_marker_style.dart';
import 'jma_region_value_label.dart';
import 'jma_region_value_badge_layer.dart';

enum IntensityFillMode { jma, csis, cwa, cwaObserved, csisObserved }

class PaintedRegionDetail {
  const PaintedRegionDetail({
    required this.region,
    required this.rawValue,
    required this.levelKey,
    required this.badgeText,
    required this.levelLabel,
    required this.levelRangeText,
    required this.valueText,
    required this.color,
    required this.sortOrder,
  });

  final TopoJsonRegion region;
  final double rawValue;
  final String levelKey;
  final String badgeText;
  final String levelLabel;
  final String levelRangeText;
  final String valueText;
  final Color color;
  final double sortOrder;
}

class PaintedRegionGroup {
  const PaintedRegionGroup({
    required this.levelKey,
    required this.badgeText,
    required this.levelLabel,
    required this.levelRangeText,
    required this.color,
    required this.sortOrder,
    required this.regions,
  });

  final String levelKey;
  final String badgeText;
  final String levelLabel;
  final String levelRangeText;
  final Color color;
  final double sortOrder;
  final List<PaintedRegionDetail> regions;
}

class FillLegendStop {
  const FillLegendStop({
    required this.key,
    required this.label,
    required this.rangeText,
    required this.color,
    required this.hitCount,
  });

  final String key;
  final String label;
  final String rangeText;
  final Color color;
  final int hitCount;
}

class InformationFillSummary {
  const InformationFillSummary({
    required this.scaleTitle,
    required this.sourceModeLabel,
    required this.isObserved,
    required this.regions,
    required this.groups,
    required this.legendStops,
  });

  static const empty = InformationFillSummary(
    scaleTitle: '',
    sourceModeLabel: '',
    isObserved: false,
    regions: [],
    groups: [],
    legendStops: [],
  );

  final String scaleTitle;
  final String sourceModeLabel;
  final bool isObserved;
  final List<PaintedRegionDetail> regions;
  final List<PaintedRegionGroup> groups;
  final List<FillLegendStop> legendStops;
}

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

  /// UI labels only; callers explicitly opt in for ordinary JMA information.
  final bool showRegionValues;
  final String warnAreaJson;
  final CwaIntensityForecast? cwaForecast;
  final List<InstrumentIntensity>? observedStations;
  final ValueChanged<List<TopoJsonRegion>>? onInformationGeometry;
  final ValueChanged<InformationFillSummary>? onInformationFillSummary;
  final Object? informationGeometryKey;

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
    this.showRegionValues = false,
    this.warnAreaJson = '',
    this.cwaForecast,
    this.observedStations,
    this.onInformationGeometry,
    this.onInformationFillSummary,
    this.informationGeometryKey,
  });

  IntensityFillLayer.cencObserved({
    super.key,
    required CencIrData data,
    this.minIntensity = 1.0,
    this.opacity = 0.55,
    this.showBorder = true,
    this.enabled = true,
    this.showRegionValues = false,
    this.onInformationGeometry,
    this.onInformationFillSummary,
    this.informationGeometryKey,
  }) : observedStations = data.instrumentIntensities,
       magnitude = 0,
       depth = data.focDepth,
       hypoLat = data.epiLat,
       hypoLng = data.epiLon,
       source = 'cn',
       mode = IntensityFillMode.csisObserved,
       warnAreaJson = '',
       cwaForecast = null;

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
  IntensityFillMode? _lastMode;
  CwaIntensityForecast? _lastCwaForecast;
  List<InstrumentIntensity>? _lastObservedStations;
  Object? _polygonStyleKey;
  List<Polygon> _polygonCache = const [];
  List<TopoJsonRegion> _paintedRegions = const [];
  InformationFillSummary _fillSummaryCache = InformationFillSummary.empty;
  Object? _publishedGeometry;
  int _geometrySerial = 0;

  void _publishGeometry(
    List<TopoJsonRegion> regions,
    InformationFillSummary summary,
  ) {
    if (widget.onInformationGeometry == null &&
        widget.onInformationFillSummary == null) {
      return;
    }
    final key = (
      widget.informationGeometryKey,
      Object.hashAll(regions),
      summary.regions.length,
    );
    if (key == _publishedGeometry) return;
    _publishedGeometry = key;
    final serial = ++_geometrySerial;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && serial == _geometrySerial) {
        widget.onInformationGeometry?.call(regions);
        widget.onInformationFillSummary?.call(summary);
      }
    });
  }

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
    final modelChanged =
        oldWidget.mode != widget.mode ||
        !identical(oldWidget.observedStations, widget.observedStations) ||
        oldWidget.cwaForecast != widget.cwaForecast;

    if (sourceChanged) {
      _loadData();
    } else if ((dataChanged || warnAreaChanged || modelChanged) &&
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
        widget.mode == _lastMode &&
        widget.cwaForecast == _lastCwaForecast &&
        identical(widget.observedStations, _lastObservedStations) &&
        widget.warnAreaJson == _lastWarnArea) {
      return;
    }

    _lastMag = widget.magnitude;
    _lastDepth = widget.depth;
    _lastLat = widget.hypoLat;
    _lastLng = widget.hypoLng;
    _lastSource = widget.source;
    _lastWarnArea = widget.warnAreaJson;
    _lastMode = widget.mode;
    _lastCwaForecast = widget.cwaForecast;
    _lastObservedStations = widget.observedStations;

    if (widget.mode == IntensityFillMode.csisObserved) {
      final values = CencIrRegionIntensities.fromStations(
        _topoData!,
        widget.observedStations ?? const [],
      );
      setState(() {
        _regionIntensities = values;
        _regionClassNames = const {};
      });
      return;
    }

    final intensities = <String, double>{};
    final classNames = <String, String>{};

    if (widget.mode == IntensityFillMode.cwa ||
        widget.mode == IntensityFillMode.cwaObserved) {
      final ranks = widget.mode == IntensityFillMode.cwaObserved
          ? CwaReportIntensities.fromWarnArea(widget.warnAreaJson)
          : widget.cwaForecast?.countyRanks;
      if (ranks != null) {
        for (final region in _topoData!.regions) {
          final rank =
              ranks[CwaIntensityPrediction.canonicalCounty(region.name)];
          if (rank != null) intensities[region.name] = rank.toDouble();
        }
      }
      setState(() {
        _regionIntensities = intensities;
        _regionClassNames = const {};
      });
      return;
    }

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
      _publishGeometry(const [], InformationFillSummary.empty);
      return const SizedBox.shrink();
    }

    final styleKey = (
      _topoData,
      _regionIntensities,
      _regionClassNames,
      widget.mode,
      widget.minIntensity,
      widget.opacity,
      widget.showBorder,
      widget.showRegionValues,
      widget.onInformationFillSummary != null,
    );
    if (styleKey == _polygonStyleKey) {
      _publishGeometry(_paintedRegions, _fillSummaryCache);
      return _polygonCache.isEmpty
          ? const SizedBox.shrink()
          : _paintPolygons(_polygonCache);
    }
    final polygons = <Polygon>[];
    final paintedRegions = <TopoJsonRegion>[];
    final regionDetails = <PaintedRegionDetail>[];

    for (final region in _topoData!.regions) {
      if ((widget.mode == IntensityFillMode.cwaObserved ||
              widget.mode == IntensityFillMode.csisObserved) &&
          !_regionIntensities.containsKey(region.name)) {
        continue;
      }
      final intensity = _regionIntensities[region.name] ?? 0;
      final className = _regionClassNames[region.name];
      final visible = widget.mode == IntensityFillMode.csisObserved
          ? CencIrRegionIntensities.isFilled(
              intensity,
              minIntensity: widget.minIntensity,
            )
          : intensity >= widget.minIntensity;
      if (className == null && !visible) {
        continue;
      }

      final color = className != null
          ? _jmaClassColor(className) ??
                Color(IntensityCalculator.getJmaShindoColor(intensity))
          : widget.mode == IntensityFillMode.jma
          ? Color(IntensityCalculator.getJmaShindoColor(intensity))
          : widget.mode == IntensityFillMode.cwa ||
                widget.mode == IntensityFillMode.cwaObserved
          ? KaShindoMarkerStyle.colorForLevel(
              CwaIntensityPrediction.markerLevels[intensity.toInt()],
            )
          : Color(IntensityCalculator.getCsisColor(intensity.round()));

      final labelPlacement =
          widget.showRegionValues &&
              widget.source == 'jp' &&
              widget.mode == IntensityFillMode.jma
          ? JmaRegionValuePlacement.forRegion(region)
          : null;
      for (
        var polygonIndex = 0;
        polygonIndex < region.polygons.length;
        polygonIndex++
      ) {
        final polygonPoints = region.polygons[polygonIndex];
        if (polygonPoints.length < 3) continue;
        final hasRegionLabel = polygonIndex == labelPlacement?.polygonIndex;

        polygons.add(
          Polygon(
            points: polygonPoints,
            color: color.withValues(alpha: widget.opacity),
            borderColor: widget.showBorder ? color : Colors.transparent,
            borderStrokeWidth: widget.showBorder ? 1.0 : 0,
            label: hasRegionLabel
                ? jmaRegionValueText(intensity, className: className)
                : null,
            labelStyle: hasRegionLabel
                ? jmaRegionValueTextStyle.copyWith(
                    color: jmaRegionValueBadgeForeground(color),
                  )
                : const TextStyle(),
            labelPlacementCalculator: labelPlacement,
          ),
        );
      }
      if (region.polygons.any((p) => p.length >= 3)) {
        paintedRegions.add(region);
        if (widget.onInformationFillSummary != null)
          regionDetails.add(
            _buildRegionDetail(
              region: region,
              intensity: intensity,
              className: className,
              color: color,
            ),
          );
      }
    }

    _polygonStyleKey = styleKey;
    _polygonCache = polygons;
    _paintedRegions = List.unmodifiable(paintedRegions);
    _fillSummaryCache = widget.onInformationFillSummary == null
        ? InformationFillSummary.empty
        : _buildSummary(regionDetails);
    _publishGeometry(_paintedRegions, _fillSummaryCache);
    if (polygons.isEmpty) {
      return const SizedBox.shrink();
    }

    // Realtime stations and waves repaint independently of this geometry.
    // Retain its display list until the report, style or map camera changes.
    return _paintPolygons(polygons);
  }

  PaintedRegionDetail _buildRegionDetail({
    required TopoJsonRegion region,
    required double intensity,
    required String? className,
    required Color color,
  }) {
    switch (widget.mode) {
      case IntensityFillMode.jma:
        final symbol = jmaRegionValueText(intensity, className: className);
        final info = IntensityCalculator.getJmaShindoInfoByLevel(symbol);
        final kanji = symbol == '0' ? '0' : info.kanji;
        final rangeText = _jmaShindoRangeText(symbol);
        final isObserved = widget.warnAreaJson.isNotEmpty;
        final numStr = isObserved
            ? intensity.toStringAsFixed(1)
            : intensity.toStringAsFixed(2);
        return PaintedRegionDetail(
          region: region,
          rawValue: intensity,
          levelKey: symbol,
          badgeText: kanji,
          levelLabel: '震度 $kanji',
          levelRangeText: '計測震度 $rangeText',
          valueText: '$kanji ($numStr)',
          color: color,
          sortOrder: info.level >= 0 ? info.level.toDouble() : intensity,
        );
      case IntensityFillMode.cwa:
      case IntensityFillMode.cwaObserved:
        final rank = intensity.round().clamp(
          0,
          CwaIntensityPrediction.labels.length - 1,
        );
        final symbol = CwaIntensityPrediction.labels[rank];
        final kanji = _cwaKanjiLabel(symbol);
        final pgaRange = _cwaPgaRangeText(rank);
        return PaintedRegionDetail(
          region: region,
          rawValue: intensity,
          levelKey: symbol,
          badgeText: kanji,
          levelLabel: '震度 $kanji',
          levelRangeText: 'PGA $pgaRange',
          valueText: '$kanji ($pgaRange)',
          color: color,
          sortOrder: rank.toDouble(),
        );
      case IntensityFillMode.csis:
      case IntensityFillMode.csisObserved:
        final level = intensity.round().clamp(1, 12);
        final roman = _csisRomanLabels[level];
        final low = (level - 0.5).clamp(0.5, 11.5).toStringAsFixed(1);
        final high = level >= 12 ? '12.0+' : (level + 0.4).toStringAsFixed(1);
        return PaintedRegionDetail(
          region: region,
          rawValue: intensity,
          levelKey: roman,
          badgeText: roman,
          levelLabel: '烈度 $roman ($level度)',
          levelRangeText: '计算值 $low~$high',
          valueText: '$roman度 (${intensity.toStringAsFixed(2)})',
          color: color,
          sortOrder: level.toDouble(),
        );
    }
  }

  InformationFillSummary _buildSummary(List<PaintedRegionDetail> details) {
    final sorted = List<PaintedRegionDetail>.from(details)
      ..sort((a, b) {
        final cmp = b.sortOrder.compareTo(a.sortOrder);
        if (cmp != 0) return cmp;
        final rawCmp = b.rawValue.compareTo(a.rawValue);
        if (rawCmp != 0) return rawCmp;
        return a.region.code.compareTo(b.region.code);
      });
    final byLevel = <String, List<PaintedRegionDetail>>{};
    for (final item in sorted) {
      (byLevel[item.levelKey] ??= []).add(item);
    }
    final groups = <PaintedRegionGroup>[
      for (final entry in byLevel.entries)
        PaintedRegionGroup(
          levelKey: entry.key,
          badgeText: entry.value.first.badgeText,
          levelLabel: entry.value.first.levelLabel,
          levelRangeText: entry.value.first.levelRangeText,
          color: entry.value.first.color,
          sortOrder: entry.value.first.sortOrder,
          regions: List.unmodifiable(entry.value),
        ),
    ]..sort((a, b) => b.sortOrder.compareTo(a.sortOrder));

    final hitCounts = <String, int>{
      for (final g in groups) g.levelKey: g.regions.length,
    };

    final (
      scaleTitle,
      sourceModeLabel,
      isObserved,
      stops,
    ) = switch (widget.mode) {
      IntensityFillMode.jma => (
        widget.source == 'kr' ? 'KMA / JMA 震度阶' : 'JMA 震度阶',
        widget.warnAreaJson.isNotEmpty
            ? '报文实测细分区域填色'
            : (widget.source == 'kr' ? '震源距离衰减模型推算填色' : '测站场地放大 (ARV) 推算填色'),
        widget.warnAreaJson.isNotEmpty,
        _buildJmaLegendStops(hitCounts),
      ),
      IntensityFillMode.cwa => (
        'CWA 地震震度阶',
        'PGA 场地衰减模型预测填色',
        false,
        _buildCwaLegendStops(hitCounts),
      ),
      IntensityFillMode.cwaObserved => (
        'CWA 地震震度阶',
        '报文实测县市最大震度填色',
        true,
        _buildCwaLegendStops(hitCounts),
      ),
      IntensityFillMode.csis => (
        '中国地震烈度表 (CSIS)',
        '震源距离衰减模型估算填色',
        false,
        _buildCsisLegendStops(hitCounts),
      ),
      IntensityFillMode.csisObserved => (
        '中国地震烈度表 (CSIS)',
        '仪器烈度测站实测填色',
        true,
        _buildCsisLegendStops(hitCounts),
      ),
    };

    return InformationFillSummary(
      scaleTitle: scaleTitle,
      sourceModeLabel: sourceModeLabel,
      isObserved: isObserved,
      regions: List.unmodifiable(sorted),
      groups: List.unmodifiable(groups),
      legendStops: List.unmodifiable(stops),
    );
  }

  static const _csisRomanLabels = [
    '',
    'I',
    'II',
    'III',
    'IV',
    'V',
    'VI',
    'VII',
    'VIII',
    'IX',
    'X',
    'XI',
    'XII',
  ];

  static String _jmaShindoRangeText(String symbol) => switch (symbol) {
    '0' => '<0.5',
    '1' => '0.5~1.4',
    '2' => '1.5~2.4',
    '3' => '2.5~3.4',
    '4' => '3.5~4.4',
    '5-' => '4.5~4.9',
    '5+' => '5.0~5.4',
    '6-' => '5.5~5.9',
    '6+' => '6.0~6.4',
    '7' => '≥6.5',
    _ => '--',
  };

  static String _cwaKanjiLabel(String symbol) => switch (symbol) {
    '5-' => '5弱',
    '5+' => '5強',
    '6-' => '6弱',
    '6+' => '6強',
    _ => '$symbol級',
  };

  static String _cwaPgaRangeText(int rank) => switch (rank) {
    0 => '<0.8gal',
    1 => '0.8~2.5gal',
    2 => '2.5~8.0gal',
    3 => '8.0~25gal',
    4 => '25~80gal',
    5 => '80~140gal',
    6 => '140~250gal',
    7 => '250~440gal',
    8 => '440~800gal',
    _ => '≥800gal',
  };

  static List<FillLegendStop> _buildJmaLegendStops(Map<String, int> hits) {
    const keys = ['1', '2', '3', '4', '5-', '5+', '6-', '6+', '7'];
    return [
      if ((hits['0'] ?? 0) > 0)
        FillLegendStop(
          key: '0',
          label: '0',
          rangeText: '<0.5',
          color: const Color(0xFF888888),
          hitCount: hits['0'] ?? 0,
        ),
      for (final key in keys)
        FillLegendStop(
          key: key,
          label: IntensityCalculator.getJmaShindoInfoByLevel(key).kanji,
          rangeText: _jmaShindoRangeText(key),
          color: Color(IntensityCalculator.getJmaShindoColorByLevel(key)),
          hitCount: hits[key] ?? 0,
        ),
    ];
  }

  static List<FillLegendStop> _buildCwaLegendStops(Map<String, int> hits) {
    return [
      for (var rank = 1; rank < CwaIntensityPrediction.labels.length; rank++)
        FillLegendStop(
          key: CwaIntensityPrediction.labels[rank],
          label: _cwaKanjiLabel(CwaIntensityPrediction.labels[rank]),
          rangeText: _cwaPgaRangeText(rank),
          color: KaShindoMarkerStyle.colorForLevel(
            CwaIntensityPrediction.markerLevels[rank],
          ),
          hitCount: hits[CwaIntensityPrediction.labels[rank]] ?? 0,
        ),
    ];
  }

  static List<FillLegendStop> _buildCsisLegendStops(Map<String, int> hits) {
    return [
      for (var level = 1; level <= 10; level++)
        FillLegendStop(
          key: _csisRomanLabels[level],
          label: level == 10 ? 'X+' : _csisRomanLabels[level],
          rangeText: level == 10
              ? '≥9.5'
              : '${(level - 0.5).toStringAsFixed(1)}~${(level + 0.4).toStringAsFixed(1)}',
          color: Color(IntensityCalculator.getCsisColor(level)),
          hitCount: level == 10
              ? (hits['X'] ?? 0) + (hits['XI'] ?? 0) + (hits['XII'] ?? 0)
              : (hits[_csisRomanLabels[level]] ?? 0),
        ),
    ];
  }

  Widget _paintPolygons(List<Polygon> polygons) => RepaintBoundary(
    child: widget.showRegionValues
        ? Stack(
            children: [
              PolygonLayer(polygons: polygons, polygonLabels: false),
              JmaRegionValueBadgeLayer(polygons: polygons),
            ],
          )
        : PolygonLayer(polygons: polygons),
  );
}
