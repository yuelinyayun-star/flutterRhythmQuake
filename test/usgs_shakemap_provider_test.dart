import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sources/usgs_shakemap_service.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/models/cenc_ir_data.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'usgs_shakemap_test.dart'
    show detailVersion, eventFor, settle, contourResponse;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
  });
  tearDown(() => SoundEffectService().enabled = true);

  test(
    'product updates redisplay bound info without live events or notifications',
    () async {
      var detail = detailVersion('1');
      final service = UsgsShakeMapService(
        client: MockClient(
          (request) async => request.url.path.endsWith('/cont_mmi.json')
              ? contourResponse(request.url)
              : http.Response(jsonEncode(detail), 200),
        ),
      );
      final provider = QuakeProvider(shakeMapService: service);
      addTearDown(provider.dispose);
      var alerts = 0;
      provider.onUnifiedEventNotified = (_, _) => alerts++;
      await service.observe([eventFor(detail)]);
      await settle();
      expect(provider.unifiedDisplayEvents, isEmpty);
      detail = detailVersion('3');
      await service.observe([eventFor(detail)]);
      await settle();
      expect(service.frame?.product.version, '3');
      expect(provider.unifiedEvents, isEmpty);
      expect(provider.unifiedDisplayEvents.single.eventId, 'us6000u0xi');
      expect(provider.unifiedDisplayEvents.single.isHistory, isTrue);
      expect(alerts, 0);
      provider.selectHistoryMapProducts(eventFor(detail));
      await settle();
      expect(service.frame?.event.eventId, 'us6000u0xi');
      expect(provider.unifiedDisplayEvents, hasLength(1));
      expect(alerts, 0);
    },
  );

  test(
    'selected CENC history cannot display another earthquake intensity report',
    () {
      Map<String, dynamic> raw(String file) =>
          jsonDecode(File('test/fixtures/$file').readAsStringSync());
      final matchingRaw = raw('cenc_ir_mojiang_20260914170727.json');
      final matching = CencIrData.fromNowQuakeJson(matchingRaw);
      final other = CencIrData.fromNowQuakeJson(
        raw('cenc_ir_qiaojia_20260908013139.json'),
      );
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      final event = QuakeMessage(
        source: QuakeSourceType.cenc,
        eventId: matchingRaw['eq_id'],
        location: matchingRaw['hypocenter'],
        magnitude: (matchingRaw['magnitude'] as num).toDouble(),
        latitude: matching.epiLat,
        longitude: matching.epiLon,
        depth: matching.focDepth,
        originTime: DateTime.parse(matchingRaw['happen_time']),
        timeZone: 8,
      );
      provider.updateRealtimeCencIrDataForTest(other);
      provider.selectHistoryMapProducts(event);
      expect(provider.cencIrData, isNull);
      provider.updateManualCencIrDataForTest(matching);
      expect(provider.cencIrData?.reportId, matching.reportId);
      provider.selectHistoryMapProducts(
        event.copyWith(latitude: event.latitude + 1),
      );
      expect(provider.cencIrData, isNull);
    },
  );

  test('saved USGS filter and setting changes control ShakeMap', () async {
    SharedPreferences.setMockInitialValues({'source_mag_filter_usgs': 7.0});
    var detail = detailVersion('1');
    var requests = 0;
    final service = UsgsShakeMapService(
      client: MockClient((request) async {
        requests++;
        return request.url.path.endsWith('/cont_mmi.json')
            ? contourResponse(request.url)
            : http.Response(jsonEncode(detail), 200);
      }),
    );
    final provider = QuakeProvider(shakeMapService: service);
    addTearDown(provider.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(provider.sourceInfoMagFilters[QuakeSourceType.usgs], 7);
    await service.observe([eventFor(detail)]);
    detail = detailVersion('3');
    await service.observe([eventFor(detail)]);
    expect(service.frame, isNull);
    expect(requests, 0);
    provider.selectHistoryMapProducts(eventFor(detail));
    await settle();
    expect(service.frame, isNull);
    expect(requests, 0);
    final loaded = Completer<void>();
    service.addListener(() {
      if (service.frame != null && !loaded.isCompleted) loaded.complete();
    });
    provider.setSourceInfoMagFilter(QuakeSourceType.usgs, 0);
    await loaded.future.timeout(const Duration(seconds: 5));
    expect(service.frame?.event.eventId, 'us6000u0xi');
    provider.setSourceInfoMagFilter(QuakeSourceType.usgs, -1);
    expect(service.frame, isNull);
    expect(service.status, isNull);
    expect(provider.unifiedEvents, isEmpty);
  });
}
