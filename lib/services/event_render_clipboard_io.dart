import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'sources/native_station_core_library_io.dart';

abstract final class EventRenderClipboard {
  static bool get supported => Platform.isWindows;
  static Future<void> writePng(Uint8List bytes) {
    if (!supported) {
      throw UnsupportedError('当前平台暂不支持复制图片');
    }
    return Isolate.run(() => _write(bytes));
  }

  static void _write(Uint8List bytes) {
    final copy = StationCoreLibrary.library
        .lookupFunction<
          Int32 Function(Pointer<Uint8>, Size),
          int Function(Pointer<Uint8>, int)
        >('rq_event_render_copy_png');
    using((arena) {
      final input = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
      input.asTypedList(bytes.length).setAll(0, bytes);
      final code = copy(input, bytes.length);
      if (code != 0) {
        throw StateError('无法写入图片剪贴板（$code），请重试');
      }
    });
  }
}
