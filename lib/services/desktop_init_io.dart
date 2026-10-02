import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';
import 'windows_preferences_worker.dart';

Future<void> initDesktopPreferences() async {
  if (!Platform.isWindows) return;
  final backend = SharedPreferencesStorePlatform.instance;
  if (backend is! SharedPreferencesWindows) return;
  final supportPath = (await getApplicationSupportDirectory()).path;
  SharedPreferencesStorePlatform.instance =
      await WindowsPreferencesWorker.start(supportPath);
}

/// 桌面端数据库初始化（Windows/Linux FFI 模式）
void initDesktopDatabase() {
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

/// 桌面端窗口初始化（仅 Windows）
Future<void> initDesktopWindow() async {
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1280, 720),
      center: true,
      title: "RhythmQuake",
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    // 确保时序错失时也能可靠显示窗口
    await windowManager.show();
    await windowManager.focus();
  }
}
