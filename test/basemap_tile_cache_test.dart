import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/widgets/map/basemap_tile_cache.dart';

class _DiskCache implements MapCachingProvider {
  final tiles = <String, CachedMapTile>{};
  int reads = 0;

  @override
  bool get isSupported => true;

  @override
  Future<CachedMapTile?> getTile(String url) async {
    reads++;
    return tiles[url];
  }

  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) async {
    final tileBytes = bytes ?? tiles[url]?.bytes;
    if (tileBytes != null) {
      tiles[url] = (bytes: tileBytes, metadata: metadata);
    }
  }
}

CachedMapTileMetadata _metadata(Duration age) => CachedMapTileMetadata(
  staleAt: DateTime.timestamp().add(age),
  lastModified: null,
  etag: 'original-etag',
);

void main() {
  test('native disk tiles survive cache worker restart', () async {
    final directory = await Directory.systemTemp.createTemp('rq-basemap-test-');
    var disk = BuiltInMapCachingProvider.getOrCreateInstance(
      cacheDirectory: directory.path,
    );
    try {
      const url = 'https://tiles.test/native/5/26/13';
      final bytes = await File('assets/images/volcano/vol.png').readAsBytes();
      final metadata = _metadata(const Duration(hours: 1));
      await BasemapTileCache(
        diskCache: disk,
      ).putTile(url: url, metadata: metadata, bytes: bytes);
      // The built-in provider writes asynchronously on its worker isolate.
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (await disk.getTile(url) == null) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Disk cache write timed out');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await disk.destroy();
      disk = BuiltInMapCachingProvider.getOrCreateInstance(
        cacheDirectory: directory.path,
      );
      final tile = await BasemapTileCache(diskCache: disk).getTile(url);
      expect(tile!.bytes, bytes);
      expect(tile.metadata.etag, metadata.etag);
      expect(tile.metadata.isStale, isFalse);
    } finally {
      await disk.destroy(deleteCache: true);
      await directory.delete();
    }
  });

  test('fresh tiles reuse original bytes without another disk read', () async {
    final disk = _DiskCache();
    final cache = BasemapTileCache(diskCache: disk);
    final bytes = Uint8List.fromList([1, 2, 3]);
    final metadata = _metadata(const Duration(hours: 1));
    await cache.putTile(url: 'base', metadata: metadata, bytes: bytes);
    final tile = await cache.getTile('base');
    expect(identical(tile!.bytes, bytes), isTrue);
    expect(identical(tile.metadata, metadata), isTrue);
    expect(disk.reads, 0);
  });

  test('new cache instances recover tiles from disk', () async {
    final disk = _DiskCache();
    final bytes = Uint8List.fromList([1, 2, 3]);
    await BasemapTileCache(diskCache: disk).putTile(
      url: 'base',
      metadata: _metadata(const Duration(hours: 1)),
      bytes: bytes,
    );
    final cache = BasemapTileCache(diskCache: disk);
    expect((await cache.getTile('base'))!.bytes, bytes);
    expect((await cache.getTile('base'))!.bytes, bytes);
    expect(disk.reads, 1);
  });

  test(
    'byte limit evicts least recently used tiles, not disk copies',
    () async {
      final disk = _DiskCache();
      final cache = BasemapTileCache(diskCache: disk, maxBytes: 6);
      for (final url in ['a', 'b']) {
        await cache.putTile(
          url: url,
          metadata: _metadata(const Duration(hours: 1)),
          bytes: Uint8List(3),
        );
      }
      await cache.getTile('a');
      await cache.putTile(
        url: 'c',
        metadata: _metadata(const Duration(hours: 1)),
        bytes: Uint8List(3),
      );
      await cache.getTile('a');
      expect(disk.reads, 0);
      expect(await cache.getTile('b'), isNotNull);
      expect(disk.reads, 1);
      expect(disk.tiles.length, 3);
    },
  );

  test('tile count and oversized tile limits are enforced', () async {
    final disk = _DiskCache();
    final cache = BasemapTileCache(diskCache: disk, maxTiles: 1, maxBytes: 6);
    for (final url in ['a', 'b', 'large']) {
      await cache.putTile(
        url: url,
        metadata: _metadata(const Duration(hours: 1)),
        bytes: Uint8List(url == 'large' ? 7 : 3),
      );
    }
    await cache.getTile('b');
    expect(disk.reads, 0);
    await cache.getTile('large');
    await cache.getTile('large');
    expect(disk.reads, 2);
    await cache.getTile('a');
    expect(disk.reads, 3);
  });

  test('expired metadata stays expired for HTTP revalidation', () async {
    final disk = _DiskCache();
    final cache = BasemapTileCache(diskCache: disk);
    final metadata = _metadata(const Duration(seconds: -1));
    await cache.putTile(url: 'base', metadata: metadata, bytes: Uint8List(3));
    final tile = await cache.getTile('base');
    expect(tile!.metadata.isStale, isTrue);
    expect(tile.metadata.etag, 'original-etag');
    expect(disk.reads, 0);
  });

  test('304 updates metadata and preserves original bytes', () async {
    final disk = _DiskCache();
    final cache = BasemapTileCache(diskCache: disk);
    final bytes = Uint8List.fromList([1, 2, 3]);
    await cache.putTile(
      url: 'base',
      metadata: _metadata(const Duration(seconds: -1)),
      bytes: bytes,
    );
    final metadata = _metadata(const Duration(hours: 1));
    await cache.putTile(url: 'base', metadata: metadata);
    final reads = disk.reads;
    final tile = await cache.getTile('base');
    expect(identical(tile!.bytes, bytes), isTrue);
    expect(tile.metadata, metadata);
    expect(disk.reads, reads);
    expect(disk.tiles['base']!.metadata, metadata);
  });

  test('memory caching also works without native disk support', () async {
    final cache = BasemapTileCache(
      diskCache: const DisabledMapCachingProvider(),
    );
    await cache.putTile(
      url: 'base',
      metadata: _metadata(const Duration(hours: 1)),
      bytes: Uint8List(3),
    );
    expect(await cache.getTile('base'), isNotNull);
    expect(await cache.getTile('missing'), isNull);
  });
}
