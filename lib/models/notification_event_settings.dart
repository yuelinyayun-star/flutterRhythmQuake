/// 单类事件的通知设置
///
/// 对应 KA 通知设置里的 notification / sound / focus 三件套。
class NotificationEventSettings {
  bool notification;
  bool sound;
  bool focus;

  NotificationEventSettings({
    this.notification = false,
    this.sound = false,
    this.focus = false,
  });

  NotificationEventSettings copyWith({
    bool? notification,
    bool? sound,
    bool? focus,
  }) {
    return NotificationEventSettings(
      notification: notification ?? this.notification,
      sound: sound ?? this.sound,
      focus: focus ?? this.focus,
    );
  }

  Map<String, dynamic> toMap() => {
    'notification': notification,
    'sound': sound,
    'focus': focus,
  };

  factory NotificationEventSettings.fromMap(Map<String, dynamic> map) {
    return NotificationEventSettings(
      notification: map['notification'] as bool? ?? false,
      sound: map['sound'] as bool? ?? false,
      focus: map['focus'] as bool? ?? false,
    );
  }
}
