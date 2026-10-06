import 'dart:async';
import 'dart:convert';
import 'dart:math' show min;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/intensity_calculator.dart';
import '../../../core/cwa_report_intensities.dart';
import '../../../models/quake_message.dart';
import 'eqlist_http_poll_gate.dart';

/// CWA地震列表服务
///
/// 该类提供台湾中央气象署(CWA)地震数据获取功能。
/// 通过ExpTech v2 API获取台湾地区的地震报告。
///
/// 主要功能：
/// - 定时轮询ExpTech v2 API
/// - 解析地震数据
/// - 转换CWA震度等级为JMA格式
/// - 24小时body-key去重缓存
///
/// 数据源：
/// - ExpTech v2 API: https://api.core.exptech.dev/api/v2/eq/report?limit=5
///
/// 震度说明：
/// CWA使用0-9级震度，与JMA震度类似：
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
  @visibleForTesting
  CwaEqlistService.forTesting(http.Client client) : _client = client;

  http.Client? _client;
  bool _fetching = false;
  int _generation = 0;
  final _details = <String, ({Map<String, dynamic> raw, DateTime at})>{};

  /// ExpTech v2 API地址
  static const String _url =
      'https://api.core.exptech.dev/api/v2/eq/report?limit=25';

  /// 定时器
  Timer? _timer;

  /// 最新地震列表
  final List<QuakeMessage> _latestList = [];

  /// 获取最新列表（只读）
  List<QuakeMessage> get latestList => List.unmodifiable(_latestList);

  /// 列表更新回调
  void Function(List<QuakeMessage>)? onListUpdated;

  /// 最新官方事件更新回调，字段格式与统一事件适配器的 CWA 输入一致。
  void Function(Map<String, dynamic>)? onCurrentUpdated;

  /// HTTP 轮询状态回调
  void Function(bool connected)? onStatusChanged;

  final EqlistHttpPollGate _pushGate = EqlistHttpPollGate();

  /// FAN already refreshed the CWA list — skip HTTP briefly.
  void noteExternalUpdate() => _pushGate.noteExternalUpdate();

  /// 启动轮询
  ///
  /// [interval] 轮询间隔，默认30秒（信息列表，无需 10s）
  void start({Duration interval = const Duration(seconds: 30)}) {
    _timer?.cancel();
    _fetch();
    _timer = Timer.periodic(interval, (_) => _fetch());
  }

  /// 停止轮询
  void stop() {
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  /// 获取地震数据
  Future<void> _fetch() async {
    if (_fetching || _pushGate.shouldSkipHttp) return;
    _fetching = true;
    final generation = _generation;
    try {
      final resp =
          await (_client?.get(Uri.parse(_url)) ?? http.get(Uri.parse(_url)))
              .timeout(const Duration(seconds: 15));
      if (generation != _generation) return;
      if (resp.statusCode != 200) {
        onStatusChanged?.call(false);
        return;
      }

      final raw = utf8.decode(resp.bodyBytes);
      final data = json.decode(raw);
      if (data is! List) {
        debugPrint(
          'CWA Eqlist unexpected format: ${raw.substring(0, min(200, raw.length))}',
        );
        onStatusChanged?.call(false);
        return;
      }

      final currentPayload = data.isNotEmpty && data.first is Map
          ? Map<String, dynamic>.from(data.first as Map)
          : null;

      _latestList.clear();
      for (final entry in data) {
        if (entry is! Map) continue;
        final parsed = _parseCwaItem(Map<String, dynamic>.from(entry));
        if (parsed != null) _latestList.add(parsed);
      }

      onListUpdated?.call(_latestList);
      onStatusChanged?.call(true);
      if (currentPayload != null) {
        final detail = await _loadDetail(currentPayload);
        if (generation != _generation) return;
        onCurrentUpdated?.call(detail ?? currentPayload);
      }
    } catch (e) {
      if (generation != _generation) return;
      debugPrint('CWA Eqlist fetch error: $e');
      onStatusChanged?.call(false);
    } finally {
      _fetching = false;
    }
  }

  @visibleForTesting
  Future<void> fetchForTesting() => _fetch();

  Future<Map<String, dynamic>?> _loadDetail(
    Map<String, dynamic> summary,
  ) async {
    final id = summary['id'];
    if (id is! String || id.isEmpty) return null;
    final key = '$id|${summary['md5'] ?? ''}';
    final cached = _details.remove(key);
    if (cached != null &&
        DateTime.now().difference(cached.at) < const Duration(minutes: 5)) {
      _details[key] = cached;
      return cached.raw;
    }
    try {
      final uri = Uri.https('api.core.exptech.dev', '/api/v2/eq/report/$id');
      final resp = await (_client?.get(uri) ?? http.get(uri)).timeout(
        const Duration(seconds: 6),
      );
      if (resp.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is! Map) return null;
      final detail = Map<String, dynamic>.from(decoded);
      // Bind the original detail to this exact summary, never the nearest quake.
      if (detail['id'] != id ||
          ![
            'time',
            'lat',
            'lon',
            'mag',
            'depth',
          ].every((field) => detail[field] == summary[field]) ||
          CwaReportIntensities.countyRanks(detail).isEmpty) {
        return null;
      }
      _details[key] = (raw: detail, at: DateTime.now());
      while (_details.length > 16) {
        _details.remove(_details.keys.first);
      }
      return detail;
    } catch (e) {
      debugPrint('CWA report detail fetch error: $e');
      return null;
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
          ? DateTime.fromMillisecondsSinceEpoch(
              timeMs,
              isUtc: true,
            ).add(const Duration(hours: 8))
          : DateTime.now();

      // 坐标和震源参数
      final double latitude =
          double.tryParse(item['lat']?.toString() ?? '') ?? 0.0;
      final double longitude =
          double.tryParse(item['lon']?.toString() ?? '') ?? 0.0;
      final double magnitude =
          double.tryParse(item['mag']?.toString() ?? '') ?? 0.0;
      final double depth =
          double.tryParse(item['depth']?.toString() ?? '') ?? 0.0;

      // 地点处理 - 提取 "(位於...)" 部分
      String location =
          item['loc']?.toString() ?? item['placeName']?.toString() ?? '';
      location = _extractCwaLocation(location);

      // 震度转换 - CWA int (0-9) 转换为日文汉字格式
      final int intensityNum =
          int.tryParse(item['int']?.toString() ?? '') ?? -1;
      final String? jmaShindo = _cwaIntensityToKanji(intensityNum);

      // 参考 USGS/EMSC，使用 CSIS 计算最大烈度
      final int maxIntensity = IntensityCalculator.calcCsisLevel(
        magnitude,
        depth,
        0,
      );

      return QuakeMessage(
        source: QuakeSourceType.cwa,
        eventId: id.isNotEmpty
            ? id
            : 'cwa_${DateTime.now().millisecondsSinceEpoch}',
        location: location.isNotEmpty ? location : '未知地点',
        magnitude: magnitude,
        latitude: latitude,
        longitude: longitude,
        depth: depth,
        originTime: originTime,
        jmaShindo: jmaShindo,
        maxIntensity: maxIntensity,
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
      case 0:
        return '0';
      case 1:
        return '1';
      case 2:
        return '2';
      case 3:
        return '3';
      case 4:
        return '4';
      case 5:
        return '5-';
      case 6:
        return '5+';
      case 7:
        return '6-';
      case 8:
        return '6+';
      case 9:
        return '7';
      default:
        return null;
    }
  }
}
