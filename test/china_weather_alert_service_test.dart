import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/china_weather_alert_service.dart';

void main() {
  const yiwuLat = 29.36;
  const yiwuLng = 120.17;

  List<dynamic> row({
    required String area,
    required String headline,
    required double lon,
    required double lat,
    String id = 'test',
    String file = '330783-000104.html',
  }) {
    return [area, file, lon, lat, id, '330783', headline];
  }

  test('county filter in Yiwu ignores neighboring Dongyang alerts', () {
    final picked = chinaWeatherPickLocalAreaForTest(
      rows: [
        row(
          area: '浙江省东阳市',
          headline: '东阳市发布暴雨红色预警信号',
          lon: 120.241,
          lat: 29.272,
        ),
      ],
      lat: yiwuLat,
      lng: yiwuLng,
      resolvedAdminArea: '浙江省金华市义乌市',
      adminLevel: ChinaWeatherAdminLevel.county,
    );

    expect(picked, isNull);
  });

  test('county filter in Yiwu keeps local Yiwu alerts', () {
    final picked = chinaWeatherPickLocalAreaForTest(
      rows: [
        row(
          area: '浙江省东阳市',
          headline: '东阳市发布暴雨红色预警信号',
          lon: 120.241,
          lat: 29.272,
        ),
        row(
          area: '浙江省金华市义乌市',
          headline: '义乌市发布高温橙色预警信号',
          lon: 120.075,
          lat: 29.306,
          id: 'yiwu',
          file: '330782-000103.html',
        ),
      ],
      lat: yiwuLat,
      lng: yiwuLng,
      resolvedAdminArea: '浙江省金华市义乌市',
      adminLevel: ChinaWeatherAdminLevel.county,
    );

    expect(picked, '浙江省金华市义乌市');
  });

  test(
    'county filter without resolved admin area does not borrow nearby alerts',
    () {
      final picked = chinaWeatherPickLocalAreaForTest(
        rows: [
          row(
            area: '浙江省东阳市',
            headline: '东阳市发布暴雨红色预警信号',
            lon: 120.241,
            lat: 29.272,
          ),
        ],
        lat: yiwuLat,
        lng: yiwuLng,
        adminLevel: ChinaWeatherAdminLevel.county,
      );

      expect(picked, isNull);
    },
  );
}
