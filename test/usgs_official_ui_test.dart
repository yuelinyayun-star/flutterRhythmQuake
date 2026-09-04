import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/usgs_eqlist_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('official USGS GeoJSON is normalized for the unified UI', () {
    final origin = DateTime.utc(2026, 6, 27, 13, 34, 52);
    final updated = DateTime.utc(2026, 6, 27, 14, 44, 30);
    final payload = UsgsEqlistService().normalizeFeatureForUnifiedUi({
      'id': 'us6000t8pa',
      'properties': {
        'code': '6000t8pa',
        'status': 'reviewed',
        'place': '43 km S of Jurm, Afghanistan',
        'mag': 6.1,
        'time': origin.millisecondsSinceEpoch,
        'updated': updated.millisecondsSinceEpoch,
      },
      'geometry': {
        'coordinates': [70.7644, 36.4731, 199],
      },
    });

    expect(payload, isNotNull);
    expect(payload!['eventId'], '6000t8pa');
    expect(payload['reviewType'], 'reviewed');
    expect(payload['originTime'], '2026-06-27T13:34:52.000Z');
    expect(payload['updateTime'], '2026-06-27T14:44:30.000Z');

    final event = QuakeEventAdapter.convert('usgsEqlist', payload, 0);
    expect(event, isNotNull);
    expect(event!.eventId, '6000t8pa');
    expect(event.apiTypeLabel, 'USGS');
    expect(event.titleText, 'USGS 地震情报正式测定');
    expect(event.reportTime, DateTime(2026, 6, 27, 22, 44, 30));
    expect(event.magnitude, 6.1);
    expect(event.depth, 199);
  });

  test('location whitelist bypasses magnitude only, not disabled source', () {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    provider.setInfoActionWhitelist('四川|重庆');
    final event = _usgsEvent(hypocenter: '四川北部', magnitude: 4.0);

    expect(provider.passesInfoMagnitudeFilterForTest(event, 5.0), isTrue);
    expect(provider.passesInfoMagnitudeFilterForTest(event, -1.0), isFalse);
    expect(
      provider.passesInfoMagnitudeFilterForTest(
        event.copyWith(hypocenter: '云南西部'),
        5.0,
      ),
      isFalse,
    );
  });

  test('USGS unified UI uses kanameishi information validity tiers', () {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);

    expect(
      provider.unifiedDismissSecondsForTest(
        _usgsEvent(magnitude: 5.0, className: 'green'),
      ),
      300,
    );
    expect(
      provider.unifiedDismissSecondsForTest(
        _usgsEvent(magnitude: 6.0, className: 'orange'),
      ),
      600,
    );
    expect(
      provider.unifiedDismissSecondsForTest(
        _usgsEvent(magnitude: 7.0, className: 'red'),
      ),
      900,
    );
    expect(
      provider.unifiedDismissSecondsForTest(
        _usgsEvent(magnitude: 7.5, className: 'purple'),
      ),
      1200,
    );
  });

  test('expired official USGS event does not enter the current UI', () {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    final oldEvent = _usgsEvent(
      magnitude: 5.0,
      reportTime: DateTime(2020, 1, 1),
    );

    provider.handleUnifiedEventForTest(oldEvent);

    expect(provider.unifiedEvents, isEmpty);
  });
}

UnifiedQuakeData _usgsEvent({
  String hypocenter = '测试地区',
  double magnitude = 5.0,
  String className = 'green',
  DateTime? reportTime,
}) {
  return UnifiedQuakeData(
    source: 'usgsEqlist',
    origin: 0,
    eventId: 'test-usgs',
    isEew: false,
    timeZone: 8,
    titleText: 'USGS自动测定',
    reportNumText: '',
    useShindo: false,
    maxIntensity: '4.0',
    className: className,
    hypocenter: hypocenter,
    originTime: DateTime(2020, 1, 1),
    reportTime: reportTime ?? DateTime(2020, 1, 1),
    magnitude: magnitude,
    depth: 10,
    depthText: '深度: 10km',
    lat: 30,
    lng: 100,
    apiTypeLabel: 'USGS',
  );
}
