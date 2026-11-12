import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sources/usgs_shakemap_service.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/models/cenc_ir_data.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'usgs_shakemap_test.dart'
    show detailVersion, eventFor, settle, contourResponse, readJson;

// These are already accepted display rows projected from unchanged captures.
// Do not rewrite historic source clocks to bypass realtime admission in UI tests.
class _DisplayProvider extends QuakeProvider {
  _DisplayProvider(UsgsShakeMapService superService, this.cards)
    : super(shakeMapService: superService, startCatalogServices: false);
  List<UnifiedQuakeData> cards;
  UnifiedQuakeData? _cameraOwner;
  @override
  List<UnifiedQuakeData> get unifiedEvents => List.unmodifiable(cards);
  @override
  UnifiedQuakeData? get mobileCameraDisplayEvent =>
      _cameraOwner ?? cards.firstOrNull;
  void focusCameraOn(UnifiedQuakeData event) {
    _cameraOwner = event;
    notifyListeners();
  }

  void acceptDisplayRows(List<UnifiedQuakeData> rows) {
    cards = rows;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
  });
  tearDown(() => SoundEffectService().enabled = true);

  test(
    'product updates join information carousel without earthquake notifications',
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
      expect(provider.unifiedEvents.single.source, 'usgsShakeMap');
      expect(provider.unifiedDisplayEvents.single.eventId, 'us6000u0xi');
      expect(provider.unifiedDisplayEvents.single.source, 'usgsShakeMap');
      expect(provider.unifiedDisplayEvents.single.reportNumText, '第3版');
      expect(provider.unifiedDisplayEvents.single.maxIntensity, '7.654');
      expect(provider.historyInfoDisplayEvent, isNull);
      final presentation = UnifiedEventPresentation.fromEvent(
        provider.unifiedDisplayEvents.single,
      );
      expect(presentation.title, 'USGS ShakeMap 烈度速报 第3版');
      expect(presentation.intensityLabel, 'MMI');
      expect(provider.unifiedDisplayEvents.single.isHistory, isTrue);
      expect(alerts, 0);
      provider.selectHistoryMapProducts(eventFor(detail));
      await settle();
      expect(service.frame?.event.eventId, 'us6000u0xi');
      expect(provider.unifiedDisplayEvents.map((e) => e.source), [
        'usgsEqlist',
        'usgsShakeMap',
      ]);
      expect(alerts, 0);
    },
  );

  test(
    'manual selection of another agency does not mask automatic products',
    () async {
      var detail = detailVersion('1');
      final service = UsgsShakeMapService(
        client: MockClient(
          (request) async => request.url.path.endsWith('/cont_mmi.json')
              ? contourResponse(request.url)
              : http.Response(jsonEncode(detail), 200),
        ),
      );
      final provider = QuakeProvider(
        shakeMapService: service,
        startCatalogServices: false,
      );
      addTearDown(provider.dispose);
      await service.observe([eventFor(detail)]);
      final raw =
          jsonDecode(
                File(
                  'test/fixtures/cenc_ir_mojiang_20260914170727.json',
                ).readAsStringSync(encoding: utf8),
              )
              as Map<String, dynamic>;
      final cenc = QuakeMessage(
        source: QuakeSourceType.cenc,
        eventId: raw['eq_id'],
        location: raw['hypocenter'],
        magnitude: (raw['magnitude'] as num).toDouble(),
        latitude: (raw['latitude'] as num).toDouble(),
        longitude: (raw['longitude'] as num).toDouble(),
        depth: (raw['depth'] as num).toDouble(),
        originTime: DateTime.parse(raw['happen_time']),
        timeZone: 8,
      );
      provider.selectHistoryMapProducts(cenc);
      detail = detailVersion('3');
      await service.observe([eventFor(detail)]);
      expect(
        service.frame,
        isNull,
      ); // The manual map remains the CENC selection.
      expect(service.automaticFrame?.product.version, '3');
      expect(provider.unifiedDisplayEvents.map((e) => e.source), [
        'cencEqlist',
        'usgsShakeMap',
      ]);
      expect(provider.historyInfoDisplayEvent?.rawEvent, same(cenc));
      service.setMagnitudeFilter(-1);
      expect(provider.shakeMapInfoDisplayEvent, isNull);
      expect(provider.unifiedDisplayEvents.single.rawEvent, same(cenc));
    },
  );

  test(
    'automatic product expiry keeps the selected row and newer USGS card',
    () {
      fakeAsync((clock) {
        var detail = detailVersion('1');
        final oldRow = eventFor(detail);
        final nextCard = QuakeEventAdapter.catalogInfo(
          eventFor(readJson('ci41345415.detail.original.geojson')),
          'usgsEqlist',
        );
        final service = UsgsShakeMapService(
          client: MockClient(
            (request) async => request.url.path.endsWith('/cont_mmi.json')
                ? contourResponse(request.url)
                : http.Response(jsonEncode(detail), 200),
          ),
        );
        final provider = _DisplayProvider(service, [nextCard]);
        unawaited(service.observe([oldRow]));
        clock.flushMicrotasks();
        detail = detailVersion('3');
        unawaited(service.observe([eventFor(detail)]));
        clock.flushMicrotasks();
        provider.selectHistoryMapProducts(oldRow);
        clock.flushMicrotasks();
        expect(provider.unifiedDisplayEvents, hasLength(3));
        clock.elapse(const Duration(minutes: 2));
        clock.flushMicrotasks();
        expect(provider.shakeMapInfoDisplayEvent, isNull);
        expect(
          service.frame,
          isNotNull,
        ); // User's manual layer remains selected.
        expect(provider.historyInfoDisplayEvent?.rawEvent, same(oldRow));
        expect(provider.unifiedDisplayEvents, hasLength(2));
        expect(provider.unifiedEvents.single, same(nextCard));
        provider.dispose();
        clock.flushMicrotasks();
      });
    },
  );

  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    for (final manual in [false, true]) {
      testWidgets(
        'USGS arrival stays visible beside ShakeMap, manual=$manual at $size',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var detail = detailVersion('1');
          final oldRow = eventFor(detail);
          final original = jsonEncode(oldRow.toMap());
          final newerRow = eventFor(
            readJson('ci41345415.detail.original.geojson'),
          );
          final nextCard = QuakeEventAdapter.catalogInfo(
            newerRow,
            'usgsEqlist',
          );
          final provider = (await tester.runAsync(() async {
            final service = UsgsShakeMapService(
              client: MockClient(
                (request) async => request.url.path.endsWith('/cont_mmi.json')
                    ? contourResponse(request.url)
                    : http.Response(jsonEncode(detail), 200),
              ),
            );
            final result = _DisplayProvider(service, [
              QuakeEventAdapter.catalogInfo(oldRow, 'usgsEqlist'),
            ]);
            await service.observe([oldRow]);
            detail = detailVersion('3');
            await service.observe([eventFor(detail)]);
            if (manual) {
              result.selectHistoryMapProducts(oldRow);
              await settle();
            }
            return result;
          }))!;
          final map = MapStateProvider();
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<QuakeProvider>.value(value: provider),
                ChangeNotifierProvider<MapStateProvider>.value(value: map),
              ],
              child: const MaterialApp(
                home: Scaffold(
                  body: SingleChildScrollView(child: AlertModule()),
                ),
              ),
            ),
          );
          expect(provider.unifiedDisplayEvents, hasLength(2));
          // A distinct USGS row arrives while the older product is still active.
          provider.acceptDisplayRows([nextCard]);
          await tester.pump();
          expect(provider.unifiedEvents.single, same(nextCard));
          expect(
            provider.unifiedDisplayEvents.map((e) => e.source),
            manual
                ? ['usgsEqlist', 'usgsEqlist', 'usgsShakeMap']
                : ['usgsEqlist', 'usgsShakeMap'],
          );
          final nextKey = find.byKey(
            ValueKey(
              'unified_card_${nextCard.source}_${nextCard.eventId}_${nextCard.reportNumText}',
            ),
          );
          final productKey = find.byKey(
            const ValueKey('unified_card_usgsShakeMap_us6000u0xi_第3版'),
          );
          if (size.shortestSide < 600) {
            if (manual) {
              await tester.pump(const Duration(seconds: 5));
            }
            expect(nextKey, findsOneWidget);
            await tester.pump(const Duration(seconds: 5));
            if (!manual) {
              // This fixture has no QuakeMapView. Submit the same next owner
              // as the real map carousel instead of freezing it on cards.first.
              expect(nextKey, findsOneWidget);
              provider.focusCameraOn(provider.shakeMapInfoDisplayEvent!);
              await tester.pump();
            }
            expect(productKey, findsOneWidget);
            expect(find.text('MMI'), findsOneWidget);
          } else {
            expect(nextKey, findsOneWidget);
            expect(productKey, findsOneWidget);
          }
          expect(provider.unifiedEvents.single, same(nextCard));
          expect(jsonEncode(oldRow.toMap()), original);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          provider.dispose();
          map.dispose();
        },
      );
    }
  }

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
