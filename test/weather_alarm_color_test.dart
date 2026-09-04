import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/weather_alarm.dart';

void main() {
  WeatherAlarm alarm({
    required String type,
    WeatherAlarmSource source = WeatherAlarmSource.fan,
  }) {
    return WeatherAlarm(
      id: 'id',
      headline: 'headline',
      effective: 'effective',
      description: 'description',
      type: type,
      source: source,
    );
  }

  test('FAN weather alarm keeps FAN level color order', () {
    expect(alarm(type: '0401').levelColor, const Color(0xFFE74C3C));
    expect(alarm(type: '0204').levelColor, const Color(0xFF3498DB));
    expect(alarm(type: '0401').levelLabel, '\u7ea2\u8272');
    expect(alarm(type: '0204').levelLabel, '\u84dd\u8272');
  });

  test('local China Weather alarm uses China Weather level color order', () {
    expect(
      alarm(
        type: '0401',
        source: WeatherAlarmSource.chinaWeatherLocal,
      ).levelColor,
      const Color(0xFF3498DB),
    );
    expect(
      alarm(
        type: '0204',
        source: WeatherAlarmSource.chinaWeatherLocal,
      ).levelColor,
      const Color(0xFFE74C3C),
    );
    expect(
      alarm(
        type: '0401',
        source: WeatherAlarmSource.chinaWeatherLocal,
      ).levelLabel,
      '\u84dd\u8272',
    );
    expect(
      alarm(
        type: '0204',
        source: WeatherAlarmSource.chinaWeatherLocal,
      ).levelLabel,
      '\u7ea2\u8272',
    );
  });

  test('JMA weather alarm uses warning level colors and labels', () {
    expect(
      alarm(type: '1104', source: WeatherAlarmSource.jmaLocal).levelColor,
      const Color(0xFFAF0000),
    );
    expect(
      alarm(type: '1103', source: WeatherAlarmSource.jmaLocal).levelColor,
      const Color(0xFFE74C3C),
    );
    expect(
      alarm(type: '1102', source: WeatherAlarmSource.jmaLocal).levelColor,
      const Color(0xFFEBC033),
    );
    expect(
      alarm(type: '1104', source: WeatherAlarmSource.jmaLocal).levelLabel,
      '\u7279\u5225',
    );
    expect(
      alarm(type: '1103', source: WeatherAlarmSource.jmaLocal).levelLabel,
      '\u8b66\u5831',
    );
    expect(
      alarm(type: '1102', source: WeatherAlarmSource.jmaLocal).levelLabel,
      '\u6ce8\u610f',
    );
  });

  test('remote weather alarm uses source time and explicit expiry', () {
    final remote = WeatherAlarm.fromFanJson({
      'id': 'weather-expiry',
      'headline': '暴雨预警',
      'effective': '2026-08-10 12:00:00',
      'expires': '2026-08-10 15:00:00',
      'description': '测试',
      'type': '0401',
    }, source: WeatherAlarmSource.whews);

    expect(remote.effectiveInstantUtc, DateTime.utc(2026, 8, 10, 4));
    expect(remote.validUntilUtc, DateTime.utc(2026, 8, 10, 7));
    expect(remote.isExpired(DateTime.utc(2026, 8, 10, 6, 59)), isFalse);
    expect(remote.isExpired(DateTime.utc(2026, 8, 10, 7)), isTrue);
  });
}
