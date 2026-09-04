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
}
