import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutterrhythmquake/models/weather_alarm.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'weather_alarm_local_only': false});
  });

  test('remote weather alarms keep the newest issue and merge API copies', () {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    final now = DateTime.now().toUtc();
    final newest = _alarm(
      id: 'weather-current',
      issueUtc: now,
      source: WeatherAlarmSource.fan,
    );
    final duplicateFromWhews = _alarm(
      id: 'weather-current',
      issueUtc: now,
      source: WeatherAlarmSource.whews,
    );
    final older = _alarm(
      id: 'weather-old',
      issueUtc: now.subtract(const Duration(hours: 1)),
      source: WeatherAlarmSource.whews,
    );

    provider.acceptRemoteWeatherAlarmForTest(newest);
    provider.acceptRemoteWeatherAlarmForTest(duplicateFromWhews);
    provider.acceptRemoteWeatherAlarmForTest(older);

    expect(provider.weatherAlarm?.id, 'weather-current');
    expect(provider.weatherAlarm?.source, WeatherAlarmSource.fan);
  });

  test('expired remote weather alarm cannot replace the current alarm', () {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    final now = DateTime.now().toUtc();
    final current = _alarm(id: 'weather-current', issueUtc: now);
    final expired = _alarm(
      id: 'weather-expired',
      issueUtc: now.subtract(const Duration(days: 2)),
    );

    provider.acceptRemoteWeatherAlarmForTest(current);
    provider.acceptRemoteWeatherAlarmForTest(expired);

    expect(provider.weatherAlarm?.id, 'weather-current');
  });

  testWidgets('a visible window rechecks the held weather alarm deadline', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 11, 1);
    final provider = QuakeProvider(
      startCatalogServices: false,
      displayNow: () => now,
    );
    final listener = AppLifecycleListener(
      onShow: provider.checkLiveEventExpiry,
    );
    void lifecycle(AppLifecycleState state) =>
        tester.binding.handleAppLifecycleStateChanged(state);

    try {
      final alarm = _alarm(id: 'held', issueUtc: now);
      provider.acceptRemoteWeatherAlarmForTest(alarm);

      lifecycle(AppLifecycleState.resumed);
      lifecycle(AppLifecycleState.inactive);
      lifecycle(AppLifecycleState.hidden);
      lifecycle(AppLifecycleState.paused);
      now = alarm.validUntilUtc.subtract(const Duration(seconds: 1));
      lifecycle(AppLifecycleState.hidden);
      lifecycle(AppLifecycleState.inactive);
      expect(provider.weatherAlarm, same(alarm));

      lifecycle(AppLifecycleState.hidden);
      lifecycle(AppLifecycleState.paused);
      now = alarm.validUntilUtc;
      lifecycle(AppLifecycleState.hidden);
      lifecycle(AppLifecycleState.inactive);
      expect(provider.weatherAlarm, isNull);
      lifecycle(AppLifecycleState.resumed);
    } finally {
      listener.dispose();
      provider.dispose();
    }
  });
}

WeatherAlarm _alarm({
  required String id,
  required DateTime issueUtc,
  WeatherAlarmSource source = WeatherAlarmSource.fan,
}) {
  return WeatherAlarm(
    id: id,
    headline: '暴雨橙色预警',
    effective: _chinaTime(issueUtc),
    description: '请注意防范',
    type: 'p0002002',
    source: source,
    receivedAtUtc: issueUtc,
  );
}

String _chinaTime(DateTime utc) {
  final value = utc.toUtc().add(const Duration(hours: 8));
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}
