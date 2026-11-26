import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import '../../models/in_app_notification.dart';
import '../../services/in_app_notification_controller.dart';
import '../../services/live_display_time.dart';

/// 应用内轻通知覆盖层
///
/// 放在页面顶层（如 MainScreen），监听 [InAppNotificationController]
/// 并在右上角弹出卡片，6 秒后自动消失或点击消失。
class InAppNotificationOverlay extends StatefulWidget {
  const InAppNotificationOverlay({super.key});

  @override
  State<InAppNotificationOverlay> createState() =>
      _InAppNotificationOverlayState();
}

class _InAppNotificationOverlayState extends State<InAppNotificationOverlay> {
  final List<_PendingNotification> _notifications = [];
  StreamSubscription<InAppNotification>? _subscription;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _lifecycle = AppLifecycleListener(onShow: _recheckExpiry);
    }
    _subscription = InAppNotificationController().stream.listen(
      _onNotification,
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _subscription?.cancel();
    for (final item in _notifications) {
      item.timer?.cancel();
    }
    super.dispose();
  }

  void _onNotification(InAppNotification notification) {
    setState(() {
      _notifications.removeWhere((item) {
        if (item.data.id != notification.id) return false;
        item.timer?.cancel();
        return true;
      });
      final pending = _PendingNotification(notification);
      pending.timer = Timer(const Duration(seconds: 6), () => _remove(pending));
      _notifications.add(pending);
      if (_notifications.length > 3) {
        final oldest = _notifications.removeAt(0);
        oldest.timer?.cancel();
      }
    });
  }

  void _recheckExpiry() {
    final now = liveDisplayElapsedUs();
    for (final item in _notifications.toList()) {
      item.timer?.cancel();
      final remaining = item.expiryUs - now;
      if (remaining <= 0) {
        _remove(item);
      } else {
        item.timer = Timer(
          Duration(microseconds: remaining),
          () => _remove(item),
        );
      }
    }
  }

  void _remove(_PendingNotification item) {
    if (!mounted) return;
    setState(() {
      _notifications.remove(item);
    });
    item.timer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    if (_notifications.isEmpty) return const SizedBox.shrink();

    return Positioned(
      top: 12,
      right: 12,
      width: 320,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: _notifications.reversed.map((item) {
            final data = item.data;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    data.onTap?.call();
                    _remove(item);
                  },
                  child: AnimatedOpacity(
                    opacity: 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: Material(
                      color: const Color(0xFF1A1A1E),
                      elevation: 6,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: data.accentColor.withValues(alpha: 0.6),
                          ),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: data.accentColor.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                data.icon,
                                color: data.accentColor,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    data.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    data.body,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.75,
                                      ),
                                      fontSize: 12,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _remove(item),
                              child: Icon(
                                Icons.close,
                                color: Colors.white.withValues(alpha: 0.5),
                                size: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _PendingNotification {
  final InAppNotification data;
  final int expiryUs =
      liveDisplayElapsedUs() + const Duration(seconds: 6).inMicroseconds;
  Timer? timer;
  _PendingNotification(this.data);
}
