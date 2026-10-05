import 'dart:convert';

import 'station_archive_storage_web.dart'
    if (dart.library.io) 'station_archive_storage_io.dart'
    as platform;

/// Compression is only a storage envelope; the JSON table itself is unchanged.
class StationArchiveStorage {
  static const prefix = 'rq-gzip-json-v1:';
  static const maxExpandedBytes = 128 * 1024 * 1024;

  static String encode(Map archive) {
    final bytes = JsonUtf8Encoder().convert(archive);
    return '$prefix${base64.encode(platform.compress(bytes))}';
  }

  static Map decode(String text) {
    if (!text.startsWith(prefix)) return jsonDecode(text) as Map;
    final bytes = platform.expand(
      base64.decode(text.substring(prefix.length).trim()),
      maxExpandedBytes,
    );
    return jsonDecode(utf8.decode(bytes)) as Map;
  }
}
