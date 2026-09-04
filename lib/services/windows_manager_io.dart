import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:local_notifier/local_notifier.dart';

/// Windows桌面管理器
///
/// 该类提供Windows桌面应用的窗口和托盘管理功能。
/// 混入TrayListener和WindowListener以响应系统事件。
///
/// 主要功能：
/// - 窗口初始化和显示
/// - 系统托盘管理
/// - 原生通知支持
/// - 紧急预警窗口置顶
///
/// 使用场景：
/// - 应用启动时初始化窗口
/// - 收到紧急预警时强制显示窗口
/// - 最小化到系统托盘
class WindowsManager with TrayListener, WindowListener {
  static final WindowsManager _instance = WindowsManager._internal();
  factory WindowsManager() => _instance;
  WindowsManager._internal();

  /// 初始化窗口管理器
  ///
  /// 执行以下初始化：
  /// 1. 窗口管理器 - 设置窗口大小和位置
  /// 2. 系统托盘 - 设置图标和右键菜单
  /// 3. 原生通知 - 初始化通知系统
  Future<void> init() async {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 720),
      center: true,
      title: "RhythmQuake",
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.setAlwaysOnTop(false);
      await windowManager.focus();
    });

    await trayManager.setIcon('assets/images/app_icon_win.ico');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show_window', label: '显示主界面'),
          MenuItem.separator(),
          MenuItem(key: 'exit_app', label: '退出程序'),
        ],
      ),
    );
    trayManager.addListener(this);

    await localNotifier.setup(appName: 'RhythmQuake');
  }

  /// 强制显示预警窗口
  ///
  /// 当收到严重地震预警时调用：
  /// - 显示并聚焦窗口
  /// - 设置窗口始终置顶
  /// - 任务栏进度条闪烁效果
  Future<void> forceShowAlert() async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setProgressBar(0.5);
  }

  /// 重置窗口状态
  ///
  /// 预警结束后调用，恢复正常窗口状态：
  /// - 取消始终置顶
  /// - 隐藏任务栏进度条
  Future<void> resetWindowState() async {
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setProgressBar(-1);
  }

  /// 托盘图标点击事件
  @override
  void onTrayIconMouseDown() {
    windowManager.show();
  }

  /// 托盘菜单项点击事件
  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_window') windowManager.show();
    if (menuItem.key == 'exit_app') windowManager.destroy();
  }
}
