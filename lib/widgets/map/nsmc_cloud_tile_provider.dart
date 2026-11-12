import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import '../../services/native_nsmc_image.dart';
import '../../services/sources/nsmc_satellite_cloud_service.dart';
import '../../services/sources/source_http_client.dart';
import '../../services/sources/web_source_proxy.dart';

Uint8List _projectTile((Uint8List, int, int) input) =>
    NativeNsmcImage.project(input.$1, z: input.$2, y: input.$3);

/// Platform IO and Flutter image ownership only. Bounds and pixel processing
/// use the native backend; visible requests run before the one-tile margin.
class NsmcCloudTileProvider extends TileProvider {
  NsmcCloudTileProvider({http.Client? client, this.concurrency = 4})
    : _client = client ?? createSourceHttpClient();
  final http.Client _client;
  final int concurrency;
  final _records = <String, _TileRecord>{};
  final _cache = <String, Uint8List>{};
  final _queue = <_TileRecord>[];
  final _visible = <String>{};
  final _ready = <String>{};
  VoidCallback? onVisibleReady;
  String? targetTime;
  bool visibleReady(DateTime time) =>
      _visible.isNotEmpty &&
      _visible.every(
        (tile) => _ready.contains(
          'nsmc://${time.toUtc().millisecondsSinceEpoch}/$tile',
        ),
      );
  void _markReady(String key) {
    if (_disposed || !_cache.containsKey(key) && !_records.containsKey(key))
      return;
    _ready.add(key);
    onVisibleReady?.call();
  }

  int _active = 0;
  bool _disposed = false, _scheduled = false;
  bool get isDisposed => _disposed;
  int get activeRequests => _active;
  int get queuedRequests => _queue.length;
  int get cachedTiles => _cache.length;
  int get cachedBytes => _cache.values.fold(0, (v, b) => v + b.length);
  @override
  bool get supportsCancelLoading => true;

  void setView(MapCamera camera) {
    final z = camera.zoom.round().clamp(0, 3), n = 1 << z;
    final scale = math.pow(2, z - camera.zoom).toDouble(),
        bounds = camera.pixelBounds;
    _visible.clear();
    for (
      var y = (bounds.top * scale / 256).floor();
      y <= (bounds.bottom * scale / 256).floor();
      y++
    ) {
      if (y < 0 || y >= n) continue;
      for (
        var x = (bounds.left * scale / 256).floor();
        x <= (bounds.right * scale / 256).floor();
        x++
      ) {
        _visible.add('$z/${x % n}/$y');
      }
    }
    _schedule();
  }

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) {
    final key = getTileUrl(coordinates, options);
    final r = _records.putIfAbsent(
      key,
      () => _TileRecord(key, coordinates, this),
    );
    if (r.consumers.add(cancelLoading)) {
      unawaited(
        cancelLoading.then((_) {
          r.consumers.remove(cancelLoading);
          if (r.consumers.isNotEmpty) return;
          if (identical(_records[key], r)) _records.remove(key);
          if (!_cache.containsKey(key)) _ready.remove(key);
          _queue.remove(r);
          if (!r.abort.isCompleted) r.abort.complete();
          if (!r.done.isCompleted) r.done.complete(null);
          final cache = PaintingBinding.instance.imageCache;
          if (cache.statusForKey(r.image).pending) cache.evict(r.image);
        }),
      );
    }
    return r.image;
  }

  Future<Uint8List?> _load(_TileRecord r) {
    final cached = _cache.remove(r.key);
    if (cached != null) {
      _cache[r.key] = cached;
      return SynchronousFuture(cached);
    }
    if (_disposed || r.abort.isCompleted) return SynchronousFuture(null);
    if (!r.enqueued) {
      r.enqueued = true;
      _queue.add(r);
      _schedule();
    }
    return r.done.future;
  }

  void _schedule() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      _queue.sort((a, b) => _priority(a).compareTo(_priority(b)));
      while (!_disposed && _active < concurrency && _queue.isNotEmpty) {
        final r = _queue.removeAt(0);
        if (r.abort.isCompleted) continue;
        _active++;
        unawaited(_fetch(r));
      }
    });
  }

  int _priority(_TileRecord r) =>
      targetTime != null && Uri.parse(r.key).host != targetTime
      ? 2
      : _visible.contains('${r.tile.z}/${r.tile.x}/${r.tile.y}')
      ? 0
      : 1;
  Future<void> _fetch(_TileRecord r) async {
    final timeout = Timer(const Duration(seconds: 15), () {
      if (!r.abort.isCompleted) r.abort.complete();
    });
    try {
      final stamp = Uri.parse(r.key).host;
      final time = DateTime.fromMillisecondsSinceEpoch(
        int.parse(stamp),
        isUtc: true,
      );
      final tile = r.tile;
      final request = http.AbortableRequest(
        'GET',
        sourceUri(nsmcSatelliteTileUri(time, tile.z, tile.x, tile.y)),
        abortTrigger: r.abort.future,
      );
      final response = await _client.send(request);
      if (response.statusCode != 200)
        throw StateError('NSMC tile HTTP ${response.statusCode}');
      final builder = BytesBuilder(copy: false);
      await for (final bytes in response.stream) {
        builder.add(bytes);
        if (builder.length > 512 * 1024)
          throw const FormatException('NSMC tile exceeds size limit');
      }
      if (_disposed || r.abort.isCompleted) return;
      final bytes = await compute(_projectTile, (
        builder.takeBytes(),
        tile.z,
        tile.y,
      ));
      if (_disposed || r.abort.isCompleted) return;
      _cache[r.key] = bytes;
      while (_cache.length > 48 || cachedBytes > 8 * 1024 * 1024) {
        final key = _cache.keys.first;
        _cache.remove(key);
        if (_records[key]?.consumers.isNotEmpty != true) _ready.remove(key);
        PaintingBinding.instance.imageCache.evict(_TileImage(key, null));
      }
      if (!r.done.isCompleted) r.done.complete(bytes);
    } catch (e, s) {
      if (!_disposed && !r.abort.isCompleted && !r.done.isCompleted)
        r.done.completeError(e, s);
    } finally {
      timeout.cancel();
      _active--;
      if (!r.done.isCompleted) r.done.complete(null);
      _schedule();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final keys = {..._cache.keys, ..._records.keys};
    for (final r in _records.values) {
      if (!r.abort.isCompleted) r.abort.complete();
      if (!r.done.isCompleted) r.done.complete(null);
    }
    for (final key in keys) {
      PaintingBinding.instance.imageCache.evict(_TileImage(key, null));
    }
    _queue.clear();
    _records.clear();
    _cache.clear();
    _ready.clear();
    _client.close();
    super.dispose();
  }
}

class _TileRecord {
  _TileRecord(this.key, this.tile, this.owner) {
    image = _TileImage(
      key,
      () => owner._load(this),
      () => owner._markReady(key),
    );
  }
  final String key;
  final TileCoordinates tile;
  final NsmcCloudTileProvider owner;
  late final _TileImage image;
  final abort = Completer<void>();
  final done = Completer<Uint8List?>();
  final consumers = <Future<void>>{};
  bool enqueued = false;
}

class _TileImage extends ImageProvider<_TileImage> {
  const _TileImage(this.key, this.load, [this.ready]);
  final String key;
  final Future<Uint8List?> Function()? load;
  final VoidCallback? ready;
  @override
  Future<_TileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(_TileImage key, ImageDecoderCallback decode) {
    final loaded = _decode(decode);
    final completer = OneFrameImageStreamCompleter(loaded);
    final lease = completer.keepAlive();
    unawaited(
      loaded.then<void>(
        (_) {
          lease.dispose();
        },
        onError: (Object e, StackTrace s) {
          lease.dispose();
        },
      ),
    );
    return completer;
  }

  Future<ImageInfo> _decode(ImageDecoderCallback decode) async {
    final bytes = await load!();
    if (bytes == null) PaintingBinding.instance.imageCache.evict(this);
    final codec = await decode(
      await ui.ImmutableBuffer.fromUint8List(
        bytes ?? TileProvider.transparentImage,
      ),
    );
    try {
      final info = ImageInfo(image: (await codec.getNextFrame()).image);
      if (bytes != null) ready?.call();
      return info;
    } finally {
      codec.dispose();
    }
  }

  @override
  bool operator ==(Object other) => other is _TileImage && key == other.key;
  @override
  int get hashCode => key.hashCode;
}

/// TileLayer owns a lease; the cloud-layer state owns the shared IO/cache.
class NsmcTileProviderLease extends TileProvider {
  NsmcTileProviderLease(this.owner);
  final NsmcCloudTileProvider owner;
  @override
  bool get supportsCancelLoading => true;
  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) => owner.getImageWithCancelLoadingSupport(
    coordinates,
    options,
    cancelLoading,
  );
}
