import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_json_decoder.dart';
import 'precipitation_stations_decoder.dart';
import 'source_http_client.dart';
import 'web_source_proxy.dart';

class PrecipitationStationsService {
  PrecipitationStationsService({http.Client? client})
    : _client = client ?? createSourceHttpClient();

  final http.Client _client;

  Future<Float64List?> fetch(DateTime time, Completer<void> abort) async {
    final local = time.toUtc().add(const Duration(hours: 8));
    final hour = local.hour.toString().padLeft(2, '0');
    final stamp =
        local.year * 1000000 +
        local.month * 10000 +
        local.day * 100 +
        local.hour;
    final uri = Uri.https(
      'img.weather.com.cn',
      '/newwebgis/sk/$hour/p_r.json',
      const {'callback': 'webgisDot'},
    );
    final request =
        http.AbortableRequest('GET', sourceUri(uri), abortTrigger: abort.future)
          ..headers.addAll(
            sourceHeaders(const {
                  'Referer': 'https://www.weather.com.cn/live/',
                }) ??
                const {},
          );
    try {
      return await (() async {
        final response = await _client.send(request);
        if (response.statusCode != 200 ||
            (response.contentLength ?? 0) > 512 * 1024) {
          await response.stream.listen(null).cancel();
          return null;
        }
        final bytes = await readApiJsonBytes(
          response.stream.transform(
            StreamTransformer.fromBind((stream) async* {
              var size = 0;
              await for (final chunk in stream) {
                size += chunk.length;
                if (size > 512 * 1024) {
                  throw const FormatException('Oversized station data');
                }
                yield chunk;
              }
            }),
          ),
        );
        if (abort.isCompleted) return null;
        return decodePrecipitationStations(bytes, stamp);
      })().timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          if (!abort.isCompleted) abort.complete();
          return null;
        },
      );
    } on http.ClientException {
      return null;
    } on FormatException {
      return null;
    }
  }

  void close() => _client.close();
}
