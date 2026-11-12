import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/epicenter_region_service.dart';
import 'package:flutterrhythmquake/services/native_east_asia_regions.dart';
import 'package:flutterrhythmquake/services/sources/usgs_eqlist_service.dart';
import 'package:flutterrhythmquake/utils/fe_regions.dart';

ByteData _asset(String name) {
  final bytes = File('assets/regions/$name').readAsBytesSync();
  return ByteData.sublistView(bytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EpicenterRegionResolver resolver;

  setUpAll(() {
    resolver = EpicenterRegionResolver.fromByteData(
      china: _asset('china_place_index.bin'),
      chinaAdmin: _asset('china_admin_regions.bin'),
      cwa: _asset('cwa_epicenter_regions.bin'),
      japanLand: _asset('japan_land_regions.bin'),
    );
  });

  tearDown(() {
    EpicenterRegionService.instance.setResolverForTesting(null);
  });

  test('uses polygon-backed China administrative names', () {
    expect(resolver.lookup(39.9042, 116.4074), '北京市东城区');
    expect(resolver.lookup(31.2304, 121.4737), '上海市黄浦区');
    expect(resolver.lookup(29.5630, 106.5516), '重庆市渝中区');
    expect(resolver.lookup(24.4798, 118.0894), '福建省厦门市');
    expect(resolver.lookup(26.0745, 119.2965), '福建省福州市');
    expect(resolver.lookup(29.36, 120.17), '浙江省金华市');
    expect(resolver.lookupChinaPlace(29.36, 120.17), '浙江省金华市义乌市');
    expect(resolver.lookupChinaPlace(29.272, 120.241), '浙江省金华市东阳市');
  });

  test(
    'uses exact Hong Kong and Macau polygons instead of coarse grid cells',
    () {
      expect(resolver.lookup(22.2819, 114.1589), '香港特别行政区中西区');
      expect(resolver.lookup(22.3193, 114.1694), '香港特别行政区油尖旺区');
      expect(resolver.lookup(22.3080, 113.9185), '香港特别行政区离岛区');
      expect(resolver.lookup(22.1987, 113.5439), '澳门特别行政区花王堂区');
      expect(resolver.lookup(22.1578, 113.5597), '澳门特别行政区嘉模堂区');
      expect(resolver.lookup(22.2210, 113.5520), '广东省珠海市');
    },
  );

  test('Japan land uses clipped subdivisions before base FE', () {
    const utoLatitude = 32.6817;
    const utoLongitude = 130.7217;

    expect(
      resolver.lookup(utoLatitude, utoLongitude),
      NativeEastAsiaRegions.supported ? '日本熊本县熊本' : null,
    );
    expect(
      resolver.lookup(24.4670, 123.0000),
      NativeEastAsiaRegions.supported ? '日本冲绳县与那国岛' : null,
    );
    EpicenterRegionService.instance.setResolverForTesting(resolver);
    expect(
      getFEName(utoLatitude, utoLongitude),
      NativeEastAsiaRegions.supported ? '日本熊本县熊本附近' : '日本九州岛附近',
    );
    expect(
      getFEName(24.4670, 123.0000),
      NativeEastAsiaRegions.supported ? '日本冲绳县与那国岛附近' : '琉球群岛西南部附近',
    );
  });

  test('official USGS normalization receives the corrected Japan name', () {
    EpicenterRegionService.instance.setResolverForTesting(resolver);
    final payload = UsgsEqlistService().normalizeFeatureForUnifiedUi({
      'id': 'us6000tgb9',
      'properties': {
        'code': '6000tgb9',
        'status': 'reviewed',
        'place': '5 km E of Uto, Japan',
        'mag': 6.8,
        'time': DateTime.utc(2026, 7, 28, 7, 27, 15).millisecondsSinceEpoch,
        'updated': DateTime.utc(2026, 7, 28, 7, 55, 29).millisecondsSinceEpoch,
      },
      'geometry': {
        'coordinates': [130.7217, 32.6817, 10],
      },
    });

    expect(payload, isNotNull);
    expect(
      payload!['location'],
      NativeEastAsiaRegions.supported ? '日本熊本县熊本附近' : '日本九州岛附近',
    );
  });

  test(
    'official Korea polygons replace disabled rectangles; US remains FE',
    () {
      expect(
        resolver.lookup(37.4837, 127.0324),
        NativeEastAsiaRegions.supported ? '韩国首尔特别市' : null,
      );
      expect(resolver.lookup(45.5152, -122.6784), isNull);
      expect(resolver.lookup(36.1699, -115.1398), isNull);
      expect(resolver.lookup(60.7212, -135.0568), isNull);

      EpicenterRegionService.instance.setResolverForTesting(resolver);
      expect(
        getFEName(37.4837, 127.0324),
        NativeEastAsiaRegions.supported ? '韩国首尔特别市附近' : '朝鲜半岛南部附近',
      );
      expect(getFEName(45.5152, -122.6784), '华盛顿州、俄勒冈州边境地区附近');
      expect(getFEName(36.1699, -115.1398), '加利福尼亚州、内华达州边境地区附近');
      expect(getFEName(60.7212, -135.0568), '加拿大育空地区南部附近');
    },
  );

  test('resolves official land and geographic seas in the native index', () {
    expect(resolver.lookup(23.1101922, 121.3562179), '台湾省台东县成功镇');
    expect(resolver.lookup(24.9517868, 122.0129126), '台湾省新北市近岸海域');
    expect(
      resolver.lookup(25.1925147, 121.4162455),
      NativeEastAsiaRegions.supported ? '中国台湾北部海域' : '台湾北部海域',
    );
  });

  test('official land fixes missing islands with domestic display names', () {
    // Original township reference coordinates, not earthquake input fixtures.
    // Juguang's township reference point is at sea between islands; use an
    // unchanged vertex from official TOWNCODE 09007030 for its coverage check.
    final points = <(double, double, String)>[
      (22.5900263, 120.28471, '台湾省高雄市旗津区'),
      (22.348635, 120.3827309, '台湾省屏东县琉球乡'),
      (22.6658421, 121.4705314, '台湾省台东县绿岛乡'),
      (22.0244984, 121.5560627, '台湾省台东县兰屿乡'),
      (23.566159, 119.578692, '台湾省澎湖县马公市'),
      (23.584072, 119.6528318, '台湾省澎湖县湖西乡'),
      (23.666538, 119.598639, '台湾省澎湖县白沙乡'),
      (23.601088, 119.5069847, '台湾省澎湖县西屿乡'),
      (23.3576577, 119.500894, '台湾省澎湖县望安乡'),
      (23.2067107, 119.4244825, '台湾省澎湖县七美乡'),
      (24.432824, 118.320697, '福建省泉州市金门县金城镇'),
      (24.488898, 118.413132, '福建省泉州市金门县金沙镇'),
      (24.4414641, 118.4171018, '福建省泉州市金门县金湖镇'),
      (24.450966, 118.334887, '福建省泉州市金门县金宁乡'),
      (24.4295409, 118.2445892, '福建省泉州市金门县烈屿乡'),
      (24.9887062, 119.4531826, '福建省莆田市秀屿区乌丘屿'),
      (26.1529312, 119.9387995, '福建省福州市连江县马祖列岛南竿'),
      (26.223938, 119.997139, '福建省福州市连江县马祖列岛北竿'),
      (25.945652978002556, 119.96425136181097, '福建省福州市连江县马祖列岛莒光'),
      (26.3672636, 120.4898789, '福建省福州市连江县马祖列岛东引'),
    ];
    for (final (lat, lng, name) in points) {
      // These are unchanged official township reference points. Verify the
      // source names here; some coastal references lie outside the coarser
      // vector-map shoreline and the main entry must then display sea.
      expect(resolver.lookupChinaPlace(lat, lng), name, reason: '$lat,$lng');
    }
  });

  test('regional source does not assign South China Sea islands to Taiwan', () {
    // Source Qijin multipart includes these coordinates; their foreign source
    // administrative grouping is excluded from the regional naming index.
    for (final point in [(20.704, 116.721), (10.376, 114.365)]) {
      expect(
        resolver.lookup(point.$1, point.$2)?.startsWith('台湾省') ?? false,
        isFalse,
      );
    }
  });

  test('China land takes priority over overlapping CWA sea polygons', () {
    expect(resolver.lookup(24.4798, 118.0894), '福建省厦门市');
    expect(resolver.lookup(24.8741, 118.6757), '福建省泉州市');
    expect(resolver.lookup(26.0745, 119.2965), '福建省福州市');
    expect(resolver.lookup(25.4541, 119.0078), '福建省莆田市');
  });

  test('rejects invalid coordinates and leaves uncovered areas to FE', () {
    expect(resolver.lookup(double.nan, 120), isNull);
    expect(resolver.lookup(91, 120), isNull);
    expect(
      resolver.lookup(35.6762, 139.6503),
      NativeEastAsiaRegions.supported ? '日本东京都23区' : null,
    );
    EpicenterRegionService.instance.setResolverForTesting(resolver);

    expect(
      getFEName(35.6762, 139.6503),
      NativeEastAsiaRegions.supported ? '日本东京都23区附近' : '日本本州南岸近海附近',
    );
    expect(getFEName(double.nan, 120), isEmpty);
    expect(getFEName(91, 120), isEmpty);
  });

  test('getFEName keeps its synchronous API after assets are loaded', () {
    EpicenterRegionService.instance.setResolverForTesting(resolver);
    expect(getFEName(39.9042, 116.4074), '北京市东城区附近');
    expect(
      getFEName(37.5750, 126.9800),
      NativeEastAsiaRegions.supported ? '韩国首尔特别市附近' : '朝鲜半岛南部附近',
    );
    expect(getFEName(23.1101922, 121.3562179), '台湾省台东县成功镇附近');
  });

  test('loads all four runtime Flutter assets', () async {
    await EpicenterRegionService.instance.load();
    expect(EpicenterRegionService.instance.isLoaded, isTrue);
    expect(getFEName(39.9042, 116.4074), '北京市东城区附近');
    expect(getFEName(23.1101922, 121.3562179), '台湾省台东县成功镇附近');
    expect(
      getFEName(22.6658421, 121.4705314),
      NativeEastAsiaRegions.supported ? '中国台湾东部海域附近' : '台湾省台东县绿岛乡附近',
    );
  });
}
