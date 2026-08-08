import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart';
import 'package:http/retry.dart';

class AllowAnyCertTileProvider extends NetworkTileProvider {
  AllowAnyCertTileProvider()
    : super(
        httpClient: _client,
        headers: {'User-Agent': 'FlutterRhythmQuake/1.0'},
        silenceExceptions: true,
      );

  static final Client _client = RetryClient(Client(), retries: 2);
}
