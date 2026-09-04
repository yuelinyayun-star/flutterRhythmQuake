import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings/Debug page background: default asset or a user-picked image.
class PageBackgroundProvider with ChangeNotifier {
  static const String _useCustomKey = 'page_background_use_custom';
  static const String _customPathKey = 'page_background_custom_path';
  static const String _customNameKey = 'page_background_custom_name';
  static const String _storedPrefix = 'custom_bg_';

  bool _useCustom = false;
  String? _customPath;
  String? _customDisplayName;
  Uint8List? _customBytes;
  int _revision = 0;

  bool get useCustom => _useCustom;
  String? get customPath => _customPath;
  String? get customDisplayName => _customDisplayName;
  Uint8List? get customBytes => _customBytes;
  int get revision => _revision;
  bool get hasCustomImage =>
      _customBytes != null &&
      _customBytes!.isNotEmpty &&
      _customPath != null &&
      _customPath!.trim().isNotEmpty &&
      File(_customPath!).existsSync();

  String get statusLabel {
    if (_useCustom && hasCustomImage) {
      final name = (_customDisplayName ?? '').trim();
      if (name.isNotEmpty) return '当前：自定义（$name）';
      return '当前：自定义背景';
    }
    return '当前：默认背景';
  }

  Future<void> load(SharedPreferences prefs) async {
    _useCustom = prefs.getBool(_useCustomKey) ?? false;
    final saved = prefs.getString(_customPathKey)?.trim();
    _customPath = (saved == null || saved.isEmpty) ? null : saved;
    final name = prefs.getString(_customNameKey)?.trim();
    _customDisplayName = (name == null || name.isEmpty) ? null : name;
    await _reloadCustomBytes();
    if (_useCustom && !hasCustomImage) {
      _useCustom = false;
    }
    _revision++;
    notifyListeners();
  }

  Future<bool> setCustomImage(String sourcePath) async {
    if (kIsWeb) return false;
    final source = File(sourcePath);
    if (!await source.exists()) return false;

    final originalName = p.basename(sourcePath);
    final ext = _safeExtension(sourcePath);
    final dir = await _backgroundDir();
    await dir.create(recursive: true);

    // Unique path per pick so Flutter image cache cannot reuse the previous file.
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final target = File(p.join(dir.path, '$_storedPrefix$stamp$ext'));
    await source.copy(target.path);
    await _clearStoredCustomFiles(keep: target.path);

    final bytes = await target.readAsBytes();
    if (bytes.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    await _evictCachedFile(_customPath);
    _customPath = target.path;
    _customDisplayName = originalName;
    _customBytes = Uint8List.fromList(bytes);
    _useCustom = true;
    await prefs.setString(_customPathKey, target.path);
    await prefs.setString(_customNameKey, originalName);
    await prefs.setBool(_useCustomKey, true);
    _revision++;
    notifyListeners();
    return true;
  }

  Future<void> restoreDefault() async {
    final prefs = await SharedPreferences.getInstance();
    _useCustom = false;
    await prefs.setBool(_useCustomKey, false);
    _revision++;
    notifyListeners();
  }

  Future<void> enableSavedCustom() async {
    if (_customPath == null) return;
    await _reloadCustomBytes();
    if (!hasCustomImage) return;
    final prefs = await SharedPreferences.getInstance();
    _useCustom = true;
    await prefs.setBool(_useCustomKey, true);
    _revision++;
    notifyListeners();
  }

  Future<void> clearCustomImage() async {
    final prefs = await SharedPreferences.getInstance();
    await _evictCachedFile(_customPath);
    await _clearStoredCustomFiles(keep: null);
    _customPath = null;
    _customDisplayName = null;
    _customBytes = null;
    _useCustom = false;
    await prefs.remove(_customPathKey);
    await prefs.remove(_customNameKey);
    await prefs.setBool(_useCustomKey, false);
    _revision++;
    notifyListeners();
  }

  Future<void> _reloadCustomBytes() async {
    _customBytes = null;
    final path = _customPath;
    if (path == null || path.trim().isEmpty) return;
    try {
      final file = File(path);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;
      _customBytes = Uint8List.fromList(bytes);
      _customDisplayName ??= p.basename(path);
    } catch (_) {
      _customBytes = null;
    }
  }

  Future<Directory> _backgroundDir() async {
    final root = await getApplicationSupportDirectory();
    return Directory(p.join(root.path, 'page_background'));
  }

  Future<void> _clearStoredCustomFiles({required String? keep}) async {
    try {
      final dir = await _backgroundDir();
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        if (keep != null && p.equals(entity.path, keep)) continue;
        final name = p.basename(entity.path);
        if (name.startsWith(_storedPrefix) || name.startsWith('custom_bg.')) {
          await _evictCachedFile(entity.path);
          await entity.delete();
        }
      }
    } catch (_) {}
  }

  Future<void> _evictCachedFile(String? path) async {
    if (path == null || path.trim().isEmpty) return;
    try {
      await FileImage(File(path)).evict();
    } catch (_) {}
  }

  static String _safeExtension(String path) {
    final ext = p.extension(path).toLowerCase();
    const allowed = {'.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'};
    if (allowed.contains(ext)) return ext;
    return '.png';
  }
}
