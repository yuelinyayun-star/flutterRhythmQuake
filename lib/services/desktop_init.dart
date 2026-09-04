/// 条件导出：根据平台选择正确的实现
export 'desktop_init_stub.dart' if (dart.library.io) 'desktop_init_io.dart';
