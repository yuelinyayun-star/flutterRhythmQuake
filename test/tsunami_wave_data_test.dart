import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/models/tsunami_message.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/native_jma_tsunami.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:flutterrhythmquake/services/sources/noaa_tsunami_area_service.dart';
import 'package:flutterrhythmquake/services/sources/incois_tsunami_detail_service.dart';
import 'package:flutterrhythmquake/services/sources/whews_service.dart';

const noaaUrl =
    'https://www.tsunami.gov/events/PAAQ/2025/09/18/t2ssp5/1/WEAK51/PAAQ.json';
final noaaBytes = File(
  'test/fixtures/noaa_ntwc_advisory_20250918.json',
).readAsBytesSync();
// Transport envelopes for the stored official response; not live warnings.
Map<String, dynamic> frame({bool cancelled = false}) => {
  'source': 'ntwc',
  'md5': cancelled ? 'protocol-cancellation' : 'protocol-warning',
  'Data': <String, dynamic>{
    'id': 'protocol-noaa',
    'level': cancelled ? 'Cancellation' : 'Advisory',
    'issueTime': cancelled ? '2025-09-18 19:08:03' : '2025-09-18 19:07:03',
    'jsonUrl': noaaUrl,
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
    TtsService().eventEnabled = false;
  });
  tearDown(() => SoundEffectService().enabled = true);

  test(
    'INCOIS original public bulletin is retained without invented observations',
    () async {
      final bytes = File(
        'test/fixtures/tsunami_regions/incois_20260820_B1.original.json',
      ).readAsBytesSync();
      final client = MockClient((_) async => http.Response.bytes(bytes, 200));
      addTearDown(client.close);
      final raw = await IncoisTsunamiDetailService(client: client).fetch(
        'https://tsunami.incois.gov.in/itews/DSSProducts/OPR/incois2026qmbb/NTWC/B1/incois2026qmbb_B1_NTWC_Pub.json',
      );
      expect(raw!['documents'], jsonDecode(utf8.decode(bytes)));
      final frames =
          jsonDecode(
                File(
                  'test/fixtures/catalog_20260917/whews_all.json',
                ).readAsStringSync(),
              )
              as List;
      final frame = frames.cast<Map>().singleWhere(
        (row) => row['source'] == 'incois',
      );
      final message = TsunamiMessage.parseInternationalTsunami(
        TsunamiSource.incois,
        Map<String, dynamic>.from(frame['Data'] as Map),
      ).copyWith(officialDetail: raw).prepareWaveData();
      expect(message.waveData['stations'], isEmpty);
      expect(message.waveData['warningActive'], isFalse);
      expect(message.sourcePayload, frame['Data']);
    },
    skip: !NativeJmaTsunami.supported,
  );

  test(
    'official detail survives fetch, WHEWS, provider and serialization',
    () async {
      final client = MockClient(
        (_) async => http.Response.bytes(noaaBytes, 200),
      );
      addTearDown(client.close);
      final service = WhewsService(
        apiToken: '',
        noaaTsunamiAreaService: NoaaTsunamiAreaService(client: client),
      );
      final provider = QuakeProvider();
      addTearDown(service.dispose);
      addTearDown(provider.dispose);
      final complete = Completer<void>();
      final subscription = service.onTsunamiEvent.listen((message) {
        provider.handleTsunamiEventForTest(message);
        if (message.officialDetail.isNotEmpty && !complete.isCompleted) {
          complete.complete();
        }
      });
      addTearDown(subscription.cancel);
      service.handleMessageForTesting(frame());
      await complete.future.timeout(const Duration(seconds: 15));
      final message = provider.ntwcTsunami!;
      expect(message.sourcePayload, frame()['Data']);
      expect(message.officialDetail, jsonDecode(utf8.decode(noaaBytes)));
      final stations = message.waveData['stations'] as List;
      expect(stations, hasLength(295));
      expect(stations.every((row) => row['observed'] == null), isTrue);
      expect(stations[1]['forecast']['unit'], 'feet');
      expect(stations[1]['binding'], 'sourceSegment');
      final restored = TsunamiMessage.fromMap(
        jsonDecode(jsonEncode(message.toMap())) as Map,
      );
      expect(restored.waveData, message.waveData);
      expect(restored.officialDetail, message.officialDetail);
    },
    skip: !NativeJmaTsunami.supported,
  );

  test('pending official fetch cannot emit after a cancellation', () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final client = MockClient((_) {
      started.complete();
      return response.future;
    });
    addTearDown(client.close);
    final service = WhewsService(
      apiToken: '',
      noaaTsunamiAreaService: NoaaTsunamiAreaService(client: client),
    );
    addTearDown(service.dispose);
    final messages = <TsunamiMessage>[];
    final subscription = service.onTsunamiEvent.listen(messages.add);
    addTearDown(subscription.cancel);
    service.handleMessageForTesting(frame());
    await started.future;
    service.handleMessageForTesting(frame(cancelled: true));
    response.complete(http.Response.bytes(noaaBytes, 200));
    // Await completion of the native detail parse as well as stream delivery.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(messages, hasLength(2));
    expect(messages.last.isCancellation, isTrue);
    expect(messages.every((message) => message.officialDetail.isEmpty), isTrue);
  });

  test(
    'same-report station enrichment is retained without changing warning state',
    () {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      final warning = TsunamiMessage.parseInternationalTsunami(
        TsunamiSource.ntwc,
        Map<String, dynamic>.from(frame()['Data'] as Map),
      );
      provider.handleTsunamiEventForTest(warning);
      final enriched = warning.copyWith(
        officialDetail: Map<String, dynamic>.from(
          jsonDecode(utf8.decode(noaaBytes)) as Map,
        ),
      );
      provider.handleTsunamiEventForTest(enriched);
      expect(provider.ntwcTsunami!.officialDetail, enriched.officialDetail);
      expect(provider.ntwcTsunami!.grade, warning.grade);
      var notifications = 0;
      provider.addListener(() => notifications++);
      provider.handleTsunamiEventForTest(enriched);
      expect(notifications, 0);
      final cancelled = warning.copyWith(
        grade: TsunamiGrade.none,
        bulletinLevel: 'cancellation',
      );
      provider.handleTsunamiEventForTest(cancelled);
      provider.handleTsunamiEventForTest(enriched);
      expect(provider.ntwcTsunami!.isCancellation, isTrue);
      expect(provider.ntwcTsunami!.waveData['warningActive'], isFalse);
    },
    skip: !NativeJmaTsunami.supported,
  );

  test(
    'NOAA detail fetch still happens when relay already has warning areas',
    () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response.bytes(noaaBytes, 200);
      });
      addTearDown(client.close);
      final service = WhewsService(
        apiToken: '',
        noaaTsunamiAreaService: NoaaTsunamiAreaService(client: client),
      );
      addTearDown(service.dispose);
      final complete = Completer<void>();
      final subscription = service.onTsunamiEvent.listen((message) {
        if (message.officialDetail.isNotEmpty && !complete.isCompleted) {
          complete.complete();
        }
      });
      addTearDown(subscription.cancel);
      final input = frame();
      (input['Data'] as Map)['warningAreas'] = [
        {'areaName': 'protocol coast', 'waveHeight': '1m'},
      ];
      service.handleMessageForTesting(input);
      await complete.future.timeout(const Duration(seconds: 15));
      expect(requests, 1);
    },
  );
}
