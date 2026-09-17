import 'dart:async';
import 'dart:io';

import 'package:http/http.dart';
import 'package:http/io_client.dart';
import 'package:http/retry.dart';

import 'shared_cancellable_tile_provider.dart';

class AllowAnyCertTileProvider extends SharedCancellableTileProvider {
  AllowAnyCertTileProvider()
    : super(
        httpClient: _client,
        headers: {'User-Agent': 'FlutterRhythmQuake/1.0'},
        silenceExceptions: false,
        attemptDecodeOfHttpErrorResponses: false,
      );

  static final HttpClient _httpClient = HttpClient()
    ..badCertificateCallback = ((X509Certificate cert, String host, int port) =>
        true)
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 15)
    ..maxConnectionsPerHost = 8;

  static final Client _client = RetryClient(
    IOClient(_httpClient),
    retries: 3,
    when: (response) => _isRetryableStatus(response.statusCode),
    whenError: (error, _) =>
        error is! RequestAbortedException &&
        (error is SocketException ||
            error is TimeoutException ||
            error is ClientException ||
            error is HandshakeException ||
            error is TlsException ||
            error is HttpException),
    delay: (retryCount) => Duration(milliseconds: 500 * (retryCount + 1)),
  );

  static bool _isRetryableStatus(int statusCode) =>
      statusCode == 408 ||
      statusCode == 429 ||
      statusCode == 500 ||
      statusCode == 502 ||
      statusCode == 503 ||
      statusCode == 504;
}
