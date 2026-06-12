import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../models/quake_message.dart';

/// CWA地震列表服务
/// 
/// 该类提供台湾中央气象署(CWA)地震数据获取功能。
/// 通过Exptech API获取台湾地区的地震报告。
/// 
/// 主要功能：
/// - 定时轮询Exptech API
/// - 解析地震数据
/// - 转换CWA震度等级为JMA格式
/// 
/// 数据源：
/// - Exptech API: https://exptech.com.tw/api/v1/earthquake/report
/// 
/// 震度说明：
/// CWA使用0-7级震度，与JMA震度类似：
/// - 0: 震度0
/// - 1: 震度1
/// - 2: 震度2
/// - 3: 震度3
/// - 4: 震度4
/// - 5: 震度5弱 (5-)
/// - 6: 震度5強 (5+)
/// - 7: 震度6弱 (6-)
/// - 8: 震度6強 (6+)
/// - 9: 震度7
class CwaEqlistService {
  static final CwaEqlistService _instance = CwaEqlistService._internal();
  factory CwaEqlistService() => _instance;
  CwaEqlistService._internal();

  /// Exptech API地址
  static const String _url = 'https://exptech.com.tw/api/v1/earthquake/report';

  /// 定时器
  Timer? _timer;

  /// 列表更新回调
  void Function(List<QuakeMessage>)? onListUpdated;

  /// 启动轮询
  /// 
  /// 每90秒获取一次数据
  void start() {
    _timer?.cancel();
    fetch();
    _timer = Timer.periodic(const Duration(seconds: 90), (_) => fetch());
  }

  /// 停止轮询
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 获取地震数据
  Future<void> fetch() async {
    try {
      final resp = await http
          .get(Uri.parse(_url))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return;

      final data = json.decode(resp.body);
      if (data is! List && data is! Map) return;

      final items = <QuakeMessage>[];
      final list = data is List ? data : [data];

      for (final entry in list) {
        if (entry is! Map) continue;
        final parsed = _parseCwaItem(Map<String, dynamic>.from(entry));
        if (parsed != null) items.add(parsed);
      }

      if (items.isNotEmpty) onListUpdated?.call(items);
    } catch (e) {
      debugPrint('CWA Eqlist fetch error: $e');
    }
  }

  /// 解析CWA数据项
  /// 
  /// 参考 kanameishi status.js cwaEqlist 处理逻辑
  QuakeMessage? _parseCwaItem(Map<String, dynamic> item) {
    try {
      final String id = item['id']?.toString() ?? '';
      
      // 时间处理 - CWA时间戳为毫秒
      final int timeMs = item['time'] ?? 0;
      final DateTime originTime = timeMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(timeMs, isUtc: true)
              .add(const Duration(hours: 8))
          : DateTime.tryParse(
                  (item['shockTime']?.toString() ?? '').replaceAll('/', '-')) ??
              DateTime.now();

      // 坐标和震源参数
      final double latitude = double.tryParse(item['lat']?.toString() ?? '') ?? 0.0;
      final double longitude = double.tryParse(item['lon']?.toString() ?? '') ?? 0.0;
      final double magnitude = double.tryParse(item['mag']?.toString() ?? '') ?? 0.0;
      final double depth = double.tryParse(item['depth']?.toString() ?? '') ?? 0.0;

      // 地点处理 - 提取 "(位於...)" 部分
      String location = item['loc']?.toString() ?? item['placeName']?.toString() ?? '';
      location = _extractCwaLocation(location);

      // 震度转换 - CWA int (0-9) 转换为日文汉字格式
      final int intensityNum = int.tryParse(item['int']?.toString() ?? '') ?? -1;
      final String? jmaShindo = _cwaIntensityToKanji(intensityNum);

      return QuakeMessage(
        source: QuakeSourceType.cwa,
        eventId: id.isNotEmpty ? id : 'cwa_${DateTime.now().millisecondsSinceEpoch}',
        location: location.isNotEmpty ? location : '未知地点',
        magnitude: magnitude,
        latitude: latitude,
        longitude: longitude,
        depth: depth,
        originTime: originTime,
        jmaShindo: jmaShindo,
        isHistory: true,
        isInfoEvent: true,
        infoTypeName: '中央氣象署地震報告',
      );
    } catch (e) {
      return null;
    }
  }

  /// 提取 CWA 地点名称
  /// 
  /// CWA地点格式: "花蓮縣政府南偏西方 25.0 公里 (位於花蓮縣秀林鄉)"
  /// 提取后: "花蓮縣秀林鄉"
  String _extractCwaLocation(String loc) {
    if (loc.isEmpty) return '未知地点';
    
    final start = loc.indexOf('(位於');
    final end = loc.indexOf(')');
    
    if (start == -1 || end == -1 || start + 3 >= end) {
      return loc;
    }
    
    return loc.substring(start + 3, end);
  }

  /// 将 CWA 震度数值转换为符号格式
  /// 
  /// 参考 kanameishi 的 shindoScale 数组
  /// - 0-4: 直接输出数字
  /// - 5: 5-
  /// - 6: 5+
  /// - 7: 6-
  /// - 8: 6+
  /// - 9: 7
  String? _cwaIntensityToKanji(int intensity) {
    switch (intensity) {
      case 0: return '0';
      case 1: return '1';
      case 2: return '2';
      case 3: return '3';
      case 4: return '4';
      case 5: return '5-';
      case 6: return '5+';
      case 7: return '6-';
      case 8: return '6+';
      case 9: return '7';
      default: return null;
    }
  }
}
