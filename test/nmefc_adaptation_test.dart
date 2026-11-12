import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/tsunami_message.dart';
import 'package:flutterrhythmquake/core/utils/alert_voice_helper.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/native_jma_tsunami.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:flutterrhythmquake/widgets/map/nmefc_tsunami_layer.dart';
import 'package:flutterrhythmquake/widgets/ui/jma_tsunami_sidebar.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Explicit protocol/UI edge cases; not historical observations or live injections.
Map<String, dynamic> protocol({
  int number = 2,
  String level = '橙色',
  int regions = 0,
}) => {
  'code': 'protocol-event',
  'details': {'batch': number},
  'timeInfo': {'alarmDate': '2026-01-01 12:00:00'},
  'warningInfo': {'level': level},
  'forecasts': [
    for (var i = 0; i < regions; i++)
      {
        'forecastArea': '区域$i',
        'maxWaveHeight': '100-300',
        'warningLevel': level,
        'estimatedArrivalTime': '12:30',
      },
  ],
  'waterLevelMonitoring': [
    {
      'stationName': 'protocol station without position',
      'location': '独立观测位置',
      'maxWaveHeight': '0',
    },
    {
      'stationName': 'protocol positioned station',
      'location': '区域0',
      'maxWaveHeight': '80',
      'coordinates': {'latitude': 24.0, 'longitude': 122.0},
    },
  ],
};

Future<void> ready(WidgetTester tester) async {
  for (var i = 0; i < 150; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (find
        .byKey(const ValueKey('jma_tsunami_sidebar_viewport'))
        .evaluate()
        .isNotEmpty) {
      return;
    }
    if (tester.takeException() case final Object error) throw error;
  }
  fail('Native NMEFC sidebar did not complete');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
    TtsService().eventEnabled = false;
  });
  group(
    'NMEFC actual native integration',
    () {
      test(
        'captured unmodified source reaches async codec and information lifecycle',
        () async {
          final archive =
              jsonDecode(
                    File(
                      'test/fixtures/catalog_20260917/whews_all.json',
                    ).readAsStringSync(),
                  )
                  as List;
          final raw = Map<String, dynamic>.from(
            archive.singleWhere((e) => e['source'] == 'tsunami')['Data'] as Map,
          );
          final encoded = jsonEncode(raw);
          final parsed = await TsunamiMessage.parseNmefcTsunamiAsync(raw);
          expect(jsonEncode(raw), encoded);
          expect(parsed.sourcePayload, raw);
          expect(parsed.eventId, '202608251500');
          expect(parsed.reportNumber, 2);
          expect(parsed.reportInstantUtc, DateTime.utc(2026, 8, 25, 7, 46, 46));
          expect(parsed.isInformation, isTrue);
          expect(parsed.isCancellation, isFalse);
          expect(parsed.isDisplayableAt(DateTime.utc(2026, 8, 25, 8)), isTrue);
          expect(
            parsed.isDisplayableAt(DateTime.utc(2026, 8, 25, 11)),
            isFalse,
          );
        },
      );
      test(
        'native report order and cancellation enter the existing provider',
        () {
          final provider = QuakeProvider(
            startCatalogServices: false,
            nativeUnifiedEvents: false,
          );
          addTearDown(provider.dispose);
          final latest = TsunamiMessage.parseNmefcTsunami(protocol(number: 3));
          provider.handleTsunamiEventForTest(latest);
          provider.handleTsunamiEventForTest(
            TsunamiMessage.parseNmefcTsunami(protocol(number: 2, level: '红色')),
          );
          expect(provider.nmefcTsunami?.reportNumber, 3);
          expect(provider.nmefcTsunami?.className, 'orange');
          provider.handleTsunamiEventForTest(
            TsunamiMessage.parseNmefcTsunami(protocol(number: 4, level: '解除')),
          );
          expect(provider.nmefcTsunami?.isCancellation, isTrue);
          provider.handleTsunamiEventForTest(latest);
          expect(provider.nmefcTsunami?.reportNumber, 4);
        },
      );
      test(
        'unknown level is not an all-clear and raw ranges remain ranges',
        () {
          final unknown = TsunamiMessage.parseNmefcTsunami(
            protocol(level: '未识别'),
          );
          expect(unknown.isCancellation, isFalse);
          expect(unknown.isActive, isFalse);
          final warning = TsunamiMessage.parseNmefcTsunami(
            protocol(regions: 1),
          );
          expect(warning.areas.single.height, isNull);
          expect(warning.areas.single.description, '100-300cm');
          expect(warning.observations.length, 2);
          expect(warning.observations.first.hasValidPosition, isFalse);
          expect(warning.observations.first.maxWaveHeightMeters, 0);
          expect(warning.observations.last.maxWaveHeight, '80cm');
          expect(
            AlertVoiceHelper.generateTsunamiText(unknown, isUpdate: false),
            isEmpty,
          );
          expect(
            AlertVoiceHelper.generateTsunamiText(warning, isUpdate: true),
            contains('第2报'),
          );
          final cancel = protocol(level: '解除');
          (cancel['warningInfo'] as Map)['title'] = '海啸信息';
          expect(
            AlertVoiceHelper.generateTsunamiText(
              TsunamiMessage.parseNmefcTsunami(cancel),
              isUpdate: true,
            ),
            contains('已经解除'),
          );
        },
      );
      testWidgets(
        'map skips only invalid positions and keeps valid observation marker',
        (tester) async {
          final message = TsunamiMessage.parseNmefcTsunami(
            protocol(regions: 1),
          );
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: FlutterMap(
                  options: const MapOptions(
                    initialCenter: LatLng(24, 122),
                    initialZoom: 5,
                  ),
                  children: [NmefcTsunamiLayer(tsunami: message)],
                ),
              ),
            ),
          );
          expect(
            tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
            hasLength(1),
          );
          expect(tester.takeException(), isNull);
        },
      );
      for (final phone in [false, true]) {
        testWidgets(
          'sidebar retains all entries and rotates every twelve seconds phone=$phone',
          (tester) async {
            final message = TsunamiMessage.parseNmefcTsunami(
              protocol(regions: 15),
            );
            await tester.pumpWidget(
              MaterialApp(
                home: MediaQuery(
                  data: MediaQueryData(
                    size: phone ? const Size(360, 800) : const Size(1700, 1000),
                    textScaler: TextScaler.linear(phone ? 1.4 : 1),
                  ),
                  child: Scaffold(
                    body: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: phone ? 240 : 420,
                        height: 250,
                        child: JmaTsunamiSidebar.nmefc(
                          message: message,
                          scale: 1,
                          maxHeight: 250,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await ready(tester);
            final indicator = find.byKey(
              const ValueKey('jma_tsunami_sidebar_page'),
            );
            final initial = tester.widget<Text>(indicator).data!;
            final total = int.parse(initial.split('/').last);
            expect(total, greaterThan(1));
            final seen = <String>{};
            for (var page = 0; page < total; page++) {
              seen.addAll(
                tester
                    .widgetList<Text>(find.byType(Text))
                    .map((e) => e.data ?? ''),
              );
              expect(tester.takeException(), isNull);
              if (page == 0) {
                await tester.pump(const Duration(seconds: 11));
                expect(tester.widget<Text>(indicator).data, initial);
                await tester.pump(const Duration(seconds: 1));
              } else {
                await tester.pump(const Duration(seconds: 12));
              }
            }
            for (var i = 0; i < 15; i++) {
              expect(seen, contains('区域$i'));
            }
            expect(seen, contains('独立观测位置'));
            expect(seen, isNot(contains('protocol station without position')));
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    },
    skip: NativeJmaTsunami.supported
        ? false
        : 'Requires Windows station-core DLL',
  );
}
