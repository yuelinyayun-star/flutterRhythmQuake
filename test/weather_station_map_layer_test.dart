import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/cma_local_weather_service.dart';
import 'package:flutterrhythmquake/widgets/map/weather_station_map_layer.dart';

void main() {
  test('parses CmaStationSummary rows correctly and determines rain severity', () {
    final rows = [
      ['54511', '北京', '中国', 2, 39.9, 116.4, 29.3, '晴', 0, '西南风', '2级'],
      ['58457', '杭州', '中国', 2, 30.2, 120.1, 25.6, '中雨', 8, '东北风', '3~4级'],
      ['59287', '广州', '中国', 2, 23.1, 113.2, 27.0, '暴雨', 10, '南风', '5级'],
      ['57510', '铜梁', '中国', 3, 29.8, 106.0, 31.0, '多云', 1, '微风', '1级'],
      ['K1418', '余杭', '中国', 3, 30.4, 120.3, 24.5, '大暴雨', 11, '东风', '6级'],
    ];

    final summaries = cmaStationSummariesFromRows(rows);
    expect(summaries, hasLength(5));

    final beijing = summaries[0];
    expect(beijing.name, '北京');
    expect(beijing.temperature, 29.3);
    expect(beijing.isRaining, isFalse);
    expect(beijing.rainSeverity, 0);

    final hangzhou = summaries[1];
    expect(hangzhou.name, '杭州');
    expect(hangzhou.isRaining, isTrue);
    expect(hangzhou.rainSeverity, 2);
    expect(hangzhou.rainWithAmountText, '中雨');

    final guangzhou = summaries[2];
    expect(guangzhou.name, '广州');
    expect(guangzhou.isRaining, isTrue);
    expect(guangzhou.rainSeverity, 4);
    expect(guangzhou.rainWithAmountText, '暴雨');

    final yuhang = summaries[4];
    expect(yuhang.id, 'K1418');
    expect(yuhang.name, '余杭');
    expect(yuhang.isRaining, isTrue);
    expect(yuhang.rainSeverity, 5);
    expect(yuhang.rainWithAmountText, '大暴雨');
  });

  test('WeatherStationDisplayMode parses keys and provides display labels', () {
    expect(WeatherStationDisplayMode.fromKey('auto'), WeatherStationDisplayMode.auto);
    expect(WeatherStationDisplayMode.fromKey('rain'), WeatherStationDisplayMode.rain);
    expect(WeatherStationDisplayMode.fromKey('temperature'), WeatherStationDisplayMode.temperature);
    expect(WeatherStationDisplayMode.fromKey('wind'), WeatherStationDisplayMode.wind);

    expect(WeatherStationDisplayMode.auto.label, '综合(降雨优先)');
    expect(WeatherStationDisplayMode.rain.label, '降水雨量');
    expect(WeatherStationDisplayMode.temperature.label, '气温实况');
    expect(WeatherStationDisplayMode.wind.label, '风向风力');
  });
}
