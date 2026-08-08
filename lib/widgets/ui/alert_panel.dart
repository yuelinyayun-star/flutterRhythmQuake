import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/quake_provider.dart';
import '../../models/intensity_theme.dart';
import '../../models/quake_message.dart';

/// 地震预警面板组件
///
/// 该组件负责在检测到地震时显示预警信息面板。
/// 显示预计烈度、倒计时、震源信息等关键预警数据。
///
/// 主要功能：
/// - 显示预计到达烈度
/// - 显示S波到达倒计时
/// - 显示震源位置、震级、深度等信息
/// - 高烈度时闪烁警示
/// - 显示应急行动建议
///
/// 预警逻辑：
/// - 根据震中距离和震级计算预计烈度
/// - 根据距离计算S波到达时间
/// - 地震发生后60秒内显示预警面板
class AlertPanel extends StatefulWidget {
  const AlertPanel({super.key});

  @override
  State<AlertPanel> createState() => _AlertPanelState();
}

class _AlertPanelState extends State<AlertPanel> {
  /// 闪烁动画控制器
  /// 用于高烈度预警时的红色闪烁效果
  final ValueNotifier<double> _flashLevel = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _flashLevel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<QuakeProvider>(
      builder: (context, provider, child) {
        final event = provider.currentEvent;
        if (event == null) {
          _syncFlashController(false);
          return const SizedBox.shrink();
        }

        final int countdown = provider.sCountdown;

        if (countdown < -60) {
          _syncFlashController(false);
          return const SizedBox.shrink();
        }

        final double intensity = provider.estimatedIntensity;
        final Color themeColor = IntensityTheme.getColor(intensity);
        final bool isSerious = intensity >= 5.0;
        _syncFlashController(isSerious);

        return Positioned(
          top: 80,
          left: 20,
          right: 20,
          child: AnimatedBuilder(
            animation: _flashLevel,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: isSerious
                      ? Colors.red.withValues(
                          alpha: _flashLevel.value * 0.8,
                        )
                      : themeColor.withValues(alpha: 0.3),
                ),
                child: child,
              );
            },
            child: Material(
              elevation: 20,
              borderRadius: BorderRadius.circular(14),
              color: const Color(0xFF1A1A1A),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _buildIntensityBadge(intensity, themeColor),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event.location,
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                "M${event.magnitude.toStringAsFixed(1)} · 深度 ${event.depth.round()}km · ${event.source.displayName}",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Divider(color: Colors.white10),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "横波预计 ",
                          style: TextStyle(fontSize: 20, color: Colors.white70),
                        ),
                        const SizedBox(width: 10),
                        _buildCountdownText(countdown, themeColor),
                        const SizedBox(width: 10),
                        const Text(
                          " 秒后抵达",
                          style: TextStyle(fontSize: 20, color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: themeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        IntensityTheme.getAction(intensity),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: themeColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _syncFlashController(bool shouldFlash) {
    final next = shouldFlash ? 1.0 : 0.0;
    if (_flashLevel.value != next) {
      _flashLevel.value = next;
    }
  }

  /// 构建烈度徽章
  ///
  /// 显示预计到达烈度的大号数字
  /// [intensity] 烈度值
  /// [color] 主题颜色
  Widget _buildIntensityBadge(double intensity, Color color) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        intensity >= 0 ? intensity.toStringAsFixed(2) : "?",
        style: const TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }

  /// 构建倒计时文本
  ///
  /// 显示S波到达倒计时的大号数字
  /// [countdown] 倒计时秒数
  /// [color] 主题颜色
  Widget _buildCountdownText(int countdown, Color color) {
    return Text(
      (countdown > 0 ? countdown : 0).toString().padLeft(2, '0'),
      style: TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: 80,
        fontWeight: FontWeight.w900,
        color: color,
        letterSpacing: -2,
      ),
    );
  }
}
