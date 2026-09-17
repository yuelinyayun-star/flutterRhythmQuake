import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/epicenter_region_service.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/utils/kma_location.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Reuse the existing WHEWS KMA adapter regression case, not a live capture.
  const whews = <String, dynamic>{
    'id': 'kma_20260723034704',
    'shockTime': '2026-07-23 02:47:04',
    'updateTime': '2026-07-23 02:48:05',
    'latitude': 36.1,
    'longitude': 128.2,
    'depth': 12,
    'magnitude': 4.2,
    'placeName': '경상북도',
    'maxIntensity': 'Ⅳ',
  };

  test(
    'FAN and WHEWS KMA use the same coordinate name without changing raw data',
    () async {
      final before = jsonEncode(whews);
      final event = QuakeEventAdapter.convertWhews('kma', whews)!;
      final fan = QuakeEventAdapter.convert('kmaEqlist', {
        'eventId': whews['id'],
        'location': '韩国附近',
        'latitude': whews['latitude'],
        'longitude': whews['longitude'],
        'magnitude': whews['magnitude'],
        'depth': whews['depth'],
        'originTime': '2026-07-23 03:47:04',
        'createTime': '2026-07-23 03:48:05',
        'maxIntensity': 4,
      }, 1)!;
      expect(event.hypocenter, '韩国附近');
      expect(event.hypocenter, fan.hypocenter);
      expect(event.apiTypeLabel, 'WHEWS');
      expect(fan.apiTypeLabel, 'FAN');
      expect(event.timeZone, 8);
      expect(fan.timeZone, 9);
      expect(event.maxIntensity, 'Ⅳ');
      expect(event.originTime, DateTime(2026, 7, 23, 2, 47, 4));
      expect(event.reportTime, DateTime(2026, 7, 23, 2, 48, 5));
      expect(jsonEncode(whews), before);
      await EpicenterRegionService.instance.load();
      expect(
        QuakeEventAdapter.convertWhews('kma', whews)!.hypocenter,
        event.hypocenter,
      );
    },
  );

  test('Yellow Sea mapping is stable for raw and already mapped names', () {
    expect(kmaDisplayLocation('서해', 35, 124), '黄海海域附近');
    expect(kmaDisplayLocation('黄海海域附近', 35, 124), '黄海海域附近');
  });

  test('missing or invalid coordinates retain the upstream name', () {
    for (final point in <(double?, double?)>[
      (null, null),
      (null, 128),
      (36, null),
      (0, 0),
      (double.nan, 128),
      (36, double.infinity),
      (91, 128),
      (36, 181),
    ]) {
      expect(kmaDisplayLocation('경상북도', point.$1, point.$2), '경상북도');
    }
    final raw = Map<String, dynamic>.from(whews)
      ..remove('latitude')
      ..remove('longitude');
    expect(QuakeEventAdapter.convertWhews('kma', raw)!.hypocenter, '경상북도');
  });
}
