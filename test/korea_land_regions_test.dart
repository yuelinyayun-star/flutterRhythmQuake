import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/epicenter_region_service.dart';
import 'package:flutterrhythmquake/services/native_korea_land_regions.dart';
import 'package:flutterrhythmquake/utils/fe_regions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group(
    'official SGIS land mapping through Rust',
    () {
      setUpAll(() async => EpicenterRegionService.instance.load());
      tearDownAll(
        () => EpicenterRegionService.instance.setResolverForTesting(null),
      );
      test('regional names use actual polygons through the display entry', () {
        expect(getFEName(37.575, 126.98), '韩国首尔特别市附近');
        expect(getFEName(35.1796, 129.0756), '韩国釜山广域市附近');
        expect(getFEName(33.4996, 126.5312), '韩国济州特别自治道附近');
        expect(getFEName(36.1, 128.2), '韩国庆尚北道附近');
      });
      test('islands retain a geographic name without disputed ownership', () {
        expect(getFEName(37.24125289916992, 131.87033081054688), '独岛（竹岛）附近');
        expect(NativeKoreaLandRegions.lookup(32.122, 125.182), isNull);
      });
      test(
        'offshore and other regions are not covered by Korea rectangles',
        () {
          expect(NativeKoreaLandRegions.lookup(37.55, 126.5), isNull);
          expect(NativeKoreaLandRegions.lookup(32.6817, 130.7217), isNull);
          expect(getFEName(32.6817, 130.7217), '日本熊本县熊本附近');
          expect(getFEName(23.1101922, 121.3562179), '台湾省台东县成功镇附近');
          expect(getFEName(39.9042, 116.4074), '北京市东城区附近');
          expect(getFEName(38.1, 142.0), '宫城县海域附近');
        },
      );
    },
    skip: !NativeKoreaLandRegions.supported
        ? 'Requires Windows station-core DLL.'
        : false,
  );
}
