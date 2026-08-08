import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/widgets/map/map_config.dart';

void main() {
  test('Tencent map is no longer exposed as a base tile option', () {
    expect(MapConfig.baseTileOptions.keys, isNot(contains('腾讯地图')));
    expect(MapConfig.baseTileOptions.values, isNot(contains('tencentJsMap')));
  });

  test('legacy Tencent tile keys migrate to Petal Light', () {
    for (final key in const [
      'tencentVector',
      'tencentWmts',
      'tencentStaticMap',
      'tencentJsMap',
    ]) {
      expect(MapConfig.normalizeBaseTileKey(key), 'petalLight');
    }
  });
}
