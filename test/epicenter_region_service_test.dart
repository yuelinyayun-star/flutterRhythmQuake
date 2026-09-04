import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/epicenter_region_service.dart';
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

  test('keeps Japan land on FE instead of CWA or Korea regions', () {
    const utoLatitude = 32.6817;
    const utoLongitude = 130.7217;

    expect(resolver.lookup(utoLatitude, utoLongitude), isNull);
    expect(resolver.lookup(24.4670, 123.0000), isNull);
    EpicenterRegionService.instance.setResolverForTesting(resolver);
    expect(getFEName(utoLatitude, utoLongitude), '日本九州岛附近');
    expect(getFEName(24.4670, 123.0000), '琉球群岛西南部附近');
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
    expect(payload!['location'], '日本九州岛附近');
  });

  test('unreliable Korea and US rectangles no longer override FE', () {
    expect(resolver.lookup(37.4837, 127.0324), isNull);
    expect(resolver.lookup(45.5152, -122.6784), isNull);
    expect(resolver.lookup(36.1699, -115.1398), isNull);
    expect(resolver.lookup(60.7212, -135.0568), isNull);

    EpicenterRegionService.instance.setResolverForTesting(resolver);
    expect(getFEName(37.4837, 127.0324), '韩国附近');
    expect(getFEName(45.5152, -122.6784), '华盛顿州、俄勒冈州边境地区附近');
    expect(getFEName(36.1699, -115.1398), '加利福尼亚州、内华达州边境地区附近');
    expect(getFEName(60.7212, -135.0568), '加拿大育空地区南部附近');
  });

  test('resolves exact CWA land, nearshore, and sea polygons', () {
    expect(resolver.lookup(23.1101922, 121.3562179), '臺東縣成功鎮');
    expect(resolver.lookup(24.9517868, 122.0129126), '新北市近岸海域');
    expect(resolver.lookup(25.1925147, 121.4162455), '臺灣北部海域');
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
    expect(resolver.lookup(35.6762, 139.6503), isNull);

    expect(getFEName(35.6762, 139.6503), '日本本州南岸近海附近');
    expect(getFEName(double.nan, 120), isEmpty);
    expect(getFEName(91, 120), isEmpty);
  });

  test('getFEName keeps its synchronous API after assets are loaded', () {
    EpicenterRegionService.instance.setResolverForTesting(resolver);
    expect(getFEName(39.9042, 116.4074), '北京市东城区附近');
    expect(getFEName(37.5750, 126.9800), '韩国附近');
    expect(getFEName(23.1101922, 121.3562179), '臺東縣成功鎮附近');
  });

  test('loads all four runtime Flutter assets', () async {
    await EpicenterRegionService.instance.load();
    expect(EpicenterRegionService.instance.isLoaded, isTrue);
    expect(getFEName(39.9042, 116.4074), '北京市东城区附近');
  });
}
