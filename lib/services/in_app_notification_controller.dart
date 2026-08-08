import 'dart:async';
import '../models/in_app_notification.dart';

/// 应用内轻通知控制器
///
/// 通过流式接口向 [InAppNotificationOverlay] 推送通知。
/// 单例，支持替换旧通知（同一 id 只保留最新一条）。
class InAppNotificationController {
  static final InAppNotificationController _instance =
      InAppNotificationController._internal();
  factory InAppNotificationController() => _instance;
  InAppNotificationController._internal();

  final _streamController = StreamController<InAppNotification>.broadcast();
  Stream<InAppNotification> get stream => _streamController.stream;

  void show(InAppNotification notification) {
    if (_streamController.isClosed) return;
    _streamController.add(notification);
  }

  void dispose() {
    _streamController.close();
  }
}
