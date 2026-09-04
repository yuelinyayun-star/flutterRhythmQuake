import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/eqlist_manager.dart';

void main() {
  final manager = EqlistManager();

  setUp(() {
    _clear(manager);
  });

  tearDown(() {
    _clear(manager);
  });

  test('dedupes same JMA event inserted from another pipeline', () {
    final origin = DateTime(2026, 6, 25, 7, 30);
    manager.updateJmaList([
      _quake(
        source: QuakeSourceType.wolfx,
        eventId: 'wolfx-jma-1',
        originTime: origin,
      ),
    ]);

    manager.upsertBucketItem(
      'jmaEqlist',
      _quake(
        source: QuakeSourceType.jma_fan,
        eventId: 'fan-jma-1',
        originTime: origin.add(const Duration(seconds: 20)),
        reportTime: origin.add(const Duration(minutes: 1)),
      ),
    );

    expect(manager.jmaList, hasLength(1));
    expect(manager.jmaList.single.eventId, 'fan-jma-1');
  });

  test('resolved JMA report replaces same-second investigation in list', () {
    final origin = DateTime(2026, 8, 9, 14, 5);
    manager.updateJmaList([
      _quake(
        source: QuakeSourceType.p2p,
        eventId: '2026-08-09 14:05:00',
        originTime: origin,
        location: '',
        magnitude: -1,
        depth: -1,
      ),
    ]);

    manager.upsertBucketItem(
      'jmaEqlist',
      _quake(
        source: QuakeSourceType.jma_fan,
        eventId: '20260809140518',
        originTime: origin,
        location: '千葉県北東部',
        magnitude: 4.2,
        depth: 10,
      ),
    );

    expect(manager.jmaList, hasLength(1));
    expect(manager.jmaList.single.eventId, '20260809140518');
    expect(manager.jmaList.single.location, '千葉県北東部');
    expect(manager.jmaList.single.magnitude, 4.2);
    expect(manager.jmaList.single.depth, 10);
  });

  test('keeps the newest 50 JMA items in source order', () {
    final origin = DateTime(2026, 7, 28, 18);
    manager.updateJmaList([
      for (var index = 0; index < 60; index++)
        _quake(
          source: QuakeSourceType.wolfx,
          eventId: 'jma-$index',
          originTime: origin.subtract(Duration(minutes: index)),
        ),
    ]);

    expect(manager.jmaList, hasLength(50));
    expect(manager.jmaList.first.eventId, 'jma-0');
    expect(manager.jmaList.last.eventId, 'jma-49');
  });
}

void _clear(EqlistManager manager) {
  manager.updateJmaList(const []);
  manager.updateCencList(const []);
  manager.updateUsgsList(const []);
  manager.updateFssnList(const []);
  manager.updateKmaList(const []);
  manager.updateCwaList(const []);
  manager.updateEmscList(const []);
}

QuakeMessage _quake({
  required QuakeSourceType source,
  required String eventId,
  required DateTime originTime,
  DateTime? reportTime,
  String location = '岩手県沖',
  double magnitude = 6.9,
  double depth = 50,
}) {
  return QuakeMessage(
    source: source,
    eventId: eventId,
    location: location,
    magnitude: magnitude,
    latitude: 39.0,
    longitude: 142.0,
    depth: depth,
    originTime: originTime,
    reportTime: reportTime,
    isHistory: true,
    isInfoEvent: true,
    maxIntensity: 6,
    jmaShindo: '6+',
  );
}
