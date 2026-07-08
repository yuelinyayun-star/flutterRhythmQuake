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
}) {
  return QuakeMessage(
    source: source,
    eventId: eventId,
    location: '岩手県沖',
    magnitude: 6.9,
    latitude: 39.0,
    longitude: 142.0,
    depth: 50,
    originTime: originTime,
    reportTime: reportTime,
    isHistory: true,
    isInfoEvent: true,
    maxIntensity: 6,
    jmaShindo: '6+',
  );
}
