import 'dart:convert';
import 'package:http/http.dart' as http;
import '../native_jma_tsunami.dart';
import 'source_http_client.dart';

/// Only follows the public JSON URL supplied by an INCOIS bulletin.
class IncoisTsunamiDetailService {
  IncoisTsunamiDetailService({http.Client? client}) : _client = client;
  final http.Client? _client;

  Future<Map<String, dynamic>?> fetch(String rawUrl) async {
    if (!NativeJmaTsunami.supported) return null;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        uri.host != 'tsunami.incois.gov.in' ||
        !uri.path.startsWith('/itews/DSSProducts/OPR/') ||
        !uri.pathSegments.contains('NTWC') ||
        !uri.path.endsWith('.json')) {
      return null;
    }
    final client = _client ?? createSourceHttpClient();
    try {
      final response = await client
          .get(uri.replace(scheme: 'https', port: 443))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      return await NativeJmaTsunami.prepareAsync({
        'op': 'incoisDetail',
        'json': utf8.decode(response.bodyBytes),
      });
    } catch (_) {
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }
}
