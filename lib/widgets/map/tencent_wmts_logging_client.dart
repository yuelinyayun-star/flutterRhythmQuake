import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart';

import 'map_config.dart';

class TencentWmtsLoggingClient extends BaseClient {
  TencentWmtsLoggingClient(this._inner);

  final Client _inner;
  static final Map<String, DateTime> _lastLogAtByTile = {};
  static String? _lastOkLogKey;
  static int _okLogCount = 0;

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final isTencent =
        MapConfig.isTencentWmtsUrl(request.url.toString()) ||
        MapConfig.isTencentStaticMapUrl(request.url.toString());
    try {
      final response = await _inner.send(request);
      if (!isTencent) return response;

      final bytes = await response.stream.toBytes();
      _logTencentResponse(request.url, response, bytes);
      return StreamedResponse(
        ByteStream.fromBytes(bytes),
        response.statusCode,
        contentLength: response.contentLength,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (e, stackTrace) {
      if (isTencent) {
        debugPrint(
          '[TencentMap] request exception: '
          '${MapConfig.redactTencentServiceUrl(request.url.toString())} '
          'error=$e',
        );
        final briefStack = stackTrace
            .toString()
            .split('\n')
            .take(3)
            .join(' | ');
        debugPrint('[TencentMap] request exception stack: $briefStack');
      }
      rethrow;
    }
  }

  @override
  void close() {
    _inner.close();
  }

  static void _logTencentResponse(
    Uri url,
    StreamedResponse response,
    List<int> bytes,
  ) {
    final status = response.statusCode;
    final contentType = response.headers['content-type'] ?? '';
    final tileKey = _tileKey(url);
    final okImage = status == 200 && contentType.startsWith('image/');
    if (okImage) {
      final okLogKey = '$tileKey:$contentType';
      if (_lastOkLogKey != okLogKey && _okLogCount < 3) {
        _okLogCount++;
        _lastOkLogKey = okLogKey;
        debugPrint(
          '[TencentMap] response ok: tile=$tileKey '
          'contentType=$contentType bytes=${bytes.length}',
        );
      }
      return;
    }

    final now = DateTime.now();
    final last = _lastLogAtByTile[tileKey];
    if (last != null && now.difference(last) < const Duration(seconds: 20)) {
      return;
    }
    _lastLogAtByTile[tileKey] = now;

    debugPrint(
      '[TencentMap] response abnormal: tile=$tileKey '
      'status=$status contentType=${contentType.isEmpty ? "unknown" : contentType} '
      'bytes=${bytes.length} '
      'url=${MapConfig.redactTencentServiceUrl(url.toString())}',
    );
    final preview = _bodyPreview(bytes);
    if (preview.isNotEmpty) {
      debugPrint('[TencentMap] response body: $preview');
    }
  }

  static String _tileKey(Uri url) {
    final params = url.queryParameters;
    if (MapConfig.isTencentStaticMapUrl(url.toString())) {
      return 'static zoom=${params['zoom'] ?? "--"} '
          'center=${params['center'] ?? "--"}';
    }
    return 'z=${params['TILEMATRIX'] ?? "--"} '
        'x=${params['TILECOL'] ?? "--"} '
        'y=${params['TILEROW'] ?? "--"}';
  }

  static String _bodyPreview(List<int> bytes) {
    if (bytes.isEmpty) return '';
    final take = bytes.length > 500 ? bytes.sublist(0, 500) : bytes;
    return utf8.decode(take, allowMalformed: true).replaceAll('\n', r'\n');
  }
}
