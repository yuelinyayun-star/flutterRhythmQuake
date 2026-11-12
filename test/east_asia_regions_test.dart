import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/epicenter_region_service.dart';
import 'package:flutterrhythmquake/services/native_east_asia_regions.dart';
import 'package:flutterrhythmquake/utils/fe_regions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Taiwan broad regions are restored with China prefix, nearshore unchanged',
    () async {
      await EpicenterRegionService.instance.load();
      final m =
          jsonDecode(
                File(
                  'assets/regions/east_asia_names.provenance.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final seas = (m['regions'] as List)
          .where((r) => r['kind'] == 'taiwanSea')
          .toList();
      expect(seas, hasLength(23));
      final broad = seas
          .where((r) => !(r['name'] as String).endsWith('近岸海域'))
          .toList();
      expect(broad, hasLength(8));
      for (final r in seas) {
        if (!(r['name'] as String).endsWith('近岸海域'))
          expect(r['name'], startsWith('中国台湾'));
        final p = r['labelPoint'] as List;
        expect(
          getFEName((p[1] as num).toDouble(), (p[0] as num).toDouble()),
          '${r['name']}附近',
        );
      }
    },
    skip: !NativeEastAsiaRegions.supported,
  );
  test(
    'basemap dash line clips overlap without replacing fine names',
    () async {
      await EpicenterRegionService.instance.load();
      for (final p in [
        (24.0, 122.8, '与那国岛近海附近'),
        (24.4, 123.1, '与那国岛近海附近'),
        (22.5, 122.5, '石垣岛以南海域附近'),
        (38.1, 142.0, '宫城县海域附近'),
        (24.467, 123.0, '日本冲绳县与那国岛附近'),
      ]) {
        expect(getFEName(p.$1, p.$2), p.$3, reason: '$p');
      }
      expect(
        NativeEastAsiaRegions.chinaLandName(24.0, 122.644),
        isNull,
        reason: 'The basemap dashed stroke is a map symbol, not land',
      );
    },
    skip: !NativeEastAsiaRegions.supported,
  );
  test(
    'East China Sea and Diaoyu use exactly the original base entry',
    () async {
      final points = [
        (29.0, 124.0),
        (25.0, 122.5),
        (25.5, 122.5),
        (26.0, 122.5),
        (25.743333333333, 123.473333333333),
        (25.9225440715, 124.55905788159185),
      ];
      EpicenterRegionService.instance.setResolverForTesting(null);
      final original = [for (final p in points) getFEName(p.$1, p.$2)];
      await EpicenterRegionService.instance.load();
      for (var i = 0; i < points.length; i++) {
        final p = points[i];
        expect(EpicenterRegionService.instance.lookup(p.$1, p.$2), isNull);
        expect(getFEName(p.$1, p.$2), original[i]);
      }
    },
    skip: !NativeEastAsiaRegions.supported,
  );
  test(
    'effective asset has no compiled overlaps and keeps original base FE',
    () {
      final manifest =
          jsonDecode(
                File(
                  'assets/regions/east_asia_names.provenance.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(manifest['compiledOverlaps'], isEmpty);
      expect(manifest['japanSubdivisionCount'], 188);
      expect(manifest['japanPrefectureCount'], 47);
      expect(manifest['format'], contains('Float64'));
      expect(translateFERegionName('SOUTH KOREA'), '朝鲜半岛南部');
    },
  );
  test(
    'all effective regions resolve from their compiled interior coordinates',
    () {
      final manifest =
          jsonDecode(
                File(
                  'assets/regions/east_asia_names.provenance.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      for (final region in manifest['regions'] as List) {
        final point = region['labelPoint'] as List;
        expect(
          NativeEastAsiaRegions.lookup(
            (point[1] as num).toDouble(),
            (point[0] as num).toDouble(),
          ),
          region['kind'] == 'baseFE' ? null : region['name'],
          reason: '${region['name']} $point',
        );
      }
    },
    skip: NativeEastAsiaRegions.supported
        ? false
        : 'Requires Windows station-core DLL.',
  );
  test(
    'coast repairs use adjacent marine names through the real display entry',
    () async {
      await EpicenterRegionService.instance.load();
      final manifest =
          jsonDecode(
                File(
                  'assets/regions/east_asia_names.provenance.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final coast = manifest['coastlineAlignment'] as Map<String, dynamic>;
      for (final gap in coast['marine']['components'] as List) {
        final point = gap['point'] as List;
        final lat = (point[1] as num).toDouble(),
            lon = (point[0] as num).toDouble();
        final name = NativeEastAsiaRegions.lookup(lat, lon);
        final baseNames = [
          '东海',
          ...manifest['baseFEReplacedTaiwanNames'] as List,
        ];
        if (name == null && (gap['owners'] as List).any(baseNames.contains)) {
          expect(EpicenterRegionService.instance.lookup(lat, lon), isNull);
          expect(getFEName(lat, lon), isNotEmpty);
          continue;
        }
        expect(
          gap['owners'] as List,
          contains(name?.replaceFirst(RegExp(r'^中国(?=台湾)'), '')),
          reason: 'Original coastal gap $point',
        );
        expect(
          getFEName(lat, lon),
          '$name附近',
          reason: 'Display path for coastal gap $point',
        );
      }
      // The unchanged reference point lies outside the coarser vector island.
      // The original township name stays available to the weather/admin API.
      expect(
        NativeEastAsiaRegions.chinaLandName(22.6658421, 121.4705314),
        isNull,
      );
      expect(
        EpicenterRegionService.instance.lookupChinaPlace(
          22.6658421,
          121.4705314,
        ),
        '台湾省台东县绿岛乡',
      );
      expect(getFEName(22.6658421, 121.4705314), '中国台湾东部海域附近');
    },
    skip: NativeEastAsiaRegions.supported
        ? false
        : 'Requires Windows station-core DLL.',
  );
  test(
    'outside fine regions the original global FE name remains available',
    () async {
      await EpicenterRegionService.instance.load();
      for (final point in [
        (0.0, -140.0),
        (29.0, 160.0),
        (65.0, 20.0),
        (-70.0, 100.0),
        (90.0, 180.0),
        (-90.0, -180.0),
      ]) {
        final name = getFEName(point.$1, point.$2);
        expect(name, isNotEmpty);
        expect(name, endsWith('附近'));
        expect(name, isNot(contains('°')));
        expect(name, isNot('韩国附近'));
      }
      if (NativeEastAsiaRegions.supported) {
        expect(getFEName(34.50392228886581, 129.36411689363132), '日本长崎县对马附近');
      }
    },
  );
}
