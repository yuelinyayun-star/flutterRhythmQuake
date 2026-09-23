import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/widgets/map/map_config.dart';

void main() {
  const fanTileKeys = <String>[
    'petalDark',
    'petalLight',
    'arcgisSatellite',
    'arcgisTopo',
    'arcgisHillshade',
    'demElevation',
    'cloudLayer',
    'rainLayer',
    'windLayer',
    'cnContour',
  ];

  test('FAN tile URLs use standard ZXY coordinates', () {
    for (final key in fanTileKeys) {
      final url = MapConfig.urlByKey(key);
      expect(url, contains('tilemap.fanstudio.tech'));
      final uri = Uri.parse(url);
      final pathTemplate = url.split('?').first;
      expect(pathTemplate, endsWith('/{z}/{x}/{y}'));
      expect(pathTemplate, isNot(endsWith('/{z}/{y}/{x}')));
      expect(uri.queryParameters['v'], '20260822-zxy');
    }
  });

  test('FAN tile sources are not treated as TMS', () {
    for (final key in fanTileKeys) {
      expect(MapConfig.isTmsTileKey(key), isFalse);
    }
  });

  test('Jian basemaps use the published XYZ paths without a token', () {
    const sources = <String, String>{
      'jianSatellite': 'arcwi',
      MapConfig.jianSatelliteRoadsKey: 'arcwi',
      'jianOcean': 'arcwob',
      'jianHillshade': 'arcwh',
      'jianTerrain': 'arcterr',
      'jianPhysical': 'arcphys',
      'jianRelief': 'arcshade',
    };
    for (final entry in sources.entries) {
      expect(MapConfig.normalizeBaseTileKey(entry.key), entry.key);
      expect(MapConfig.isJianTileKey(entry.key), isTrue);
      expect(
        MapConfig.urlByKey(entry.key),
        'https://tilemap.sismotide.top/${entry.value}/{z}/{x}/{y}',
      );
      expect(MapConfig.isTmsTileKey(entry.key), isFalse);
    }
    expect(
      MapConfig.jianTransportation,
      'https://tilemap.sismotide.top/arctrans/{z}/{x}/{y}',
    );
    expect(MapConfig.jianTransportationMaxNativeZoom, 13);
    expect(MapConfig.maxNativeZoomByKey('jianSatellite'), 18);
    expect(MapConfig.maxNativeZoomByKey(MapConfig.jianSatelliteRoadsKey), 18);
    expect(MapConfig.maxNativeZoomByKey('jianOcean'), 10);
    expect(MapConfig.maxNativeZoomByKey('jianHillshade'), 15);
    expect(MapConfig.maxNativeZoomByKey('jianTerrain'), 9);
    expect(MapConfig.maxNativeZoomByKey('jianPhysical'), 8);
    expect(MapConfig.maxNativeZoomByKey('jianRelief'), 13);
    expect(MapConfig.maxNativeZoomByKey('petalLight'), 19);
  });
}
