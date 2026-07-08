import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ntp/ntp.dart';

enum NtpSyncState {
  local,
  synced,
  stale,
}

/// NTP时间同步服务
/// 
/// 该类提供网络时间协议(NTP)同步功能。
/// 用于校正设备本地时间与标准时间的偏差。
/// 
/// 主要功能：
/// - 同步NTP服务器时间
/// - 计算设备时间偏移量
/// - 提供修正后的当前时间
/// - 定时同步防止时钟漂移
/// 
/// 使用场景：
/// - 地震预警需要精确的时间同步
/// - 确保S波到达倒计时准确
/// - 多设备协同需要统一时间基准
class NtpService {
  static final NtpService _instance = NtpService._internal();
  factory NtpService() => _instance;
  NtpService._internal();

  static const Duration _syncInterval = Duration(hours: 1);
  static const Duration _retryDelay = Duration(seconds: 30);
  static const Duration _maxOffsetAge = Duration(hours: 6);
  static const Duration _httpTimeout = Duration(seconds: 5);
  static const List<String> _httpTimeUrls = [
    'https://api.fanstudio.tech/tool/ntp.php',
  ];
  static const List<String> _ntpServers = [
    'pool.ntp.org',
    'ntp.aliyun.com',
    'time.apple.com',
    'time.windows.com',
  ];

  /// 设备时间与NTP时间的偏移量（毫秒）
  /// 
  /// 正值表示标准时间快于设备时间
  /// 负值表示标准时间慢于设备时间
  int _deviceOffset = 0;
  
  /// 是否已同步
  bool _isSynced = false;
  DateTime? _lastSyncedAt;
  bool _syncInProgress = false;
  Timer? _periodicTimer;
  Timer? _retryTimer;

  int get deviceOffset => _deviceOffset;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  bool get hasUsableOffset => _hasUsableOffset;
  bool get isSynced => syncState == NtpSyncState.synced;

  NtpSyncState get syncState {
    if (!_hasUsableOffset) return NtpSyncState.local;
    return _isSynced ? NtpSyncState.synced : NtpSyncState.stale;
  }

  bool get _hasUsableOffset {
    final syncedAt = _lastSyncedAt;
    if (syncedAt == null) return false;
    return DateTime.now().difference(syncedAt) <= _maxOffsetAge;
  }

  /// 获取经过修正后的当前时间
  /// 
  /// 返回NTP校准后的时间
  DateTime get now {
    final localNow = DateTime.now();
    if (!_hasUsableOffset) return localNow;
    return localNow.add(Duration(milliseconds: _deviceOffset));
  }

  /// 同步时间
  /// 
  /// 优先使用参考项目同款 HTTP 时间接口，UDP NTP 不通时也能拿到稳定偏移。
  /// HTTP 接口失败后再尝试 NTP 服务器。
  /// 
  /// [lookUpAddress] NTP服务器地址
  /// 常用服务器：
  /// - pool.ntp.org: NTP池，全球分布
  /// - time.apple.com: 苹果时间服务器
  /// - ntp.aliyun.com: 阿里云NTP服务器
  Future<void> syncTime({String lookUpAddress = 'pool.ntp.org'}) async {
    if (_syncInProgress) return;
    _syncInProgress = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    Object? lastError;
    try {
      for (final url in _httpTimeUrls) {
        try {
          debugPrint('--- 正在同步 HTTP 时间自: $url ---');
          await _syncHttpTime(url);
          debugPrint('--- HTTP 时间同步成功! 当前偏移量: $_deviceOffset ms ---');
          debugPrint('--- 修正后时间: ${now.toIso8601String()} ---');
          return;
        } catch (e) {
          lastError = e;
          debugPrint('--- HTTP 时间同步失败: $url $e ---');
        }
      }

      final servers = <String>[
        lookUpAddress,
        ..._ntpServers.where((server) => server != lookUpAddress),
      ];
      for (final server in servers) {
        try {
          debugPrint('--- 正在同步 NTP 时间自: $server ---');
          final offset = await NTP.getNtpOffset(
            lookUpAddress: server,
            timeout: const Duration(seconds: 5),
          );

          _applyOffset(offset);

          debugPrint('--- NTP 同步成功! 当前偏移量: $_deviceOffset ms ---');
          debugPrint('--- 修正后时间: ${now.toIso8601String()} ---');
          return;
        } catch (e) {
          lastError = e;
          debugPrint('--- NTP 同步失败: $server $e ---');
        }
      }

      throw lastError ?? StateError('所有时间同步源均失败');
    } catch (e) {
      debugPrint('--- 时间同步失败: $e ---');
      _isSynced = false;
      _scheduleRetry();
    } finally {
      _syncInProgress = false;
    }
  }

  Future<void> _syncHttpTime(String url) async {
    final startedAt = DateTime.now();
    final response = await http.get(Uri.parse(url)).timeout(_httpTimeout);
    final endedAt = DateTime.now();
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('时间接口返回格式无效');
    }
    final rawMs = decoded['unixtime_ms'];
    final serverMs = rawMs is num
        ? rawMs.round()
        : int.tryParse(rawMs?.toString() ?? '');
    if (serverMs == null || serverMs <= 0) {
      throw const FormatException('时间接口缺少 unixtime_ms');
    }

    final localMidpointMs =
        (startedAt.millisecondsSinceEpoch + endedAt.millisecondsSinceEpoch) ~/
        2;
    _applyOffset(serverMs - localMidpointMs);
  }

  void _applyOffset(int offset) {
    _deviceOffset = offset;
    _isSynced = true;
    _lastSyncedAt = DateTime.now();
  }

  void _scheduleRetry() {
    if (_retryTimer?.isActive == true) return;
    _retryTimer = Timer(_retryDelay, () {
      _retryTimer = null;
      syncTime();
    });
  }

  /// 启动定时同步任务
  /// 
  /// 建议每小时执行一次，防止系统时钟漂移。
  /// 立即执行一次同步，然后每小时重复。
  void startPeriodicSync() {
    if (_periodicTimer?.isActive == true) return;
    syncTime();
    _periodicTimer = Timer.periodic(_syncInterval, (timer) {
      syncTime();
    });
  }
}
