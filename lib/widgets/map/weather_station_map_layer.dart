import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/sources/cma_local_weather_service.dart';

/// 气象站展示模式
enum WeatherStationDisplayMode {
  /// 综合模式：降雨优先（有降雨测站突出降雨量级，无雨测站展示气温）
  auto,

  /// 降水雨量模式：专属雨量色阶，高亮展示小雨/中雨/大雨/暴雨等降水
  rain,

  /// 气温模式：全国气温冷暖色阶与温度数值
  temperature,

  /// 风向风力模式：风向旋转指针与风力等级
  wind;

  static WeatherStationDisplayMode fromKey(String? key) {
    switch (key?.trim().toLowerCase()) {
      case 'rain':
        return WeatherStationDisplayMode.rain;
      case 'temperature':
      case 'temp':
        return WeatherStationDisplayMode.temperature;
      case 'wind':
        return WeatherStationDisplayMode.wind;
      case 'auto':
      default:
        return WeatherStationDisplayMode.auto;
    }
  }

  String get key {
    switch (this) {
      case WeatherStationDisplayMode.auto:
        return 'auto';
      case WeatherStationDisplayMode.rain:
        return 'rain';
      case WeatherStationDisplayMode.temperature:
        return 'temperature';
      case WeatherStationDisplayMode.wind:
        return 'wind';
    }
  }

  String get label {
    switch (this) {
      case WeatherStationDisplayMode.auto:
        return '综合(降雨优先)';
      case WeatherStationDisplayMode.rain:
        return '降水雨量';
      case WeatherStationDisplayMode.temperature:
        return '气温实况';
      case WeatherStationDisplayMode.wind:
        return '风向风力';
    }
  }
}

/// 高性能气象站实况地图图层
///
/// 采用单 Canvas 批处理绘制 + 视口空间剔除 (Viewport Culling) + LOD 视距分级自适应渲染，
/// 配合后台 Worker 批量防抖预加载，彻底消除缩放卡顿，60fps/120fps 丝滑流畅。
class WeatherStationMapLayer extends StatefulWidget {
  final List<CmaStationSummary> stations;
  final WeatherStationDisplayMode mode;

  const WeatherStationMapLayer({
    super.key,
    required this.stations,
    this.mode = WeatherStationDisplayMode.auto,
  });

  @override
  State<WeatherStationMapLayer> createState() => _WeatherStationMapLayerState();
}

class _WeatherStationMapLayerState extends State<WeatherStationMapLayer> {
  Timer? _debounceTimer;

  void _scheduleViewportPreload(MapCamera camera) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      // 预取视口内及周边扩展区域站点，用户放大或移动前数据已在内存就绪
      final bounds = camera.visibleBounds;
      final visibleIds = widget.stations
          .where((stn) => bounds.contains(LatLng(stn.latitude, stn.longitude)))
          .map((stn) => stn.id)
          .toList();

      if (visibleIds.isNotEmpty) {
        CmaLocalWeatherService.preloadStations(visibleIds);
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stations.isEmpty) return const SizedBox.shrink();
    final camera = MapCamera.of(context);
    _scheduleViewportPreload(camera);

    return ValueListenableBuilder<Map<String, CmaLocalWeatherObservation>>(
      valueListenable: CmaLocalWeatherService.stationObservationMapNotifier,
      builder: (context, observations, _) {
        return MobileLayerTransformer(
          child: RepaintBoundary(
            child: CustomPaint(
              size: camera.size,
              isComplex: true,
              willChange: false,
              painter: _WeatherStationPainter(
                camera: camera,
                stations: widget.stations,
                mode: widget.mode,
                observations: observations,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WeatherStationPainter extends CustomPainter {
  final MapCamera camera;
  final List<CmaStationSummary> stations;
  final WeatherStationDisplayMode mode;
  final Map<String, CmaLocalWeatherObservation> observations;

  _WeatherStationPainter({
    required this.camera,
    required this.stations,
    required this.mode,
    required this.observations,
  });

  // === CMA 中国气象局官方业务标准配色 (GB/T 28592-2012 / NMC 色标体系) ===
  static const Color _cNoRain = Color(0xFF78909C); // 无降水 (蓝灰底色)
  static const Color _cRain1 = Color(0xFFA6F28F); // 小雨/阵雨 (0.1~9.9mm: 官方标准浅翠绿)
  static const Color _cRain2 = Color(0xFF3DBA3D); // 中雨 (10~24.9mm: 官方标准深绿)
  static const Color _cRain3 = Color(0xFF61B8FF); // 大雨 (25~49.9mm: 官方标准天蓝)
  static const Color _cRain4 = Color(0xFF0000FF); // 暴雨 (50~99.9mm: 官方标准纯深蓝)
  static const Color _cRain5 = Color(0xFFFA00FA); // 大暴雨 (100~249.9mm: 官方标准洋红亮紫)
  static const Color _cRain6 = Color(0xFF700000); // 特大暴雨 (>=250mm: 官方标准褐红)

  static Color _getRainColor(int severity) {
    switch (severity) {
      case 5:
        return _cRain6; // 特大暴雨
      case 4:
        return _cRain5; // 大暴雨 / 暴雨
      case 3:
        return _cRain3; // 大雨
      case 2:
        return _cRain2; // 中雨
      case 1:
        return _cRain1; // 小雨 / 阵雨
      default:
        return _cNoRain;
    }
  }

  /// CMA 中央气象台全国气温实况标准色标
  static Color _getTemperatureColor(double? temp) {
    if (temp == null) return _cNoRain;
    if (temp <= -20) return const Color(0xFF1E3CFF); // 极寒 (< -20℃: 深蓝紫)
    if (temp <= -10) return const Color(0xFF0078FF); // 严寒 (-20~-10℃: 深蓝)
    if (temp <= 0) return const Color(0xFF00D2FF); // 微寒 (-10~0℃: 天蓝)
    if (temp <= 10) return const Color(0xFF00FFC8); // 凉爽 (0~10℃: 浅青绿)
    if (temp <= 16) return const Color(0xFF70E000); // 温和 (10~16℃: 黄绿)
    if (temp <= 20) return const Color(0xFFFFFF00); // 舒适 (16~20℃: 柠檬黄)
    if (temp <= 24) return const Color(0xFFFFC800); // 温暖 (20~24℃: 金黄)
    if (temp <= 28) return const Color(0xFFFF9600); // 较热 (24~28℃: 橙色)
    if (temp <= 32) return const Color(0xFFFF6400); // 炎热 (28~32℃: 橙红)
    if (temp <= 35) return const Color(0xFFFF0000); // 酷热 (32~35℃: 正红)
    if (temp <= 37) return const Color(0xFFC80000); // 高温黄警 (35~37℃: 深红)
    if (temp <= 40) return const Color(0xFF960064); // 高温橙警 (37~40℃: 洋红)
    return const Color(0xFF640064); // 高温红警 (>=40℃: 深褐紫)
  }

  /// CMA 蒲福风级官方预警配色
  static Color _getWindColor(String scale) {
    final s = scale.trim();
    if (s.contains('微风') || s.contains('1级') || s.contains('2级')) {
      return const Color(0xFF81C784); // 0~2级: 微风浅绿
    }
    if (s.contains('3') || s.contains('4')) {
      return const Color(0xFF4DB6AC); // 3~4级: 清风青绿
    }
    if (s.contains('5') || s.contains('6')) {
      return const Color(0xFFFFB74D); // 5~6级: 强风黄橙
    }
    if (s.contains('7') || s.contains('8')) {
      return const Color(0xFFFF7043); // 7~8级: 大风橙红
    }
    if (s.contains('9') || s.contains('10')) {
      return const Color(0xFFE53935); // 9~10级: 狂风鲜红
    }
    if (s.contains('11') || s.contains('12') || s.contains('13') || s.contains('14')) {
      return const Color(0xFF880E4F); // 11级+: 飓风紫红
    }
    return const Color(0xFF78909C);
  }

  static String _windScaleToSpeedText(String scale) {
    final s = scale.trim();
    if (s.isEmpty) return '0.0m/s';
    if (s.contains('微风') ||
        s.contains('0级') ||
        s.contains('1级') ||
        s.contains('2级') ||
        s.contains('1-2')) {
      return '1.5m/s';
    }
    if (s.contains('3-4')) return '5.5m/s';
    if (s.contains('3级')) return '4.4m/s';
    if (s.contains('4-5')) return '8.0m/s';
    if (s.contains('4级')) return '6.7m/s';
    if (s.contains('5-6')) return '10.8m/s';
    if (s.contains('5级')) return '9.3m/s';
    if (s.contains('6-7')) return '13.9m/s';
    if (s.contains('6级')) return '12.3m/s';
    if (s.contains('7-8')) return '17.2m/s';
    if (s.contains('7级')) return '15.5m/s';
    if (s.contains('8-9')) return '20.8m/s';
    if (s.contains('8级')) return '18.9m/s';
    if (s.contains('9-10')) return '24.5m/s';
    if (s.contains('9级')) return '22.6m/s';
    if (s.contains('10级')) return '26.4m/s';
    if (s.contains('11级')) return '30.5m/s';
    if (s.contains('12级')) return '34.8m/s';

    final match = RegExp(r'(\d+)').firstMatch(s);
    if (match != null) {
      final grade = int.tryParse(match.group(1) ?? '') ?? 0;
      if (grade <= 2) return '1.5m/s';
      if (grade == 3) return '4.4m/s';
      if (grade == 4) return '6.7m/s';
      if (grade == 5) return '9.3m/s';
      if (grade == 6) return '12.3m/s';
      if (grade == 7) return '15.5m/s';
      if (grade >= 8) return '${(15.0 + (grade - 7) * 2.5).toStringAsFixed(1)}m/s';
    }
    return '0.0m/s';
  }

  static double? _windDirectionToAngle(String dir) {
    final d = dir.trim();
    if (d.contains('北风') && !d.contains('东') && !d.contains('西')) return 0.0;
    if (d.contains('东北')) return math.pi * 0.25;
    if (d.contains('东风')) return math.pi * 0.5;
    if (d.contains('东南')) return math.pi * 0.75;
    if (d.contains('南风')) return math.pi;
    if (d.contains('西南')) return math.pi * 1.25;
    if (d.contains('西风')) return math.pi * 1.5;
    if (d.contains('西北')) return math.pi * 1.75;
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final worldWidth = camera.getWorldWidthAtZoom();
    final origin = camera.pixelOrigin;
    final visible = camera.pixelBounds.inflate(36);
    final fillPaint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()..style = PaintingStyle.stroke;
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    final zoom = camera.zoom;
    final isDistant = zoom < 6.2;
    final isMedium = zoom >= 6.2 && zoom < 9.2;
    final isClose = zoom >= 9.2;

    for (final stn in stations) {
      final projected = camera.projectAtZoom(LatLng(stn.latitude, stn.longitude));
      _drawStation(
        canvas: canvas,
        projected: projected,
        origin: origin,
        visible: visible,
        fillPaint: fillPaint,
        strokePaint: strokePaint,
        textPainter: textPainter,
        stn: stn,
        isDistant: isDistant,
        isMedium: isMedium,
        isClose: isClose,
      );

      if (worldWidth > 0) {
        // 世界左右跨界平移处理
        for (double shift = -worldWidth;; shift -= worldWidth) {
          final shifted = Offset(projected.dx + shift, projected.dy);
          if (!visible.contains(shifted)) break;
          _drawStation(
            canvas: canvas,
            projected: shifted,
            origin: origin,
            visible: visible,
            fillPaint: fillPaint,
            strokePaint: strokePaint,
            textPainter: textPainter,
            stn: stn,
            isDistant: isDistant,
            isMedium: isMedium,
            isClose: isClose,
          );
        }
        for (double shift = worldWidth;; shift += worldWidth) {
          final shifted = Offset(projected.dx + shift, projected.dy);
          if (!visible.contains(shifted)) break;
          _drawStation(
            canvas: canvas,
            projected: shifted,
            origin: origin,
            visible: visible,
            fillPaint: fillPaint,
            strokePaint: strokePaint,
            textPainter: textPainter,
            stn: stn,
            isDistant: isDistant,
            isMedium: isMedium,
            isClose: isClose,
          );
        }
      }
    }
  }

  void _drawStation({
    required Canvas canvas,
    required Offset projected,
    required Offset origin,
    required Rect visible,
    required Paint fillPaint,
    required Paint strokePaint,
    required TextPainter textPainter,
    required CmaStationSummary stn,
    required bool isDistant,
    required bool isMedium,
    required bool isClose,
  }) {
    if (!visible.contains(projected)) return;
    final pos = projected - origin;

    final isRaining = stn.isRaining;
    final rainSev = stn.rainSeverity;

    // 确定主体颜色
    Color baseColor;
    switch (mode) {
      case WeatherStationDisplayMode.rain:
        baseColor = _getRainColor(rainSev);
        break;
      case WeatherStationDisplayMode.temperature:
        baseColor = _getTemperatureColor(stn.temperature);
        break;
      case WeatherStationDisplayMode.wind:
        baseColor = _getWindColor(stn.windScale);
        break;
      case WeatherStationDisplayMode.auto:
      default:
        baseColor = isRaining ? _getRainColor(rainSev) : _getTemperatureColor(stn.temperature);
        break;
    }

    if (isDistant) {
      // 1. 远景极简点阵：全部测站点正常 100% 不透明度清晰呈现
      if (isRaining) {
        // 微型光晕边缘 (半径 3.0px)
        strokePaint
          ..color = baseColor.withValues(alpha: 0.32)
          ..strokeWidth = 0.7;
        canvas.drawCircle(pos, 3.0, strokePaint);
      }

      // 主体色点 (100% 正常不透明度)
      fillPaint.color = baseColor;
      canvas.drawCircle(pos, 1.8, fillPaint);
      return;
    }

    final obs = observations[stn.id];
    if (obs == null && (isMedium || isClose)) {
      unawaited(CmaLocalWeatherService.fetchStationObservation(stn.id));
    }

    // 1. 真实降水实测文本（直接使用官方天气现象代码表对应天气 + 真实实测数值，如 "大雨 12.5mm"、"晴 0.0mm"、"多云 0.0mm"）
    final prec = obs?.precipitation;
    final weatherName = stn.weather.isNotEmpty ? stn.weather : '晴';
    final rainAmount = (prec ?? 0.0).toStringAsFixed(1);
    final rainText = '$weatherName ${rainAmount}mm';

    // 2. 真实风速实测文本（风向 + 真实风速数值 + 风力等级 如 "东北风 4.4m/s (3级)"）
    final windDir = obs?.windDirection.isNotEmpty == true ? obs!.windDirection : stn.windDirection;
    final windSpeed = obs?.windSpeed;
    final windScale = obs?.windScale.isNotEmpty == true ? obs!.windScale : stn.windScale;
    final windText = [
      if (windDir.isNotEmpty) windDir else '风向',
      if (windSpeed != null) '${windSpeed.toStringAsFixed(1)}m/s',
      if (windScale.isNotEmpty) '($windScale)',
    ].join(' ');

    // 3. 真实气温数值（纯数值+单位 如 "25.8℃"）
    final tempVal = obs?.temperature ?? stn.temperature;
    final tempText = tempVal != null ? '${tempVal.toStringAsFixed(1)}℃' : '';

    // 中景（Medium LOD）：
    // 1. 胶囊内仅显示对应的实测数值与单位 (如 "12.5mm" / "4.4m/s" / "25.8℃")
    String badgeValueText = '';
    switch (mode) {
      case WeatherStationDisplayMode.rain:
        badgeValueText = '${rainAmount}mm';
        break;
      case WeatherStationDisplayMode.temperature:
        badgeValueText = tempText;
        break;
      case WeatherStationDisplayMode.wind:
        badgeValueText = windSpeed != null
            ? '${windSpeed.toStringAsFixed(1)}m/s'
            : _windScaleToSpeedText(stn.windScale);
        break;
      case WeatherStationDisplayMode.auto:
      default:
        badgeValueText = (isRaining || (prec != null && prec > 0.0))
            ? '${rainAmount}mm'
            : tempText;
        break;
    }

    // 2. 站点下方字幕：显示站点名 + 官方实况天气现象 (如 "诸暨 大雨" / "诸暨 东北风 (3级)")
    String subtitleText = '';
    switch (mode) {
      case WeatherStationDisplayMode.wind:
        subtitleText = [
          stn.name,
          if (windDir.isNotEmpty) windDir,
          if (windScale.isNotEmpty) '($windScale)',
        ].join(' ');
        break;
      case WeatherStationDisplayMode.rain:
      case WeatherStationDisplayMode.temperature:
      case WeatherStationDisplayMode.auto:
      default:
        subtitleText = '${stn.name} $weatherName';
        break;
    }

    if (isMedium || isClose) {
      final dotRadius = isClose ? 4.8 : (isRaining ? 4.2 : 3.4);

      // 绘制圆点
      fillPaint.color = baseColor;
      canvas.drawCircle(pos, dotRadius, fillPaint);
      strokePaint
        ..color = isClose ? Colors.white : Colors.black.withValues(alpha: 0.55)
        ..strokeWidth = isClose ? 1.2 : 1.0;
      canvas.drawCircle(pos, dotRadius, strokePaint);

      // 风向指针
      if (mode == WeatherStationDisplayMode.wind || isRaining || windDir.isNotEmpty) {
        final angle = _windDirectionToAngle(windDir);
        if (angle != null) {
          final pointerLength = isClose ? 7.5 : 6.0;
          final dx = math.sin(angle) * pointerLength;
          final dy = -math.cos(angle) * pointerLength;
          strokePaint
            ..color = baseColor
            ..strokeWidth = isClose ? 1.8 : 1.5;
          canvas.drawLine(pos, Offset(pos.dx + dx, pos.dy + dy), strokePaint);
        }
      }

      if (mode != WeatherStationDisplayMode.auto) {
        // 专项模式（降水/风速/气温）：采用【纯数值胶囊 + 测站正下方居中字幕】样式
        if (badgeValueText.isNotEmpty) {
          final textColor = (isRaining && baseColor.computeLuminance() > 0.5)
              ? const Color(0xFF102027)
              : Colors.white;

          textPainter.text = TextSpan(
            text: badgeValueText,
            style: TextStyle(
              color: textColor,
              fontSize: isClose ? (isRaining ? 10.5 : 10.0) : (isRaining ? 10.0 : 9.5),
              fontWeight: FontWeight.w800,
              height: 1.1,
              shadows: textColor == Colors.white
                  ? const [
                      Shadow(color: Colors.black54, blurRadius: 2.0, offset: Offset(0.5, 0.5)),
                    ]
                  : null,
            ),
          );
          textPainter.textAlign = TextAlign.center;
          textPainter.layout();

          final bgRect = RRect.fromRectAndRadius(
            Rect.fromLTWH(
              pos.dx + (isClose ? 6.0 : 5.0),
              pos.dy - (textPainter.height / 2) - (isClose ? 2.0 : 1.5),
              textPainter.width + (isClose ? 7.0 : 6.0),
              textPainter.height + (isClose ? 4.0 : 3.0),
            ),
            Radius.circular(isClose ? 4.0 : 3.5),
          );
          fillPaint.color = isRaining
              ? baseColor.withValues(alpha: 0.95)
              : (isClose
                  ? Colors.black.withValues(alpha: 0.72)
                  : Colors.black.withValues(alpha: 0.68));
          canvas.drawRRect(bgRect, fillPaint);

          textPainter.paint(
            canvas,
            Offset(pos.dx + (isClose ? 9.5 : 8.0), pos.dy - (textPainter.height / 2)),
          );
        }

        if (subtitleText.isNotEmpty) {
          textPainter.text = TextSpan(
            text: subtitleText,
            style: TextStyle(
              color: Colors.white,
              fontSize: isClose ? 10.0 : 9.5,
              fontWeight: FontWeight.w700,
              height: 1.1,
              shadows: const [
                Shadow(color: Colors.black, blurRadius: 3.0, offset: Offset(0.5, 0.5)),
                Shadow(color: Colors.black87, blurRadius: 4.0, offset: Offset(-0.5, -0.5)),
              ],
            ),
          );
          textPainter.textAlign = TextAlign.center;
          textPainter.layout();

          final subtitleOffset = Offset(
            pos.dx - (textPainter.width / 2),
            pos.dy + dotRadius + (isClose ? 3.5 : 3.0),
          );
          textPainter.paint(canvas, subtitleOffset);
        }
        return;
      }

      // 综合模式（auto）：在第 2 层与第 3 层均展示 4 行完整详细信息卡片
      final spans = <TextSpan>[
        TextSpan(
          text: '${stn.name}\n',
          style: TextStyle(
            color: Colors.white,
            fontSize: isClose ? 11.0 : 10.5,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        // 降水/天气行
        TextSpan(
          text: '$rainText\n',
          style: TextStyle(
            color: isRaining ? baseColor : const Color(0xFF80D8FF),
            fontSize: isClose ? 10.0 : 9.5,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
      ];

      // 气温行（显示真实数值 ℃）
      final tempVal = obs?.temperature ?? stn.temperature;
      if (tempVal != null) {
        spans.add(
          TextSpan(
            text: '${tempVal.toStringAsFixed(1)}℃\n',
            style: TextStyle(
              color: const Color(0xFFFFD54F),
              fontSize: isClose ? 9.5 : 9.0,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        );
      }

      // 风向风速行（显示真实数值 m/s 与风力等级，独立成行）
      final windSpeed = obs?.windSpeed;
      final windScale = obs?.windScale.isNotEmpty == true ? obs!.windScale : stn.windScale;
      if (windDir.isNotEmpty || windSpeed != null || windScale.isNotEmpty) {
        final windParts = <String>[
          if (windDir.isNotEmpty) windDir,
          if (windSpeed != null) '${windSpeed.toStringAsFixed(1)}m/s',
          if (windScale.isNotEmpty) '($windScale)',
        ];
        spans.add(
          TextSpan(
            text: windParts.join(' '),
            style: TextStyle(
              color: const Color(0xFF80CBC4),
              fontSize: isClose ? 9.0 : 8.5,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        );
      }

      textPainter.text = TextSpan(children: spans);
      textPainter.textAlign = TextAlign.left;
      textPainter.layout();

      final badgeRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          pos.dx + (isClose ? 7.0 : 6.0),
          pos.dy - (textPainter.height / 2) - 2.0,
          textPainter.width + 6.0,
          textPainter.height + 4.0,
        ),
        Radius.circular(isClose ? 4.0 : 3.5),
      );

      fillPaint.color = const Color(0xDD1E1E1E);
      canvas.drawRRect(badgeRect, fillPaint);
      strokePaint
        ..color = baseColor.withValues(alpha: 0.8)
        ..strokeWidth = 0.8;
      canvas.drawRRect(badgeRect, strokePaint);

      textPainter.paint(
        canvas,
        Offset(pos.dx + (isClose ? 10.0 : 9.0), pos.dy - (textPainter.height / 2)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WeatherStationPainter oldDelegate) {
    return oldDelegate.camera != camera ||
        oldDelegate.stations != stations ||
        oldDelegate.mode != mode ||
        oldDelegate.observations != observations;
  }
}
