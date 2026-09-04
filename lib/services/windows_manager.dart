/// 条件导出：Windows 桌面管理器
///
/// - Web 平台：windows_manager_stub.dart（空操作）
/// - 非 Web 平台：windows_manager_io.dart（完整桌面实现）
export 'windows_manager_stub.dart'
    if (dart.library.io) 'windows_manager_io.dart';
