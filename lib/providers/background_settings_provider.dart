/// 移动端后台设置提供者
///
/// 管理应用在后台运行时的行为与通知策略，包括：
/// - 后台运行总开关
/// - 信息事件后台通知开关
/// - EEW 后台通知开关及本地烈度阈值
///
/// 所有设置持久化到 SharedPreferences。
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackgroundSettingsProvider with ChangeNotifier {
  static const String _prefix = 'background_';
  static const String _enabledKey = '${_prefix}enabled';
  static const String _reportEnabledKey = '${_prefix}report_enabled';
  static const String _eewEnabledKey = '${_prefix}eew_enabled';
  static const String _eewMinIntensityKey = '${_prefix}eew_min_intensity';

  bool _enabled = false;
  bool _reportEnabled = true;
  bool _eewEnabled = true;
  double _eewMinIntensity = 0.0;

  bool get enabled => _enabled;
  bool get reportEnabled => _reportEnabled;
  bool get eewEnabled => _eewEnabled;
  double get eewMinIntensity => _eewMinIntensity;

  /// 是否允许发送 EEW 系统通知
  bool get canNotifyEew => _enabled && _eewEnabled;

  /// 是否允许发送信息事件系统通知
  bool get canNotifyReport => _enabled && _reportEnabled;

  /// 加载持久化设置
  Future<void> load(SharedPreferences prefs) async {
    _enabled = prefs.getBool(_enabledKey) ?? false;
    _reportEnabled = prefs.getBool(_reportEnabledKey) ?? true;
    _eewEnabled = prefs.getBool(_eewEnabledKey) ?? true;
    _eewMinIntensity = prefs.getDouble(_eewMinIntensityKey) ?? 0.0;
    notifyListeners();
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _saveDouble(String key, double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, value);
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    await _saveBool(_enabledKey, value);
    notifyListeners();
  }

  Future<void> setReportEnabled(bool value) async {
    if (_reportEnabled == value) return;
    _reportEnabled = value;
    await _saveBool(_reportEnabledKey, value);
    notifyListeners();
  }

  Future<void> setEewEnabled(bool value) async {
    if (_eewEnabled == value) return;
    _eewEnabled = value;
    await _saveBool(_eewEnabledKey, value);
    notifyListeners();
  }

  Future<void> setEewMinIntensity(double value) async {
    final normalized = _normalizeIntensity(value);
    if (_eewMinIntensity == normalized) return;
    _eewMinIntensity = normalized;
    await _saveDouble(_eewMinIntensityKey, normalized);
    notifyListeners();
  }

  /// 判断给定本地烈度是否满足 EEW 后台通知阈值
  bool matchesEewThreshold(double localIntensity) {
    if (!_enabled || !_eewEnabled) return false;
    if (_eewMinIntensity <= 0.0) return true;
    return localIntensity >= _eewMinIntensity;
  }

  static double _normalizeIntensity(double value) {
    if (value < 0.5) return 0.0;
    if (value < 1.5) return 1.0;
    if (value < 2.5) return 2.0;
    if (value < 3.5) return 3.0;
    if (value < 4.5) return 4.0;
    if (value < 5.5) return 5.0;
    if (value < 6.5) return 6.0;
    return 7.0;
  }

  static String intensityLabel(double value) {
    if (value <= 0.0) return '全量通知';
    return '预估烈度 ≥ ${value.toStringAsFixed(0)}';
  }
}
