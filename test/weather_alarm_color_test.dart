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
}
