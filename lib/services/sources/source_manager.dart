/// 数据源管理器
///
/// 本模块实现了地震数据源的统一管理和协调。
/// 采用单例模式，负责管理所有数据源服务的生命周期和消息分发。
///
/// ## 主要功能
///
/// - **数据源注册**: 统一注册和管理所有数据源服务
/// - **状态监控**: 实时监控各数据源的连接状态
/// - **消息分发**: 接收并分发地震消息到事件总线
/// - **去重处理**: 防止重复消息的传播
///
/// ## 支持的数据源
///
/// - **Wolfx**: 日本气象厅紧急地震速报
/// - **FAN**: 全球地震数据聚合平台
/// - **P2PQuake**: 日本气象厅地震/海啸情报
/// - **NIED**: 日本强震观测网
/// - **S-net**: 日本海底地震观测网
/// - **KMA**: 韩国气象厅地震情报
/// - **USGS**: 美国地质调查局地震目录
///
/// ## 使用示例
///
/// ```dart
/// final manager = SourceManager();
/// manager.registerSource(WolfxService());
/// manager.registerSource(FanService());
/// manager.startAll();
///
/// // 监听状态更新
/// manager.onStatusUpdate.listen((update) {
///   print('${update.sourceName}: ${update.status}');
/// });
/// ```
library;

import 'dart:async';
import 'base_source.dart';
import '../event_bus.dart';
import '../../models/quake_message.dart';
import '../../models/source_status.dart';
import '../../models/source_credential_info.dart';

/// 数据源状态更新事件
///
/// 当数据源连接状态发生变化时发出此事件。
/// 包含数据源名称和新的连接状态。
class SourceStatusUpdate {
  /// 数据源名称
  ///
  /// 标识状态发生变化的数据源，如 "Wolfx"、"FAN"、"P2P" 等。
  final String sourceName;

  /// 新的连接状态
  ///
  /// 可能的值：
  /// - [SourceStatus.disconnected]: 已断开
  /// - [SourceStatus.connecting]: 连接中
  /// - [SourceStatus.connected]: 已连接
  /// - [SourceStatus.error]: 连接错误
  final SourceStatus status;
  final String? authenticationStatus;
  final SourceCredentialInfo? credentialInfo;

  /// 构造函数
  ///
  /// 参数：
  /// - [sourceName]: 数据源名称
  /// - [status]: 新的连接状态
  SourceStatusUpdate(this.sourceName, this.status,
    {this.authenticationStatus, this.credentialInfo});
}

/// 数据源管理器
///
/// 单例模式实现，统一管理所有地震数据源服务。
///
/// ## 设计模式
///
/// 采用单例模式确保全局只有一个管理器实例，
/// 所有数据源共享同一个管理器，便于统一协调。
///
/// ## 消息流程
///
/// 1. 数据源服务接收原始数据
/// 2. 数据源服务解析并生成 QuakeMessage
/// 3. SourceManager 接收消息并进行去重
/// 4. 通过 QuakeEventBus 发布给订阅者
///
/// ## 去重机制
///
/// 使用时间+坐标组合作为去重键，防止同一地震事件
/// 被多个数据源重复报告。去重记录保留1小时后自动清理。
class SourceManager {
  /// 单例实例
  ///
  /// 全局唯一的 SourceManager 实例。
  static final SourceManager _instance = SourceManager._internal();

  /// 工厂构造函数
  ///
  /// 返回单例实例，确保全局只有一个管理器。
  factory SourceManager() => _instance;

  /// 私有构造函数
  ///
  /// 内部构造函数，防止外部直接创建实例。
  SourceManager._internal();

  /// 已注册的数据源列表
  ///
  /// 存储所有已注册的数据源服务实例。
  final List<BaseSourceService> _sources = [];

  /// 已处理消息的去重ID缓存
  ///
  /// 键: 去重ID（时间+坐标组合）
  /// 值: 处理时间
  ///
  /// 用于防止同一地震事件被重复处理。
  final Map<String, DateTime> _processedIds = {};

  /// 状态更新流控制器
  ///
  /// 广播模式，允许多个监听者同时订阅状态更新。
  final _statusController = StreamController<SourceStatusUpdate>.broadcast();
  final _eventController = StreamController<QuakeMessage>.broadcast();

  /// 状态更新事件流
  ///
  /// 订阅此流可实时获取各数据源的连接状态变化。
  ///
  /// ## 使用示例
  ///
  /// ```dart
  /// manager.onStatusUpdate.listen((update) {
  ///   if (update.status == SourceStatus.error) {
  ///     print('${update.sourceName} 连接失败');
  ///   }
  /// });
  /// ```
  Stream<SourceStatusUpdate> get onStatusUpdate => _statusController.stream;

  /// 经过去重后的原始统一入口消息，用于 Android 前台服务跨 isolate 转发。
  Stream<QuakeMessage> get onQuakeEvent => _eventController.stream;

  final List<StreamSubscription<QuakeMessage>> _sourceSubscriptions = [];
  bool _started = false;
  final Set<String> _disabledSourceNames = {};

  /// 注册数据源服务
  ///
  /// 将数据源服务添加到管理器中进行统一管理。
  /// 注册后会自动绑定状态变化回调。
  ///
  /// 参数：
  /// - [source]: 要注册的数据源服务实例
  ///
  /// ## 使用示例
  ///
  /// ```dart
  /// manager.registerSource(WolfxService());
  /// manager.registerSource(FanService());
  /// ```
  void registerSource(BaseSourceService source) {
    _sources.add(source);
    source.onStatusChanged = (status) {
      _statusController.add(SourceStatusUpdate(source.name, status,
        authenticationStatus: source.authenticationStatus,
        credentialInfo: source.credentialInfo));
    };
  }

  void setSourceEnabled(String sourceName, bool enabled) {
    if (isSourceEnabled(sourceName) == enabled) return;
    BaseSourceService? source;
    for (final item in _sources) {
      if (item.name == sourceName) {
        source = item;
        break;
      }
    }
    if (enabled) {
      _disabledSourceNames.remove(sourceName);
      if (_started) source?.connect();
    } else {
      _disabledSourceNames.add(sourceName);
      source?.disconnect();
    }
  }

  bool isSourceEnabled(String sourceName) {
    return !_disabledSourceNames.contains(sourceName);
  }

  /// 启动所有数据源
  ///
  /// 遍历所有已注册的数据源，依次建立连接并开始监听消息。
  /// 每个数据源的消息事件都会被转发到 [_handleIncomingEvent] 处理。
  ///
  /// ## 启动流程
  ///
  /// 1. 调用数据源的 connect() 方法建立连接
  /// 2. 订阅数据源的 onEvent 流接收消息
  /// 3. 消息经过去重后发布到事件总线
  /// 4. 采用 80ms 错峰握手，避免 6 个 WSS/TLS 连接同时发起造成 CPU 瞬时飙升
  void startAll({Duration stagger = const Duration(milliseconds: 80)}) {
    if (_started) return;
    _started = true;
    var delayIndex = 0;
    for (var source in _sources) {
      _sourceSubscriptions.add(source.onEvent.listen(_handleIncomingEvent));
      if (source.autoStart && isSourceEnabled(source.name)) {
        if (delayIndex == 0 || stagger == Duration.zero) {
          source.connect();
        } else {
          final delayMs = delayIndex * stagger.inMilliseconds;
          Timer(Duration(milliseconds: delayMs), () {
            if (!_started || !isSourceEnabled(source.name)) return;
            source.connect();
          });
        }
        delayIndex++;
      }
    }
  }

  void stopAll() {
    if (!_started) return;
    _started = false;
    for (final source in _sources) {
      source.disconnect();
    }
    for (final subscription in _sourceSubscriptions) {
      subscription.cancel();
    }
    _sourceSubscriptions.clear();
  }

  /// 清空当前 isolate 的源实例，供 Android 前台服务重载设置时使用。
  void reset() {
    stopAll();
    _sources.clear();
    _disabledSourceNames.clear();
    _processedIds.clear();
  }

  /// 获取指定类型的数据源实例
  ///
  /// 从已注册的数据源中查找并返回指定类型的实例。
  /// 用于需要直接访问特定数据源的场景。
  ///
  /// 参数：
  /// - [T]: 数据源服务的类型
  ///
  /// 返回：
  /// - 找到的数据源实例，如果不存在则返回 null
  ///
  /// ## 使用示例
  ///
  /// ```dart
  /// final nied = manager.getSource<NiedMonitor>();
  /// if (nied != null) {
  ///   print('NIED 当前状态: ${nied.currentStatus}');
  /// }
  /// ```
  T? getSource<T extends BaseSourceService>() {
    for (final source in _sources) {
      if (source is T) return source;
    }
    return null;
  }

  /// 处理接收到的地震事件
  ///
  /// 对消息进行去重检查，通过后发布到事件总线。
  ///
  /// ## 去重策略
  ///
  /// 使用 "分钟级时间_纬度_经度" 作为去重键。
  /// 同一分钟内、同一位置（精确到0.1度）的事件视为重复。
  ///
  /// ## 缓存清理
  ///
  /// 每次处理消息后，清理超过1小时的缓存记录，
  /// 防止内存无限增长。
  ///
  /// 参数：
  /// - [event]: 接收到的地震消息
  void _handleIncomingEvent(QuakeMessage event) {
    if (!event.isHistory) {
      final dedupeId = _dedupeKey(event);
      if (dedupeId != null) {
        if (_processedIds.containsKey(dedupeId)) {
          return;
        }
        _processedIds[dedupeId] = DateTime.now();
      }
    }

    QuakeEventBus().publish(event);
    _eventController.add(event);

    _processedIds.removeWhere(
      (key, time) => DateTime.now().difference(time).inHours > 1,
    );
  }

  String? _dedupeKey(QuakeMessage event) {
    if (event.isInfoEvent) return null;
    final eventId = event.eventId.trim();
    if (eventId.isEmpty) return null;
    final reportNumber = event.reportNumber ?? -1;
    return '${event.source.name}|$eventId|$reportNumber';
  }
}
