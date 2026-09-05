import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../models/weather_alert_map_item.dart';

/// 全国气象灾害预警地图数据服务
///
/// 负责从中国天气网/CMA官方接口定时拉取全量突发气象灾害预警多边形与等级数据，
/// 并在后台线程完成高性能 GeoJSON 解析。
class ChinaWeatherAlertMapService {
  static final ChinaWeatherAlertMapService _instance = ChinaWeatherAlertMapService._internal();
  factory ChinaWeatherAlertMapService() => _instance;
  ChinaWeatherAlertMapService._internal();

  static const String endpoint = 'https://forecast.weather.com.cn/api/v1/traffic/alarm/alarmMap';

  /// 全局预警多边形数据通知器
  static final ValueNotifier<List<WeatherAlertMapItem>> alertItemsNotifier =
      ValueNotifier<List<WeatherAlertMapItem>>(<WeatherAlertMapItem>[]);

  /// 加载状态指示器
  static final ValueNotifier<bool> isLoadingNotifier = ValueNotifier<bool>(false);

  /// 内存快照有效期（3 分钟）
  static const Duration snapshotTtl = Duration(minutes: 3);

  /// 全局静态内存快照（跨实例/热重载复用）
  static List<WeatherAlertMapItem>? _snapshotItems;
  static DateTime? _snapshotTime;

  Timer? _timer;
  bool _isRunning = false;
  DateTime? _lastFetchTime;
  Digest? _lastPayloadDigest;
  int _generation = 0;

  bool get isRunning => _isRunning;
  DateTime? get lastFetchTime => _lastFetchTime ?? _snapshotTime;

  /// 检查快照是否在有效期内
  static bool get hasValidSnapshot =>
      _snapshotItems != null &&
      _snapshotTime != null &&
      DateTime.now().difference(_snapshotTime!) < snapshotTtl;

  /// 启动定时拉取（默认每 2 分钟轮询一次）
  void start({Duration interval = const Duration(minutes: 2)}) {
    if (_isRunning) return;
    _isRunning = true;

    // 若当前已有新鲜快照，直接瞬间恢复，避免热重载或重启时重复拉取
    if (hasValidSnapshot && _snapshotItems != null) {
      if (alertItemsNotifier.value.isEmpty) {
        alertItemsNotifier.value = _snapshotItems!;
      }
      _lastFetchTime = _snapshotTime;
      _timer?.cancel();
      _timer = Timer.periodic(interval, (_) => fetchNow());
      return;
    }

    fetchNow();
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => fetchNow());
  }

  /// 停止定时轮询
  void stop() {
    if (!_isRunning) return;
    _isRunning = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  /// 触发一次网络拉取（若缓存有效且非强制刷新则直接复用）
  Future<void> fetchNow({bool force = false}) async {
    if (isLoadingNotifier.value) return;

    if (!force && hasValidSnapshot && _snapshotItems != null) {
      if (alertItemsNotifier.value.isEmpty) {
        alertItemsNotifier.value = _snapshotItems!;
      }
      _lastFetchTime = _snapshotTime;
      return;
    }

    isLoadingNotifier.value = true;
    final generation = _generation;
    try {
      final uri = Uri.parse(endpoint);
      final resp = await http.get(
        uri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/json, text/plain, */*',
        },
      ).timeout(const Duration(seconds: 12));

      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        if (generation != _generation) return;
        final digest = sha256.convert(resp.bodyBytes);
        if (digest == _lastPayloadDigest) {
          _snapshotTime = DateTime.now();
          _lastFetchTime = _snapshotTime;
          return;
        }
        final rawText = utf8.decode(resp.bodyBytes, allowMalformed: true);
        final parsedItems = await compute(_parseAlertMapJson, rawText);
        if (generation != _generation) return;
        _lastPayloadDigest = digest;
        _snapshotItems = parsedItems;
        _snapshotTime = DateTime.now();
        alertItemsNotifier.value = parsedItems;
        _lastFetchTime = _snapshotTime;
      }
    } catch (e) {
      debugPrint('[ChinaWeatherAlertMapService] 拉取气象预警地图数据失败: $e');
    } finally {
      isLoadingNotifier.value = false;
    }
  }

  /// 顶级函数供 compute 在独立 Isolate 中异步解析
  static List<WeatherAlertMapItem> _parseAlertMapJson(String rawBody) {
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is! Map<String, dynamic>) return const [];
      final result = decoded['result'];
      if (result is! Map<String, dynamic>) return const [];
      final data = result['data'];
      if (data is! List) return const [];

      final items = <WeatherAlertMapItem>[];
      for (final rawItem in data) {
        if (rawItem is List) {
          final item = WeatherAlertMapItem.fromRawList(rawItem);
          if (item != null) {
            items.add(item);
          }
        }
      }
      return items;
    } catch (_) {
      return const [];
    }
  }

  final Map<String, WeatherAlertDetail> _detailCache = {};
  final Map<String, Future<WeatherAlertDetail?>> _detailRequests = {};
  static const int detailCacheLimit = 64;

  /// 拉取指定预警的官方详细信息（带内存缓存）
  Future<WeatherAlertDetail?> fetchAlertDetail(String fileId) async {
    if (fileId.isEmpty) return null;
    final key = fileId.endsWith('.html') ? fileId : '$fileId.html';
    final cached = _detailCache.remove(key);
    if (cached != null) {
      _detailCache[key] = cached;
      return cached;
    }
    final pending = _detailRequests[key];
    if (pending != null) return pending;
    final request = _fetchAlertDetail(key);
    _detailRequests[key] = request;
    try {
      return await request;
    } finally {
      _detailRequests.remove(key);
    }
  }

  Future<WeatherAlertDetail?> _fetchAlertDetail(String fileId) async {
    try {
      final cleanFile = fileId.endsWith('.html') ? fileId : '$fileId.html';
      final uri = Uri.parse(
        'https://product.weather.com.cn/alarm/webdata/$cleanFile?_=${DateTime.now().millisecondsSinceEpoch}',
      );
      final resp = await http.get(
        uri,
        headers: {
          'Referer': 'http://www.weather.com.cn/alarm/',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        final rawJs = utf8.decode(resp.bodyBytes, allowMalformed: true);
        final detail = WeatherAlertDetail.fromRawJs(rawJs, fileId);
        if (detail != null) {
          _detailCache[fileId] = detail;
          while (_detailCache.length > detailCacheLimit) {
            _detailCache.remove(_detailCache.keys.first);
          }
          return detail;
        }
      }
    } catch (e) {
      debugPrint('[ChinaWeatherAlertMapService] 拉取预警详情失败 ($fileId): $e');
    }
    return null;
  }
}
