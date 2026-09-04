import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/local_weather_region.dart';

void main() {
  test('uses JMA weather inside Japan and not on the Korean peninsula', () {
    expect(LocalWeatherRegion.usesJapan(35.68, 139.76), isTrue);
    expect(LocalWeatherRegion.usesJapan(26.21, 127.68), isTrue);
    expect(LocalWeatherRegion.usesJapan(43.06, 141.35), isTrue);
    expect(LocalWeatherRegion.usesJapan(34.21, 129.29), isTrue);
    expect(LocalWeatherRegion.usesJapan(37.57, 126.98), isFalse);
    expect(LocalWeatherRegion.usesJapan(35.18, 129.08), isFalse);
  });

  test('uses CMA weather in mainland China but not Taiwan or Japan', () {
    expect(LocalWeatherRegion.usesChina(29.56, 106.55), isTrue);
    expect(LocalWeatherRegion.usesChina(39.90, 116.40), isTrue);
    expect(LocalWeatherRegion.usesChina(25.03, 121.56), isFalse);
    expect(LocalWeatherRegion.usesChina(35.68, 139.76), isFalse);
    expect(LocalWeatherRegion.usesJapan(25.03, 121.56), isFalse);
  });
}
