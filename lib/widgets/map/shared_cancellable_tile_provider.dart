import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

/// Coordinates cancellation with flutter_map's URL-based image cache.
class SharedCancellableTileProvider extends NetworkTileProvider {
  SharedCancellableTileProvider({
    super.httpClient,
    super.headers,
    super.silenceExceptions,
    super.attemptDecodeOfHttpErrorResponses,
    super.cachingProvider,
  });

  final Map<String, _TileRequest> _requests = {};

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) {
    final url = getTileUrl(coordinates, options);
    // Fallback images do not share flutter_map's URL-based cache key.
    if (getTileFallbackUrl(coordinates, options) != null) {
      return super.getImageWithCancelLoadingSupport(
        coordinates,
        options,
        cancelLoading,
      );
    }
    final request = _requests.putIfAbsent(url, () {
      final abort = Completer<void>();
      return _TileRequest(
        abort,
        super.getImageWithCancelLoadingSupport(
          coordinates,
          options,
          abort.future,
        ),
      );
    });
    if (request.consumers.add(cancelLoading)) {
      unawaited(
        cancelLoading.then((_) {
          request.consumers.remove(cancelLoading);
          if (request.consumers.isNotEmpty) return;
          if (identical(_requests[url], request)) _requests.remove(url);
          // Detach the pending cache entry BEFORE aborting. Otherwise a new tile
          // can inherit the old request's successful transparent cancellation image.
          // Completed images stay cached for later camera moves.
          unawaited(
            request.image.obtainKey(ImageConfiguration.empty).then((key) {
              final cache = PaintingBinding.instance.imageCache;
              if (cache.statusForKey(key).pending) cache.evict(key);
              request.abort.complete();
            }),
          );
        }),
      );
    }
    return request.image;
  }
}

class _TileRequest {
  _TileRequest(this.abort, this.image);

  final Completer<void> abort;
  final ImageProvider image;
  final Set<Future<void>> consumers = {};
}
