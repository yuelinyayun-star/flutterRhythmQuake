import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/calculator.dart';
import 'package:flutterrhythmquake/core/travel_time_service.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('unified EEW countdown uses the S-wave travel-time table', () async {
    await TravelTimeService().load();
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final event = _eewEvent();
    const userLat = 35.60;
    const userLng = 140.20;
    const elapsedSeconds = 12;

    final actual = provider.unifiedSCountdownForTest(
      event,
      userLat: userLat,
      userLng: userLng,
      elapsedSeconds: elapsedSeconds,
    );
    final distance = QuakeCalculator.haversineDistance(
      event.lat!,
      event.lng!,
      userLat,
      userLng,
    );
    final reachTime = TravelTimeService().calcReachTime(
      distance <= 2000 ? 'jma2001' : 'jb',
      false,
      event.depth,
      distance,
    );
    final expected = (reachTime - elapsedSeconds).floor();

    expect(actual, expected < 0 ? 0 : expected);
    expect(
      provider.unifiedEventKeyForTest(event),
      isNot(provider.unifiedEventKeyForTest(event.copyWith(source: 'cea'))),
    );
  });

  test('unified EEW countdown skips cancelled and non-EEW events', () async {
    await TravelTimeService().load();
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      provider.unifiedSCountdownForTest(
        _eewEvent().copyWith(isCanceled: true),
        userLat: 35.60,
        userLng: 140.20,
        elapsedSeconds: 12,
      ),
      isNull,
    );
    expect(
      provider.unifiedSCountdownForTest(
        _eewEvent().copyWith(isEew: false),
        userLat: 35.60,
        userLng: 140.20,
        elapsedSeconds: 12,
      ),
      isNull,
    );
  });

  test(
    'unified countdown speech defaults to strong local intensity only',
    () async {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final shindoEvent = _eewEvent();
      expect(
        provider.unifiedCountdownIsStrongForTest(
          shindoEvent,
          userLat: shindoEvent.lat!,
          userLng: shindoEvent.lng!,
        ),
        isTrue,
      );
      expect(
        provider.unifiedCountdownIsStrongForTest(
          shindoEvent,
          userLat: 0,
          userLng: 0,
        ),
        isFalse,
      );

      final csisEvent = shindoEvent.copyWith(useShindo: false);
      expect(
        provider.unifiedCountdownIsStrongForTest(
          csisEvent,
          userLat: csisEvent.lat!,
          userLng: csisEvent.lng!,
        ),
        isTrue,
      );
      expect(
        provider.unifiedCountdownIsStrongForTest(
          csisEvent,
          userLat: 0,
          userLng: 0,
        ),
        isFalse,
      );
    },
  );
}

UnifiedQuakeData _eewEvent() {
  return UnifiedQuakeData(
    source: 'jmaEew',
    origin: 0,
    eventId: 'countdown-test',
    isEew: true,
    timeZone: 9,
    titleText: '紧急地震速报',
    reportNumText: '第1报',
    useShindo: true,
    maxIntensity: '4',
    className: 'yellow',
    hypocenter: '测试震中',
    originTime: DateTime(2026, 8, 5, 12),
    magnitude: 5.1,
    depth: 30,
    lat: 35.10,
    lng: 140.50,
  );
}
