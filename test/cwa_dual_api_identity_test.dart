import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/background_event_processor.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/fan_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final jianFirst in [false, true]) {
    test(
      'CWA Jian/FAN identity survives revised origin and coordinates; Jian first=$jianFirst',
      () {
        SharedPreferences.setMockInitialValues({});
        // Explicit protocol boundary inputs, not claimed historical captures.
        final origin = DateTime.now().toUtc();
        final wall = origin.add(const Duration(hours: 8));
        final fanRaw = <String, dynamic>{
          'id': 'CWA-identity-contract',
          'updates': 1,
          'shockTime': wall.toIso8601String(),
          'magnitude': 4.5,
          'depth': 40,
          'latitude': 23.61,
          'longitude': 121.33,
          'placeName': 'contract first',
        };
        final jianRaw = <String, dynamic>{
          'id': 'CWA-identity-contract',
          'number': 3,
          'originTime': origin
              .subtract(const Duration(seconds: 1))
              .millisecondsSinceEpoch,
          'magnitude': 4.6,
          'depth': 30,
          'latitude': 23.54,
          'longitude': 121.59,
          'placeName': 'contract revision',
        };
        final before = jsonEncode([fanRaw, jianRaw]);
        final fan = FanService.decodeEventPayload(
          fanRaw,
          sourceHint: 'cwa_eew',
        )!;
        final jian = QuakeEventAdapter.convertJian('cwa-eew', jianRaw)!;
        expect(fan.eventId, jian.eventId);
        final provider = QuakeProvider(startCatalogServices: false);
        addTearDown(provider.dispose);
        final background = BackgroundEventProcessor(sourceInfoMagFilters: {});
        for (final event
            in jianFirst ? [jian, fan, jian, fan] : [fan, jian, fan, jian]) {
          provider.handleUnifiedEventForTest(event);
          background.process(event);
        }
        expect(provider.unifiedEvents, hasLength(1));
        expect(provider.unifiedEvents.single.reportNumText, '第3報');
        expect(provider.unifiedEvents.single.apiTypeLabel, 'Jian Project');
        expect(provider.eewHistory, hasLength(1));
        expect(provider.eewHistory.single.latest.magnitude, 4.6);
        expect(provider.eewHistory.single.reportCount, jianFirst ? 1 : 2);
        expect(background.process(fan).type, BackgroundEventResultType.dropped);
        expect(jsonEncode([fanRaw, jianRaw]), before);
      },
    );
  }
}
