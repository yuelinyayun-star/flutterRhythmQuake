import 'package:flutter/material.dart';
import 'widgets/map/compliance_map_view.dart';
import 'widgets/ui/alert_panel.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 底层：合规地图
          ComplianceMapView(),

          // 顶层：预警浮窗（内部自带 Consumer 监听）
          const AlertPanel(),

          // 可以在底部再加一个列表组件
        ],
      ),
    );
  }
}
