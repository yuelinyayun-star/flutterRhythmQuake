import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../core/utils/topojson_loader.dart';
import '../../models/jma_lpgm_bulletin.dart';

class JmaLpgmRegionFillLayer extends StatefulWidget {
  const JmaLpgmRegionFillLayer({super.key, required this.bulletin});

  final JmaLpgmBulletin bulletin;

  @override
  State<JmaLpgmRegionFillLayer> createState() => _JmaLpgmRegionFillLayerState();
}

class _JmaLpgmRegionFillLayerState extends State<JmaLpgmRegionFillLayer> {
  TopoJsonData? _data;

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
    final regionsByCode = <String, JmaLpgmRegion>{
      for (final region in widget.bulletin.regions)
        if (region.code.trim().isNotEmpty) region.code.trim(): region,
    };
    final polygons = <Polygon>[];
    for (final topo in data.regions) {
      final region = regionsByCode[topo.code.trim()];
      if (region == null) continue;
      final color = jmaLpgmClassColor(region.maxLgInt);
      for (final points in topo.polygons) {
        if (points.length < 3) continue;
        polygons.add(
          Polygon(
            points: points,
            color: color.withValues(alpha: 0.42),
            borderColor: color.withValues(alpha: 0.8),
            borderStrokeWidth: 1,
          ),
        );
      }
    }
    return polygons.isEmpty
        ? const SizedBox.shrink()
        : PolygonLayer(polygons: polygons);
  }
}
