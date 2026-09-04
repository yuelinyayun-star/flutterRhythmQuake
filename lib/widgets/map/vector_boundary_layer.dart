import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../services/boundary_service.dart';

/// 矢量边界线图层
///
/// 该组件负责在地图上显示行政区划边界线和城市名称标签。
/// 使用BoundaryService加载预处理的边界数据。
///
/// 主要功能：
/// - 显示省界、市界等行政区划边界
/// - 显示城市名称标签
/// - 支持多层边界叠加显示
///
/// 数据来源：BoundaryService (本地GeoJSON数据)
class VectorBoundaryLayer extends StatefulWidget {
  const VectorBoundaryLayer({super.key});

  @override
  State<VectorBoundaryLayer> createState() => _VectorBoundaryLayerState();
}

class _VectorBoundaryLayerState extends State<VectorBoundaryLayer> {
  /// 加载边界数据
  ///
  /// 从BoundaryService加载预处理的边界数据
  /// 加载完成后触发界面刷新
  Future<void> _load() async {
    await BoundaryService().load();
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final service = BoundaryService();
    final allPolylines = <Polyline>[];
    final allLabels = <Marker>[];

    for (var layer in service.layers) {
      allPolylines.addAll(layer.polylines);
    }

    for (var label in service.cityLabels) {
      allLabels.add(
        Marker(
          width: 80,
          height: 22,
          point: label.coord,
          child: Text(
            label.name,
            style: const TextStyle(
              color: Color(0xCCEEEEEE),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
              shadows: [
                Shadow(
                  color: Color(0xFF000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Stack(
      children: [
        if (allPolylines.isNotEmpty) PolylineLayer(polylines: allPolylines),
        if (allLabels.isNotEmpty) MarkerLayer(markers: allLabels),
      ],
    );
  }
}
