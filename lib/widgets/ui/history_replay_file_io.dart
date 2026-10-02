import 'dart:io';
import 'dart:typed_data';

bool get isMobile => Platform.isAndroid || Platform.isIOS;

Future<Uint8List> readBytes(String path, {required int maxBytes}) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in File(path).openRead()) {
    if (bytes.length + chunk.length > maxBytes) {
      throw FormatException('回放包超过 ${maxBytes ~/ (1024 * 1024)} MiB');
    }
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}

Future<void> writeBytes(String path, Uint8List bytes) async {
  await File(path).writeAsBytes(bytes, flush: true);
}
