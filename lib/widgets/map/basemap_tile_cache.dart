import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_map/flutter_map.dart';

/// Keeps compressed basemap tiles separate from Flutter's decoded image cache.
class BasemapTileCache implements MapCachingProvider {
  BasemapTileCache({
    this.diskCache,
    this.maxBytes = 32 * 1024 * 1024,
    this.maxTiles = 2048,
  }) : assert(maxBytes > 0),
       assert(maxTiles > 0);

  static final shared = BasemapTileCache(
    maxBytes:
        !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS)
        ? 16 * 1024 * 1024
        : 32 * 1024 * 1024,
  );

  final MapCachingProvider? diskCache;
  final int maxBytes;
  final int maxTiles;
  final _tiles = <String, CachedMapTile>{};
  int _byteCount = 0;

  MapCachingProvider get _disk =>
      diskCache ?? BuiltInMapCachingProvider.getOrCreateInstance();

  @override
  bool get isSupported => true;

  @override
  Future<CachedMapTile?> getTile(String url) async {
    final cached = _remove(url);
    if (cached != null) {
      _remember(url, cached);
      return cached;
    }
    final disk = _disk;
    if (!disk.isSupported) return null;
    final tile = await disk.getTile(url);
    if (tile != null) _remember(url, tile);
    return tile;
  }

  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) async {
    final disk = _disk;
    // A 304 response updates freshness without replacing the original bytes.
    final previous = bytes == null
        ? _tiles[url] ?? (disk.isSupported ? await disk.getTile(url) : null)
        : null;
    final tileBytes = bytes ?? previous?.bytes;
    if (tileBytes != null) {
      _remember(url, (bytes: tileBytes, metadata: metadata));
    }
    if (disk.isSupported) {
      await disk.putTile(url: url, metadata: metadata, bytes: bytes);
    }
  }

  CachedMapTile? _remove(String url) {
    final tile = _tiles.remove(url);
    if (tile != null) _byteCount -= tile.bytes.lengthInBytes;
    return tile;
  }

  void _remember(String url, CachedMapTile tile) {
    _remove(url);
    if (tile.bytes.lengthInBytes > maxBytes) return;
    _tiles[url] = tile;
    _byteCount += tile.bytes.lengthInBytes;
    while (_byteCount > maxBytes || _tiles.length > maxTiles) {
      _remove(_tiles.keys.first);
    }
  }
}
