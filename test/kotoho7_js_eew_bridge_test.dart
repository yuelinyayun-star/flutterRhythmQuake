import 'package:flutter_test/flutter_test.dart';

import 'package:flutterrhythmquake/core/source_estimation/kotoho7_js_eew_bridge.dart';

void main() {
  test('Dart bridge calls JS circle trigger reference', () {
    final slots = List<Object?>.filled(140, 0);
    slots[0] = 1; // 0EEW +1 active
    slots[7] = 40; // 0EEW +8 depth
    slots[8] = '5.6'; // 0EEW +9 magnitude
    slots[11] = 500; // 0EEW +12 outer radius
    slots[12] = 220; // 0EEW +13 inner/reference radius

    final activeFlags = List<Object?>.filled(10, 0);
    activeFlags[0] = 1;

    final extra = List<Object?>.filled(140, '');
    extra[2] = 0.2; // 0-2EEW追加情報 +3

    final result = Kotoho7JsEewBridge.circleTrigger(
      Kotoho7JsCircleTriggerInput(
        metadata: {
          'kotoho7_eew_slots': slots,
          'kotoho7_eew_active_flags': activeFlags,
          'kotoho7_eew_extra_info': extra,
          'kotoho7_eew_global_active': 1,
        },
        stationIndex1: 123,
        currentState: 3,
        threshold: 3,
        pointCount: 1,
        shindo: 0,
        triggerAgeSeconds: 3,
        stationDistances: const [
          {'stationIndex1': 123, 'slotIndex1': 1, 'distanceKm': 230},
        ],
      ),
    );

    expect(result.available, isTrue);
    expect(result.ok, isTrue);
    expect(result.promoted, isTrue);
    expect(result.result['reason'], '円の中トリガ');
  });
}
