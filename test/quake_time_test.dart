import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/quake_time.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';

void main() {
  test('formatUnifiedOriginClock uses source wall-clock components', () {
    final event = UnifiedQuakeData(
      source: 'whews_sgc',
      origin: 9,
      eventId: 'SGC-1',
      isEew: false,
      timeZone: 8,
      titleText: '哥伦比亚地质局地震信息',
      reportNumText: '正式',
      useShindo: false,
      maxIntensity: '-',
      className: 'green',
      hypocenter: '哥伦比亚',
      originTime: DateTime(2026, 8, 13, 19, 22, 0),
      magnitude: 3.6,
      depth: 94,
      depthText: '深度: 94km',
      apiTypeLabel: 'WHEWS',
    );

    expect(
      QuakeTime.formatUnifiedOriginClock(event),
      '2026-08-13 19:22:00 (UTC+8)',
    );
    expect(
      QuakeTime.formatUnifiedOriginClock(event, includeSeconds: false),
      '2026-08-13 19:22 (UTC+8)',
    );
  });

  test('wall-clock conversion keeps JST and UTC+8 instants distinct', () {
    final jst = QuakeTime.wallClockToUtc(
      DateTime(2026, 8, 13, 19, 22),
      const Duration(hours: 9),
    );
    final cst = QuakeTime.wallClockToUtc(
      DateTime(2026, 8, 13, 18, 22),
      const Duration(hours: 8),
    );

    expect(jst, cst);
    expect(jst.isUtc, isTrue);
  });

  test('explicit event timezone overrides source fallback for expiry math', () {
    final event = QuakeMessage(
      source: QuakeSourceType.fssnCmt,
      eventId: 'fssn-cmt-test',
      location: 'test',
      magnitude: 5,
      latitude: 0,
      longitude: 0,
      depth: 10,
      originTime: DateTime(2026, 8, 13, 19, 22),
      timeZone: 8,
    );

    expect(QuakeTime.eventInstantUtc(event), DateTime.utc(2026, 8, 13, 11, 22));
  });

  test('serialized timezone accepts the legacy string form', () {
    final event = QuakeMessage.fromMap({
      'eventId': 'serialized-timezone',
      'source': 'QuakeSourceType.cenc',
      'location': 'test',
      'magnitude': 4.0,
      'latitude': 0.0,
      'longitude': 0.0,
      'depth': 10.0,
      'originTime': '2026-08-13T11:22:00.000Z',
      'isTest': 0,
      'isTsunamiWarning': 0,
      'isHistory': 0,
      'isInfoEvent': 0,
      'timeZone': '8',
      'isWarn': 0,
      'isFinal': 0,
      'isCanceled': 0,
      'isAssumption': 0,
    });

    expect(event.timeZone, 8);
  });

  test('source display keeps Japan CMT at UTC+9 on a UTC+8 device', () {
    final event = QuakeMessage(
      source: QuakeSourceType.hinetAquaCmt,
      eventId: 'aqua-display-test',
      location: '日本海域',
      magnitude: 5.1,
      latitude: 35,
      longitude: 140,
      depth: 20,
      originTime: DateTime(2026, 8, 13, 20, 22),
      timeZone: 9,
    );

    expect(QuakeTime.displayClock(event), DateTime(2026, 8, 13, 20, 22));
    expect(QuakeTime.zoneLabel(event), 'UTC+9');
  });
}
