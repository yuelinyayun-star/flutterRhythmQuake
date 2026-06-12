/// Web 存根——Windows 桌面管理器空操作

/// Windows桌面管理器（Web 存根）
class WindowsManager {
  static final WindowsManager _instance = WindowsManager._internal();
  factory WindowsManager() => _instance;
  WindowsManager._internal();

  Future<void> init() async {}
  Future<void> forceShowAlert() async {}
  Future<void> resetWindowState() async {}
}