/// 数据源服务基类
///
/// 本模块定义了所有地震数据源服务的抽象基类。
/// 所有数据源服务（如 Wolfx、FAN、P2PQuake 等）都必须继承此类。
///
/// ## 设计模式
///
/// 采用模板方法模式，定义了数据源服务的标准接口：
/// - [connect]: 建立数据源连接
/// - [disconnect]: 断开数据源连接
/// - [emit]: 发送地震消息到事件流
///
/// ## 事件流
///
/// 每个数据源服务都有一个广播事件流 [onEvent]，
/// 用于向订阅者推送解析后的地震消息。
///
/// ## 状态管理
///
/// 数据源服务通过 [onStatusChanged] 回调通知状态变化，
/// 状态包括：连接中、已连接、断开、错误等。
///
/// ## 使用示例
///
/// ```dart
/// class MySourceService extends BaseSourceService {
///   @override
///   String get name => 'MySource';
///
///   @override
///   void connect() {
///     onStatusChanged?.call(SourceStatus.connecting);
///     // 建立连接...
///     onStatusChanged?.call(SourceStatus.connected);
///   }
///
///   @override
///   void disconnect() {
///     // 断开连接...
///     onStatusChanged?.call(SourceStatus.disconnected);
///   }
///
///   void onDataReceived(Map<String, dynamic> data) {
///     final message = parseData(data);
///     emit(message);
///   }
/// }
/// ```

import 'dart:async';
import '../../models/quake_message.dart';
import '../../models/unified_quake_data.dart';
import '../../models/tsunami_message.dart';
import '../../models/source_status.dart';
import '../../models/source_credential_info.dart';

/// 数据源服务抽象基类
///
/// 所有地震数据源服务的基类，定义了标准接口和事件流机制。
///
/// ## 职责
///
/// - 管理数据源连接生命周期
/// - 提供地震消息事件流 (QuakeMessage + UnifiedQuakeData)
/// - 通知连接状态变化
///
/// ## 子类需要实现的方法
///
/// - [name]: 返回数据源名称标识
/// - [connect]: 建立数据源连接
/// - [disconnect]: 断开数据源连接
abstract class BaseSourceService {
  /// 地震消息事件流控制器
  ///
  /// 使用广播模式，允许多个订阅者同时监听。
  final _controller = StreamController<QuakeMessage>.broadcast();

  /// 统一数据事件流控制器
  final _unifiedController = StreamController<UnifiedQuakeData>.broadcast();

  /// 海啸事件流控制器
  final _tsunamiController = StreamController<TsunamiMessage>.broadcast();

  /// 地震消息事件流
  ///
  /// 订阅此流可以接收该数据源解析后的地震消息。
  /// 通常由 [SourceManager] 统一订阅并分发。
  Stream<QuakeMessage> get onEvent => _controller.stream;

  /// 统一数据事件流
  Stream<UnifiedQuakeData> get onUnifiedEvent => _unifiedController.stream;

  /// 海啸事件流
  Stream<TsunamiMessage> get onTsunamiEvent => _tsunamiController.stream;

  /// 数据源名称标识
  ///
  /// 用于在日志和状态显示中标识此数据源。
  /// 例如：'Wolfx'、'FAN'、'P2P' 等。
  String get name;

  String? get authenticationStatus => null;
  SourceCredentialInfo? get credentialInfo => null;

  /// 连接状态变化回调
  ///
  /// 当数据源连接状态发生变化时触发。
  /// 由 [SourceManager] 设置，用于更新全局状态。
  /// Whether this source should be connected by [SourceManager.startAll].
  bool get autoStart => true;

  Function(SourceStatus status)? onStatusChanged;

  /// 建立数据源连接
  ///
  /// 子类需要实现此方法以建立与数据源的连接。
  /// 连接成功后应调用 `onStatusChanged?.call(SourceStatus.connected)`。
  void connect();

  /// 断开数据源连接
  ///
  /// 子类需要实现此方法以断开与数据源的连接。
  /// 断开后应调用 `onStatusChanged?.call(SourceStatus.disconnected)`。
  void disconnect();

  /// 发送地震消息到事件流
  ///
  /// 当数据源解析出新的地震消息时调用此方法。
  /// 消息将被广播给所有订阅者。
  ///
  /// 参数：
  /// - [event]: 要发送的地震消息
  void emit(QuakeMessage event) {
    _controller.add(event);
  }

  /// 发送统一数据到事件流
  void emitUnified(UnifiedQuakeData event) {
    _unifiedController.add(event);
  }

  /// 发送海啸消息到事件流
  void emitTsunami(TsunamiMessage event) {
    _tsunamiController.add(event);
  }

  /// 清理资源
  ///
  /// 子类可以重写此方法来清理特定资源。
  /// 基类实现会关闭事件流控制器。
  void dispose() {
    _controller.close();
    _unifiedController.close();
    _tsunamiController.close();
  }
}
