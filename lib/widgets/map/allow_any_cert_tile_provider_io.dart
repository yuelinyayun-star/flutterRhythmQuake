import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart';
import 'package:http/io_client.dart';
import 'package:http/retry.dart';

import 'map_config.dart';
import 'tencent_wmts_logging_client.dart';

class AllowAnyCertTileProvider extends NetworkTileProvider {
  AllowAnyCertTileProvider()
    : super(
        httpClient: _client,
        headers: {
          'User-Agent': 'FlutterRhythmQuake/1.0',
          'x-legacy-url-decode': 'no',
        },
        silenceExceptions: true,
      );

  static final HttpClient _httpClient = HttpClient()
    ..badCertificateCallback = ((X509Certificate cert, String host, int port) =>
        true)
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 30)
    ..maxConnectionsPerHost = 12;

  static final Client _client = TencentWmtsLoggingClient(
    RetryClient(IOClient(_httpClient), retries: 2),
  );
  static int _tencentWmtsTileLogCount = 0;
  static bool? _lastTencentWmtsSignedState;
  static int _tencentStaticTileLogCount = 0;

  @override
  String getTileUrl(TileCoordinates coordinates, TileLayer options) {
    final url = super.getTileUrl(coordinates, options);
    if (MapConfig.isTencentStaticMapTemplate(url)) {
      final staticUrl = MapConfig.tencentStaticMapTileUrl(
        z: coordinates.z.round(),
        x: coordinates.x.round(),
        y: coordinates.y.round(),
      );
      if (_tencentStaticTileLogCount < 3) {
        _tencentStaticTileLogCount++;
        debugPrint(
          '[TencentStaticMap] tile url: z=${coordinates.z} '
          'x=${coordinates.x} y=${coordinates.y} '
          '${MapConfig.redactTencentServiceUrl(staticUrl)}',
        );
      }
      return staticUrl;
    }
    final signedUrl = MapConfig.signedTencentWmtsUrl(url);
    if (MapConfig.isTencentWmtsUrl(signedUrl)) {
      final signedState = MapConfig.hasTencentWmtsSecretKey;
      const signatureLogVersion = 'official-ordinal-v3';
      if (_tencentWmtsTileLogCount < 3 ||
          _lastTencentWmtsSignedState != signedState) {
        _tencentWmtsTileLogCount++;
        _lastTencentWmtsSignedState = signedState;
        debugPrint(
          '[TencentWMTS] tile url: z=${coordinates.z} '
          'x=${coordinates.x} y=${coordinates.y} '
          'sigMode=$signatureLogVersion '
          '${MapConfig.redactTencentWmtsUrl(signedUrl)}',
        );
      }
    }
    return signedUrl;
  }
}
