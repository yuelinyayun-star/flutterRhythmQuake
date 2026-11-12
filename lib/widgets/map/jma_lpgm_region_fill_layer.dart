import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../core/utils/topojson_loader.dart';
import '../../models/jma_lpgm_bulletin.dart';
import 'intensity_fill_layer.dart';

class JmaLpgmRegionFillLayer extends StatefulWidget {
  const JmaLpgmRegionFillLayer({
    super.key,
    required this.bulletin,
    this.informationGeometryKey,
    this.onInformationGeometry,
    this.onInformationFillSummary,
  });

  final JmaLpgmBulletin bulletin;
  final Object? informationGeometryKey;
  final ValueChanged<List<TopoJsonRegion>>? onInformationGeometry;
  final ValueChanged<InformationFillSummary>? onInformationFillSummary;

  @override
  State<JmaLpgmRegionFillLayer> createState() => _JmaLpgmRegionFillLayerState();
}

class _JmaLpgmRegionFillLayerState extends State<JmaLpgmRegionFillLayer> {
  TopoJsonData? _data;
  Object? _publishedGeometry;
  Object? _styleKey;
  List<Polygon> _polygons = const [];
  List<TopoJsonRegion> _painted = const [];
  InformationFillSummary _summary = InformationFillSummary.empty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await TopoJsonLoader.loadJpEew();
    if (mounted) setState(() => _data = data);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null || widget.bulletin.regions.isEmpty) {
      return const SizedBox.shrink();
    }
    final key = (
      data,
      widget.bulletin.signature,
      widget.onInformationGeometry != null,
      widget.onInformationFillSummary != null,
    );
    if (_styleKey == key) {
      _publishGeometry(key);
      return _paintPolygons();
    }
    final regionsByCode = <String, JmaLpgmRegion>{
      for (final region in widget.bulletin.regions)
        if (region.code.trim().isNotEmpty) region.code.trim(): region,
    };
    final polygons = <Polygon>[];
    final painted = <TopoJsonRegion>[];
    final details = <PaintedRegionDetail>[];
    for (final topo in data.regions) {
      final region = regionsByCode[topo.code.trim()];
      if (region == null || region.maxLgInt < 1 || region.maxLgInt > 4) {
        continue;
      }
      final color = jmaLpgmClassColor(region.maxLgInt);
      for (final points in topo.polygons) {
        if (points.length < 3) continue;
        polygons.add(
          Polygon(
            points: points,
            color: color.withValues(alpha: 0.55),
            borderColor: color,
            borderStrokeWidth: 1,
          ),
        );
      }
      if (topo.polygons.any((p) => p.length >= 3)) {
        painted.add(topo);
        final lg = region.maxLgInt.clamp(1, 4);
        final rangeText = _lpgmRangeText(lg);
        if (widget.onInformationFillSummary != null) {
          details.add(
            PaintedRegionDetail(
              region: topo,
              rawValue: lg.toDouble(),
              levelKey: '$lg',
              badgeText: '$lg',
              levelLabel: '阶级 $lg',
              levelRangeText: 'SVA $rangeText',
              valueText: '阶级$lg ($rangeText)',
              color: color,
              sortOrder: lg.toDouble(),
            ),
          );
        }
      }
    }
    _styleKey = key;
    _polygons = polygons;
    _painted = List.unmodifiable(painted);
    _summary = widget.onInformationFillSummary == null
        ? InformationFillSummary.empty
        : _buildLpgmSummary(details);
    _publishGeometry(key);
    return _paintPolygons();
  }

  void _publishGeometry(Object styleKey) {
    final key = (styleKey, widget.informationGeometryKey);
    if ((widget.onInformationGeometry != null ||
            widget.onInformationFillSummary != null) &&
        key != _publishedGeometry) {
      _publishedGeometry = key;
      final painted = _painted;
      final summary = _summary;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _publishedGeometry == key) {
          widget.onInformationGeometry?.call(painted);
          widget.onInformationFillSummary?.call(summary);
        }
      });
    }
  }

  Widget _paintPolygons() => _polygons.isEmpty
      ? const SizedBox.shrink()
      : RepaintBoundary(
          child: PolygonLayer(polygons: _polygons, polygonLabels: false),
        );

  static String _lpgmRangeText(int lg) => switch (lg) {
    1 => '5~15cm/s',
    2 => '15~50cm/s',
    3 => '50~100cm/s',
    _ => '>100cm/s',
  };

  static InformationFillSummary _buildLpgmSummary(
    List<PaintedRegionDetail> details,
  ) {
    final sorted = List<PaintedRegionDetail>.from(details)
      ..sort((a, b) {
        final cmp = b.sortOrder.compareTo(a.sortOrder);
        return cmp != 0 ? cmp : a.region.code.compareTo(b.region.code);
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
    final hits = <String, int>{
      for (final g in groups) g.levelKey: g.regions.length,
    };
    final stops = [
      for (var lg = 1; lg <= 4; lg++)
        FillLegendStop(
          key: '$lg',
          label: '阶级$lg',
          rangeText: _lpgmRangeText(lg),
          color: jmaLpgmClassColor(lg),
          hitCount: hits['$lg'] ?? 0,
        ),
    ];
    return InformationFillSummary(
      scaleTitle: 'JMA 长周期地震动阶级',
      sourceModeLabel: '长周期观测区域填色',
      isObserved: true,
      regions: List.unmodifiable(sorted),
      groups: List.unmodifiable(groups),
      legendStops: List.unmodifiable(stops),
    );
  }
}
