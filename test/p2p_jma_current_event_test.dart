import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'same JMA info event keeps detailed P2P state on later lower update',
    () {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);

      final detail = UnifiedQuakeData(
        source: 'jmaEqlist',
        origin: 2,
        eventId: '2026-06-27 02:33:00',
        isEew: false,
        timeZone: 9,
        titleText: '各地の震度に関する情報',
        reportNumText: '',
        useShindo: true,
        maxIntensity: '3',
        className: 'green',
        hypocenter: '福島県会津',
        originTime: DateTime(2026, 6, 26, 17, 33),
        reportTime: DateTime(2026, 6, 26, 17, 35, 55),
        magnitude: 3.6,
        depth: 10,
        depthText: '深さ: 10km',
        lat: 37.1,
        lng: 139.4,
        warnArea: '[{"name":"福島県会津","intensity":"3","className":"green"}]',
        apiTypeLabel: 'P2PQ',
      );

      final laterDestination = UnifiedQuakeData(
        source: 'jmaEqlist',
        origin: 1,
        eventId: '20260627023300',
        isEew: false,
        timeZone: 9,
        titleText: '震源に関する情報',
        reportNumText: '',
        useShindo: true,
        maxIntensity: '不明',
        className: 'dark-gray',
        hypocenter: '福島県会津',
        originTime: DateTime(2026, 6, 26, 17, 33),
        reportTime: DateTime(2026, 6, 26, 17, 36, 5),
        magnitude: 3.6,
        depth: 10,
        depthText: '深さ: 10km',
        lat: 37.1,
        lng: 139.4,
        apiTypeLabel: 'FAN',
      );

      final merged = provider.mergeUnifiedInfoEventForTest(
        detail,
        laterDestination,
      );

      expect(merged.eventId, detail.eventId);
      expect(merged.titleText, '各地の震度に関する情報');
      expect(merged.maxIntensity, '3');
      expect(merged.className, 'green');
      expect(merged.warnArea, detail.warnArea);
      expect(merged.hypocenter, '福島県会津');
    },
  );

  test(
    'USGS same report body correction is accepted like kanameishi store',
    () {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);

      final reportTime = DateTime(2026, 6, 27, 22, 44, 30);
      final originTime = DateTime(2026, 6, 27, 21, 34, 52);
      final oldEvent = UnifiedQuakeData(
        source: 'usgsEqlist',
        origin: 1,
        eventId: '6000t8pa',
        isEew: false,
        timeZone: 8,
        titleText: 'USGS 地震情报正式测定',
        reportNumText: '',
        useShindo: false,
        maxIntensity: '5.0',
        className: 'green',
        hypocenter: '阿富汗',
        originTime: originTime,
        reportTime: reportTime,
        magnitude: 6.0,
        depth: 199,
        depthText: '深度: 199km',
        lat: 36.4731,
        lng: 70.7644,
      );
      final corrected = oldEvent.copyWith(magnitude: 6.1, maxIntensity: '6.0');

      expect(
        provider.isUsgsSameReportBodyCorrectionForTest(oldEvent, corrected),
        isTrue,
      );
    },
  );

  test('USGS cached body skips repeated updateTime-only push', () {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);

    final event = UnifiedQuakeData(
      source: 'usgsEqlist',
      origin: 1,
      eventId: '6000t8pa',
      isEew: false,
      timeZone: 8,
      titleText: 'USGS 地震情报正式测定',
      reportNumText: '',
      useShindo: false,
      maxIntensity: '5.0',
      className: 'green',
      hypocenter: '阿富汗',
      originTime: DateTime(2026, 6, 27, 21, 34, 52),
      reportTime: DateTime(2026, 6, 27, 22, 44, 30),
      magnitude: 6.1,
      depth: 199,
      depthText: '深度: 199km',
      lat: 36.4731,
      lng: 70.7644,
    );

    expect(provider.shouldSuppressCachedUsgsInfoBodyForTest(event), isFalse);
    expect(
      provider.shouldSuppressCachedUsgsInfoBodyForTest(
        event.copyWith(reportTime: DateTime(2026, 6, 28, 0, 10)),
      ),
      isTrue,
    );
    expect(
      provider.shouldSuppressCachedUsgsInfoBodyForTest(
        event.copyWith(magnitude: 6.2, maxIntensity: '6.0'),
      ),
      isFalse,
    );
  });

  test('no-update FAN event is suppressed after it was already seen', () {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);

    final event = UnifiedQuakeData(
      source: 'emsc',
      origin: 1,
      eventId: 'emsc2026abcd',
      isEew: false,
      timeZone: 8,
      titleText: 'EMSC quake info',
      reportNumText: '',
      useShindo: false,
      maxIntensity: '4.0',
      className: 'green',
      hypocenter: 'Test region',
      originTime: DateTime(2026, 6, 27, 10),
      reportTime: DateTime(2026, 6, 27, 10),
      magnitude: 5.2,
      depth: 10,
      lat: 1,
      lng: 2,
    );

    expect(provider.shouldSuppressSeenNoUpdateInfoEventForTest(event), isFalse);

    provider.rememberNoUpdateInfoEventForTest(event);

    expect(provider.shouldSuppressSeenNoUpdateInfoEventForTest(event), isTrue);
  });

  test('no-update FAN seen key normalizes Eqlist source aliases', () {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);

    final event = UnifiedQuakeData(
      source: 'emsc',
      origin: 1,
      eventId: 'emsc2026alias',
      isEew: false,
      timeZone: 8,
      titleText: 'EMSC quake info',
      reportNumText: '',
      useShindo: false,
      maxIntensity: '4.0',
      className: 'green',
      hypocenter: 'Test region',
      originTime: DateTime(2026, 6, 27, 10),
      reportTime: DateTime(2026, 6, 27, 10),
      magnitude: 5.2,
      depth: 10,
      lat: 1,
      lng: 2,
    );

    provider.rememberNoUpdateInfoEventForTest(event);

    expect(
      provider.unifiedEventKeyForTest(event),
      provider.unifiedEventKeyForTest(event.copyWith(source: 'emscEqlist')),
    );
    expect(
      provider.shouldSuppressSeenNoUpdateInfoEventForTest(
        event.copyWith(source: 'emscEqlist'),
      ),
      isTrue,
    );
  });
}
