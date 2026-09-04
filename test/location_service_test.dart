import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/location_service.dart';

void main() {
  test('parses district-level city field from upgraded FAN geo_ip', () {
    final lookup = parseFanstudioGeoIpResponse({
      'ip': '61.135.169.121',
      'country': '中国',
      'province': '北京市',
      'city': '西城区',
      'isp': 'China Unicom Beijing Province Network',
      'latitude': 39.9236,
      'longitude': 116.36,
    });

    expect(lookup, isNotNull);
    expect(lookup!.city, isNull);
    expect(lookup.district, '西城区');
    expect(lookup.regionLabel, '北京市 西城区');
  });

  test('parses explicit district field when provided', () {
    final lookup = parseFanstudioGeoIpResponse({
      'ip': '1.2.3.4',
      'country': '中国',
      'province': '浙江',
      'city': '金华市',
      'district': '义乌市',
      'latitude': 29.30,
      'longitude': 120.09,
    });

    expect(lookup, isNotNull);
    expect(lookup!.city, '金华市');
    expect(lookup.district, '义乌市');
    expect(lookup.regionLabel, '浙江 金华市 义乌市');
  });

  test('deduplicates province and city labels', () {
    expect(buildGeoIpRegionLabel(province: '北京市', city: '北京'), '北京市');
    expect(buildGeoIpRegionLabel(province: '浙江', city: '金华'), '浙江 金华');
  });

  test('rejects geo_ip error payloads', () {
    expect(parseFanstudioGeoIpResponse({'error': 'AUV俺不中了'}), isNull);
  });
}
