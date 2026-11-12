import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/core/event_animation_clock.dart';
import 'package:flutterrhythmquake/core/utils/topojson_loader.dart';
import 'package:flutterrhythmquake/core/utils/alert_voice_helper.dart';
import 'package:flutterrhythmquake/models/tsunami_message.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/debug/local_inject_decoder.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:flutterrhythmquake/widgets/map/tsunami_layer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

const fixtureRoot = 'test/fixtures/jma_tsunami';

Map<String, dynamic> documentedFrame() =>
    jsonDecode(File('$fixtureRoot/jian.documented.json').readAsStringSync())
        as Map<String, dynamic>;

// Project original official fields into the model; never alter the XML fixture.
TsunamiMessage officialSample(String suffix) {
  final raw = File(
    '$fixtureRoot/32-39_11_${suffix}_250206_VTSE41.original.xml',
  ).readAsStringSync();
  final xml = XmlDocument.parse(raw);
  final head = xml.findAllElements('Head').single;
  String headText(String tag) =>
      head.findElements(tag).firstOrNull?.innerText ?? '';
  final forecast = xml.findAllElements('Forecast').single;
  final areas = forecast.findElements('Item').map((item) {
    final kind = item
        .findElements('Category')
        .single
        .findElements('Kind')
        .single;
    return TsunamiAreaInfo(
      name: item
          .findElements('Area')
          .single
          .findElements('Name')
          .single
          .innerText,
      grade: jmaTsunamiGradeFromKind(
        kind.findElements('Name').single.innerText,
      ),
    );
  }).toList();
  final grade = areas.fold(
    TsunamiGrade.none,
    (value, area) => area.grade.index > value.index ? area.grade : value,
  );
  return TsunamiMessage(
    source: TsunamiSource.jma,
    eventId: headText('EventID'),
    reportTime: headText('ReportDateTime'),
    expires: headText('ValidDateTime'),
    title: headText('Title'),
    titleText: head
        .findElements('Headline')
        .single
        .findElements('Text')
        .single
        .innerText,
    grade: grade,
    areas: areas,
    sourcePayload: {'xml': raw},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
    TtsService().eventEnabled = false;
  });
  tearDown(() => SoundEffectService().enabled = true);

  test(
    'documented Jian payload preserves identity, epoch, region grades and original',
    () {
      final raw = documentedFrame()['Data'] as Map<String, dynamic>;
      final before = jsonEncode(raw);
      final message = TsunamiMessage.parseJianJmaTsunami(raw);
      expect(jsonEncode(raw), before);
      expect(message.sourcePayload, raw);
      expect(message.eventId, raw['headline']);
      expect(message.reportNumber, raw['number']);
      expect(
        message.reportInstantUtc!.millisecondsSinceEpoch,
        raw['originTime'],
      );
      expect(message.displayUntilUtc!.millisecondsSinceEpoch, raw['endTime']);
      expect(
        message.originTime,
        isEmpty,
      ); // issue clock is not earthquake origin.
      expect(message.title, '津波警報');
      expect(message.epicenterName, raw['place']);
      expect(message.grade, TsunamiGrade.warning);
      expect(message.areas.map((area) => area.grade), [
        TsunamiGrade.warning,
        TsunamiGrade.watch,
        TsunamiGrade.forecast,
      ]);
      expect(message.areas.last.className, 'blue');
      expect(message.areas.last.description, '０．２ｍ未満');
      expect(message.areas.last.height, isNull);
      final restored = TsunamiMessage.fromMap(message.toMap());
      expect(restored.toMap(), message.toMap());
    },
  );

  test(
    'official codes 71 and 72 both retain forecasts, distinct from removal',
    () {
      final raw = File(
        '$fixtureRoot/32-39_11_13_250206_VTSE41.original.xml',
      ).readAsStringSync();
      final xml = XmlDocument.parse(raw);
      final codes = <String>{};
      for (final kind in xml.findAllElements('Kind')) {
        final code = kind.findElements('Code').single.innerText;
        if (code != '71' && code != '72') continue;
        codes.add(code);
        expect(
          jmaTsunamiGradeFromKind(kind.findElements('Name').single.innerText),
          TsunamiGrade.forecast,
        );
      }
      expect(codes, {'71', '72'});
      final message = officialSample('13');
      expect(message.isForecast, isTrue);
      expect(message.isInformation, isTrue);
      expect(message.isActive, isFalse);
      expect(
        message.isCancellation,
        isFalse,
      ); // headline mentions lifting advisory.
      expect(message.isDisplayableAt(message.reportInstantUtc!), isTrue);
      expect(message.hasCoastalDisplayAt(message.reportInstantUtc!), isTrue);
      expect(message.isDisplayableAt(message.displayUntilUtc!), isFalse);
      expect(message.hasCoastalDisplayAt(message.displayUntilUtc!), isFalse);
      expect(
        AlertVoiceHelper.generateTsunamiText(message, isUpdate: false),
        isNot(contains('解除')),
      );
      final restored = TsunamiMessage.fromMap(message.toMap());
      expect(restored.toMap(), message.toMap());
      expect(restored.areas.every((area) => area.className == 'blue'), isTrue);
    },
  );

  test('official warning to forecast update rejects a late older warning', () {
    final provider = QuakeProvider(startCatalogServices: false);
    addTearDown(provider.dispose);
    final warning = officialSample('02');
    final forecast = officialSample('13');
    expect(warning.grade, TsunamiGrade.majorWarning);
    provider.handleTsunamiEventForTest(warning);
    provider.handleTsunamiEventForTest(forecast);
    provider.handleTsunamiEventForTest(warning);
    expect(provider.jmaTsunami, same(forecast));
  });

  test('same-time P2P all-clear cannot erase explicit official forecast', () {
    final provider = QuakeProvider(startCatalogServices: false);
    addTearDown(provider.dispose);
    final forecast = officialSample('13');
    // P2P 552 represents the same official removal time but has no forecast grade.
    final cancellation = TsunamiMessage.parseJmaTsunami({
      'cancelled': true,
      'issue': {'time': forecast.reportTime},
      'areas': <Object>[],
    });
    provider.handleTsunamiEventForTest(forecast);
    provider.handleTsunamiEventForTest(cancellation);
    expect(provider.jmaTsunami!.isForecast, isTrue);
    expect(provider.jmaTsunami!.areas.length, forecast.areas.length);
    expect(provider.jmaTsunami!.expires, forecast.expires);
    provider.handleTsunamiEventForTest(forecast);
    expect(provider.jmaTsunami!.isForecast, isTrue);
  });

  test('raw Jian tsunami also uses common parser in local replay', () {
    final frame = documentedFrame();
    final before = jsonEncode(frame);
    final batch = LocalInjectDecoder.decode(frame);
    expect(batch.events, isEmpty);
    expect(batch.tsunamis, hasLength(1));
    expect(batch.tsunamis.single.sourcePayload, frame['Data']);
    expect(jsonEncode(frame), before);
  });

  testWidgets(
    'official forecast blinks existing blue coastline and releases clock on expiry',
    (tester) async {
      final message = officialSample('13');
      final original = jsonEncode(message.toMap());
      final clock = EventAnimationClock.instance;
      final initialLeases = clock.activeLeaseCount;
      var displayTime = message.reportInstantUtc!;
      await tester.runAsync(() => TopoJsonLoader.loadJpTsunami());
      Widget map() => MaterialApp(
        home: Scaffold(
          body: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(38, 140),
              initialZoom: 4,
            ),
            children: [TsunamiLayer(tsunami: message, now: () => displayTime)],
          ),
        ),
      );
      await tester.pumpWidget(map());
      await tester.pump();
      final layer = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
      expect(layer.polylines, isNotEmpty);
      expect(
        layer.polylines.every((line) => line.color == const Color(0xFF3399FF)),
        isTrue,
      );
      expect(clock.activeLeaseCount, initialLeases + 1);
      final coastlineOpacity = find.ancestor(
        of: find.byType(PolylineLayer),
        matching: find.byType(Opacity),
      );
      final phases = <double>[];
      for (var phase = 0; phase < 6; phase++) {
        await tester.pump(const Duration(milliseconds: 500));
        final opacity = tester.widget<Opacity>(coastlineOpacity).opacity;
        expect(opacity, clock.blink2Fps.value % 6 != 0 ? 1.0 : 0.0);
        phases.add(opacity);
        expect(
          tester.widget<PolylineLayer>(find.byType(PolylineLayer)),
          same(layer),
        );
      }
      expect(phases.where((opacity) => opacity == 1), hasLength(5));
      expect(phases.where((opacity) => opacity == 0), hasLength(1));
      displayTime = message.displayUntilUtc!;
      await tester.pumpWidget(map());
      await tester.pump();
      expect(find.byType(PolylineLayer), findsNothing);
      expect(clock.activeLeaseCount, initialLeases);
      expect(jsonEncode(message.toMap()), original);
      expect(tester.takeException(), isNull);
    },
  );
}
