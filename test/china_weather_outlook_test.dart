import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/china_weather_hourly_service.dart';

void main() {
  final source = File(
    'test/fixtures/china_weather_hourly/yiwu_outlook.js',
  ).readAsStringSync();
  final outlook = parseChinaWeatherOutlook(source);
  final today = outlook.days.first.date.add(const Duration(hours: 4));

  test('daily and life data retain every official raw field', () {
    final rawDays = chinaWeatherJsonValue(source, 'fc40') as List;
    expect(outlook.days.length, rawDays.length);
    for (var i = 0; i < rawDays.length; i++) {
      expect(outlook.days[i].raw, rawDays[i]);
    }
    final rawIndices = chinaWeatherJsonVariable(source, 'index3d')['i'] as List;
    expect(outlook.indices.map((i) => i.raw).toList(), rawIndices);
    expect(() => outlook.days.first.raw['003'] = '0', throwsUnsupportedError);
    expect(outlook.upcoming(today), hasLength(15));
    expect(outlook.today(today), same(outlook.days.first));
    expect(outlook.today(today)?.sunrise, '05:40');
    expect(outlook.today(today)?.sunset, '18:15');
  });

  test(
    'Beijing midnight selects correct day and expires previous day indices',
    () {
      final midnight = outlook.days.first.date.add(const Duration(hours: 16));
      expect(
        outlook.today(midnight.subtract(const Duration(seconds: 1))),
        same(outlook.days.first),
      );
      expect(outlook.today(midnight), same(outlook.days[1]));
      expect(outlook.todayIndices(today), isNotEmpty);
      expect(outlook.todayIndices(midnight), isEmpty);
      expect(outlook.upcoming(today.add(const Duration(days: 60))), isEmpty);
      expect(outlook.today(today.add(const Duration(days: 60))), isNull);
    },
  );

  test(
    'JSON array scanner handles braces inside strings without running code',
    () {
      expect(chinaWeatherJsonValue('var x=[{"s":"}]["}];throw 1;', 'x'), [
        {'s': '}]['},
      ]);
      expect(
        () => chinaWeatherJsonVariable('var x=[];', 'x'),
        throwsFormatException,
      );
      expect(
        () => chinaWeatherJsonValue('var x=execute();', 'x'),
        throwsFormatException,
      );
      expect(
        () => parseChinaWeatherOutlook('var fc40=[{"009":"20260230"}];'),
        throwsFormatException,
      );
    },
  );

  test('optional indices cannot destroy a valid daily forecast', () {
    final dailySource = source.split('var index3d').first;
    final result = parseChinaWeatherOutlook(dailySource);
    expect(result.days.length, outlook.days.length);
    expect(result.indices, isEmpty);
    for (final value in ['', 'NaN', 'Infinity', '9999']) {
      expect(chinaWeatherTemperature(value), isNull);
    }
    expect(chinaWeatherTemperature('0'), 0);
    expect(chinaWeatherTemperature('-10'), -10);
  });
}
