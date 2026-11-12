import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'connection_retry_store.dart';

ConnectionRetryStore createConnectionRetryStore(String namespace) =>
    FileConnectionRetryStore(namespace: namespace);

/// A file lock shares atomic updates with a collector running as another process.
class FileConnectionRetryStore implements ConnectionRetryStore {
  FileConnectionRetryStore({String? path, this.namespace = 'jian_auth_retry'})
    : _path = path;
  final String namespace;
  String? _path;
  Future<String> _defaultPath() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final directory = await getApplicationSupportDirectory();
      return '${directory.path}${Platform.pathSeparator}$namespace.json';
    }
    final root = Platform.isWindows
        ? Platform.environment['LOCALAPPDATA']
        : Platform.environment['XDG_STATE_HOME'] ??
              Platform.environment['HOME'];
    if (root == null || root.isEmpty)
      throw StateError('Jian retry state directory unavailable');
    return '$root${Platform.pathSeparator}RhythmQuake${Platform.pathSeparator}$namespace.json';
  }

  @override
  Future<T> update<T>(
    String fingerprint,
    T Function(Map<String, dynamic>) action,
  ) async {
    final path = _path ??= await _defaultPath();
    return Future<T>.sync(() {
      final file = File(path);
      file.parent.createSync(recursive: true);
      final handle = File('$path.lock').openSync(mode: FileMode.append);
      try {
        handle.lockSync(FileLock.exclusive);
        try {
          if (!file.existsSync() && handle.lengthSync() != 0) {
            throw StateError('Jian retry state missing');
          }
          final bytes = file.existsSync() ? file.readAsBytesSync() : <int>[];
          if (file.existsSync() && bytes.isEmpty) {
            throw const FormatException('Empty Jian retry state');
          }
          final records = bytes.isEmpty
              ? <String, dynamic>{}
              : Map<String, dynamic>.from(
                  jsonDecode(utf8.decode(bytes)) as Map,
                );
          final record = Map<String, dynamic>.from(
            records[fingerprint] as Map? ?? {},
          );
          final result = action(record);
          records[fingerprint] = record;
          final output = utf8.encode(jsonEncode(records));
          final staging = File(
            '$path.$pid.${DateTime.now().microsecondsSinceEpoch}.pending',
          );
          try {
            staging.writeAsBytesSync(output, flush: true);
            staging.renameSync(path);
          } finally {
            if (staging.existsSync()) staging.deleteSync();
          }
          if (handle.lengthSync() == 0) {
            handle.writeByteSync(1);
            handle.flushSync();
          }
          return result;
        } finally {
          handle.unlockSync();
        }
      } finally {
        handle.closeSync();
      }
    });
  }
}
