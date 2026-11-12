import 'dart:typed_data';

abstract final class EventRenderClipboard {
  static bool get supported => false;
  static Future<void> writePng(Uint8List bytes) =>
      Future.error(UnsupportedError('当前平台暂不支持复制图片'));
}
