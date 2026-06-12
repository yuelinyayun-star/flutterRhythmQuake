/// 烈度主题配置
///
/// 本模块定义了地震烈度的颜色映射和行为建议。
/// 用于在 UI 中根据烈度等级显示对应的颜色和行动建议。
///
/// ## 烈度标准
///
/// 本应用使用中国地震烈度标准 (GB/T 17742-2020)：
/// - I-II 度: 无感-微感
/// - III-IV 度: 轻度有感
/// - V-VI 度: 中度有感
/// - VII-VIII 度: 强烈有感
/// - IX-X 度: 破坏性
/// - XI-XII 度: 毁灭性

import 'package:flutter/material.dart';

/// 烈度主题类
///
/// 提供烈度相关的颜色和文本配置。
class IntensityTheme {
  /// 根据烈度值获取对应颜色
  ///
  /// 颜色映射规则：
  /// - < 1.0: 灰色 (无感)
  /// - 1.0-2.9: 绿色 (轻微)
  /// - 3.0-4.9: 黄色 (中等)
  /// - 5.0-6.9: 橙色 (强烈)
  /// - 7.0-8.9: 红色 (严重)
  /// - >= 9.0: 紫色 (毁灭性)
  ///
  /// 参数：
  /// - [intensity]: 烈度值 (通常为 1-12)
  ///
  /// 返回：
  /// - 对应的 Material Color
  static Color getColor(double intensity) {
    if (intensity < 1.0) return Colors.grey;
    if (intensity < 3.0) return Colors.green;
    if (intensity < 5.0) return Colors.yellow;
    if (intensity < 7.0) return Colors.orange;
    if (intensity < 9.0) return Colors.red;
    return Colors.purple;
  }

  /// 根据烈度值获取行动建议
  ///
  /// 建议内容基于中国地震局发布的地震应急指南。
  ///
  /// 参数：
  /// - [intensity]: 烈度值
  ///
  /// 返回：
  /// - 对应的行动建议文本
  static String getAction(double intensity) {
    if (intensity < 3.0) return "轻微震感，请保持镇静。";
    if (intensity < 5.0) return "震感强烈，请寻找安全避险处。";
    if (intensity < 7.0) return "地震严重，请远离易倒塌物体！";
    return "破坏性地震，请立即避险！";
  }
}
