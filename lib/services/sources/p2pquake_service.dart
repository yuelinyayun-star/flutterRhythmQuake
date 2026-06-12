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
/// - 心跳检测：每30秒发送 ping 消息保持连接活跃
/// - 故障恢复：重连成功后自动重置重试计数

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'base_source.dart';
import '../../models/quake_message.dart';
import '../../models/tsunami_message.dart';
import '../../models/unified_quake_data.dart';
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

  /// WebSocket 服务器地址
  ///
  /// P2PQuake API v2 的 WebSocket 端点。
  static const String _wsUrl = 'wss://api.p2pquake.net/v2/ws';

  /// 心跳间隔
  ///
  /// 每30秒发送一次 ping 消息以保持连接活跃。
  /// 这是 P2PQuake 服务器的推荐心跳间隔。
  static const Duration _pingInterval = Duration(seconds: 30);

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
  void connect() {
    _isManualClose = false;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _cleanup();
    onStatusChanged?.call(SourceStatus.connecting);
    debugPrint('正在建立 P2PQuake 链路: $_wsUrl (尝试次数: ${_retryCount + 1})');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));

      _channel!.stream.listen(
        (data) {
          debugPrint('RAW >> P2PQuake: $data');
          if (_retryCount > 0) {
            debugPrint('P2PQuake 链路已恢复正常');
          }
          if (_retryCount == 0) {
            debugPrint('P2PQuake WebSocket 已连接，等待 JMA 地震/津波报文...');
          }
          _retryCount = 0;
          onStatusChanged?.call(SourceStatus.connected);
          _startPing();
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

      final issueType = issue['type']?.toString() ?? '';

      if (issueType == 'ScalePrompt') {
        _handleScalePrompt(json, issue, eq);
        _emitP2pUnified(json);
        return;
      }

      if (issueType == 'Destination') {
        _handleDestination(json, issue, eq);
        _emitP2pUnified(json);
        return;
      }

      _handleFullReport(json, issue, eq, issueType);
      _emitP2pUnified(json);
    } catch (e) {
      debugPrint('P2PQuake 551 地震情报解析异常: $e');
    }
  }

  /// 处理震度速报 (ScalePrompt)
  ///
  /// 震度速报是地震发生后最快发布的速报，仅包含最大震度信息。
  /// 此时震源位置和震级尚未确定。
  ///
  /// ## 数据特点
  /// - 只有最大震度，无震源位置
  /// - 无震级和深度信息
  /// - 发布速度最快（通常在震后1-2分钟）
  ///
  /// 参数：
  /// - [json]: 完整的 JSON 数据
  /// - [issue]: 发布信息对象
  /// - [eq]: 地震信息对象
  void _handleScalePrompt(
    Map<String, dynamic> json,
    Map<String, dynamic> issue,
    Map<String, dynamic> eq,
  ) {
    final int maxScale = int.tryParse(eq['maxScale']?.toString() ?? '') ?? -1;
    final String shindo = _maxScaleToShindo(maxScale);

    final String eventId = _makeEventId(json);
    debugPrint('P2PQuake 震度速報(551): 最大震度 $shindo');

    emit(QuakeMessage(
      source: QuakeSourceType.p2p,
      eventId: eventId,
      location: '日本境内',
      magnitude: -1,
      latitude: 0.0,
      longitude: 0.0,
      depth: -1,
      originTime: _parseReportTime(issue),
      maxIntensity: maxScale > 0 ? (maxScale / 10).round() : null,
      jmaShindo: maxScale > 0 ? shindo : null,
      infoTypeName: '震度速報',
      isInfoEvent: true,
    ));
  }

  /// 处理震源速报 (Destination)
  ///
  /// 震源速报包含震源位置、深度和震级信息，但不包含震度数据。
  ///
  /// ## 数据特点
  /// - 有震源位置（经纬度）
  /// - 有震级和深度
  /// - 无震度信息
  /// - 发布速度较快（通常在震后2-3分钟）
  ///
  /// 参数：
  /// - [json]: 完整的 JSON 数据
  /// - [issue]: 发布信息对象
  /// - [eq]: 地震信息对象
  void _handleDestination(
    Map<String, dynamic> json,
    Map<String, dynamic> issue,
    Map<String, dynamic> eq,
  ) {
    final hypo = eq['hypocenter'];
    if (hypo == null) return;

    final String location = hypo['name']?.toString() ?? '未知地点';
    final double lat = _parseCoordD(hypo['latitude']);
    final double lng = _parseCoordD(hypo['longitude']);
    final double depth = _parseDepthV(hypo['depth']);
    final double magnitude =
        double.tryParse(hypo['magnitude']?.toString() ?? '-1') ?? -1;
    final String eventId = _makeEventId(json);

    debugPrint(
      'P2PQuake 震源に関する情報(551): $location '
      'M${magnitude > 0 ? magnitude.toStringAsFixed(1) : "?"} '
      '深度 ${depth > 0 ? depth.round() : "?"}km',
    );

    emit(QuakeMessage(
      source: QuakeSourceType.p2p,
      eventId: eventId,
      location: location,
      magnitude: magnitude,
      latitude: lat,
      longitude: lng,
      depth: depth > 0 ? depth : 0.0,
      originTime: _parseReportTime(issue),
      maxIntensity: null,
      infoTypeName: '震源に関する情報',
      isInfoEvent: true,
    ));
  }

  /// 处理完整地震报告
  ///
  /// 处理 ScaleAndDestination、DetailScale、Foreign、Other 类型的地震情报。
  /// 这些类型包含完整的震源和震度信息。
  ///
  /// ## 支持的类型
  /// - **ScaleAndDestination**: 震度震源速报（最常见）
  /// - **DetailScale**: 详细震度速报
  /// - **Foreign**: 海外地震情报
  /// - **Other**: 其他类型地震情报
  ///
  /// 参数：
  /// - [json]: 完整的 JSON 数据
  /// - [issue]: 发布信息对象
  /// - [eq]: 地震信息对象
  /// - [issueType]: 情报类型字符串
  void _handleFullReport(
    Map<String, dynamic> json,
    Map<String, dynamic> issue,
    Map<String, dynamic> eq,
    String issueType,
  ) {
    final hypo = eq['hypocenter'];
    if (hypo == null) return;

    final String location = hypo['name']?.toString() ?? '未知地点';
    final double lat = _parseCoordD(hypo['latitude']);
    final double lng = _parseCoordD(hypo['longitude']);
    final double depth = _parseDepthV(hypo['depth']);
    final double magnitude =
        double.tryParse(hypo['magnitude']?.toString() ?? '-1') ?? -1;

    final int maxScale = int.tryParse(eq['maxScale']?.toString() ?? '') ?? -1;
    final String shindo = _maxScaleToShindo(maxScale);
    final int? jmaIntensity =
        maxScale > 0 ? (maxScale / 10).round() : null;

    final String eventId = _makeEventId(json);

    final title = _issueTypeLabel(issueType);
    debugPrint(
      'P2PQuake $title(551): $location '
      'M${magnitude > 0 ? magnitude.toStringAsFixed(1) : "?"} '
      '震度 $shindo '
      '深度 ${depth > 0 ? depth.round() : "?"}km',
    );

    emit(QuakeMessage(
      source: QuakeSourceType.p2p,
      eventId: eventId,
      location: location,
      magnitude: magnitude,
      latitude: lat,
      longitude: lng,
      depth: depth > 0 ? depth : 0.0,
      originTime: _parseReportTime(issue),
      maxIntensity: jmaIntensity,
      jmaShindo: shindo,
      infoTypeName: title,
      isInfoEvent: true,
    ));
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

  /// 解析坐标值
  ///
  /// P2PQuake API 返回的坐标可能带有方向前缀（如 "N35.5"）。
  /// 此方法解析并转换为标准十进制度数。
  ///
  /// ## 格式支持
  /// - 带前缀: "N35.5" → 35.5, "S35.5" → -35.5
  /// - 纯数值: "35.5" → 35.5
  ///
  /// 参数：
  /// - [value]: 原始坐标值（可能是字符串或数值）
  ///
  /// 返回：
  /// - 解析后的十进制度数，南纬/西经为负值
  double _parseCoordD(dynamic value) {
    if (value == null) return 0.0;
    String v = value.toString().trim();
    if (v.isEmpty) return 0.0;

    final String prefix = v[0].toUpperCase();
    if (prefix == 'N' || prefix == 'S' || prefix == 'E' || prefix == 'W') {
      double val = double.tryParse(v.substring(1)) ?? 0.0;
      return prefix == 'S' || prefix == 'W' ? -val : val;
    }
    return double.tryParse(v) ?? 0.0;
  }

  /// 解析深度值
  ///
  /// P2PQuake API 返回的深度可能带有单位（如 "10km"）。
  /// 此方法提取数值部分。
  ///
  /// 参数：
  /// - [value]: 原始深度值（可能是字符串或数值）
  ///
  /// 返回：
  /// - 解析后的深度值（单位：km）
  double _parseDepthV(dynamic value) {
    if (value == null) return 0.0;
    String v = value.toString().trim().toLowerCase();
    v = v.replaceAll('km', '').trim();
    return double.tryParse(v) ?? 0.0;
  }

  /// 将 maxScale 转换为震度等级字符串
  ///
  /// P2PQuake API 使用整数编码震度等级：
  /// - 10: 震度1
  /// - 20: 震度2
  /// - 30: 震度3
  /// - 40: 震度4
  /// - 45: 震度5弱
  /// - 46: 震度5弱（另一种编码）
  /// - 50: 震度5强
  /// - 55: 震度6弱
  /// - 60: 震度6强
  /// - 70: 震度7
  ///
  /// 参数：
  /// - [maxScale]: API 返回的震度编码值
  ///
  /// 返回：
  /// - 震度等级字符串（如 "5弱"、"7"）
  String _maxScaleToShindo(int maxScale) {
    if (maxScale <= 0) return '不明';
    switch (maxScale) {
      case 10: return '1';
      case 20: return '2';
      case 30: return '3';
      case 40: return '4';
      case 45: return '5弱';
      case 46: return '5弱';
      case 50: return '5强';
      case 55: return '6弱';
      case 60: return '6强';
      case 70: return '7';
      default: return '${(maxScale / 10).floor()}';
    }
  }

  /// 获取情报类型标签
  ///
  /// 将 API 返回的情报类型代码转换为可读的中文标签。
  ///
  /// 参数：
  /// - [type]: 情报类型代码
  ///
  /// 返回：
  /// - 中文标签字符串
  String _issueTypeLabel(String type) {
    switch (type) {
      case 'ScalePrompt':
        return '震度速報';
      case 'Destination':
        return '震源に関する情報';
      case 'ScaleAndDestination':
        return '震度・震源に関する情報';
      case 'DetailScale':
        return '各地の震度に関する情報';
      case 'Foreign':
        return '遠地地震に関する情報';
      case 'Other':
        return 'その他の情報';
      default:
        return '地震情報';
    }
  }

  /// 解析报告时间
  ///
  /// 从 issue 对象中提取地震发生时间。
  ///
  /// ## 时间格式
  /// API 返回的时间格式为 "2024/01/01 15:00:00"，
  /// 需要转换为 DateTime 对象。
  ///
  /// 参数：
  /// - [issue]: 发布信息对象
  ///
  /// 返回：
  /// - 解析后的 DateTime 对象，解析失败则返回当前时间
  DateTime _parseReportTime(Map<String, dynamic> issue) {
    final raw = issue['time']?.toString();
    if (raw != null && raw.isNotEmpty) {
      final dt = DateTime.tryParse(raw.replaceAll('/', '-'));
      if (dt != null) return dt;
    }
    return DateTime.now();
  }

  /// 生成事件 ID
  ///
  /// 从 JSON 数据中提取或生成唯一的事件标识符。
  ///
  /// ## ID 来源优先级
  /// 1. MongoDB ObjectId (_id.$oid)
  /// 2. 基于时间和消息代码的哈希值
  ///
  /// 参数：
  /// - [json]: 完整的消息 JSON 数据
  ///
  /// 返回：
  /// - 唯一的事件 ID 字符串
  String _makeEventId(Map<String, dynamic> json) {
    final id = json['_id'];
    if (id is Map && id['\$oid'] != null) {
      return id['\$oid'].toString();
    }
    final time = json['time']?.toString() ?? '';
    return 'p2p_${time}_${json['code']}'.hashCode.abs().toString();
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
    int delay = (_retryCount * 5).clamp(3, 30);

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

  void _emitP2pUnified(Map<String, dynamic> json) {
    final result = QuakeEventAdapter.convert('jmaEqlist', json, 2);
    if (result != null) emitUnified(result);
  }
}
