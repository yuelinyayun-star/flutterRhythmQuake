import 'dart:typed_data';
import '../../services/debug/history_replay.dart';

bool get isMobile => false;
bool get supportsDirectoryReplay => false;
Future<Uint8List> exportReplayBytes(HistoryReplayPackage package) =>
    Future.error(UnsupportedError('Browser file paths cannot be written'));
Future<HistoryReplayPackage> importReplay(String path) =>
    Future.error(UnsupportedError('Browser paths cannot be read'));
Future<void> exportReplay(HistoryReplayPackage package, String path) =>
    Future.error(UnsupportedError('Browser paths cannot be written'));

Future<Uint8List> readBytes(String path, {required int maxBytes}) =>
    Future.error(UnsupportedError('Browser file paths cannot be read'));

Future<void> writeBytes(String path, Uint8List bytes) =>
    Future.error(UnsupportedError('Browser file paths cannot be written'));
