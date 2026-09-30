import 'dart:typed_data';

bool get isMobile => false;

Future<Uint8List> readBytes(String path, {required int maxBytes}) =>
    Future.error(UnsupportedError('Browser file paths cannot be read'));

Future<void> writeBytes(String path, Uint8List bytes) =>
    Future.error(UnsupportedError('Browser file paths cannot be written'));
