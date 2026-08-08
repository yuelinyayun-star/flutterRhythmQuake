/// Wolfx 地震预警聚合服务
///
/// 本模块实现了 Wolfx WebSocket API 的数据获取与处理。
/// Wolfx 是一个聚合多个地震预警数据源的实时推送服务。
///
/// 支持的数据源：
/// - **JMA**: 日本气象厅紧急地震速报
/// - **CENC**: 中国地震台网中心地震预警
/// - **FJ_EEW**: 福建省地震局地震预警
/// - **CQ_EEW**: 重庆市地震局地震预警
/// - **SC_EEW**: 四川省地震局地震预警
/// - **CWA**: 台湾中央气象署地震预警
///
/// 主要功能：
/// - WebSocket 实时连接管理
/// - 多格式消息解析与分发
/// - 自动重连与错误处理
/// - 心跳检测与响应
///
/// 数据流程：
/// 1. 建立 WebSocket 连接到 wss://ws-api.wolfx.jp/all_eew
/// 2. 接收实时推送的地震预警消息
/// 3. 根据消息类型分发到对应的处理方法
/// 4. 解析数据并转换为统一的 QuakeMessage 格式
/// 5. 通过回调通知上层应用

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'base_source.dart';
import '../quake_event_adapter.dart';
import '../../models/quake_message.dart';
import '../../models/source_status.dart';

/// Wolfx 服务类
///
/// 继承自 BaseSourceService，实现 Wolfx API 的具体逻辑。
/// 负责管理 WebSocket 连接、消息解析和数据分发。
class WolfxService extends BaseSourceService {
  /// 服务名称标识
  @override
  String get name => 'Wolfx';

  // ═══════════════════════════════════════════════════════════════════════════
  // 连接配置
  // ═══════════════════════════════════════════════════════════════════════════

  /// WebSocket 服务端点 URL
  ///
  /// Wolfx API 的统一入口，订阅所有地震预警数据流。
  final String _wsUrl = "wss://ws-api.wolfx.jp/all_eew";

  /// WebSocket 通道实例
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSubscription;

  // ═══════════════════════════════════════════════════════════════════════════
  // 状态变量
  // ═══════════════════════════════════════════════════════════════════════════

  /// 重连定时器
  Timer? _reconnectTimer;
  Timer? _queryTimer;

  /// 重试计数器
  int _retryCount = 0;

  /// 每次连接都会递增，旧连接的异步回调不得操作新连接。
  int _connectionSerial = 0;
  int _failedConnectionSerial = -1;

  /// 每种报文仅保留最后一次完整原始内容，用于压制查询得到的重复日志。
  final Map<String, String> _lastLoggedRawPayloadByType = {};

  void Function(List<QuakeMessage>)? onJmaEqlistUpdated;

  /// 是否为手动关闭
  ///
  /// 用于区分手动断开和异常断开。
  /// 手动断开时不触发自动重连。
  bool _isManualClose = false;

  // ═══════════════════════════════════════════════════════════════════════════
  // 连接管理
  // ═══════════════════════════════════════════════════════════════════════════

  /// 发起连接
  ///
  /// 建立 WebSocket 连接到 Wolfx 服务器。
  /// 连接成功后自动监听消息流，连接失败则触发重连机制。
  @override
  void connect() {
    unawaited(_connect());
  }

  Future<void> _connect() async {
    _isManualClose = false;
    _lastLoggedRawPayloadByType.clear();
    final serial = ++_connectionSerial;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _cleanup();
    if (!_isCurrentConnection(serial)) return;

    onStatusChanged?.call(SourceStatus.connecting);
    print("正在建立 Wolfx 链路: $_wsUrl (尝试次数: ${_retryCount + 1})");

    WebSocketChannel? channel;
    try {
      final newChannel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      channel = newChannel;
      if (!_isCurrentConnection(serial)) {
        await newChannel.sink.close();
        return;
      }
      _channel = newChannel;
      _channelSubscription = newChannel.stream.listen(
        (data) {
          if (!_isActiveConnection(newChannel, serial)) return;

          // 收到首包才表示数据链路真正恢复。
          if (_retryCount > 0) {
            print("Wolfx 链路已恢复正常");
          }
          _retryCount = 0;
          onStatusChanged?.call(SourceStatus.connected);
          _dispatch(data, newChannel, serial);
        },
        onDone: () {
          if (!_isActiveConnection(newChannel, serial)) return;
          print("Wolfx 链路远程关闭");
          unawaited(_handleFailure(newChannel, serial));
        },
        onError: (Object err) {
          if (!_isActiveConnection(newChannel, serial)) return;
          print("Wolfx 链路传输错误: $err");
          unawaited(_handleFailure(newChannel, serial));
        },
        cancelOnError: true,
      );

      await newChannel.ready.timeout(const Duration(seconds: 10));
      if (!_isActiveConnection(newChannel, serial)) return;

      unawaited(_sendSubscriptionMessages(newChannel, serial));
      _queryTimer?.cancel();
      _queryTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => unawaited(_sendSubscriptionMessages(newChannel, serial)),
      );
    } catch (e) {
      if (!_isCurrentConnection(serial)) return;
      if (_failedConnectionSerial == serial) return;
      print("Wolfx 初始握手失败: $e");
      await _handleFailure(channel, serial);
    }
  }

  bool _isCurrentConnection(int serial) {
    return !_isManualClose && serial == _connectionSerial;
  }

  bool _isActiveConnection(WebSocketChannel channel, int serial) {
    return _isCurrentConnection(serial) && identical(_channel, channel);
  }

  void _logRawPayload(
    String type,
    Map<String, dynamic> json,
    String rawPayload,
  ) {
    if (_lastLoggedRawPayloadByType[type] == rawPayload) return;
    _lastLoggedRawPayloadByType[type] = rawPayload;
    print('RAW >> Wolfx $type: $json');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 消息分发
  // ═══════════════════════════════════════════════════════════════════════════

  /// 消息分发器
  ///
  /// 根据消息类型将数据分发到对应的处理方法。
  ///
  /// 支持的消息类型：
  /// - `heartbeat`: 心跳消息，需要回复 pong
  /// - `jma_eew`: 日本气象厅紧急地震速报
  /// - `cenc_eew`: 中国地震台网中心地震预警
  /// - `fj_eew`: 福建省地震局地震预警
  /// - `cq_eew`: 重庆市地震局地震预警
  /// - `sc_eew`: 四川省地震局地震预警
  /// - `cenc_eqlist`: 中国地震台网地震列表
  /// - 空类型: 台湾中央气象署地震预警
  ///
  /// 参数：
  /// - [data]: 原始消息数据
  void _dispatch(dynamic data, WebSocketChannel channel, int connectionSerial) {
    try {
      final json = jsonDecode(data);
      if (json is! Map<String, dynamic>) return;
      final rawPayload = data is String ? data : jsonEncode(json);

      final String type = json['type']?.toString() ?? '';

      // 处理心跳消息
      if (type == 'heartbeat') {
        if (!_isActiveConnection(channel, connectionSerial)) return;
        channel.sink.add(
          jsonEncode({
            "type": "pong",
            "timestamp": json['timestamp']?.toString(),
          }),
        );
        return;
      }
      if (type == 'pong') return;

      // 根据类型分发到对应处理方法
      switch (type) {
        case 'jma_eew':
          _logRawPayload(type, json, rawPayload);
          _emitUnified('jmaEew', json);
          break;
        case 'cenc_eew':
          _logRawPayload(type, json, rawPayload);
          _emitUnified('ceaEew', json);
          break;
        case 'cwa_eew':
          _logRawPayload(type, json, rawPayload);
          _emitUnified('cwaEew', json);
          break;
        case 'fj_eew':
          _logRawPayload(type, json, rawPayload);
          _emitUnified('fjEew', json);
          break;
        case 'cq_eew':
          _logRawPayload(type, json, rawPayload);
          _emitUnified('cqEew', json);
          break;
        case 'sc_eew':
          _logRawPayload(type, json, rawPayload);
          _emitUnified('scEew', json);
          break;
        case 'cenc_eqlist':
          _logRawPayload(type, json, rawPayload);
          final firstEntry = json['No1'];
          if (firstEntry is Map) {
            _emitUnified('cencEqlist', Map<String, dynamic>.from(firstEntry));
          }
          break;
        case 'jma_eqlist':
          final jmaItems = QuakeEventAdapter.convertWolfxJmaEqlist(json);
          if (jmaItems.isNotEmpty) onJmaEqlistUpdated?.call(jmaItems);
          break;
        case '':
          _logRawPayload('cwa_eew', json, rawPayload);
          _emitUnified('cwaEew', json);
          break;
        default:
          print("Wolfx 未知 type: $type");
      }
    } catch (e) {
      print("Wolfx 数据解析异常: $e");
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 错误处理与重连
  // ═══════════════════════════════════════════════════════════════════════════

  /// 处理连接失败
  ///
  /// 当连接出错或断开时调用。
  /// 如果不是手动关闭，则安排自动重连。
  Future<void> _handleFailure(
    WebSocketChannel? channel,
    int connectionSerial,
  ) async {
    if (!_isCurrentConnection(connectionSerial)) return;
    if (channel != null && !identical(_channel, channel)) return;
    if (_failedConnectionSerial == connectionSerial) return;

    _failedConnectionSerial = connectionSerial;
    onStatusChanged?.call(SourceStatus.error);
    final delay = (3 + _retryCount).clamp(3, 10);
    _retryCount++;

    // 与参考项目一致：3 秒起步，每次增加 1 秒，最大 10 秒。
    print("Wolfx 链路异常，$delay秒后重连 (第$_retryCount次)");

    _reconnectTimer?.cancel();
    await _cleanup();
    if (!_isCurrentConnection(connectionSerial)) return;

    _reconnectTimer = Timer(Duration(seconds: delay), () {
      if (!_isCurrentConnection(connectionSerial)) return;
      connect();
    });
  }

  /// 清理资源
  ///
  /// 关闭 WebSocket 连接并释放相关资源。
  Future<void> _cleanup() async {
    _queryTimer?.cancel();
    _queryTimer = null;

    final subscription = _channelSubscription;
    final channel = _channel;
    _channelSubscription = null;
    _channel = null;

    try {
      await subscription?.cancel();
    } catch (_) {}
    try {
      await channel?.sink.close();
    } catch (_) {}
  }

  Future<void> _sendSubscriptionMessages(
    WebSocketChannel channel,
    int connectionSerial,
  ) async {
    const messages = [
      'query_jmaeew',
      'query_cwaeew',
      'query_cenceew',
      'query_sceew',
      'query_fjeew',
      'query_jmaeqlist',
      'query_cenceqlist',
    ];

    final interval = Duration(
      milliseconds: (10000 ~/ messages.length).clamp(0, 2000).toInt(),
    );
    for (final message in messages) {
      if (!_isActiveConnection(channel, connectionSerial)) return;
      channel.sink.add(message);
      await Future<void>.delayed(interval);
    }
  }

  /// 断开连接
  ///
  /// 手动断开 WebSocket 连接。
  /// 设置手动关闭标志，避免触发自动重连。
  @override
  void disconnect() {
    _isManualClose = true;
    _connectionSerial++;
    _retryCount = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    unawaited(_cleanup());
    onStatusChanged?.call(SourceStatus.disconnected);
    print("Wolfx 链路已手动断开");
  }

  /// 通过适配器转换并发射统一事件
  void _emitUnified(String source, Map<String, dynamic> data) {
    final result = QuakeEventAdapter.convert(source, data, 0);
    if (result != null) {
      emitUnified(result);
    }
  }

  /// 释放资源
  ///
  /// 完全清理所有资源，包括定时器和连接。
  @override
  void dispose() {
    disconnect();
    _reconnectTimer?.cancel();
    super.dispose();
  }
}
