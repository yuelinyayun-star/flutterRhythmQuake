import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification_event_settings.dart';

/// 通知设置 Provider
///
/// 参考 KA 的通知设置结构，提供 EEW / EEW警报 / 地震信息 三类开关。
class NotificationSettingsProvider extends ChangeNotifier {
  static const String _prefix = 'notif_settings_';

  final NotificationEventSettings onEew = NotificationEventSettings(
    sound: true,
  );
  final NotificationEventSettings onEewWarn = NotificationEventSettings(
    sound: true,
  );
  final NotificationEventSettings onReport = NotificationEventSettings(
    sound: true,
  );

  bool _gameMode = false;
  bool get gameMode => _gameMode;

  Future<void> load(SharedPreferences prefs) async {
    _loadGroup(prefs, 'onEew', onEew);
    _loadGroup(prefs, 'onEewWarn', onEewWarn);
    _loadGroup(prefs, 'onReport', onReport);
    _gameMode = prefs.getBool('${_prefix}gameMode') ?? false;
    notifyListeners();
  }

  void _loadGroup(
    SharedPreferences prefs,
    String key,
    NotificationEventSettings target,
  ) {
    target.notification = prefs.getBool('$_prefix${key}_notification') ?? false;
    target.sound = prefs.getBool('$_prefix${key}_sound') ?? true;
    target.focus = prefs.getBool('$_prefix${key}_focus') ?? false;
  }

  Future<void> _saveGroup(
    SharedPreferences prefs,
    String key,
    NotificationEventSettings target,
  ) async {
    await prefs.setBool('$_prefix${key}_notification', target.notification);
    await prefs.setBool('$_prefix${key}_sound', target.sound);
    await prefs.setBool('$_prefix${key}_focus', target.focus);
  }

  Future<void> setEew({bool? notification, bool? sound, bool? focus}) async {
    _apply(onEew, notification: notification, sound: sound, focus: focus);
    await _persistGroup('onEew', onEew);
  }

  Future<void> setEewWarn({
    bool? notification,
    bool? sound,
    bool? focus,
  }) async {
    _apply(onEewWarn, notification: notification, sound: sound, focus: focus);
    await _persistGroup('onEewWarn', onEewWarn);
  }

  Future<void> setOnReport({
    bool? notification,
    bool? sound,
    bool? focus,
  }) async {
    _apply(onReport, notification: notification, sound: sound, focus: focus);
    await _persistGroup('onReport', onReport);
  }

  Future<void> setGameMode(bool value) async {
    if (_gameMode == value) return;
    _gameMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_prefix}gameMode', value);
    notifyListeners();
  }

  void _apply(
    NotificationEventSettings target, {
    bool? notification,
    bool? sound,
    bool? focus,
  }) {
    if (notification != null) target.notification = notification;
    if (sound != null) target.sound = sound;
    if (focus != null) target.focus = focus;
    notifyListeners();
  }

  Future<void> _persistGroup(
    String key,
    NotificationEventSettings target,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await _saveGroup(prefs, key, target);
  }

  /// KA 兼容语义：游戏模式下不发送通知和弹窗
  bool get canNotify => !_gameMode;
}
