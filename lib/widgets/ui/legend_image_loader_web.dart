import 'dart:typed_data';

import 'package:http/http.dart' as http;

Future<Uint8List?> fetchLegendBytes(
  String url, {
  required String userAgent,
}) async {
  try {
    // Browsers set User-Agent and Referer themselves. If CORS disallows this
    // request, the debug page retains its built-in fallback geometry.
    final response = await http.get(Uri.parse(url));
    return response.statusCode == 200 ? response.bodyBytes : null;
  } catch (_) {
    return null;
  }
}
