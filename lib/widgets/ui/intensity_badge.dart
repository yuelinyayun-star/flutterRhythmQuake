import 'package:flutter/material.dart';

/// 烈度徽章组件
/// 
/// 该组件用于显示日本气象厅(JMA)格式的烈度等级徽章。
/// 根据烈度等级显示对应的背景颜色。
/// 
/// 主要功能：
/// - 显示烈度等级文本
/// - 根据烈度等级设置背景颜色
/// - 支持自定义尺寸
/// 
/// JMA烈度颜色方案：
/// - 震度1: 灰色
/// - 震度2: 蓝色
/// - 震度3: 绿色
/// - 震度4: 黄色
/// - 震度5弱/5强: 橙色
/// - 震度6弱/6强: 红色
/// - 震度7: 紫色
class IntensityBadge extends StatelessWidget {
  /// 烈度等级文本
  /// 如 "1", "2", "3", "4", "5-", "5+", "6-", "6+", "7"
  final String intensity;
  
  /// 徽章尺寸
  /// 默认为40像素
  final double size;

  const IntensityBadge({super.key, required this.intensity, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _getBackgroundColor(intensity),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          intensity,
          style: TextStyle(fontFamily: 'JetBrainsMono',
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  /// 根据烈度等级获取背景颜色
  /// 
  /// [intensity] 烈度等级文本
  /// 返回对应的背景颜色
  Color _getBackgroundColor(String intensity) {
    switch (intensity) {
      case '1': return Color(0xFF808080);
      case '2': return Color(0xFF4B7BB1);
      case '3': return Color(0xFF2E9B5F);
      case '4': return Color(0xFFEBC033);
      case '5-': case '5+': return Color(0xFFE67E22);
      case '6-': case '6+': return Color(0xFFE74C3C);
      case '7': return Color(0xFF8E44AD);
      default: return Color(0xFF34495E);
    }
  }
}
