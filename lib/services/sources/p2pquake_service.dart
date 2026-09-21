/// P2PQuake 地震预警服务
///
/// 本模块实现了 P2PQuake WebSocket API 的数据获取与处理。
/// P2PQuake 是一个提供日本气象厅 (JMA) 地震和海啸预警的实时推送服务。
///
/// ## 服务概述
///
/// P2PQuake 通过 WebSocket 连接到 api.p2pquake.net 服务器，
/// 实时接收日本气象厅发布的地震情报和海啸预警。
///
/// ## 支持的消息类型
///
/// ### 地震情报 (code 551)
/// - **ScalePrompt**: 震度速报 - 地震发生后最快发布的速报，仅包含最大震度
/// - **Destination**: 震源速报 - 包含震源位置、深度、震级信息
/// - **ScaleAndDestination**: 震度震源速报 - 同时包含震度和震源信息
/// - **DetailScale**: 详细震度速报 - 包含各观测点的详细震度数据
/// - **Foreign**: 海外地震情报 - 日本以外地区的地震信息
/// - **Other**: 其他类型地震情报
///
/// ### 海啸情报 (code 552)
/// - **MajorWarning**: 大海啸警报 - 预计浪高超过3米
/// - **Warning**: 海啸警报 - 预计浪高1-3米
/// - **Watch**: 海啸注意报 - 预计浪高0.2-1米
/// - **取消报**: 海啸警报解除
///
/// ## 震度等级说明
///
/// JMA 震度等级采用 0-7 的整数等级，以及 5弱、5强、6弱、6强：
/// - 0: 震度0 (无感)
/// - 1: 震度1 (微震)
/// - 2: 震度2 (轻震)
/// - 3: 震度3 (弱震)
/// - 4: 震度4 (中震)
/// - 5弱: 震度5弱 (强震)
/// - 5强: 震度5强 (强震)
/// - 6弱: 震度6弱 (烈震)
/// - 6强: 震度6强 (烈震)
/// - 7: 震度7 (激震)
///
/// ## 连接机制
///
/// - 自动重连：连接断开后自动尝试重连，采用递增延迟策略
/// - 心跳检测：每10秒发送 ping 消息保持连接活跃
/// - 故障恢复：重连成功后自动重置重试计数

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../models/source_payload.dart';
import 'base_source.dart';
import '../../models/tsunami_message.dart';
import '../quake_event_adapter.dart';
import '../../models/source_status.dart';

/// P2PQuake 服务类
///
/// 继承自 [BaseSourceService]，实现 P2PQuake WebSocket 数据源。
///
/// ## 使用示例
///
/// ```dart
/// final service = P2PQuakeService();
/// service.onStatusChanged = (status) {
///   print('连接状态: $status');
/// };
/// service.onMessage = (message) {
///   print('收到地震消息: ${message.location}');
/// };
/// service.connect();
/// ```
class P2PQuakeService extends BaseSourceService {
  /// 服务名称标识
  ///
  /// 用于在日志和状态显示中标识此数据源。
  @override
  String get name => 'P2P';

  final Map<String, Map<String, dynamic>> _jmaEqInfoStateByTime = {};

  /// WebSocket 服务器地址
  ///
  /// P2PQuake API v2 的 WebSocket 端点。
  static const String _wsUrl = 'wss://api.p2pquake.net/v2/ws';

  /// 心跳间隔
  ///
  /// 每10秒发送一次 ping 消息以保持连接活跃。
  /// 这是 P2PQuake 服务器的推荐心跳间隔。
  static const Duration _pingInterval = Duration(seconds: 10);

  /// WebSocket 通道实例
  WebSocketChannel? _channel;

  /// 重连定时器
  ///
  /// 用于在连接失败后延迟重连。
  Timer? _reconnectTimer;

  /// 心跳定时器
  ///
  /// 用于定期发送 ping 消息。
  Timer? _pingTimer;

  /// 重试计数器
  ///
  /// 记录连续连接失败的次数，用于计算重连延迟。
  int _retryCount = 0;

  /// 手动关闭标志
  ///
  /// 当用户主动调用 disconnect() 时设置为 true，
  /// 阻止自动重连机制触发。
  bool _isManualClose = false;

  /// 发起连接
  ///
  /// 建立 WebSocket 连接到 P2PQuake 服务器。
  ///
  /// ## 连接流程
  ///
  /// 1. 重置状态标志和定时器
  /// 2. 清理旧的连接资源
  /// 3. 更新状态为 [SourceStatus.connecting]
  /// 4. 建立 WebSocket 连接
  /// 5. 监听数据流、关闭和错误事件
  ///
  /// ## 自动重连
  ///
  /// 连接失败或断开后，会自动触发重连机制。
  /// 重连延迟随失败次数递增，最长30秒。
  @override
  void connect() async {
    _isManualClose = false;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _cleanup();
    onStatusChanged?.call(SourceStatus.connecting);
    debugPrint('正在建立 P2PQuake 链路: $_wsUrl (尝试次数: ${_retryCount + 1})');

    try {
      final channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 10));
      if (_channel != channel) return;
      final recovered = _retryCount > 0;
      _retryCount = 0;
      onStatusChanged?.call(SourceStatus.connected);
      if (recovered) {
        debugPrint('P2PQuake 链路已恢复正常');
      }
      debugPrint('P2PQuake WebSocket 已连接，等待 JMA 地震/津波报文...');
      _startPing();

      channel.stream.listen(
        (data) {
          debugPrint('RAW >> P2PQuake: $data');
          onStatusChanged?.call(SourceStatus.connected);
          _handleData(data);
        },
        onDone: () {
          debugPrint('P2PQuake 链路远程关闭');
          _stopPing();
          _handleFailure();
        },
        onError: (err) {
          debugPrint('P2PQuake 链路传输错误: $err');
          _stopPing();
          _handleFailure();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('P2PQuake 初始握手失败: $e');
      _handleFailure();
    }
  }

  /// 启动心跳定时器
  ///
  /// 连接成功后调用，定期发送 ping 消息保持连接活跃。
  void _startPing() {
    _pingTimer?.cancel();
    _sendPing();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      _sendPing();
    });
  }

  /// 停止心跳定时器
  ///
  /// 连接断开或发生错误时调用。
  void _stopPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// 发送心跳消息
  ///
  /// 向服务器发送 'ping' 字符串，服务器会返回 'pong'。
  /// 这用于检测连接是否仍然活跃。
  void _sendPing() {
    try {
      if (_channel != null) {
        _channel!.sink.add('ping');
      }
    } catch (_) {}
  }

  /// 处理接收到的原始数据
  ///
  /// 解析 WebSocket 接收到的数据，支持单条消息和消息数组。
  ///
  /// 参数：
  /// - [data]: WebSocket 接收到的原始数据（通常是 JSON 字符串）
  void _handleData(dynamic data) {
    try {
      final json = jsonDecode(data.toString());

      if (json is List) {
        for (final item in json) {
          if (item is Map<String, dynamic>) {
            _dispatchMessage(item);
          }
        }
        return;
      }

      if (json is Map<String, dynamic>) {
        _dispatchMessage(json);
      }
    } catch (e) {
      debugPrint('P2PQuake 数据解析异常: $e');
    }
  }

  /// 消息分发器
  ///
  /// 根据消息代码将消息分发到对应的处理方法。
  ///
  /// ## 消息代码
  /// - **551**: JMA 地震情报
  /// - **552**: JMA 海啸情报
  ///
  /// 参数：
  /// - [json]: 解析后的 JSON 消息对象
  void _dispatchMessage(Map<String, dynamic> json) {
    final int code = json['code'] is int
        ? json['code']
        : int.tryParse(json['code']?.toString() ?? '') ?? 0;

    switch (code) {
      case 551:
        _handleJmaEqInfo(json);
        return;
      case 552:
        _handleJmaTsunami(json);
    }
  }

  /// 处理 JMA 地震情报 (code 551)
  ///
  /// 根据情报类型分发到对应的处理方法。
  ///
  /// ## 情报类型
  /// - **ScalePrompt**: 震度速报（最快，仅最大震度）
  /// - **Destination**: 震源速报（震源位置信息）
  /// - **ScaleAndDestination**: 震度震源速报（完整信息）
  /// - **DetailScale**: 详细震度速报
  /// - **Foreign**: 海外地震情报
  /// - **Other**: 其他类型
  ///
  /// 参数：
  /// - [json]: 完整的地震情报 JSON 数据
  void _handleJmaEqInfo(Map<String, dynamic> json) {
    try {
      final issue = json['issue'];
      if (issue == null) return;

      final eq = json['earthquake'];
      if (eq == null) return;

      final payload = snapshotSourcePayload(json);
      _emitP2pUnified(_mergeJmaEqInfo(json), payload);
    } catch (e) {
      debugPrint('P2PQuake 551 地震情报解析异常: $e');
    }
  }

  /// 处理 JMA 海啸情报 (code 552)
  ///
  /// 解析海啸预警信息，支持警报、注意报和取消报。
  ///
  /// ## 海啸等级
  /// - **MajorWarning**: 大海啸警报（预计浪高 > 3m）
  /// - **Warning**: 海啸警报（预计浪高 1-3m）
  /// - **Watch**: 海啸注意报（预计浪高 0.2-1m）
  /// - **取消报**: 海啸警报解除
  ///
  /// 参数：
  /// - [json]: 完整的海啸情报 JSON 数据
  void _handleJmaTsunami(Map<String, dynamic> json) {
    try {
      final tsunami = TsunamiMessage.parseJmaTsunami(json);
      debugPrint(
        'P2PQuake 海啸情报(552): ${tsunami.title}'
        '${tsunami.isActive ? " (${tsunami.areas.length}区域)" : ""}',
      );
      emitTsunami(tsunami);
    } catch (e) {
      debugPrint('P2PQuake 552 海啸情报解析异常: $e');
    }
  }

  /// 处理连接失败
  ///
  /// 更新状态并触发自动重连机制。
  void _handleFailure() {
    onStatusChanged?.call(SourceStatus.error);
    if (!_isManualClose) {
      _scheduleReconnect();
    }
  }

  /// 调度重连
  ///
  /// 使用递增延迟策略安排下一次重连尝试。
  ///
  /// ## 重连策略
  /// - 基础延迟: 3秒
  /// - 递增步长: 每次失败增加5秒
  /// - 最大延迟: 30秒
  void _scheduleReconnect() {
    if (_isManualClose) return;
    if (_reconnectTimer?.isActive ?? false) return;

    _retryCount++;
    final delay = (_retryCount + 2).clamp(3, 10);

    _reconnectTimer = Timer(Duration(seconds: delay), () {
      connect();
    });
  }

  /// 清理连接资源
  ///
  /// 关闭 WebSocket 通道并释放相关资源。
  void _cleanup() {
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  /// 断开连接
  ///
  /// 主动断开 WebSocket 连接并停止自动重连。
  ///
  /// 调用此方法后，服务将不会自动重连，
  /// 直到再次调用 [connect] 方法。
  @override
  void disconnect() {
    _isManualClose = true;
    _reconnectTimer?.cancel();
    _stopPing();
    _cleanup();
    onStatusChanged?.call(SourceStatus.disconnected);
  }

  /// 调试打印
  ///
  /// 输出调试信息到控制台。
  void debugPrint(String message) {
    // ignore: avoid_print
    print(message);
  }

  @visibleForTesting
  void handleMessageForTesting(String data) => _handleData(data);

  void _emitP2pUnified(
    Map<String, dynamic> json,
    Map<String, dynamic> payload,
  ) {
    final result = QuakeEventAdapter.convert('jmaEqlist', json, 2);
    if (result != null) emitUnified(result.copyWith(sourcePayload: payload));
  }

  Map<String, dynamic> _mergeJmaEqInfo(Map<String, dynamic> json) {
    final earthquake = json['earthquake'];
    if (earthquake is! Map<String, dynamic>) return json;

    final key = earthquake['time']?.toString().trim();
    if (key == null || key.isEmpty) return json;

    final previous = _jmaEqInfoStateByTime[key];
    if (previous == null) {
      final stored = _deepCopyMap(json);
      _jmaEqInfoStateByTime[key] = stored;
      _trimJmaEqInfoState();
      return stored;
    }

    final merged = _deepCopyMap(previous);
    final current = _deepCopyMap(json);
    merged.addAll(current);
    final issue = current['issue'];
    final issueType = issue is Map<String, dynamic>
        ? issue['type']?.toString() ?? ''
        : '';

    final previousEq = previous['earthquake'];
    final currentEq = current['earthquake'];
    if (previousEq is Map<String, dynamic> &&
        currentEq is Map<String, dynamic>) {
      final mergedEq = _deepCopyMap(previousEq)..addAll(currentEq);

      final currentHypocenter = currentEq['hypocenter'];
      final previousHypocenter = previousEq['hypocenter'];
      if (currentHypocenter is Map<String, dynamic>) {
        if (_hasValidHypocenter(currentHypocenter)) {
          mergedEq['hypocenter'] = currentHypocenter;
        } else if (previousHypocenter is Map<String, dynamic>) {
          mergedEq['hypocenter'] = previousHypocenter;
        }
      }

      if (!_hasValidMaxScale(currentEq['maxScale']) &&
          _hasValidMaxScale(previousEq['maxScale'])) {
        mergedEq['maxScale'] = previousEq['maxScale'];
      }
      if (issueType == 'Destination' &&
          _hasValidMaxScale(previousEq['maxScale'])) {
        mergedEq['maxScale'] = previousEq['maxScale'];
      }

      merged['earthquake'] = mergedEq;
    }

    final currentPoints = current['points'];
    final previousPoints = previous['points'];
    if (previousPoints is List &&
        (issueType == 'Destination' ||
            (currentPoints is List && currentPoints.isEmpty))) {
      merged['points'] = previousPoints;
    }

    _jmaEqInfoStateByTime[key] = merged;
    return merged;
  }

  Map<String, dynamic> _deepCopyMap(Map<String, dynamic> value) {
    return jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  }

  bool _hasValidHypocenter(Map<String, dynamic> hypocenter) {
    final name = hypocenter['name']?.toString().trim() ?? '';
    final lat = _parseDouble(hypocenter['latitude']);
    final lng = _parseDouble(hypocenter['longitude']);
    final normalizedName = name.toLowerCase();
    return name.isNotEmpty &&
        normalizedName != '調査中' &&
        normalizedName != '调查中' &&
        normalizedName != '不明' &&
        normalizedName != '不詳' &&
        normalizedName != 'unknown' &&
        lat != null &&
        lng != null &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180 &&
        (lat != 0 || lng != 0);
  }

  bool _hasValidMaxScale(dynamic value) {
    final scale = value is int ? value : int.tryParse(value?.toString() ?? '');
    return scale != null && scale > 0;
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  void _trimJmaEqInfoState() {
    while (_jmaEqInfoStateByTime.length > 20) {
      _jmaEqInfoStateByTime.remove(_jmaEqInfoStateByTime.keys.first);
    }
  }
}
