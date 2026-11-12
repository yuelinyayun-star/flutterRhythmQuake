import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'debug/station_archive_storage_io.dart' as compression;

/// IO owner for the directory format. Invoked by the serial storage isolate.
/// Report bodies and frames are never embedded in an event manifest.
class ReplayHistoryFiles {
  ReplayHistoryFiles(this.root);
  final String root;

  /// IO-platform boundary. Native builds override these with a bounded Rust
  /// writer; the portable owner commits one file before returning.
  void acceptFrame(String key, Map frame) {
    _commitSync(
      File(framePath(key)),
      JsonUtf8Encoder().convert(frame),
      gzip: true,
    );
  }

  String acceptReport(String key, Map report) {
    final bytes = JsonUtf8Encoder().convert(report);
    final digest = sha256.convert(bytes).toString();
    _commitSync(File(reportPath(key, digest)), bytes);
    return digest;
  }

  String acceptCollectorJson(String directory, String prefix, Map value) {
    if (directory.isEmpty ||
        directory
            .split('/')
            .any(
              (s) =>
                  s.isEmpty ||
                  s == '.' ||
                  s == '..' ||
                  s.contains('\\') ||
                  s.contains(':'),
            ) ||
        !RegExp(r'^[a-zA-Z0-9_]*$').hasMatch(prefix)) {
      throw const FormatException('Invalid collector file identity');
    }
    final bytes = JsonUtf8Encoder().convert(value);
    final name = '$prefix${sha256.convert(bytes)}.json';
    _commitSync(File('$root/$directory/$name'), bytes);
    return name;
  }

  String acceptCollectorFrame(String prefix, Map frame) {
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(prefix)) {
      throw const FormatException('Invalid collector frame prefix');
    }
    final bytes = compression.compress(JsonUtf8Encoder().convert(frame));
    final name = '$prefix${sha256.convert(bytes)}.json.gz';
    _commitSync(File('$root/frames/$name'), bytes);
    return name;
  }

  void _commitSync(File file, List<int> bytes, {bool gzip = false}) {
    if (file.existsSync()) {
      final saved = file.readAsBytesSync();
      final expanded = gzip
          ? compression.expand(saved, 128 * 1024 * 1024)
          : saved;
      if (sha256.convert(expanded) != sha256.convert(bytes)) {
        throw const FormatException('Conflicting replay file identity');
      }
      return;
    }
    file.parent.createSync(recursive: true);
    final pending = File('${file.path}.pending');
    pending.writeAsBytesSync(
      gzip ? compression.compress(bytes) : bytes,
      flush: true,
    );
    pending.renameSync(file.path);
  }

  Map<String, dynamic> get pendingStatus => const {
    'pending': 0,
    'bytes': 0,
    'peakBytes': 0,
    'limitBytes': 0,
  };
  Future<void> flushPending() async {}
  void retryPending() {}
  void dispose() {}
  static String keyHash(String key) =>
      sha256.convert(utf8.encode(key)).toString();
  String eventPath(String key) => '$root/events/${keyHash(key)}';
  String recordPath(String key) => key.contains('_event_')
      ? '${eventPath(key)}/event.json'
      : '$root/index/${keyHash(key)}.json';
  String framePath(String key) => '$root/frames/${keyHash(key)}.json.gz';
  String reportPath(String key, String digest) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('Invalid report file identity');
    }
    return '${eventPath(key)}/reports/$digest.json';
  }

  Future<void> _atomic(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    final pending = File('${file.path}.pending');
    await pending.writeAsBytes(bytes, flush: true);
    await pending.rename(file.path);
  }

  Future<Map<String, dynamic>?> record(String key) async {
    final file = File(recordPath(key));
    if (!await file.exists()) {
      return null;
    }
    final map = jsonDecode(await file.readAsString(encoding: utf8)) as Map;
    if (map['key'] != key) {
      throw const FormatException('History key mismatch');
    }
    return Map<String, dynamic>.from(map);
  }

  Future<bool> writeRecord(String key, Object? value, Map? snapshot) async {
    await _atomic(
      File(recordPath(key)),
      JsonUtf8Encoder().convert({
        'key': key,
        'value': value,
        'snapshot': ?snapshot,
      }),
    );
    return true;
  }

  Future<String> writeReport(String key, Map report) async {
    final bytes = JsonUtf8Encoder().convert(report);
    final digest = sha256.convert(bytes).toString();
    final file = File(reportPath(key, digest));
    if (!await file.exists()) {
      await _atomic(file, bytes);
    } else if ((await sha256.bind(file.openRead()).first).toString() !=
        digest) {
      throw const FormatException('Saved report file is corrupted');
    }
    return digest;
  }

  Future<Map<String, dynamic>> readReport(String key, String digest) async {
    final bytes = await File(reportPath(key, digest)).readAsBytes();
    if (sha256.convert(bytes).toString() != digest) {
      throw const FormatException('Saved report checksum mismatch');
    }
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
  }

  Future<bool> writeFrame(String key, Map frame) async {
    final file = File(framePath(key));
    final bytes = compression.compress(JsonUtf8Encoder().convert(frame));
    if (await file.exists()) {
      final previous = await sha256.bind(file.openRead()).first;
      if (previous != sha256.convert(bytes)) {
        throw const FormatException('Conflicting station frame identity');
      }
      return true;
    }
    await _atomic(file, bytes);
    return true;
  }

  Future<Map<String, dynamic>> readFrame(String key) async =>
      Map<String, dynamic>.from(
        jsonDecode(
              utf8.decode(
                compression.expand(
                  await File(framePath(key)).readAsBytes(),
                  128 * 1024 * 1024,
                ),
              ),
            )
            as Map,
      );

  Future<bool> remove(String key, {bool frame = false}) async {
    // Delete only files addressed by a hashed application-owned identity.
    if (!frame && key.contains('_event_')) {
      final directory = Directory(eventPath(key));
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } else {
      final file = File(frame ? framePath(key) : recordPath(key));
      if (await file.exists()) {
        await file.delete();
      }
    }
    return true;
  }
}
