/// 合规地图视图组件
///
/// 本组件是应用的主地图视图，用于显示地震相关的地理信息。
/// 采用 FlutterMap 作为底层地图引擎，支持多种图层叠加。
///
/// ## 主要功能
///
/// - **地图控制器管理**: 创建和管理 MapController 实例
/// - **与 Provider 集成**: 将控制器注入 MapStateProvider
/// - **支持动画移动**: 通过 Provider 实现平滑的地图移动动画
///
/// ## 地图配置
///
/// - **初始中心**: 北纬35度，东经105度（中国中部）
/// - **初始缩放**: 4.0 级（省级视图）
///
/// ## 图层结构
///
/// 地图支持以下图层：
/// - 底图层（天地图/其他地图源）
/// - GeoJSON 边界层
/// - 震中标记层
/// - 烈度等震线层
/// - 测站数据层
///
/// ## 使用示例
///
/// ```dart
/// // 在 MainScreen 中使用
/// Scaffold(
///   body: Stack(
///     children: [
///       ComplianceMapView(),
///       AlertPanel(),
///     ],
///   ),
/// )
/// ```

library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';
import '../../providers/map_state_provider.dart';

/// 合规地图视图组件
///
/// 应用的主地图视图，负责地图的渲染和控制器管理。
/// 使用 TickerProviderStateMixin 支持地图动画。
class ComplianceMapView extends StatefulWidget {
  /// 构造函数
  const ComplianceMapView({super.key});

  @override
  State<ComplianceMapView> createState() => _ComplianceMapViewState();
}

/// 合规地图视图状态类
///
/// 混入 TickerProviderStateMixin 以支持动画控制器。
class _ComplianceMapViewState extends State<ComplianceMapView>
    with TickerProviderStateMixin {
  /// 地图控制器
  ///
  /// 用于控制地图的移动、缩放等操作。
  /// 在 initState 中创建，并在下一帧注入到 MapStateProvider。
  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MapStateProvider>().setController(_mapController, this);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: _mapController,
      options: const MapOptions(
        initialCenter: MapStateProvider.defaultCenter,
        initialZoom: MapStateProvider.defaultZoom,
      ),
      children: [],
    );
  }
}
