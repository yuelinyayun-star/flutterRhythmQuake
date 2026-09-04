import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/widgets/map/quake_map_view.dart';

void main() {
  test('same JMA event ID uses distinct EEW and information layer keys', () {
    final eewKey = unifiedMapLayerKey(
      source: QuakeSourceType.jma_fan,
      eventId: '20260811075957',
      isEew: true,
      index: 0,
    );
    final infoKey = unifiedMapLayerKey(
      source: QuakeSourceType.jma_fan,
      eventId: '20260811075957',
      isEew: false,
      index: 1,
    );

    expect(eewKey, 'jma_fan_eew_20260811075957');
    expect(infoKey, 'jma_fan_info_20260811075957');
    expect(eewKey, isNot(infoKey));
  });

  test('non-empty event ID keeps its layer key when list index changes', () {
    final first = unifiedMapLayerKey(
      source: QuakeSourceType.jma_fan,
      eventId: '20260811075957',
      isEew: true,
      index: 0,
    );
    final updated = unifiedMapLayerKey(
      source: QuakeSourceType.jma_fan,
      eventId: '20260811075957',
      isEew: true,
      index: 4,
    );

    expect(updated, first);
  });

  testWidgets('same-ID JMA EEW and information layers coexist in a Stack', (
    tester,
  ) async {
    final eewKey = unifiedMapLayerKey(
      source: QuakeSourceType.jma_fan,
      eventId: '20260811075957',
      isEew: true,
      index: 0,
    );
    final infoKey = unifiedMapLayerKey(
      source: QuakeSourceType.jma_fan,
      eventId: '20260811075957',
      isEew: false,
      index: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            SizedBox(key: ValueKey('unified_$eewKey')),
            SizedBox(key: ValueKey('unified_$infoKey')),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(SizedBox), findsNWidgets(2));
  });
}
