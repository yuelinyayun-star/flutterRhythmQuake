import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/tsunami_message.dart';
import 'native_jma_tsunami.dart';
import 'sources/native_http_client.dart';

class NmefcCoastalMap {
  const NmefcCoastalMap(this.bytes, this.caption);
  final Uint8List bytes;
  final String caption;
}

/// Rust selects the report attachment and its identity; WinHTTP fetches bytes.
/// No polling and no substitute map. Retain at most two report images when the
/// existing sidebar carousel unmounts a page and then returns to it.
class NmefcCoastalMapService {
  NmefcCoastalMapService({http.Client? client}) : _client = client;
  final http.Client? _client;
  static final _images = <String, Future<NmefcCoastalMap>>{};
  final _clientImages = <String, Future<NmefcCoastalMap>>{};

  Future<NmefcCoastalMap?> load(TsunamiMessage message) async {
    if (!NativeJmaTsunami.supported) return null;
    final plan = await NativeJmaTsunami.prepareAsync({
      'op': 'nmefcCoastalMap',
      'message': message.toMap(),
    });
    final url = plan['url'] as String;
    if (url.isEmpty) return null;
    final key = plan['cacheKey'] as String;
    // Injected transports retain their own cache and client ownership.
    final images = _client == null ? _images : _clientImages;
    final image = images.putIfAbsent(
      key,
      () => _fetch(url, plan['caption'] as String),
    );
    while (images.length > 2) {
      images.remove(images.keys.first);
    }
    try {
      return await image;
    } catch (_) {
      if (identical(images[key], image)) images.remove(key);
      rethrow;
    }
  }

  Future<NmefcCoastalMap> _fetch(String url, String caption) async {
    final client =
        _client ??
        NativeHttpClient(requestTimeout: const Duration(seconds: 15));
    try {
      final response = await client
          .get(
            Uri.parse(url),
            headers: {
              // A new report can reuse an image URL. Revalidate rather than showing
              // a stale transport-cache image from an older report.
              'Cache-Control': 'no-cache',
            },
          )
          .timeout(const Duration(seconds: 18));
      if (response.statusCode != 200) {
        throw http.ClientException(
          'HTTP ${response.statusCode}',
          Uri.parse(url),
        );
      }
      if (response.bodyBytes.isEmpty ||
          response.bodyBytes.length > 8 * 1024 * 1024) {
        throw const FormatException('Invalid coastal forecast image size');
      }
      return NmefcCoastalMap(response.bodyBytes, caption);
    } finally {
      if (_client == null) client.close();
    }
  }
}
