import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/models/jma_tsunami_list.dart';
import 'package:flutterrhythmquake/models/tsunami_message.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/native_jma_tsunami.dart';
import 'package:flutterrhythmquake/services/debug/local_inject_decoder.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:flutterrhythmquake/services/sources/whews_service.dart';
import 'package:flutterrhythmquake/widgets/ui/jma_tsunami_list_card.dart';

const fixtureRoot = 'test/fixtures/jma_tsunami';
Map<String, dynamic> documentedObservations() =>
    jsonDecode(
          '{${File('$fixtureRoot/whews.observations.documented.fragment.txt').readAsStringSync()}}',
        )
        as Map<String, dynamic>;
// Protocol ordering cases, not live events. Documented station values stay intact.
Map<String, dynamic> protocol(String telegram, int number, String time) => {
  'id': '20260811050000',
  'telegramType': telegram,
  'updates': number,
  'createTime': time,
  'infoTypeName': '発表',
  'title': telegram == 'VTSE51' ? '津波情報' : '津波警報',
  if (telegram == 'VTSE51')
    ...documentedObservations()
  else
    'areas': [
      {'name': '岩手県', 'kind': '津波警報', 'maxHeight': '3'},
    ],
};
List<JmaTsunamiListGroup> project(TsunamiMessage message) => [
  for (final row
      in NativeJmaTsunami.prepare({
            'op': 'project',
            'message': message.toMap(),
            'nowMs': 0,
          })['groups']
          as List)
    JmaTsunamiListGroup.fromMap(row as Map),
];
Future<void> layout(WidgetTester tester, String grade) async {
  final finder = find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith(
          'jma_tsunami_cell_${grade}_',
        ),
  );
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
    if (tester.takeException() case final Object error) throw error;
  }
  fail('Native observation layout did not complete');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
    TtsService().eventEnabled = false;
  });
  tearDown(() => SoundEffectService().enabled = true);
  if (!NativeJmaTsunami.supported) {
    test(
      'requires explicit native DLL',
      () {},
      skip: 'Set RQ_STATION_CORE_LIBRARY',
    );
    return;
  }
  test(
    'Mock WHEWS forecast and observation use the live native parser and keep both displays',
    () async {
      final provider = QuakeProvider(
        startCatalogServices: false,
        nativeUnifiedEvents: false,
      );
      addTearDown(provider.dispose);
      final frames = [
        for (final telegram in ['VTSE41', 'VTSE51'])
          {
            'source': 'jma_tsunami',
            'Data': protocol(telegram, 1, '2026-08-11 05:30:00'),
          },
      ];
      final original = jsonEncode(frames);
      final decoded = LocalInjectDecoder.decode(frames, format: 'whews');
      expect(decoded.tsunamis, hasLength(2));
      for (var i = 0; i < 2; i++) {
        final live = await TsunamiMessage.parseJmaSourceAsync(
          'whews',
          Map<String, dynamic>.from(frames[i]['Data'] as Map),
        );
        expect(decoded.tsunamis[i].toMap(), live.toMap());
        provider.handleTsunamiEventForTest(decoded.tsunamis[i]);
      }
      await provider.jmaTsunamiListReadyForTest;
      expect(provider.jmaTsunami!.grade, TsunamiGrade.warning);
      expect(provider.jmaTsunamiListenable.value.map((group) => group.grade), [
        'warning',
        'observation',
      ]);
      expect(
        provider.jmaTsunamiListenable.value.last.rows.single.name,
        '岩手山田沖',
      );
      expect(jsonEncode(frames), original);
    },
  );
  test(
    'original observation fields survive native parsing and model serialization',
    () async {
      final raw = documentedObservations();
      final original = jsonEncode(raw);
      final message = await TsunamiMessage.parseJmaSourceAsync('whews', raw);
      expect(jsonEncode(raw), original);
      expect(message.sourcePayload, raw);
      final restored = TsunamiMessage.fromMap(message.toMap());
      expect(restored.jmaDetails, message.jmaDetails);
      expect(restored.observations.single.maxWaveHeightMeters, 0.8);
      expect(restored.observations.single.hasValidPosition, isFalse);
      final row = project(restored).single.rows.single;
      expect(row.arrivalTime, '2026-08-11 05:25:00');
      expect(row.height, '0.8m');
      expect(row.secondary.first.time, '2026-08-11 05:20:00');
      expect(row.secondary.first.text, '押し');
    },
  );
  test(
    'observation-first startup and later updates keep independent report numbers',
    () async {
      final provider = QuakeProvider(
        startCatalogServices: false,
        nativeUnifiedEvents: false,
      );
      addTearDown(provider.dispose);
      final raw = protocol('VTSE51', 1, '2026-08-11 05:30:00');
      provider.handleTsunamiEventForTest(
        await TsunamiMessage.parseJmaSourceAsync('whews', raw),
      );
      provider.handleTsunamiEventForTest(
        await TsunamiMessage.parseJmaSourceAsync(
          'whews',
          protocol('VTSE41', 7, '2026-08-11 05:10:00'),
        ),
      );
      await provider.jmaTsunamiListReadyForTest;
      expect(provider.jmaTsunami!.grade, TsunamiGrade.warning);
      expect(provider.jmaTsunamiListenable.value.map((v) => v.grade), [
        'warning',
        'observation',
      ]);
      expect(provider.jmaTsunamiListenable.value.map((v) => v.reportNumber), [
        7,
        1,
      ]);
      // Only first-wave data changes; maximum wave remains identical.
      final next = protocol('VTSE51', 2, '2026-08-11 05:31:00');
      ((next['observations'] as List).single['stations'] as List)
              .single['firstInitial'] =
          '引き';
      provider.handleTsunamiEventForTest(
        await TsunamiMessage.parseJmaSourceAsync('whews', next),
      );
      await provider.jmaTsunamiListReadyForTest;
      expect(
        provider
            .jmaTsunamiListenable
            .value
            .last
            .rows
            .single
            .secondary
            .first
            .text,
        '引き',
      );
      expect(provider.jmaTsunamiListenable.value.last.reportNumber, 2);
      provider.handleTsunamiEventForTest(
        await TsunamiMessage.parseJmaSourceAsync('whews', raw),
      );
      expect(
        provider.jmaTsunami!.jmaDetails['observationReport']['reportNumber'],
        2,
      );
    },
  );
  test(
    'initial WHEWS snapshot keeps both telegrams with identical id number and time',
    () async {
      final service = WhewsService(apiToken: 'protocol-test');
      addTearDown(service.dispose);
      final events = service.onTsunamiEvent.take(2).toList();
      service.handleMessageForTesting([
        {
          'source': 'jma_tsunami',
          'Data': protocol('VTSE41', 1, '2026-08-11 05:30:00'),
        },
        {
          'source': 'jma_tsunami',
          'Data': protocol('VTSE51', 1, '2026-08-11 05:30:00'),
        },
      ]);
      final received = await events.timeout(const Duration(seconds: 10));
      expect(received.map((v) => v.jmaDetails['telegramType']).toSet(), {
        'VTSE41',
        'VTSE51',
      });
      expect(received.every((v) => v.isInitialSnapshot), isTrue);
    },
  );
  for (final width in [220.0, 390.0]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        'first and maximum wave fit two-column cells at $width x$textScale',
        (tester) async {
          late TsunamiMessage message;
          await tester.runAsync(() async {
            message = await TsunamiMessage.parseJmaSourceAsync(
              'whews',
              protocol('VTSE51', 1, '2026-08-11 05:30:00'),
            );
          });
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: width,
                      child: JmaTsunamiListCard(
                        group: project(message).single,
                        scale: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await layout(tester, 'observation');
          const clock = TsunamiMessage(source: TsunamiSource.jma);
          expect(find.text('岩手山田沖'), findsOneWidget);
          expect(find.byType(Tooltip), findsNothing);
          expect(find.text('0.8m'), findsOneWidget);
          expect(
            find.textContaining(
              '第1波 ${clock.formatLocalHourMinute('2026-08-11 05:20:00')} 押し',
            ),
            findsOneWidget,
          );
          expect(
            find.text(clock.formatLocalHourMinute('2026-08-11 05:25:00')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
  test(
    'documented station forecast carries distinct arrival and high tide',
    () async {
      final raw =
          jsonDecode(
                File(
                  '$fixtureRoot/whews.forecast_stations.documented.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final message = await TsunamiMessage.parseJmaSourceAsync(
        'whews',
        raw['Data'] as Map<String, dynamic>,
      );
      final card = project(message).last;
      expect(card.grade, 'stationForecast');
      expect(card.rows.single.arrivalTime, '2026-07-28 17:00:00');
      expect(card.rows.single.heightTime, '2026-07-28 21:04:00');
      expect(message.sourcePayload, raw['Data']);
    },
  );
}
