import 'dart:io';
import 'dart:typed_data';

bool get isMobile => Platform.isAndroid || Platform.isIOS;

Future<Uint8List> readBytes(String path) => File(path).readAsBytes();

Future<void> writeBytes(String path, Uint8List bytes) async {
  await File(path).writeAsBytes(bytes, flush: true);
}
