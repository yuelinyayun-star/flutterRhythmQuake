import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/epicenter_region_service.dart';
import 'package:flutterrhythmquake/services/native_japan_sea_regions.dart';
import 'package:flutterrhythmquake/services/native_korea_land_regions.dart';
import 'package:flutterrhythmquake/utils/fe_regions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group(
    'native regional sea names',
    () {
      late EpicenterRegionResolver resolver;
      setUpAll(() {
        ByteData asset(String name) => ByteData.sublistView(
          File('assets/regions/$name').readAsBytesSync(),
        );
        resolver = EpicenterRegionResolver.fromByteData(
          china: asset('china_place_index.bin'),
          chinaAdmin: asset('china_admin_regions.bin'),
          cwa: asset('cwa_epicenter_regions.bin'),
          japanLand: asset('japan_land_regions.bin'),
        );
      });
      tearDown(
        () => EpicenterRegionService.instance.setResolverForTesting(null),
      );

      test(
        'geographic seas reach display while raw forecast grids stay available',
        () {
          EpicenterRegionService.instance.setResolverForTesting(resolver);
          expect(getFEName(38.1, 142.0), '宫城县海域附近');
          expect(getFEName(38.1, 142.8), '三陆海域附近');
          expect(getFEName(37.4, 142.0), '福岛县海域附近');
          expect(getFEName(39.5, 142.3), '岩手县海域附近');
          expect(NativeJapanSeaRegions.lookup(38.1, 142.0), '宫城县海域');
        },
      );

      test('domestic regions keep priority before geographic seas', () {
        expect(resolver.lookup(25 + 44.6 / 60, 123 + 28.4 / 60), isNull);
        expect(resolver.lookup(25 + 55.3 / 60, 124 + 33.5 / 60), isNull);
        expect(resolver.lookup(25.9225440715, 124.55905788159185), isNull);
        expect(resolver.lookup(26.5, 124.5), isNull);
        expect(resolver.lookup(24.9517868, 122.0129126), '台湾省新北市近岸海域');
        expect(resolver.lookup(25.1925147, 121.4162455), '中国台湾北部海域');
        expect(resolver.lookup(24.4798, 118.0894), '福建省厦门市');
        // Original reference point falls seaward of the actual KA shoreline.
        expect(resolver.lookup(22.6658421, 121.4705314), '中国台湾东部海域');
      });

      test(
        'Japanese real land overrides base FE; unrelated countries retain FE',
        () {
          for (final p in [(45.5152, -122.6784)]) {
            expect(resolver.lookup(p.$1, p.$2), isNull, reason: '$p');
          }
          EpicenterRegionService.instance.setResolverForTesting(resolver);
          expect(getFEName(32.6817, 130.7217), '日本熊本县熊本附近');
          expect(getFEName(24.467, 123.0), '日本冲绳县与那国岛附近');
          expect(
            getFEName(37.4837, 127.0324),
            NativeKoreaLandRegions.supported ? '韩国首尔特别市附近' : '朝鲜半岛南部附近',
          );
        },
      );

      test('static UTF8 lookup rejects invalid coordinates', () {
        for (var i = 0; i < 1000; i++) {
          expect(NativeJapanSeaRegions.lookup(38.1, 142.0), '宫城县海域');
        }
        expect(NativeJapanSeaRegions.lookup(double.nan, 142), isNull);
        expect(NativeJapanSeaRegions.lookup(91, 142), isNull);
        expect(NativeJapanSeaRegions.lookup(38, double.infinity), isNull);
      });
    },
    skip: !NativeJapanSeaRegions.supported
        ? 'Requires Windows station-core DLL; set RQ_STATION_CORE_LIBRARY.'
        : false,
  );

  test('compiled data records the source and reviewed domestic aliases', () {
    final manifest =
        jsonDecode(
              File(
                'assets/regions/japan_sea_regions.provenance.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(manifest['count'], 120);
    final names = {
      for (final row in manifest['regions']) row['code']: row['displayName'],
    };
    expect(names[858], '东海');
    expect(names[859], '东海');
    expect(names[860], '东海');
    expect(names[487], '远州滩');
    expect(names[191], '十胜海域');
    expect(names[193], '苫小牧海域');
    expect(names[677], '濑户内海中部');
    expect(names[785], '有明海');
    expect(names[939], '萨哈林岛（库页岛）周边海域');
    expect(names.values.any((n) => '$n'.contains('尖阁')), isFalse);
    expect(names.keys.any((code) => code == 900 || code >= 940), isFalse);
  });
}
