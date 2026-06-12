import 'dart:async';
import '../models/quake_message.dart';

/// 地震事件总线
/// 
/// 该类提供全局事件广播功能，用于在应用内传递地震事件。
/// 采用单例模式，确保全局只有一个事件总线实例。
/// 
/// 主要功能：
/// - 发布地震事件
/// - 订阅地震事件流
/// - 过滤测试事件
/// 
/// 使用场景：
/// - 数据源收到新地震时发布事件
/// - UI组件订阅事件并更新显示
/// - 预警系统监听事件触发警报
class QuakeEventBus {
  static final QuakeEventBus _instance = QuakeEventBus._internal();
  factory QuakeEventBus() => _instance;
  QuakeEventBus._internal();

  /// 广播流控制器
  /// 
  /// 使用广播模式，允许多个Widget同时监听
  final _controller = StreamController<QuakeMessage>.broadcast();
  
  /// 事件流
  /// 
  /// 订阅此流可以接收所有发布的地震事件
  Stream<QuakeMessage> get onNewEvent => _controller.stream;

  /// 发布地震事件
  /// 
  /// 将地震事件广播给所有订阅者。
  /// 测试事件(isTest=true)不会被发布。
  /// 
  /// [message] 要发布的地震消息
  void publish(QuakeMessage message) {
    if (!message.isTest) {
      _controller.add(message);
    }
  }
}
