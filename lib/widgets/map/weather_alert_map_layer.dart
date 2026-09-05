import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/weather_alert_map_item.dart';
import '../../services/sources/china_weather_alert_map_service.dart';

/// 全国气象灾害预警地图图层组件
///
/// 严格遵循中国气象局（CMA）与国家标准 GB/T 28564-2012 规范：
/// 1. 多边形图层：绘制受灾行政区县的半透明染色多边形面与轮廓边框；
/// 2. 国标四宫格气象徽章：按 LOD 视距过滤算法（省级 Zoom 4~5、市级 Zoom 4~8、县级 Zoom >=6.8）
///    在预警中心点精准绘制 40×36 标准四宫格气象徽章（图形符号 + 竖排中文 + 等级字 + 英文全称）；
/// 3. 交互点击弹窗：点击命中测试由父层 MapOptions.onTap 处理，弹窗由父层驱动。
///
/// 注意：本组件内部不持有任何手势检测器（GestureDetector），所有点击由
/// [onAlertTap] 回调从外部触发。这避免了 FlutterMap 手势竞技场抢占问题。
class WeatherAlertMapLayer extends StatelessWidget {
  final List<WeatherAlertMapItem> alerts;

  /// 当前选中的预警项（由父组件维护状态）
  final WeatherAlertMapItem? selectedAlert;

  /// 当选中项需要关闭时调用
  final VoidCallback? onDismiss;

  const WeatherAlertMapLayer({
    super.key,
    required this.alerts,
    this.selectedAlert,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const SizedBox.shrink();
    final camera = MapCamera.of(context);
    final zoom = camera.zoom;

    // 筛选当前缩放等级下可见的预警图标（严格遵循 CMA 官方分级 LOD 规则）
    final visibleAlerts =
        alerts.where((a) => a.isIconVisibleAtZoom(zoom)).toList();
    final selected = selectedAlert;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. 预警多边形区域染色层（纯渲染，无手势，点击由父层 MapOptions.onTap 处理）
        RepaintBoundary(
          child: CustomPaint(
            painter: _WeatherAlertPolygonPainter(
              alerts: alerts,
              camera: camera,
              selectedAlertId: selected?.id,
            ),
            size: Size.infinite,
            isComplex: true,
            willChange: false,
          ),
        ),

        // 2. 国标四宫格气象徽章图层（随缩放动态平滑缩放，放大地图时更清晰饱满）
        () {
          final zoomScale = getBadgeZoomScale(zoom);
          return MarkerLayer(
            markers: visibleAlerts.map((alert) {
              final isSelected = alert.id == selected?.id;
              final selectedScale = isSelected ? 1.15 : 1.0;
              final totalScale = zoomScale * selectedScale;
              final markerW = 44.0 * totalScale;
              final markerH = 40.0 * totalScale;

              return Marker(
                point: alert.center,
                width: markerW,
                height: markerH,
                alignment: Alignment.center,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: CustomPaint(
                    painter: _WeatherAlertSingleBadgePainter(
                      alert: alert,
                      scale: totalScale,
                      isSelected: isSelected,
                    ),
                    size: Size.infinite,
                  ),
                ),
              );
            }).toList(),
          );
        }(),

        // 3. 选中预警弹窗详情卡片（以屏幕像素锚定在预警中心上方，彻底规避 MarkerLayer 缩放形变）
        if (selected != null) ...[
          () {
            final cardRect = getPopupCardRect(selected, camera);
            if (cardRect == null) return const SizedBox.shrink();

            return Positioned(
              left: cardRect.left,
              top: cardRect.top,
              width: cardRect.width,
              child: _WeatherAlertPopupCard(
                alert: selected,
                onClose: onDismiss ?? () {},
              ),
            );
          }(),
        ],
      ],
    );
  }

  /// 计算随地图缩放级别动态变化的图标缩放系数（远景 0.85x ~ 近景 1.28x）
  static double getBadgeZoomScale(double zoom) {
    final t = ((zoom - 3.5) / 5.5).clamp(0.0, 1.0);
    return 0.85 + 0.43 * t; // 0.85 ~ 1.28
  }

  /// 计算当前打开的弹窗卡片在屏幕上的绝对矩形包围盒（显示在预警图标右侧，避免遮挡图标）
  static Rect? getPopupCardRect(WeatherAlertMapItem? selected, MapCamera camera) {
    if (selected == null) return null;
    final pt = camera.latLngToScreenOffset(selected.center);
    final zoomScale = getBadgeZoomScale(camera.zoom);
    const cardW = 340.0;
    const approxCardH = 280.0;
    // 图标在选中状态下的半宽约为 22.0 * zoomScale * 1.15，弹窗放置在图标右侧（留出间隙）
    final iconOffsetRight = 24.0 * zoomScale * 1.15 + 10.0;
    final left = pt.dx + iconOffsetRight;
    final top = pt.dy - 36.0;
    return Rect.fromLTWH(left, top, cardW, approxCardH);
  }

  /// 静态命中测试：给定屏幕像素坐标（camera 投影），找到最近的可见预警徽章或多边形区域。
  /// 由父层 MapOptions.onTap 调用。
  /// [screenOffset] 为相对于 FlutterMap widget 左上角的屏幕坐标（TapPosition.relative）。
  static WeatherAlertMapItem? hitTest(
    List<WeatherAlertMapItem> alerts,
    MapCamera camera,
    Offset screenOffset, {
    WeatherAlertMapItem? selectedAlert,
  }) {
    // 0. 防穿透拦截：如果点击落在当前弹窗卡片区域内，绝不触发下层任何多边形或徽章
    if (selectedAlert != null) {
      final cardRect = getPopupCardRect(selectedAlert, camera);
      if (cardRect != null && cardRect.inflate(8.0).contains(screenOffset)) {
        return null;
      }
    }

    final tapLatLng = camera.screenOffsetToLatLng(screenOffset);
    final zoom = camera.zoom;
    final zoomScale = getBadgeZoomScale(zoom);

    // 1. 优先检测徽章（屏幕像素距离内命中，考虑当前缩放下的徽章半径）
    WeatherAlertMapItem? closestBadge;
    double closestDist = double.infinity;
    final badgeHitRadiusPx = 28.0 * zoomScale;

    for (final alert in alerts) {
      if (!alert.isIconVisibleAtZoom(zoom)) continue;
      final centerPx = camera.latLngToScreenOffset(alert.center);
      final dx = centerPx.dx - screenOffset.dx;
      final dy = centerPx.dy - screenOffset.dy;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist <= badgeHitRadiusPx && dist < closestDist) {
        closestDist = dist;
        closestBadge = alert;
      }
    }
    if (closestBadge != null) return closestBadge;

    // 2. 次优先检测多边形面
    for (final alert in alerts.reversed) {
      if (alert.containsLocation(tapLatLng)) return alert;
    }

    return null;
  }
}



class _WeatherAlertPolygonPainter extends CustomPainter {
  // Each ring retains only its latest projection; old snapshots remain collectable.
  static final _projectedRings = Expando<
      ({double zoom, Object crs, Path path, Rect bounds})>();
  final List<WeatherAlertMapItem> alerts;
  final MapCamera camera;
  final String? selectedAlertId;

  _WeatherAlertPolygonPainter({
    required this.alerts,
    required this.camera,
    this.selectedAlertId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (alerts.isEmpty) return;
    final origin = camera.pixelOrigin;
    final viewport = (Offset.zero & size).shift(origin).inflate(3);
    canvas.save();
    canvas.translate(-origin.dx, -origin.dy);

    for (final alert in alerts) {
      if (alert.polygons.isEmpty) continue;
      final isSelected = alert.id == selectedAlertId;
      final levelColor = alert.levelColor;

      final fillPaint = Paint()
        ..color = isSelected
            ? levelColor.withValues(alpha: 0.42)
            : levelColor.withValues(alpha: 0.22)
        ..style = PaintingStyle.fill;

      final strokePaint = Paint()
        ..color = isSelected
            ? Colors.white
            : levelColor.withValues(alpha: 0.85)
        ..strokeWidth = isSelected ? 2.5 : 1.2
        ..style = PaintingStyle.stroke;

      for (final polygon in alert.polygons) {
        if (polygon.length < 3) continue;

        var projected = _projectedRings[polygon];
        if (projected == null || projected.zoom != camera.zoom ||
            projected.crs != camera.crs) {
          final path = Path();
          for (var i = 0; i < polygon.length; i++) {
            final px = camera.projectAtZoom(polygon[i], camera.zoom);
            if (i == 0) {
              path.moveTo(px.dx, px.dy);
            } else {
              path.lineTo(px.dx, px.dy);
            }
          }
          path.close();
          projected = (zoom: camera.zoom, crs: camera.crs,
              path: path, bounds: path.getBounds());
          _projectedRings[polygon] = projected;
        }
        if (!viewport.overlaps(projected.bounds)) continue;
        canvas.drawPath(projected.path, fillPaint);
        canvas.drawPath(projected.path, strokePaint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WeatherAlertPolygonPainter oldDelegate) {
    return oldDelegate.selectedAlertId != selectedAlertId ||
        oldDelegate.camera != camera ||
        oldDelegate.alerts != alerts;
  }
}

class _WeatherAlertSingleBadgePainter extends CustomPainter {
  final WeatherAlertMapItem alert;
  final double scale;
  final bool isSelected;

  _WeatherAlertSingleBadgePainter({
    required this.alert,
    required this.scale,
    required this.isSelected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    _drawStandardCmaAlertBadge(
      canvas,
      cx,
      cy,
      alert,
      scale,
      isSelected: isSelected,
    );
  }

  @override
  bool shouldRepaint(covariant _WeatherAlertSingleBadgePainter oldDelegate) {
    return oldDelegate.alert != alert ||
        oldDelegate.scale != scale ||
        oldDelegate.isSelected != isSelected;
  }

  /// 绘制国家标准 GB/T 28564-2012 40×36 四宫格气象灾害预警徽章
  static void _drawStandardCmaAlertBadge(
    Canvas canvas,
    double cx,
    double cy,
    WeatherAlertMapItem alert,
    double scale, {
    bool isSelected = false,
  }) {
    final w = 40.0 * scale;
    final h = 36.0 * scale;
    final rect = Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(3.0 * scale));

    final levelColor = alert.levelColor;
    final textColor = alert.onLevelTextColor;
    final frameBorderColor = isSelected ? Colors.white : const Color(0xFF3F444E);

    // 1. 整体投影阴影（选中时高亮光晕）
    final shadowPaint = Paint()
      ..color = isSelected
          ? levelColor.withValues(alpha: 0.8)
          : Colors.black.withValues(alpha: 0.5)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, (isSelected ? 6.0 : 2.5) * scale);
    canvas.drawRRect(rrect.shift(Offset(0, (isSelected ? 0 : 1.2) * scale)), shadowPaint);

    // 2. 切割圆角区域并在内部绘制 4 个象限
    canvas.save();
    canvas.clipRRect(rrect);

    final splitX = rect.left + w * 0.52;
    final splitY = rect.top + h * 0.65;

    // 【象限 1：左上 - 图形符号区（浅银灰色背景）】
    final q1Rect = Rect.fromLTRB(rect.left, rect.top, splitX, splitY);
    final q1Paint = Paint()..color = const Color(0xFFE2E4E8);
    canvas.drawRect(q1Rect, q1Paint);

    // 绘制灾害几何图形符号
    _drawHazardSymbol(canvas, q1Rect, alert.signalType, levelColor, scale);

    // 【象限 2：右上 - 竖排中文名称区（等级色背景）】
    final q2Rect = Rect.fromLTRB(splitX, rect.top, rect.right, splitY);
    final q2Paint = Paint()..color = levelColor;
    canvas.drawRect(q2Rect, q2Paint);

    // 绘制竖排中文（如 大/雾、暴/雨、雷/电）
    final chars = alert.verticalChineseChars;
    final charCount = chars.length;
    final charFontSize = (charCount <= 2 ? 8.8 : 7.2) * scale;
    final charStyle = TextStyle(
      color: textColor,
      fontSize: charFontSize,
      fontWeight: FontWeight.w900,
      fontFamily: 'MPLUSRounded1c',
      fontFamilyFallback: const ['Microsoft YaHei', 'PingFang SC', 'sans-serif'],
      height: 1.05,
    );

    for (var i = 0; i < charCount; i++) {
      final span = TextSpan(text: chars[i], style: charStyle);
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr)..layout();
      final charY = q2Rect.top + (q2Rect.height / (charCount + 1)) * (i + 1) - tp.height / 2;
      tp.paint(canvas, Offset(q2Rect.center.dx - tp.width / 2, charY));
      tp.dispose();
    }

    // 【象限 3：左下 - 单字等级区（等级色背景）】
    final q3Rect = Rect.fromLTRB(rect.left, splitY, splitX * 0.95 + rect.left * 0.05, rect.bottom);
    final q3Paint = Paint()..color = levelColor;
    canvas.drawRect(q3Rect, q3Paint);

    final levelSpan = TextSpan(
      text: alert.levelSingleChar,
      style: TextStyle(
        color: textColor,
        fontSize: 7.8 * scale,
        fontWeight: FontWeight.w900,
        fontFamily: 'MPLUSRounded1c',
        fontFamilyFallback: const ['Microsoft YaHei', 'PingFang SC', 'sans-serif'],
      ),
    );
    final levelTp = TextPainter(text: levelSpan, textDirection: TextDirection.ltr)..layout();
    levelTp.paint(
      canvas,
      Offset(q3Rect.center.dx - levelTp.width / 2, q3Rect.center.dy - levelTp.height / 2),
    );
    levelTp.dispose();

    // 【象限 4：右下 - 英文全称区（等级色背景）】
    final q4Rect = Rect.fromLTRB(q3Rect.right, splitY, rect.right, rect.bottom);
    final q4Paint = Paint()..color = levelColor;
    canvas.drawRect(q4Rect, q4Paint);

    final engText = alert.englishName;
    final engFontSize = (engText.length > 8 ? 4.6 : 5.4) * scale;
    final engSpan = TextSpan(
      text: engText,
      style: TextStyle(
        color: textColor,
        fontSize: engFontSize,
        fontWeight: FontWeight.w900,
        fontFamily: 'JetBrainsMono',
        fontFamilyFallback: const ['sans-serif'],
        letterSpacing: -0.2,
      ),
    );
    final engTp = TextPainter(text: engSpan, textDirection: TextDirection.ltr)..layout();
    engTp.paint(
      canvas,
      Offset(q4Rect.center.dx - engTp.width / 2, q4Rect.center.dy - engTp.height / 2),
    );
    engTp.dispose();

    // 绘制内部分割线
    final gridLinePaint = Paint()
      ..color = frameBorderColor
      ..strokeWidth = (isSelected ? 1.4 : 1.0) * scale
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(splitX, rect.top), Offset(splitX, splitY), gridLinePaint);
    canvas.drawLine(Offset(rect.left, splitY), Offset(rect.right, splitY), gridLinePaint);
    canvas.drawLine(Offset(q3Rect.right, splitY), Offset(q3Rect.right, rect.bottom), gridLinePaint);

    canvas.restore();

    // 3. 绘制外部边框
    final framePaint = Paint()
      ..color = frameBorderColor
      ..strokeWidth = (isSelected ? 2.0 : 1.3) * scale
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(rrect, framePaint);
  }

  /// 绘制气象国标几何图案符号
  static void _drawHazardSymbol(
    Canvas canvas,
    Rect bounds,
    String type,
    Color levelColor,
    double scale,
  ) {
    final cx = bounds.center.dx;
    final cy = bounds.center.dy;
    final symbolPaint = Paint()
      ..color = levelColor
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;

    if (type.contains('雾') || type.contains('霾')) {
      // 大雾/霾：3 条水平圆角横杠（完全对齐国标与截图）
      final barW = 12.0 * scale;
      final barH = 2.4 * scale;
      final barGap = 1.8 * scale;
      final totalH = 3 * barH + 2 * barGap;
      final startY = cy - totalH / 2;

      for (var i = 0; i < 3; i++) {
        final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - barW / 2, startY + i * (barH + barGap), barW, barH),
          Radius.circular(1.2 * scale),
        );
        canvas.drawRRect(r, symbolPaint);
      }
    } else if (type.contains('雷') || type.contains('闪电')) {
      // 雷电：闪电折线
      final boltPath = ui.Path()
        ..moveTo(cx + 1.5 * scale, cy - 7.5 * scale)
        ..lineTo(cx - 4.5 * scale, cy + 0.5 * scale)
        ..lineTo(cx - 0.5 * scale, cy + 0.5 * scale)
        ..lineTo(cx - 3.5 * scale, cy + 8.0 * scale)
        ..lineTo(cx + 4.5 * scale, cy - 0.5 * scale)
        ..lineTo(cx + 0.5 * scale, cy - 0.5 * scale)
        ..close();
      canvas.drawPath(boltPath, symbolPaint);
    } else if (type.contains('雨')) {
      // 暴雨/大雨：雨云 + 雨滴
      final cloudPath = ui.Path()
        ..addOval(Rect.fromCircle(center: Offset(cx - 2.5 * scale, cy - 2.5 * scale), radius: 3.5 * scale))
        ..addOval(Rect.fromCircle(center: Offset(cx + 2.5 * scale, cy - 2.0 * scale), radius: 4.2 * scale))
        ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 5.5 * scale, cy - 3.0 * scale, 11.0 * scale, 4.5 * scale),
          Radius.circular(2.0 * scale),
        ));
      canvas.drawPath(cloudPath, symbolPaint);

      // 下方雨滴线
      final dropPaint = Paint()
        ..color = levelColor
        ..strokeWidth = 1.3 * scale
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(cx - 3.5 * scale, cy + 3.0 * scale), Offset(cx - 4.5 * scale, cy + 6.5 * scale), dropPaint);
      canvas.drawLine(Offset(cx, cy + 3.0 * scale), Offset(cx - 1.0 * scale, cy + 6.5 * scale), dropPaint);
      canvas.drawLine(Offset(cx + 3.5 * scale, cy + 3.0 * scale), Offset(cx + 2.5 * scale, cy + 6.5 * scale), dropPaint);
    } else if (type.contains('风') || type.contains('台风')) {
      // 大风/台风：风向流线
      final windPaint = Paint()
        ..color = levelColor
        ..strokeWidth = 1.4 * scale
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(cx - 5.5 * scale, cy - 3.5 * scale), Offset(cx + 4.0 * scale, cy - 3.5 * scale), windPaint);
      canvas.drawLine(Offset(cx - 4.0 * scale, cy), Offset(cx + 5.5 * scale, cy), windPaint);
      canvas.drawLine(Offset(cx - 5.5 * scale, cy + 3.5 * scale), Offset(cx + 2.0 * scale, cy + 3.5 * scale), windPaint);
    } else if (type.contains('雪') || type.contains('寒潮') || type.contains('结冰') || type.contains('霜冻')) {
      // 雪/结冰：六角雪花
      final snowPaint = Paint()
        ..color = levelColor
        ..strokeWidth = 1.3 * scale
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      for (var i = 0; i < 3; i++) {
        final rad = i * math.pi / 3;
        final cosV = math.cos(rad) * 6.0 * scale;
        final sinV = math.sin(rad) * 6.0 * scale;
        canvas.drawLine(Offset(cx - cosV, cy - sinV), Offset(cx + cosV, cy + sinV), snowPaint);
      }
    } else if (type.contains('火')) {
      // 火险：火焰
      final firePath = ui.Path()
        ..moveTo(cx, cy - 7.0 * scale)
        ..quadraticBezierTo(cx + 5.5 * scale, cy - 1.0 * scale, cx + 4.5 * scale, cy + 5.0 * scale)
        ..quadraticBezierTo(cx, cy + 7.5 * scale, cx - 4.5 * scale, cy + 5.0 * scale)
        ..quadraticBezierTo(cx - 5.5 * scale, cy - 1.0 * scale, cx, cy - 7.0 * scale)
        ..close();
      canvas.drawPath(firePath, symbolPaint);
    } else {
      // 通用警报：圆角感叹号
      canvas.drawCircle(Offset(cx, cy + 4.0 * scale), 1.3 * scale, symbolPaint);
      final exR = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 1.2 * scale, cy - 6.0 * scale, 2.4 * scale, 7.5 * scale),
        Radius.circular(1.0 * scale),
      );
      canvas.drawRRect(exR, symbolPaint);
    }
  }

}

/// 预警详细信息浮动卡片（高质感毛玻璃风格）
class _WeatherAlertPopupCard extends StatefulWidget {
  final WeatherAlertMapItem alert;
  final VoidCallback onClose;

  const _WeatherAlertPopupCard({
    required this.alert,
    required this.onClose,
  });

  @override
  State<_WeatherAlertPopupCard> createState() => _WeatherAlertPopupCardState();
}

class _WeatherAlertPopupCardState extends State<_WeatherAlertPopupCard> {
  late Future<WeatherAlertDetail?> _detailFuture;
  bool _isCloseHovered = false;
  bool _isCopyHovered = false;
  bool _isDetailHovered = false;

  @override
  void initState() {
    super.initState();
    _detailFuture = ChinaWeatherAlertMapService().fetchAlertDetail(widget.alert.fileId);
  }

  @override
  void didUpdateWidget(covariant _WeatherAlertPopupCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.alert.fileId != widget.alert.fileId) {
      _detailFuture = ChinaWeatherAlertMapService().fetchAlertDetail(widget.alert.fileId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final alert = widget.alert;
    final levelColor = alert.levelColor;

    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              // 统一通透毛玻璃底色与精细半透描边
              color: const Color(0x990F1422),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.all(14),
            child: FutureBuilder<WeatherAlertDetail?>(
              future: _detailFuture,
              builder: (context, snapshot) {
                final detail = snapshot.data;
                final content = detail?.issueContent.isNotEmpty == true
                    ? detail!.issueContent
                    : alert.title;
                final timeText = detail?.issueTime.isNotEmpty == true
                    ? detail!.issueTime
                    : '最新生效中';
                final isLoading =
                    snapshot.connectionState == ConnectionState.waiting;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 头部栏：等级标签 + 地区 + 高灵敏度大触控关闭按键
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3.5,
                          ),
                          decoration: BoxDecoration(
                            color: levelColor.withValues(alpha: 0.20),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: levelColor.withValues(alpha: 0.70),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            '${alert.signalType} · ${alert.signalLevel}',
                            style: TextStyle(
                              color: levelColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            alert.areaName,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // 独立高灵敏关闭按键（30x30 大点击命中区）
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onEnter: (_) => setState(() => _isCloseHovered = true),
                          onExit: (_) => setState(() => _isCloseHovered = false),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.onClose,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: _isCloseHovered
                                    ? Colors.white.withValues(alpha: 0.25)
                                    : Colors.white.withValues(alpha: 0.09),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _isCloseHovered
                                      ? Colors.white.withValues(alpha: 0.45)
                                      : Colors.white.withValues(alpha: 0.18),
                                  width: 0.8,
                                ),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 时间信息行
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          size: 12.5,
                          color: Colors.white54,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '发布时间：$timeText',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11.5,
                          ),
                        ),
                        if (isLoading) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: levelColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    // 细分隔线
                    Container(
                      height: 0.8,
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                    const SizedBox(height: 10),
                    // 预警完整正文（无多余嵌套容器，直接呈现完整文字）
                    Container(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: SelectableText(
                          content,
                          style: const TextStyle(
                            color: Color(0xFFF1F5F9),
                            fontSize: 13,
                            height: 1.52,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                    if (detail?.relieveTime.isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.timer_off_outlined,
                            size: 12,
                            color: Colors.white38,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '预计解除：${detail!.relieveTime}',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    // 底部操作按钮栏
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onEnter: (_) => setState(() => _isCopyHovered = true),
                          onExit: (_) => setState(() => _isCopyHovered = false),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              final messenger = ScaffoldMessenger.maybeOf(context);
                              final textToCopy = detail?.issueContent.isNotEmpty == true
                                  ? detail!.issueContent
                                  : alert.title;
                              Clipboard.setData(ClipboardData(text: textToCopy));
                              messenger?.showSnackBar(
                                const SnackBar(
                                  content: Text('预警信息已复制到剪贴板'),
                                  duration: Duration(seconds: 2),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _isCopyHovered
                                    ? Colors.white.withValues(alpha: 0.16)
                                    : Colors.white.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _isCopyHovered
                                      ? Colors.white.withValues(alpha: 0.30)
                                      : Colors.white.withValues(alpha: 0.14),
                                  width: 0.8,
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.content_copy_rounded,
                                    size: 12,
                                    color: Colors.white70,
                                  ),
                                  SizedBox(width: 5),
                                  Text(
                                    '复制内容',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onEnter: (_) => setState(() => _isDetailHovered = true),
                          onExit: (_) => setState(() => _isDetailHovered = false),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () async {
                              final url = detail?.detailWebUrl ??
                                  'http://www.weather.com.cn/alarm/newalarmcontent.shtml?file=${alert.fileId}';
                              final uri = Uri.parse(url);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _isDetailHovered
                                    ? levelColor.withValues(alpha: 0.30)
                                    : levelColor.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _isDetailHovered
                                      ? levelColor.withValues(alpha: 0.90)
                                      : levelColor.withValues(alpha: 0.65),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.open_in_new_rounded,
                                    size: 12,
                                    color: levelColor,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '官方详情 >',
                                    style: TextStyle(
                                      color: levelColor,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
