import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/background_event_processor.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
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
    'later JMA report replaces investigation fields with resolved values',
    () {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      final originTime = DateTime(2026, 8, 9, 14, 5);
      final investigating = UnifiedQuakeData(
        source: 'jmaEqlist',
        origin: 2,
        eventId: '2026-08-09 14:05:00',
        isEew: false,
        timeZone: 9,
        titleText: '震度速報',
        reportNumText: '',
        useShindo: true,
        maxIntensity: '4',
        className: 'yellow',
        hypocenter: '',
        originTime: originTime,
        reportTime: originTime.add(const Duration(seconds: 18)),
        magnitude: -1,
        depth: -1,
        lat: null,
        lng: null,
      );
      final resolved = investigating.copyWith(
        origin: 3,
        eventId: '20260809140518',
        titleText: '震源・震度に関する情報',
        reportNumText: '第2報',
        hypocenter: '千葉県北東部',
        reportTime: originTime.add(const Duration(seconds: 40)),
        magnitude: 4.2,
        depth: 10,
        depthText: '深度 10 km',
        lat: 35.8,
        lng: 140.6,
      );

      final merged = provider.mergeUnifiedInfoEventForTest(
        investigating,
        resolved,
      );

      expect(merged.eventId, investigating.eventId);
      expect(merged.titleText, '震源・震度に関する情報');
      expect(merged.reportNumText, '第2報');
      expect(merged.hypocenter, '千葉県北東部');
      expect(merged.magnitude, 4.2);
      expect(merged.depth, 10);
      expect(merged.depthText, '深度 10 km');
      expect(merged.lat, 35.8);
      expect(merged.lng, 140.6);
    },
  );

  test('P2P investigation event is not converted into a map epicenter', () {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    final sourceNow = DateTime.now().toUtc().add(const Duration(hours: 9));
    final originTime = DateTime(
      sourceNow.year,
      sourceNow.month,
      sourceNow.day,
      sourceNow.hour,
      sourceNow.minute,
      sourceNow.second,
    ).subtract(const Duration(minutes: 1));
    final event = QuakeEventAdapter.convert('jmaEqlist', {
      '_id': 'p2p-investigation-current',
      'earthquake': {
        'hypocenter': {
          'name': '調査中',
          'magnitude': -1,
          'depth': -1,
          'latitude': -200,
          'longitude': -200,
        },
        'maxScale': 30,
        'time': _formatJmaTime(originTime, slash: true),
      },
      'issue': {
        'type': 'ScalePrompt',
        'time': _formatJmaTime(
          originTime.add(const Duration(seconds: 18)),
          slash: true,
        ),
      },
      'points': [
        {'addr': '埼玉県南部', 'isArea': true, 'pref': '埼玉県', 'scale': 30},
      ],
    }, 2);

    expect(event, isNotNull);
    provider.handleUnifiedEventForTest(event!);

    expect(provider.unifiedEvents, hasLength(1));
    final mapEvent = provider.unifiedMapEvents.single;
    expect(mapEvent.latitude.isNaN, isTrue);
    expect(mapEvent.longitude.isNaN, isTrue);
    expect(mapEvent.magnitude, -1);
    expect(mapEvent.jmaShindo, '3');
    expect(provider.unifiedEvents.single.warnArea, contains('埼玉県南部'));
  });

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

  test('P2P and WHEWS JMA information merge by shock time', () {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    final sourceNow = DateTime.now().toUtc().add(const Duration(hours: 9));
    final originTime = DateTime(
      sourceNow.year,
      sourceNow.month,
      sourceNow.day,
      sourceNow.hour,
      sourceNow.minute,
      sourceNow.second,
    ).subtract(const Duration(minutes: 1));
    final p2pReportTime = originTime.add(const Duration(seconds: 30));
    final whewsReportTime = originTime.add(const Duration(seconds: 31));
    final p2p = QuakeEventAdapter.convert('jmaEqlist', {
      '_id': 'p2p-jma-current',
      'earthquake': {
        'hypocenter': {
          'name': '三重県南部',
          'magnitude': 3.2,
          'depth': 10,
          'latitude': 34.2,
          'longitude': 136.1,
        },
        'maxScale': 30,
        'time': _formatJmaTime(originTime, slash: true),
      },
      'issue': {
        'type': 'DetailScale',
        'time': _formatJmaTime(p2pReportTime, slash: true),
      },
      'points': [
        {'addr': '熊野市紀和町板屋', 'isArea': false, 'pref': '三重県', 'scale': 30},
      ],
    }, 2);
    final whews = QuakeEventAdapter.convertWhews('jma', {
      'id': _timeToken(whewsReportTime),
      'updates': 1,
      'shockTime': _formatJmaTime(originTime),
      'createTime': _formatJmaTime(whewsReportTime),
      'latitude': 34.2,
      'longitude': 136.1,
      'depth': 10,
      'magnitude': 3.2,
      'placeName': '三重県南部',
      'maxIntensity': '3',
      'infoTypeName': '発表',
      'title': '震源・震度に関する情報',
      'intensities': const [],
    });

    expect(p2p, isNotNull);
    expect(whews, isNotNull);
    expect(p2p!.eventId, isNot(whews!.eventId));
    expect(
      provider.unifiedEventKeyForTest(p2p),
      provider.unifiedEventKeyForTest(whews),
    );

    provider.handleUnifiedEventForTest(p2p);
    provider.handleUnifiedEventForTest(whews);

    expect(provider.unifiedEvents, hasLength(1));
    final merged = provider.unifiedEvents.single;
    expect(merged.eventId, p2p.eventId);
    expect(merged.titleText, '各地の震度に関する情報');
    expect(merged.reportNumText, isEmpty);

    final processor = BackgroundEventProcessor(sourceInfoMagFilters: const {});
    expect(processor.process(p2p).type, BackgroundEventResultType.newEvent);
    final backgroundUpdate = processor.process(whews);
    expect(backgroundUpdate.type, BackgroundEventResultType.update);
    expect(backgroundUpdate.event?.warnArea, p2p.warnArea);
    expect(backgroundUpdate.event?.titleText, '各地の震度に関する情報');
  });

  test('later P2P update does not inherit WHEWS report number', () {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    final originTime = DateTime(2026, 8, 15, 20, 30);
    final whews = UnifiedQuakeData(
      source: 'jmaEqlist',
      origin: 3,
      eventId: '20260815203000',
      isEew: false,
      timeZone: 9,
      titleText: '震源・震度に関する情報',
      reportNumText: '第1報',
      useShindo: true,
      maxIntensity: '1',
      className: 'gray',
      hypocenter: '台湾付近',
      originTime: originTime,
      reportTime: originTime.add(const Duration(minutes: 2)),
      magnitude: 4.6,
      depth: 70,
      depthText: '深さ: 70km',
      apiTypeLabel: 'WHEWS',
    );
    final p2p = UnifiedQuakeData(
      source: 'jmaEqlist',
      origin: 2,
      eventId: '2026-08-15 20:30:00',
      isEew: false,
      timeZone: 9,
      titleText: '各地の震度に関する情報',
      reportNumText: '',
      useShindo: true,
      maxIntensity: '1',
      className: 'gray',
      hypocenter: '台湾付近',
      originTime: originTime,
      reportTime: originTime.add(const Duration(minutes: 3)),
      magnitude: 4.6,
      depth: 70,
      depthText: '深さ: 70km',
      apiTypeLabel: 'P2PQ',
    );

    final merged = provider.mergeUnifiedInfoEventForTest(whews, p2p);
    expect(merged.origin, 2);
    expect(merged.titleText, '各地の震度に関する情報');
    expect(merged.reportNumText, isEmpty);
    expect(UnifiedEventPresentation.fromEvent(merged).title, '各地の震度に関する情報');
  });

  test('WHEWS JMA cancellation does not retain an old intensity layer', () {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    final originTime = DateTime(2026, 8, 9, 14, 5);
    final active = UnifiedQuakeData(
      source: 'jmaEqlist',
      origin: 2,
      eventId: '2026-08-09 14:05:00',
      isEew: false,
      timeZone: 9,
      titleText: '各地の震度に関する情報',
      reportNumText: '',
      useShindo: true,
      maxIntensity: '3',
      className: 'green',
      hypocenter: '奈良県',
      originTime: originTime,
      reportTime: originTime.add(const Duration(minutes: 3)),
      magnitude: 3.2,
      depth: 10,
      depthText: '深さ: 10km',
      lat: 34.68,
      lng: 135.82,
      warnArea: '[{"name":"奈良県","intensity":"3"}]',
    );
    final canceled = active.copyWith(
      origin: 3,
      eventId: '20260809140518',
      titleText: '震源・震度に関する情報',
      reportNumText: '第2報（取消）',
      className: 'dark-gray',
      isCanceled: true,
      warnArea: '',
    );

    final merged = provider.mergeUnifiedInfoEventForTest(active, canceled);
    expect(merged.isCanceled, isTrue);
    expect(merged.warnArea, isEmpty);
  });
}

String _formatJmaTime(DateTime value, {bool slash = false}) {
  String two(int number) => number.toString().padLeft(2, '0');
  final separator = slash ? '/' : '-';
  return '${value.year.toString().padLeft(4, '0')}$separator'
      '${two(value.month)}$separator${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}

String _timeToken(DateTime value) =>
    _formatJmaTime(value).replaceAll(RegExp(r'[^0-9]'), '');
