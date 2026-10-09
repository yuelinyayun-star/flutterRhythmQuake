import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/core/utils/quake_time.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/tsunami_message.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/background_event_processor.dart';
import 'package:flutterrhythmquake/services/debug/local_inject_decoder.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/whews_service.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:flutterrhythmquake/widgets/map/international_tsunami_layer.dart';
import 'package:flutterrhythmquake/widgets/map/nmefc_tsunami_layer.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync(encoding: utf8))
        as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final funvisis = fixture('funvisis_documented_20261008.json');
  final cwa = fixture('cwa_tsunami_documented_20261008.json');
  final cat = fixture('cat_tsunami_captured_20260917.json');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
    TtsService().eventEnabled = false;
  });
  tearDown(() => SoundEffectService().enabled = true);

  test(
    'unchanged FUNVISIS example uses existing catalog UI and filters',
    () async {
      final raw = Map<String, dynamic>.from(funvisis['Data'] as Map);
      final original = jsonEncode(raw);
      final event = QuakeEventAdapter.convertWhews('funvisis', raw)!;
      expect(jsonEncode(raw), original);
      expect(event.sourcePayload, raw);
      expect(event.source, 'whews_funvisis');
      expect(event.isEew, isFalse);
      expect(event.apiTypeLabel, 'WHEWS');
      expect(event.reportNumText, isEmpty); // Mw is a magnitude type.
      expect(event.timeZone, 8);
      expect(event.originTime, DateTime(2026, 10, 1, 11, 45));
      expect(
        QuakeTime.unifiedInstantUtc(event),
        DateTime.utc(2026, 10, 1, 3, 45),
      );
      expect(event.hypocenter, matches(RegExp(r'[\u4e00-\u9fff]')));
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      expect(
        provider.unifiedSourceTypeForTest(event),
        QuakeSourceType.funvisis,
      );
      expect(
        QuakeProvider.infoMagFilterSources,
        contains(QuakeSourceType.funvisis),
      );
      provider.handleUnifiedEventForTest(event);
      expect(
        provider.unifiedEvents,
        isEmpty,
      ); // Old example is never made live.
      expect(
        provider.historyBySource['whews_funvisis']!.single.eventId,
        raw['id'],
      );
      expect(
        BackgroundEventProcessor(sourceInfoMagFilters: {}).process(event).type,
        BackgroundEventResultType.dropped,
      );
      provider.setSourceInfoMagFilter(QuakeSourceType.funvisis, -1);
      expect(
        provider.historyList.where((e) => e.source == QuakeSourceType.funvisis),
        isEmpty,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    },
  );

  test(
    'original CWA fields, raw placeholders, UTC+8 and background round trip',
    () {
      final raw = Map<String, dynamic>.from(cwa['Data'] as Map);
      final original = jsonEncode(raw);
      final event = TsunamiMessage.parseInternationalTsunami(
        TsunamiSource.cwa,
        raw,
      );
      expect(jsonEncode(raw), original);
      expect(event.sourcePayload, raw);
      expect(event.eventId, '115005');
      expect(event.id, '115005-2');
      expect(event.reportNumber, 2);
      expect(event.isInformation, isTrue);
      expect(event.isCancellation, isFalse);
      expect(event.htmlUrl, isEmpty);
      expect(event.reportInstantUtc, DateTime.utc(2026, 7, 28, 8, 28));
      expect(
        event.informationDisplayUntilUtc,
        DateTime.utc(2026, 7, 28, 16, 28),
      );
      expect(event.isDisplayableAt(event.reportInstantUtc!), isTrue);
      expect(event.isDisplayableAt(event.displayUntilUtc!), isFalse);
      expect(event.areas.single.description, '...；波高：...');
      expect(event.areas.single.height, isNull);
      expect(event.observations.single.stationId, '...');
      expect(event.observations.single.latitude, 23.5);
      expect(event.observations.single.maxWaveHeightMeters, isNull);
      expect(event.observations.single.condition, '...');
      final saved = TsunamiMessage.fromMap(
        jsonDecode(jsonEncode(event.toMap())) as Map,
      );
      expect(saved.toMap(), event.toMap());
      final local = event.reportInstantUtc!.toLocal();
      expect(
        event.formatLocalTime(event.reportTime),
        '${QuakeTime.formatWallClock(local)} (${QuakeTime.formatTimeZone(local.timeZoneOffset)})',
      );
    },
  );

  test(
    'saved CAT capture retains actual bulletin URL and information state',
    () {
      final raw = Map<String, dynamic>.from(cat['Data'] as Map);
      final original = jsonEncode(raw);
      final event = TsunamiMessage.parseInternationalTsunami(
        TsunamiSource.cat,
        raw,
      );
      expect(jsonEncode(raw), original);
      expect(event.sourcePayload, raw);
      expect(event.isInformation, isTrue);
      expect(event.isCancellation, isFalse);
      expect(event.reportNumber, 1);
      expect(event.htmlUrl, raw['bulletinUrl']);
      expect(event.reportInstantUtc, DateTime.utc(2026, 9, 14, 21, 18, 9));
      expect(TsunamiMessage.fromMap(event.toMap()).sourcePayload, raw);
    },
  );

  test(
    'aggregate and local decoder route both tsunami sources away from quake UI',
    () async {
      final service = WhewsService(apiToken: 'test-token');
      addTearDown(service.dispose);
      final tsunamis = <TsunamiMessage>[];
      final quakes = <UnifiedQuakeData>[];
      final s1 = service.onTsunamiEvent.listen(tsunamis.add);
      final s2 = service.onUnifiedEvent.listen(quakes.add);
      addTearDown(s1.cancel);
      addTearDown(s2.cancel);
      service.handleMessageForTesting([cat, cwa, funvisis]);
      service.handleMessageForTesting(cat);
      service.handleMessageForTesting(cwa);
      await Future<void>.delayed(Duration.zero);
      expect(tsunamis.map((e) => e.source).toSet(), {
        TsunamiSource.cat,
        TsunamiSource.cwa,
      });
      expect(tsunamis.every((e) => e.isInitialSnapshot), isTrue);
      expect(quakes.single.source, 'whews_funvisis');
      final decoded = LocalInjectDecoder.decode([cat, cwa], format: 'whews');
      expect(decoded.events, isEmpty);
      expect(decoded.tsunamis, hasLength(2));
    },
  );

  test('actual CWA Information does not become cancellation from quoted text', () {
    final raw = fixture('cwa_tsunami_captured_20261008.raw.json');
    final original = jsonEncode(raw);
    final event = TsunamiMessage.parseInternationalTsunami(TsunamiSource.cwa, raw);
    expect(event.titleText, contains('解除'));
    expect(event.isInformation, isTrue);
    expect(event.isCancellation, isFalse);
    expect(event.sourcePayload, raw);
    expect(jsonEncode(raw), original);
    expect(event.isDisplayableAt(DateTime.now()), isFalse);
  });

  // Explicit application-model scenarios, never edited or retimed source JSON.
  for (final source in [TsunamiSource.cat, TsunamiSource.cwa]) {
    test('$source lower report cannot revive a cancelled newer report', () {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      final old = TsunamiMessage(
        source: source,
        id: 'model-report-1',
        eventId: 'model-event',
        reportNumber: 1,
        timeZone: 8,
        reportTime: '2026-10-08 12:01:00',
        bulletinLevel: 'Warning',
        grade: TsunamiGrade.warning,
      );
      final cancel = TsunamiMessage(
        source: source,
        id: 'model-report-2',
        eventId: 'model-event',
        reportNumber: 2,
        timeZone: 8,
        reportTime: '2026-10-08 12:00:00',
        bulletinLevel: 'Cancellation',
      );
      provider.handleTsunamiEventForTest(old);
      provider.handleTsunamiEventForTest(cancel);
      provider.handleTsunamiEventForTest(old);
      final current = provider.additionalTsunamis.single;
      expect(current.reportNumber, 2);
      expect(current.id, 'model-report-2');
      expect(current.isCancellation, isTrue);
      expect(current.isDisplayableAt(DateTime.now()), isFalse);
    });
  }

  testWidgets(
    'CWA station reuses observation marker and invalid positions are skipped',
    (tester) async {
      const event = TsunamiMessage(
        source: TsunamiSource.cwa,
        grade: TsunamiGrade.warning,
        observations: [
          TsunamiObservationInfo(
            stationName: 'model-station',
            stationId: 'model-id',
            location: '',
            latitude: 23.5,
            longitude: 121,
            maxWaveHeight: '未知',
          ),
          TsunamiObservationInfo(
            stationName: 'invalid-model-station',
            location: '',
            latitude: double.nan,
            longitude: double.nan,
          ),
        ],
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(23.5, 121),
                initialZoom: 5,
              ),
              children: [InternationalTsunamiLayer(tsunami: event)],
            ),
          ),
        ),
      );
      expect(find.byType(MarkerLayer), findsOneWidget);
      expect(find.byType(TsunamiObservationMarker), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
