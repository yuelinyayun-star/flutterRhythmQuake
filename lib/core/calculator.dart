import 'dart:math';

/// 地震计算工具类
/// 
/// 该类提供地震相关的物理计算功能。
/// 包括地震波传播计算和距离计算等。
/// 
/// 主要功能：
/// - P波和S波速度常量
/// - 哈弗辛公式计算球面距离
/// - 计算地震发生后流逝的时间
/// 
/// 物理参数说明：
/// - P波(纵波): 速度约6km/s，最先到达，破坏性较小
/// - S波(横波): 速度约3.5km/s，后到达，破坏性强
class QuakeCalculator {
  /// P波(纵波)传播速度
  /// 单位: km/s
  static const double pWaveSpeed = 6.0;
  
  /// S波(横波)传播速度
  /// 单位: km/s
  static const double sWaveSpeed = 3.5;

  /// 使用哈弗辛公式计算球面两点间的大圆距离
  /// 
  /// 该方法考虑了地球曲率，适用于远距离计算。
  /// 
  /// [lat1] 起点纬度
  /// [lon1] 起点经度
  /// [lat2] 终点纬度
  /// [lon2] 终点经度
  /// 
  /// 返回两点间的距离，单位: km
  static double haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const double r = 6371; // 地球平均半径 km
    double dLat = (lat2 - lat1) * pi / 180;
    double dLon = (lon2 - lon1) * pi / 180;
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  /// 计算从地震发生到当前时间的流逝秒数
  /// 
  /// [originTime] 地震发生时间
  /// [now] 当前时间
  /// 
  /// 返回流逝的秒数
  static double getElapsedSeconds(DateTime originTime, DateTime now) {
    return now.difference(originTime).inMilliseconds / 1000.0;
  }
}
