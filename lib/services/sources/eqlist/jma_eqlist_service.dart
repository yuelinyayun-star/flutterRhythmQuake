import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../models/quake_message.dart';

/// JMA地震情报服务
///
/// 该类提供日本气象厅(JMA)地震情报获取功能。
/// 通过P2PQuake API获取JMA发布的地震情报。
///
/// 主要功能：
/// - 定时轮询P2PQuake API
/// - 解析不同类型的地震情报
/// - 转换JMA震度等级
/// - 时间格式处理 (JST = UTC+9)
///
/// 数据源：
/// - P2PQuake API: https://api.p2pquake.net/v2/history?codes=551
///
/// 情报类型：
/// - ScalePrompt: 震度速报 (只有震度，震源调查中)
/// - Destination: 震源情报 (只有震源，震度不明)
/// - ScaleAndDestination: 震度・震源情报
/// - DetailScale: 各地震度情报
/// - Foreign: 远地地震情报
/// - Other: 其他情报
class JmaEqlistService {
  static final JmaEqlistService _instance = JmaEqlistService._internal();
  factory JmaEqlistService() => _instance;
  JmaEqlistService._internal();

  /// P2PQuake API地址
  ///
  /// codes=551 表示地震情报
  /// limit=20 获取最近20条
  static const String _url =
      'https://api.p2pquake.net/v2/history?codes=551&limit=20';

  /// 定时器
  Timer? _timer;

  /// 列表更新回调
  void Function(List<QuakeMessage>)? onListUpdated;

  /// 启动轮询
  ///
  /// 每30秒获取一次数据
  void start() {
    _timer?.cancel();
    fetch();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => fetch());
  }

  /// 停止轮询
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 获取地震情报数据
  Future<void> fetch() async {
    try {
      final resp = await http
          .get(Uri.parse(_url))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return;

      final list = json.decode(resp.body) as List?;
      if (list == null || list.isEmpty) return;

      final items = <QuakeMessage>[];
      for (final item in list) {
        if (item is! Map) continue;
        final parsed = _parseP2PQuakeItem(Map<String, dynamic>.from(item));
        if (parsed != null) items.add(parsed);
      }

      if (items.isNotEmpty) onListUpdated?.call(items);
    } catch (e) {
      debugPrint('JMA Eqlist fetch error: $e');
    }
  }

  /// 解析P2PQuake数据项
  ///
  /// 参考 kanameishi status.js jmaEqlist 处理逻辑
  QuakeMessage? _parseP2PQuakeItem(Map<String, dynamic> item) {
    try {
      final earthquake = item['earthquake'] as Map?;
      final issue = item['issue'] as Map?;
      if (earthquake == null) return null;

      final String timeStr = (earthquake['time']?.toString() ?? '').replaceAll(
        '/',
        '-',
      );
      final String eventId = timeStr;

      final DateTime originTime = DateTime.tryParse(timeStr) ?? DateTime.now();

      final String issueType = issue?['type']?.toString() ?? '';
      final String issueTime = (issue?['time']?.toString() ?? '').replaceAll(
        '/',
        '-',
      );
      final DateTime? reportTime = issueTime.isNotEmpty
          ? DateTime.tryParse(issueTime)
          : null;

      final hypocenter = earthquake['hypocenter'] as Map?;
      final String location = hypocenter?['name']?.toString() ?? '';
      final double latitude = _parseNum(hypocenter?['latitude']);
      final double longitude = _parseNum(hypocenter?['longitude']);
      final double magnitude = _parseNum(hypocenter?['magnitude']);
      final double depth = _parseDepth(hypocenter?['depth']);
      if (_isInvestigatingLocation(location) ||
          (latitude == 0.0 && longitude == 0.0)) {
        return null;
      }

      final int maxScale =
          int.tryParse(earthquake['maxScale']?.toString() ?? '') ?? 0;
      final String? jmaShindo = _scaleToShindo(maxScale);
      if (jmaShindo == null) return null;

      final String title = _getIssueTitle(issueType);

      return QuakeMessage(
        source: QuakeSourceType.wolfx,
        eventId: eventId,
        location: location,
        magnitude: magnitude,
        latitude: latitude,
        longitude: longitude,
        depth: depth,
        originTime: originTime,
        jmaShindo: jmaShindo,
        isHistory: true,
        isTest: false,
        reportTime: reportTime,
        infoTypeName: title,
        isInfoEvent: true,
      );
    } catch (e) {
      return null;
    }
  }

  /// 获取情报类型标题
  String _getIssueTitle(String type) {
    switch (type) {
      case 'ScalePrompt':
        return '震度速報';
      case 'Destination':
        return '震源情報';
      case 'ScaleAndDestination':
        return '震度・震源情報';
      case 'DetailScale':
        return '各地の震度情報';
      case 'Foreign':
        return '遠地地震情報';
      case 'Other':
        return 'その他の情報';
      default:
        return '地震情報';
    }
  }

  /// 解析数值
  double _parseNum(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty) return 0.0;
    final firstChar = s[0].toUpperCase();
    if (firstChar == 'N' ||
        firstChar == 'S' ||
        firstChar == 'E' ||
        firstChar == 'W') {
      final val = double.tryParse(s.substring(1)) ?? 0.0;
      return (firstChar == 'S' || firstChar == 'W') ? -val : val;
    }
    return double.tryParse(s) ?? 0.0;
  }

  /// 解析深度
  double _parseDepth(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    final s = v.toString().toLowerCase().trim();
    if (s == 'ごく浅い' || s == 'very shallow') return 0.0;
    if (s == '不明' || s == 'unknown') return -1.0;
    return double.tryParse(s.replaceAll('km', '').trim()) ?? 0.0;
  }

  /// 将仪器震度转换为JMA震度等级
  ///
  /// P2PQuake返回的maxScale是仪器震度×10
  /// 例如: 45 -> 震度5弱, 46 -> 震度5強
  String? _scaleToShindo(int maxScale) {
    if (maxScale <= 0) return null;
    final s = maxScale / 10.0;
    if (s < 0.5) return '0';
    if (s < 1.5) return '1';
    if (s < 2.5) return '2';
    if (s < 3.5) return '3';
    if (s < 4.5) return '4';
    if (s < 5.0) return '5-';
    if (s < 5.5) return '5+';
    if (s < 6.0) return '6-';
    if (s < 6.5) return '6+';
    return '7';
  }

  bool _isInvestigatingLocation(String location) {
    final s = location.trim().toLowerCase();
    if (s.isEmpty) return true;
    return s == '調査中' || s == '调查中' || s == '不明' || s == '不詳' || s == 'unknown';
  }
}
