import 'dart:io';
import 'dart:typed_data';
import '../../services/debug/history_replay.dart';
import '../../services/debug/history_replay_directory_io.dart';

bool get isMobile => Platform.isAndroid || Platform.isIOS;
bool get supportsDirectoryReplay => true;
Future<HistoryReplayPackage> importReplay(String path) =>
    importReplayFile(path);
Future<void> exportReplay(HistoryReplayPackage package, String path) =>
    exportReplayDirectory(package, path);

Future<Uint8List> exportReplayBytes(HistoryReplayPackage package) async {
  final directory = await Directory.systemTemp.createTemp('rq-mobile-export-');
  try {
    final path = '${directory.path}/capture.zip';
    await exportReplayDirectory(package, path);
    // Mobile file_picker requires bytes. Only the final compressed ZIP enters
    // that bridge; individual expanded reports/frames are never accumulated.
    return await readBytes(path, maxBytes: HistoryReplayPackage.maxBytes);
  } finally {
    await directory.delete(recursive: true);
  }
}

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
