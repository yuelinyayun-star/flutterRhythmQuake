import 'dart:math';
import '../services/sources/nied_monitor.dart';

/// 旧版 JS 载体中的网格搜索震源推算算法
///
/// 代码载体: kotoho7/scratch-realtime-earthquake-viewer-page
/// sb3 过程: `点-震源 距離計算`, `JMA2001距離近似`, `緯度経度で距離km`
///
/// 注意：这里的 Scratch/TurboWarp 只表示公开 JS/SB3 载体，不表示算法归属。
/// 本项目按 JQ/JQuake-style GIF 反解参考来理解这条旧算法。
class HypocenterEstimator {
  /// 震源推算结果
  final double latitude;
  final double longitude;
  final double confidence;

  const HypocenterEstimator({
    required this.latitude,
    required this.longitude,
    this.confidence = 0.0,
  });

  /// 从公开 JS/SB3 载体提取的 188 点扫描线坐标
  /// 数据来源: リアルタイム地震ビューアー v1.6.3
  /// 目标: 受信と検出, 过程: 点-震源 距離計算
  /// 计算: lat = _polyLat(n), lng = 135 + lon_offset/100
  static const List<_ScanPoint> _scanPoints = [
    _ScanPoint(35.0979, 145.84),
    _ScanPoint(35.0979, 145.32),
    _ScanPoint(35.0979, 145.13),
    _ScanPoint(35.0979, 144.32),
    _ScanPoint(35.0979, 143.85),
    _ScanPoint(35.0979, 143.39),
    _ScanPoint(35.0653, 144.11),
    _ScanPoint(35.0979, 145.51),
    _ScanPoint(35.0979, 145.09),
    _ScanPoint(35.0979, 145.07),
    _ScanPoint(35.0979, 144.15),
    _ScanPoint(35.0979, 146.43),
    _ScanPoint(35.0979, 146.01),
    _ScanPoint(35.0979, 145.5),
    _ScanPoint(35.0979, 147.12),
    _ScanPoint(35.0979, 146.33),
    _ScanPoint(35.0979, 145.59),
    _ScanPoint(35.1142, 147.41),
    _ScanPoint(35.0979, 146.6),
    _ScanPoint(35.0979, 148.38),
    _ScanPoint(35.0979, 147.88),
    _ScanPoint(35.1142, 148.46),
    _ScanPoint(35.0653, 146.46),
    _ScanPoint(35.0653, 146.42),
    _ScanPoint(35.0653, 146.91),
    _ScanPoint(35.0979, 144.72),
    _ScanPoint(35.1142, 144.9),
    _ScanPoint(35.0979, 144.93),
    _ScanPoint(35.0979, 144.53),
    _ScanPoint(35.0979, 144.22),
    _ScanPoint(35.0979, 145.82),
    _ScanPoint(35.0979, 145.19),
    _ScanPoint(35.0979, 144.65),
    _ScanPoint(35.0979, 146.06),
    _ScanPoint(35.1142, 145.5),
    _ScanPoint(35.0979, 146.32),
    _ScanPoint(35.0979, 145.82),
    _ScanPoint(35.0979, 145.7),
    _ScanPoint(35.1142, 142.5),
    _ScanPoint(35.1142, 142.06),
    _ScanPoint(35.1468, 142.11),
    _ScanPoint(35.1142, 143.04),
    _ScanPoint(35.1142, 141.1),
    _ScanPoint(35.1142, 140.28),
    _ScanPoint(35.1142, 141.24),
    _ScanPoint(35.1142, 140.28),
    _ScanPoint(35.0816, 139.63),
    _ScanPoint(35.0816, 138.76),
    _ScanPoint(35.0816, 139.18),
    _ScanPoint(35.1142, 141.44),
    _ScanPoint(35.1142, 140.56),
    _ScanPoint(35.1142, 141.49),
    _ScanPoint(35.1142, 140.57),
    _ScanPoint(35.1142, 139.7),
    _ScanPoint(35.1142, 139.82),
    _ScanPoint(35.1142, 139.24),
    _ScanPoint(35.1142, 138.72),
    _ScanPoint(35.0979, 137.96),
    _ScanPoint(35.0979, 137.93),
    _ScanPoint(35.0816, 137.96),
    _ScanPoint(35.0816, 136.95),
    _ScanPoint(35.0816, 136.38),
    _ScanPoint(35.0816, 137.35),
    _ScanPoint(35.0816, 136.81),
    _ScanPoint(35.0816, 137.12),
    _ScanPoint(35.0816, 136.71),
    _ScanPoint(35.0816, 136.39),
    _ScanPoint(35.0816, 136.14),
    _ScanPoint(35.1142, 136.24),
    _ScanPoint(35.0979, 135.76),
    _ScanPoint(35.0979, 135.85),
    _ScanPoint(35.0816, 135.26),
    _ScanPoint(35.0897, 135.83),
    _ScanPoint(35.1142, 135.82),
    _ScanPoint(35.1142, 135.95),
    _ScanPoint(35.049, 134.05),
    _ScanPoint(35.0653, 134.68),
    _ScanPoint(35.0326, 134.25),
    _ScanPoint(35.049, 133.77),
    _ScanPoint(35.049, 132.71),
    _ScanPoint(35.049, 125.52),
    _ScanPoint(35.0979, 135.49),
    _ScanPoint(35.0979, 135.54),
    _ScanPoint(35.1142, 137.51),
    _ScanPoint(35.1142, 137.8),
    _ScanPoint(35.1142, 138.62),
    _ScanPoint(35.0816, 138.78),
    _ScanPoint(35.0816, 137.02),
    _ScanPoint(35.0816, 136.98),
    _ScanPoint(35.1142, 137.73),
    _ScanPoint(35.1142, 136.64),
    _ScanPoint(35.0816, 136.16),
    _ScanPoint(35.0816, 135.64),
    _ScanPoint(35.106, 135.82),
    _ScanPoint(35.1549, 135.72),
    _ScanPoint(35.0816, 137.06),
    _ScanPoint(35.0816, 136.49),
    _ScanPoint(35.0816, 135.83),
    _ScanPoint(35.1142, 136.37),
    _ScanPoint(35.1142, 135.57),
    _ScanPoint(35.1305, 135.72),
    _ScanPoint(35.1142, 134.86),
    _ScanPoint(35.0816, 135.31),
    _ScanPoint(35.0816, 135.13),
    _ScanPoint(35.0816, 134.86),
    _ScanPoint(35.0816, 134.94),
    _ScanPoint(35.0816, 135.1),
    _ScanPoint(35.0816, 134.99),
    _ScanPoint(35.0816, 134.54),
    _ScanPoint(35.0816, 134.09),
    _ScanPoint(35.0816, 135.45),
    _ScanPoint(35.0816, 135.06),
    _ScanPoint(35.0816, 135.53),
    _ScanPoint(35.0816, 135.12),
    _ScanPoint(35.0816, 134.72),
    _ScanPoint(35.0816, 134.3),
    _ScanPoint(35.0816, 135.53),
    _ScanPoint(35.0979, 134.92),
    _ScanPoint(35.0979, 134.99),
    _ScanPoint(35.0979, 134.25),
    _ScanPoint(35.049, 134.18),
    _ScanPoint(35.0979, 133.91),
    _ScanPoint(35.0979, 133.43),
    _ScanPoint(35.0816, 135.46),
    _ScanPoint(35.0816, 135.5),
    _ScanPoint(35.0816, 135.38),
    _ScanPoint(35.0816, 135.36),
    _ScanPoint(35.0816, 134.84),
    _ScanPoint(35.0816, 136.44),
    _ScanPoint(35.0816, 135.11),
    _ScanPoint(35.0816, 134.69),
    _ScanPoint(35.0816, 134.78),
    _ScanPoint(35.0979, 134.5),
    _ScanPoint(35.0979, 134.29),
    _ScanPoint(35.0816, 133.78),
    _ScanPoint(35.0816, 133.54),
    _ScanPoint(35.0816, 134.15),
    _ScanPoint(35.0816, 134.02),
    _ScanPoint(35.0816, 133.72),
    _ScanPoint(35.0816, 133.45),
    _ScanPoint(35.0816, 133.06),
    _ScanPoint(35.0816, 133.19),
    _ScanPoint(35.0816, 133.37),
    _ScanPoint(35.0816, 132.76),
    _ScanPoint(35.0816, 134.22),
    _ScanPoint(35.0816, 133.96),
    _ScanPoint(35.0816, 133.94),
    _ScanPoint(35.0816, 134.03),
    _ScanPoint(35.1142, 133.3),
    _ScanPoint(35.1305, 133.56),
    _ScanPoint(35.1142, 133.3),
    _ScanPoint(35.1142, 132.92),
    _ScanPoint(35.0816, 133.01),
    _ScanPoint(35.0816, 132.91),
    _ScanPoint(35.0816, 132.85),
    _ScanPoint(35.0979, 132.4),
    _ScanPoint(35.1142, 132.29),
    _ScanPoint(35.0816, 134.22),
    _ScanPoint(35.0816, 133.52),
    _ScanPoint(35.0816, 132.38),
    _ScanPoint(35.1142, 132.51),
    _ScanPoint(35.1142, 132.27),
    _ScanPoint(35.1142, 131.77),
    _ScanPoint(35.1549, 131.83),
    _ScanPoint(35.0816, 133.21),
    _ScanPoint(35.0816, 132.88),
    _ScanPoint(35.0816, 132.42),
    _ScanPoint(35.0816, 132.89),
    _ScanPoint(35.1305, 131.85),
    _ScanPoint(35.1305, 132.05),
    _ScanPoint(35.1305, 131.11),
    _ScanPoint(35.1305, 131.37),
    _ScanPoint(35.1305, 131.04),
    _ScanPoint(35.1305, 130.68),
    _ScanPoint(35.1142, 128.58),
    _ScanPoint(35.0979, 131.11),
    _ScanPoint(35.1142, 129.8),
    _ScanPoint(35.1142, 129.49),
    _ScanPoint(35.1305, 127.11),
    _ScanPoint(35.1305, 126.14),
    _ScanPoint(35.1142, 125.4),
    _ScanPoint(35.1305, 124.75),
    _ScanPoint(35.0979, 124.93),
    _ScanPoint(35.0979, 124.41),
    _ScanPoint(35.0979, 123.13),
    _ScanPoint(35.0979, 122.82),
    _ScanPoint(35.1142, 122.83),
    _ScanPoint(35.0979, 122.63),
  ];

  /// 从激活的 NIED 测站列表推算震中位置（旧 JS/SB3 载体网格搜索法）
  ///
  /// [stations] 必须包含 isActive=true 且 level>=0 的站
  /// 返回估算的震中坐标和置信度
  static HypocenterEstimator? estimate(List<NiedStation> stations) {
    final active = stations.where((s) => s.isActive && s.level >= 0).toList();
    if (active.length < 3) return null;

    var bestLat = 0.0;
    var bestLng = 0.0;
    var bestScore = double.infinity;

    // 188 点扫描线搜索（与 scratch-realtime-earthquake-viewer-page 载体对齐）
    for (final point in _scanPoints) {
      var totalDist = 0.0;
      for (final s in active) {
        final dist = _jma2001Distance(
          point.lat,
          point.lng,
          s.coordinate.latitude,
          s.coordinate.longitude,
        );
        // 按震度加权: level 越高贡献越大
        final weight = 1.0 + (s.level / 20.0);
        totalDist += dist * weight;
      }

      if (totalDist < bestScore) {
        bestScore = totalDist;
        bestLat = point.lat;
        bestLng = point.lng;
      }
    }

    // 细搜索: 在最佳点周围 ±0.5° 以 0.05° 步长
    _gridSearch(
      active,
      bestLat - 0.5,
      bestLat + 0.5,
      bestLng - 0.5,
      bestLng + 0.5,
      20,
      20,
      (lat, lng) {
        var totalDist = 0.0;
        for (final s in active) {
          final dist = _jma2001Distance(
            lat,
            lng,
            s.coordinate.latitude,
            s.coordinate.longitude,
          );
          final weight = 1.0 + (s.level / 20.0);
          totalDist += dist * weight;
        }
        if (totalDist < bestScore) {
          bestScore = totalDist;
          bestLat = lat;
          bestLng = lng;
        }
      },
    );

    final confidence = (1.0 / (1.0 + bestScore / (active.length * 100))).clamp(
      0.0,
      1.0,
    );

    return HypocenterEstimator(
      latitude: bestLat,
      longitude: bestLng,
      confidence: confidence,
    );
  }

  /// 网格搜索辅助函数
  static void _gridSearch(
    List<NiedStation> stations,
    double latMin,
    double latMax,
    double lonMin,
    double lonMax,
    int latSteps,
    int lonSteps,
    void Function(double lat, double lng) onPoint,
  ) {
    for (int i = 0; i <= latSteps; i++) {
      final lat = latMin + (latMax - latMin) * i / latSteps;
      for (int j = 0; j <= lonSteps; j++) {
        final lng = lonMin + (lonMax - lonMin) * j / lonSteps;
        onPoint(lat, lng);
      }
    }
  }

  /// JMA2001 平面距离近似 (替代 haversine)
  ///
  /// 日本周边使用简化的平面距离公式:
  /// d_km ≈ sqrt((111.0 * dlat)² + (91.0 * dlon)²)
  /// 与 scratch-realtime-earthquake-viewer-page 载体中的 JMA2001 表近似公式结果高度一致
  static double _jma2001Distance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dlat = (lat2 - lat1) * 111.0;
    final dlon = (lon2 - lon1) * 91.0;
    return sqrt(dlat * dlat + dlon * dlon);
  }
}

class _ScanPoint {
  final double lat;
  final double lng;
  const _ScanPoint(this.lat, this.lng);
}
