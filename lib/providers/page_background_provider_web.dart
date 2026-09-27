import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Browser backgrounds use bytes because file picker paths are not readable.
class PageBackgroundProvider with ChangeNotifier {
  static const _enabledKey = 'page_background_use_custom';
  static const _nameKey = 'page_background_custom_name';
  static const _bytesKey = 'page_background_custom_bytes_web';
  static const _maxBytes = 2 * 1024 * 1024;

  bool _useCustom = false;
  String? _name;
  Uint8List? _bytes;
  int _revision = 0;

  bool get useCustom => _useCustom;
  String? get customPath => null;
  String? get customDisplayName => _name;
  Uint8List? get customBytes => _bytes;
  int get revision => _revision;
  bool get hasCustomImage => _bytes?.isNotEmpty ?? false;
  String get statusLabel =>
      _useCustom && hasCustomImage ? '当前：自定义（${_name ?? '背景'}）' : '当前：默认背景';

  Future<void> load(SharedPreferences prefs) async {
    _useCustom = prefs.getBool(_enabledKey) ?? false;
    _name = prefs.getString(_nameKey);
    final encoded = prefs.getString(_bytesKey);
    try {
      _bytes = encoded == null ? null : base64Decode(encoded);
    } catch (_) {
      _bytes = null;
    }
    if (!hasCustomImage) _useCustom = false;
    _changed();
  }

  Future<bool> setCustomImage(String sourcePath) async => false;

  Future<bool> setCustomImageBytes(Uint8List bytes, String name) async {
    if (bytes.isEmpty || bytes.length > _maxBytes) return false;
    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.setString(_bytesKey, base64Encode(bytes));
      await prefs.setString(_nameKey, name);
      await prefs.setBool(_enabledKey, true);
    } catch (_) {
      return false;
    }
    _bytes = Uint8List.fromList(bytes);
    _name = name;
    _useCustom = true;
    _changed();
    return true;
  }

  Future<void> restoreDefault() async {
    _useCustom = false;
    await (await SharedPreferences.getInstance()).setBool(_enabledKey, false);
    _changed();
  }

  Future<void> enableSavedCustom() async {
    if (!hasCustomImage) return;
    _useCustom = true;
    await (await SharedPreferences.getInstance()).setBool(_enabledKey, true);
    _changed();
  }

  Future<void> clearCustomImage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_bytesKey);
    await prefs.remove(_nameKey);
    await prefs.setBool(_enabledKey, false);
    _bytes = null;
    _name = null;
    _useCustom = false;
    _changed();
  }

  void _changed() {
    _revision++;
    notifyListeners();
  }
}
