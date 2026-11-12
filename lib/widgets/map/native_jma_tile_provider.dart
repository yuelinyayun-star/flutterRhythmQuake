import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

/// Viewport URL resolution, shared image-cache ownership and Flutter codec only.
/// Network concurrency, retries and cancellation are owned by the source worker.
class NativeJmaTileProvider extends TileProvider {
  NativeJmaTileProvider(this.load);
  final Future<Uint8List?> Function(Uri, Future<void>) load;
  final _requests = <String, _Request>{};
  @override
  bool get supportsCancelLoading => true;
  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) {
    final url = getTileUrl(coordinates, options);
    final request = _requests.putIfAbsent(url, () {
      final abort = Completer<void>();
      return _Request(
        abort,
        _Image(url, () => load(Uri.parse(url), abort.future)),
      );
    });
    if (request.consumers.add(cancelLoading)) {
      unawaited(
        cancelLoading.then((_) async {
          request.consumers.remove(cancelLoading);
          if (request.consumers.isNotEmpty) return;
          if (identical(_requests[url], request)) _requests.remove(url);
          final key = await request.image.obtainKey(ImageConfiguration.empty);
          final cache = PaintingBinding.instance.imageCache;
          if (cache.statusForKey(key).pending) cache.evict(key);
          request.abort.complete();
        }),
      );
    }
    return request.image;
  }
}

class _Request {
  _Request(this.abort, this.image);
  final Completer<void> abort;
  final _Image image;
  final consumers = <Future<void>>{};
}

class _Image extends ImageProvider<_Image> {
  const _Image(this.url, this.loader);
  final String url;
  final Future<Uint8List?> Function() loader;
  @override
  Future<_Image> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(_Image key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _decode(decode), scale: 1);
  Future<ui.Codec> _decode(ImageDecoderCallback decode) async {
    final bytes = await loader();
    if (bytes == null) {
      // A source stop can cancel before flutter_map prunes the tile. Do not
      // retain the framework's cancellation image under the real tile URL.
      PaintingBinding.instance.imageCache.evict(this);
    }
    return decode(
      await ui.ImmutableBuffer.fromUint8List(
        bytes ?? TileProvider.transparentImage,
      ),
    );
  }

  @override
  bool operator ==(Object other) => other is _Image && other.url == url;
  @override
  int get hashCode => url.hashCode;
}
