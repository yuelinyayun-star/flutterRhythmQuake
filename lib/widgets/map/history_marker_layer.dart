import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/quake_message.dart';
import '../../core/utils/world_wrap.dart';

/// 历史地震标记图层
///
/// 该组件负责在地图上显示历史地震事件的标记。
/// 用于在地图上标记已发生的地震位置，便于用户查看历史地震分布。
///
/// 主要功能：
/// - 显示震中位置的十字标记
/// - 显示震级标签
/// - 标记具有发光效果增强可见性
///
/// 与QuakeWaveLayer的区别：
/// - HistoryMarkerLayer: 静态标记，用于历史地震
/// - QuakeWaveLayer: 动态动画，用于当前地震波传播
class HistoryMarkerLayer extends StatelessWidget {
  /// 地震事件数据
  /// 包含震中坐标和震级信息
  final QuakeMessage? event;

  const HistoryMarkerLayer({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    if (event == null) return const SizedBox.shrink();
    if (event!.latitude == 0.0 && event!.longitude == 0.0) return const SizedBox.shrink();

    return Builder(
      builder: (innerContext) {
        final camera = MapCamera.of(innerContext);
        final centerLatLng = WorldWrap.latLngClosestToCamera(
          LatLng(event!.latitude, event!.longitude),
          camera,
        );
        return Stack(
          children: [
            CustomPaint(
              painter: HistoryCrossPainter(
                latitude: event!.latitude,
                longitude: event!.longitude,
                magnitude: event!.magnitude,
                camera: camera,
              ),
              size: Size.infinite,
            ),
          ],
        );
      },
    );
  }
}

/// 历史地震十字标记绘制器
///
/// 负责在Canvas上绘制历史地震的震中标记
class HistoryCrossPainter extends CustomPainter {
  /// 震中纬度
  final double latitude;

  /// 震中经度
  final double longitude;

  /// 地震震级
  final double magnitude;

  /// 地图相机对象
  /// 用于坐标转换
  final MapCamera camera;

  HistoryCrossPainter({
    required this.latitude,
    required this.longitude,
    required this.magnitude,
    required this.camera,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerLatLng = WorldWrap.latLngClosestToCamera(
      LatLng(latitude, longitude),
      camera,
    );
    final center = camera.getOffsetFromOrigin(centerLatLng);

    if (center.dx < -200 ||
        center.dx > size.width + 200 ||
        center.dy < -200 ||
        center.dy > size.height + 200) {
      return;
    }

    _drawGlow(canvas, center);
    _drawCrosshair(canvas, center);
    _drawLabel(canvas, center);
  }

  /// 绘制发光效果
  ///
  /// 在十字标记周围添加发光效果
  /// 增强标记的可见性
  void _drawGlow(Canvas canvas, Offset center) {
    final glowPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.round;

    final s = 16.0;
    canvas.drawLine(
      Offset(center.dx - s, center.dy - s),
      Offset(center.dx + s, center.dy + s),
      glowPaint,
    );
    canvas.drawLine(
      Offset(center.dx + s, center.dy - s),
      Offset(center.dx - s, center.dy + s),
      glowPaint,
    );
  }

  /// 绘制十字标记
  ///
  /// 使用红色十字标记震中位置
  /// 中心添加白色圆点增强定位精度
  void _drawCrosshair(Canvas canvas, Offset center) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final s = 14.0;
    canvas.drawLine(
      Offset(center.dx - s, center.dy - s),
      Offset(center.dx + s, center.dy + s),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx + s, center.dy - s),
      Offset(center.dx - s, center.dy + s),
      paint,
    );

    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 3.0, dotPaint);
  }

  /// 绘制震级标签
  ///
  /// 在震中上方显示震级信息
  void _drawLabel(Canvas canvas, Offset center) {
    final label = 'M${magnitude.toStringAsFixed(1)}';
    final bgPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final labelX = center.dx - textPainter.width / 2;
    final labelY = center.dy - 30;

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        labelX - 4,
        labelY - 2,
        textPainter.width + 8,
        textPainter.height + 4,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(bgRect, bgPaint);

    textPainter.paint(canvas, Offset(labelX, labelY));
  }

  @override
  bool shouldRepaint(covariant HistoryCrossPainter oldDelegate) {
    return oldDelegate.latitude != latitude ||
        oldDelegate.longitude != longitude ||
        oldDelegate.magnitude != magnitude;
  }
}
