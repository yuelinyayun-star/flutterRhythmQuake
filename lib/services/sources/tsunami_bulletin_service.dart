import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/tsunami_message.dart';
import '../native_jma_tsunami.dart';
import 'source_http_client.dart';

/// Follows the bulletin attached to this report; the relay payload is untouched.
class TsunamiBulletinService {
  TsunamiBulletinService({http.Client? client}) : _client = client;
  final http.Client? _client;

  Future<Map<String, dynamic>?> fetch(TsunamiMessage message) async {
    final url = Uri.tryParse(message.htmlUrl);
    if (url == null || url.userInfo.isNotEmpty) return null;
    final nmefc =
        message.source == TsunamiSource.nmefc &&
        url.host == 'obs.nmefc.cn' &&
        url.path.startsWith('/Warning/TsunamiAdvice/') &&
        url.path.endsWith('.html') &&
        url.pathSegments.last ==
            '${message.eventId}_${message.reportNumber}.html';
    final noaa =
        {TsunamiSource.ptwc, TsunamiSource.ntwc}.contains(message.source) &&
        {'www.tsunami.gov', 'tsunami.gov'}.contains(url.host) &&
        url.path.startsWith('/events/') &&
        url.path.endsWith('.txt') &&
        url.pathSegments.contains(message.eventId) &&
        url.pathSegments.contains('${message.reportNumber}');
    if (!nmefc && !noaa) return null;
    final client = _client ?? createSourceHttpClient();
    try {
      final response = await client
          .get(url.replace(scheme: 'https', port: 443))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final original = utf8.decode(response.bodyBytes);
      if (nmefc) {
        final view = await NativeJmaTsunami.prepareAsync({
          'op': 'nmefcBulletin',
          'html': original,
        });
        if ((view['bulletinText'] as String).isEmpty) return null;
        return {
          ...view,
          'bulletinUrl': url.toString(),
          'bulletinHtml': original,
        };
      }
      // A successful HTML error page is not a NOAA text bulletin.
      if (!original.contains('TSUNAMI') ||
          original.trimLeft().startsWith('<')) {
        return null;
      }
      return {'bulletinText': original, 'bulletinUrl': url.toString()};
    } catch (_) {
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }
}
