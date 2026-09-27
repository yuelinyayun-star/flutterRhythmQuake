import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

Future<Uint8List?> fetchLegendBytes(
  String url, {
  required String userAgent,
}) async {
  final client = HttpClient()
    ..badCertificateCallback = ((X509Certificate cert, String host, int port) =>
        true);
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set('Referer', 'https://www.lmoni.bosai.go.jp/monitor/');
    request.headers.set('User-Agent', userAgent);
    final response = await request.close();
    if (response.statusCode != 200) return null;
    return consolidateHttpClientResponseBytes(response);
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}
