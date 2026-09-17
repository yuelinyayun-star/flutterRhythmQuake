import 'package:http/http.dart';
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

  static final Client _client = RetryClient(
    Client(),
    retries: 2,
    when: (response) =>
        response.statusCode == 408 ||
        response.statusCode == 429 ||
        response.statusCode == 500 ||
        response.statusCode == 502 ||
        response.statusCode == 503 ||
        response.statusCode == 504,
    whenError: (error, _) =>
        error is! RequestAbortedException && error is ClientException,
    delay: (retryCount) => Duration(milliseconds: 600 * (retryCount + 1)),
  );
}
