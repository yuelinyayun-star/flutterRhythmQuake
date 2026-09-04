import 'package:flutter_test/flutter_test.dart';

import 'package:flutterrhythmquake/models/jma_lpgm_bulletin.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('JMA LPGM enters unified UI, replaces by event id, and clears', () {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    final now = DateTime.now().toUtc();

    provider.acceptJmaLpgm(_bulletin(now, serial: 1, maxLgInt: 2));
    expect(provider.unifiedEvents, hasLength(1));
    expect(provider.unifiedEvents.single.isJmaLpgm, isTrue);
    expect(provider.unifiedEvents.single.jmaLpgmBulletin?.serial, 1);
    expect(
      UnifiedEventPresentation.fromEvent(
        provider.unifiedEvents.single,
      ).intensityValue,
      '长周期',
    );

    provider.acceptJmaLpgm(_bulletin(now, serial: 2, maxLgInt: 4));
    expect(provider.unifiedEvents, hasLength(1));
    expect(provider.unifiedEvents.single.jmaLpgmBulletin?.serial, 2);
    expect(provider.unifiedEvents.single.jmaLpgmBulletin?.maxLgInt, 4);

    provider.clearJmaLpgm('lpgm-test-event');
    expect(provider.unifiedEvents, isEmpty);
  });
}

JmaLpgmBulletin _bulletin(
  DateTime now, {
  required int serial,
  required int maxLgInt,
}) {
  return JmaLpgmBulletin(
    eventId: 'lpgm-test-event',
    serial: serial,
    infoType: '发表',
    headline: '长周期地震动に関する観測情報',
    maxInt: '4',
    maxLgInt: maxLgInt,
    lgCategory: '1',
    originTime: now.subtract(const Duration(minutes: 5)),
    reportTime: now,
    hypocenter: '测试海域',
    latitude: 35,
    longitude: 140,
    depthKm: 20,
    magnitude: 6.2,
    regions: [JmaLpgmRegion(name: '千葉県南部', code: '342', maxLgInt: maxLgInt)],
  );
}
