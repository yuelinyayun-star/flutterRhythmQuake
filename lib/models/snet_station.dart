/// S-net 海底地震观测站数据模型
///
/// 本模块定义了日本 S-net (Seafloor Observation Network for Earthquakes and Tsunamis)
/// 海底地震观测网的数据结构。
///
/// ## S-net 简介
///
/// S-net 是世界上最大的海底地震观测网络，由日本气象厅和防灾科学技术研究所运营。
/// 网络由约150个海底观测站组成，沿日本海沟分布，用于：
/// - 海底地震监测
/// - 海啸预警
/// - 地震学研究
///
/// ## 测站类型
///
/// - **速度计**: 测量地面运动速度
/// - **加速度计**: 测量地面运动加速度
///
/// ## 网络代码
///
/// - **0120**: 速度计网络
/// - **0120A**: 加速度计网络

import 'package:latlong2/latlong.dart';

/// S-net 海底观测站
///
/// 表示单个 S-net 海底观测站的信息和实时数据。
class SnetStation {
  /// 测站代码
  ///
  /// 格式为 "SXXYZZ"，其中：
  /// - SXX: 区域代码 (S01-S07)
  /// - Y: 线路编号
  /// - ZZ: 测站编号
  ///
  /// 例如: S01A01, S05B03
  final String code;

  /// 测站名称
  final String name;

  /// 经纬度坐标
  ///
  /// 使用 LatLng 类型，便于地图显示。
  final LatLng coordinate;

  /// 海底深度
  ///
  /// 单位：米 (m)。
  /// 正值表示海底深度，0 表示陆地测站。
  final double depth;

  /// 网络代码
  ///
  /// - "0120": 速度计网络
  /// - "0120A": 加速度计网络
  final String network;

  /// 测站类型
  ///
  /// - "velocity": 速度计
  /// - "acceleration": 加速度计
  final String type;

  /// 实时震度
  ///
  /// 当前观测到的震度值。
  /// null 表示暂无数据。
  double? intensity;

  /// 计测震度 (shindo)
  ///
  /// 从图片像素颜色解析出的计测震度值。
  double shindo;

  /// 震度等级
  ///
  /// 从 shindo 转换的 raw level 值。
  int level;

  /// 图片像素 X 坐标 (z=7 拼接图)
  int pixelX;

  /// 图片像素 Y 坐标 (z=7 拼接图)
  int pixelY;

  /// 是否活跃
  bool isActive;

  /// 实时水压
  ///
  /// 用于海啸监测的水压数据。
  /// 单位：MPa 或其他标准化单位。
  double? pressure;

  /// 最后更新时间
  ///
  /// 数据最后更新的时间戳。
  DateTime? lastUpdate;

  /// 构造函数
  ///
  /// 创建一个 S-net 测站实例。
  /// [code], [name], [coordinate], [depth], [network], [type] 为必填参数。
  SnetStation({
    required this.code,
    required this.name,
    required this.coordinate,
    required this.depth,
    required this.network,
    required this.type,
    this.intensity,
    this.pressure,
    this.lastUpdate,
    this.shindo = 0.0,
    this.level = -1,
    this.pixelX = 0,
    this.pixelY = 0,
    this.isActive = false,
  });

  /// 判断是否为海底测站
  ///
  /// 深度大于 0 的测站位于海底。
  bool get isSeafloor => depth > 0;

  /// 判断是否有有效数据
  ///
  /// 有震度或水压数据时返回 true。
  bool get hasData => intensity != null || pressure != null;

  /// 字符串表示
  @override
  String toString() => 'SnetStation($code, ${coordinate.latitude}, ${coordinate.longitude}, depth: ${depth}m)';
}

/// S-net 网络配置
///
/// 包含 S-net 网络的静态配置信息。
class SnetConfig {
  /// 速度计网络代码
  static const String networkCodeVelocity = '0120';

  /// 加速度计网络代码
  static const String networkCodeAcceleration = '0120A';

  /// 测站信息 URL
  ///
  /// Hi-net 提供的测站信息 JavaScript 文件。
  static const String stationInfoUrl = 'https://www.hinet.bosai.go.jp/st_info/snet_station.js';

  /// 实时数据 URL
  ///
  /// Hi-net 提供的实时数据目录。
  static const String realtimeDataUrl = 'https://www.hinet.bosai.go.jp/realtime/snet/';

  /// 公开数据 URL
  ///
  /// 日本气象厅公开数据接口。
  static const String publicDataUrl = 'https://www.data.jma.go.jp/svd/eqev/data/daily_map/';

  /// S-net 测站区域划分
  ///
  /// 根据测站代码前缀划分的地理区域。
  static const Map<String, String> regions = {
    'S01': '北海道东部',
    'S02': '青森县冲',
    'S03': '岩手县冲',
    'S04': '宫城县冲',
    'S05': '福岛县冲',
    'S06': '茨城县冲',
    'S07': '千叶县冲',
  };

  /// 获取测站所属区域
  ///
  /// 根据测站代码前缀返回对应的地理区域名称。
  ///
  /// 参数：
  /// - [stationCode]: 测站代码 (如 "S01A01")
  ///
  /// 返回：
  /// - 区域名称字符串
  static String getRegion(String stationCode) {
    if (stationCode.length < 3) return '未知区域';
    final regionPrefix = stationCode.substring(0, 3);
    return regions[regionPrefix] ?? '未知区域';
  }
}
