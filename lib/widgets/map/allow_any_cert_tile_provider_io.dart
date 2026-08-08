import 'dart:io';

import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart';
import 'package:http/io_client.dart';
import 'package:http/retry.dart';

class AllowAnyCertTileProvider extends NetworkTileProvider {
  AllowAnyCertTileProvider()
    : super(
        httpClient: _client,
        headers: {'User-Agent': 'FlutterRhythmQuake/1.0'},
        silenceExceptions: true,
      );

  static final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 30)
    ..maxConnectionsPerHost = 12;

  static final Client _client = RetryClient(IOClient(_httpClient), retries: 2);
}
