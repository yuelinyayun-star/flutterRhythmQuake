import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/vector_basemap_service.dart';
import 'package:flutterrhythmquake/widgets/map/map_config.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:latlong2/latlong.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sources = VectorBasemapService.assetPaths
      .map((p) => File(p).readAsStringSync())
      .toList();
  const checks = [
    (
      1561,
      1573,
      95629,
      '95d0495902b6ca977b0f5cbb5e733ee8cc55c15ef2182dcf5509dec1c3b0e955',
      'fd50d0d130307be2b67f0b2cde1102303f277fccda067946387fa0f90144b7f1',
    ),
    (
      400,
      400,
      27807,
      '0a78934167d64f112a64393be3ed3a276c0584e3e56fc46ea3791049790bea0b',
      '11d407cb4ea88d7089139434dd41b9557c3c9f7bc3d93f89a40f90eb77095062',
    ),
    (
      421,
      429,
      26205,
      '4b64a2d342c1017b1b571a4e02c92bafac0e114e9f3c31860b1b1bba4dc56965',
      '6a74048a519248083deb83a88af892504b0e12aece55093cd947b8171b724c80',
    ),
  ];
  for (var i = 0; i < sources.length; i++) {
    test(
      'KA source $i preserves every ring and matches topojson-client 3.1.0',
      () {
        final data = parseVectorBasemap(sources[i]);
        final check = checks[i];
        expect(sha256.convert(utf8.encode(sources[i])).toString(), check.$4);
        expect(data.polygons, hasLength(check.$1));
        final rings = data.polygons.expand((p) => p.rings).toList();
        expect(rings, hasLength(check.$2));
        expect(rings.fold<int>(0, (n, r) => n + r.length), check.$3);
        final canonical = data.polygons
            .map(
              (p) => [
                p.name,
                p.rings
                    .map(
                      (r) => r
                          .map(
                            (p) => [
                              p.longitude.toStringAsFixed(9),
                              p.latitude.toStringAsFixed(9),
                            ],
                          )
                          .toList(),
                    )
                    .toList(),
              ],
            )
            .toList();
        expect(
          sha256.convert(utf8.encode(jsonEncode(canonical))).toString(),
          check.$5,
        );
        expect(
          data.borders.length,
          lessThanOrEqualTo((jsonDecode(sources[i])['arcs'] as List).length),
        );
      },
    );
  }

  test(
    'original composition preserves China islands and unnamed maritime strokes',
    () {
      final world = parseVectorBasemap(sources[0]);
      final japan = parseVectorBasemap(sources[1]);
      final china = parseVectorBasemap(sources[2]);
      final worldNames = world.polygons.map((p) => p.name).toSet();
      for (final name in ['中国', '中华人民共和国', '台湾', '日本']) {
        expect(worldNames, isNot(contains(name)));
      }
      final cnNames = china.polygons.map((p) => p.name).toSet();
      expect(
        cnNames,
        containsAll(['台湾省', '香港特别行政区', '澳门特别行政区', '西藏自治区', '新疆维吾尔自治区', '海南省']),
      );
      expect(cnNames.length, 35);
      final diaoyu = const LatLng(25.744, 123.479);
      expect(
        china.polygons.any(
          (p) => p.name == '台湾省' && _contains(p.rings.first, diaoyu),
        ),
        isTrue,
      );
      expect(
        japan.polygons.any((p) => _contains(p.rings.first, diaoyu)),
        isFalse,
      );
      final unnamed = china.polygons.where((p) => p.name.isEmpty).toList();
      expect(unnamed, hasLength(10));
      expect(
        unnamed.expand((p) => p.rings.first).any((p) => p.latitude < 4),
        isTrue,
      );
    },
  );

  test(
    'load is lazy, shared, cached, and retryable without an empty success',
    () async {
      var reads = 0;
      final service = VectorBasemapService(
        loadAsset: (p) async {
          reads++;
          return File(p).readAsStringSync();
        },
      );
      expect(reads, 0);
      final first = service.load();
      expect(identical(first, service.load()), isTrue);
      final data = await first;
      expect(identical(data, await service.load()), isTrue);
      expect(reads, 3);
      var fail = true;
      final retry = VectorBasemapService(
        loadAsset: (p) async {
          if (fail) throw const FormatException('test failure');
          return File(p).readAsStringSync();
        },
      );
      await expectLater(retry.load(), throwsFormatException);
      fail = false;
      expect(await retry.load(), hasLength(3));
    },
  );

  test('basemap selection is optional and does not resolve a raster URL', () {
    final provider = MapStateProvider();
    addTearDown(provider.dispose);
    expect(provider.tileKey, 'petalLight');
    expect(
      MapConfig.normalizeBaseTileKey(MapConfig.vectorBasemapKey),
      MapConfig.vectorBasemapKey,
    );
    provider.setTileKey(MapConfig.vectorBasemapKey);
    expect(provider.tileUrl, isEmpty);
    provider.setTileKey('petalLight');
    expect(provider.tileUrl, MapConfig.petalLight);
  });
}

bool _contains(List<LatLng> ring, LatLng p) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final a = ring[i], b = ring[j];
    if ((a.latitude > p.latitude) != (b.latitude > p.latitude) &&
        p.longitude <
            (b.longitude - a.longitude) *
                    (p.latitude - a.latitude) /
                    (b.latitude - a.latitude) +
                a.longitude) {
      inside = !inside;
    }
  }
  return inside;
}
