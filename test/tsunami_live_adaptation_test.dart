import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutterrhythmquake/services/sources/tsunami_bulletin_service.dart';
import 'package:flutterrhythmquake/services/sources/whews_service.dart';
import 'package:flutterrhythmquake/services/sources/noaa_tsunami_area_service.dart';
import 'package:flutterrhythmquake/models/tsunami_message.dart';
import 'package:flutterrhythmquake/services/native_jma_tsunami.dart';
import 'package:flutterrhythmquake/models/jma_tsunami_list.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/widgets/ui/eqlist_panel.dart';

const liveRoot = 'test/fixtures/tsunami_live_20261024';
List<Map<String, dynamic>> liveFrames() =>
    (jsonDecode(File('$liveRoot/frame_000.original').readAsStringSync())
            as List)
        .whereType<Map>()
        .map((v) => Map<String, dynamic>.from(v))
        .toList();
TsunamiMessage liveMessage(Map<String, dynamic> f) => f['source'] == 'tsunami'
    ? TsunamiMessage.parseNmefcTsunami(
        Map<String, dynamic>.from(f['Data'] as Map),
      )
    : TsunamiMessage.parseInternationalTsunami(
        TsunamiSource.values.byName(
          (f['source'] as String).replaceFirst('_tsunami', ''),
        ),
        Map<String, dynamic>.from(f['Data'] as Map),
      );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'captured API and official response bytes still match their acquisition hashes',
    () {
      final aggregate =
          jsonDecode(File('$liveRoot/manifest.json').readAsStringSync()) as Map;
      final details =
          jsonDecode(File('$liveRoot/details-manifest.json').readAsStringSync())
              as List;
      for (final row in [...aggregate['frames'] as List, ...details]) {
        expect(
          sha256
              .convert(File('$liveRoot/${row['file']}').readAsBytesSync())
              .toString(),
          row['sha256'],
        );
      }
    },
  );
  test(
    'audit actual received telegrams without changing source fields',
    () async {
      expect(NativeJmaTsunami.supported, isTrue);
      final rows = <Map<String, dynamic>>[];
      for (final f in liveFrames().where(
        (f) => {
          'tsunami',
          'ntwc',
          'ptwc',
          'incois',
          'cat_tsunami',
          'cwa_tsunami',
        }.contains(f['source']),
      )) {
        final m = liveMessage(f);
        final view = await NativeJmaTsunami.prepareAsync({
          'op': 'internationalProject',
          'message': m.toMap(),
          'nowMs': m.reportInstantUtc!.millisecondsSinceEpoch,
        });
        expect(m.sourcePayload, f['Data']);
        rows.add({
          'source': f['source'],
          'id': m.id,
          'reportTime': m.reportTime,
          'grade': m.grade.name,
          'bulletinLevel': m.bulletinLevel,
          'groups': view['groups'],
        });
      }
      Directory('tmp/tsunami_live_20261024').createSync(recursive: true);
      File(
        'tmp/tsunami_live_20261024/adapted.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
    },
  );
  test(
    'current no-threat scopes and ongoing monitoring survive actual source wording',
    () async {
      final expected = {
        'tsunami': '震源周围可能引发局地海啸；我国沿岸无海啸影响',
        'ntwc': '美国西海岸、不列颠哥伦比亚及阿拉斯加无海啸危险',
        'ptwc': '关岛及北马里亚纳群岛无海啸威胁',
        'incois': '印度沿岸无海啸威胁',
        'cwa_tsunami': '太平洋地区可能有海啸威胁，持续监视后续影响',
      };
      for (final f in liveFrames().where(
        (f) => expected.containsKey(f['source']),
      )) {
        var m = liveMessage(f);
        final original = jsonEncode(m.sourcePayload);
        if (f['source'] == 'tsunami') {
          final raw = File(
            '$liveRoot/tsunami_html.original',
          ).readAsStringSync();
          final client = MockClient(
            (r) async => http.Response.bytes(utf8.encode(raw), 200),
          );
          final detail = await TsunamiBulletinService(client: client).fetch(m);
          expect(detail?['bulletinHtml'], raw);
          expect(detail?['bulletinText'], contains('震源周围引发局地海啸'));
          expect(detail?['bulletinText'], isNot(contains('注：')));
          m = m.copyWith(officialDetail: detail);
          client.close();
        } else if (f['source'] == 'ptwc') {
          m = m.copyWith(
            officialDetail: {
              'bulletinText': File(
                '$liveRoot/ptwc_bulletinUrl.original',
              ).readAsStringSync(),
            },
          );
        }
        final v = NativeJmaTsunami.prepare({
          'op': 'internationalProject',
          'message': m.toMap(),
          'nowMs': m.reportInstantUtc!.millisecondsSinceEpoch,
        });
        final g = (v['groups'] as List).single;
        expect(g['pinned'], false);
        expect(g['informationText'], expected[f['source']]);
        expect(g['eventText'], contains(m.epicenterName));
        expect(g['eventText'], contains('M${m.magnitude}'));
        expect(jsonEncode(m.sourcePayload), original);
        if (f['source'] == 'cwa_tsunami') {
          expect(g['informationText'], isNot(contains('无海啸威胁')));
        }
      }
    },
  );
  test('expired original information stays removed on repeated projection', () {
    for (final f in liveFrames().where(
      (f) => {
        'tsunami',
        'ntwc',
        'ptwc',
        'incois',
        'cat_tsunami',
        'cwa_tsunami',
      }.contains(f['source']),
    )) {
      final m = liveMessage(f);
      final after = m.displayUntilUtc!.add(const Duration(seconds: 1));
      for (var i = 0; i < 3; i++) {
        final v = NativeJmaTsunami.prepare({
          'op': 'internationalProject',
          'message': m.toMap(),
          'nowMs': after.millisecondsSinceEpoch,
        });
        expect(v['groups'], isEmpty, reason: f['source']);
      }
    }
  });
  test(
    'WHEWS information level still fetches this report official NOAA data and text',
    () async {
      final f = liveFrames().firstWhere((f) => f['source'] == 'ptwc');
      // Run the captured original through the service at its actual capture time.
      final requests = <String>[];
      final client = MockClient((r) async {
        requests.add(r.url.path);
        return http.Response.bytes(
          File(
            '$liveRoot/ptwc_${r.url.path.endsWith('.json') ? 'jsonUrl' : 'bulletinUrl'}.original',
          ).readAsBytesSync(),
          200,
        );
      });
      final service = WhewsService(
        apiToken: 'unused-offline',
        now: () => liveMessage(f).reportInstantUtc!,
        noaaTsunamiAreaService: NoaaTsunamiAreaService(client: client),
        tsunamiBulletinService: TsunamiBulletinService(client: client),
      );
      final events = <TsunamiMessage>[];
      final sub = service.onTsunamiEvent.listen(events.add);
      try {
        service.handleMessageForTesting(f);
        for (var i = 0; i < 40 && events.length < 2; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(events, isNotEmpty);
        expect(events, hasLength(2));
        expect(
          events.last.officialDetail['bulletinText'],
          File('$liveRoot/ptwc_bulletinUrl.original').readAsStringSync(),
        );
        expect(requests, hasLength(2));
        expect(events.last.sourcePayload, f['Data']);
      } finally {
        await sub.cancel();
        service.dispose();
        client.close();
      }
    },
  );
  testWidgets(
    'live original information stays in populated 1* cells during repeated catalog refreshes',
    (tester) async {
      tester.view.physicalSize = const Size(1700, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final font = FontLoader('LiveReview')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync(),
            ),
          ),
        );
      await font.load();
      final groups = <JmaTsunamiListGroup>[];
      for (final f in liveFrames().where(
        (f) => {
          'tsunami',
          'ntwc',
          'ptwc',
          'incois',
          'cwa_tsunami',
        }.contains(f['source']),
      )) {
        var m = liveMessage(f);
        if (f['source'] == 'tsunami') {
          m = m.copyWith(
            officialDetail: NativeJmaTsunami.prepare({
              'op': 'nmefcBulletin',
              'html': File(
                '$liveRoot/tsunami_html.original',
              ).readAsStringSync(),
            }),
          );
        } else if (f['source'] == 'ptwc') {
          m = m.copyWith(
            officialDetail: {
              'bulletinText': File(
                '$liveRoot/ptwc_bulletinUrl.original',
              ).readAsStringSync(),
            },
          );
        }
        final view = NativeJmaTsunami.prepare({
          'op': 'internationalProject',
          'message': m.toMap(),
          'nowMs': m.reportInstantUtc!.millisecondsSinceEpoch,
        });
        groups.addAll(
          (view['groups'] as List).map((g) => JmaTsunamiListGroup.fromMap(g)),
        );
      }
      SharedPreferences.setMockInitialValues({});
      final provider = QuakeProvider(
        startCatalogServices: false,
        nativeUnifiedEvents: false,
      );
      final map = MapStateProvider();
      await tester.runAsync(() => provider.eewHistoryReadyForTest);
      final capture = GlobalKey();
      provider.internationalTsunamiListenable.value = groups;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: provider),
            ChangeNotifierProvider.value(value: map),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark().copyWith(
              textTheme: ThemeData.dark().textTheme.apply(
                fontFamily: 'LiveReview',
              ),
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: RepaintBoundary(
                  key: capture,
                  child: const SizedBox(
                    width: 446,
                    height: 700,
                    child: EqlistPanel(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      final before = <String, double>{};
      for (final g in groups) {
        expect(find.text(g.informationText), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(ValueKey('jma_tsunami_${g.key}')),
            matching: find.text(g.eventText),
          ),
          findsOneWidget,
        );
        before[g.key] = tester
            .getTopLeft(find.byKey(ValueKey('jma_tsunami_${g.key}')))
            .dy;
      }
      for (var i = 0; i < 5; i++) {
        provider.internationalTsunamiListenable.value = [
          for (final g in groups) JmaTsunamiListGroup.fromMap(g.toMap()),
        ];
        await tester.pump();
        for (final g in groups) {
          expect(find.text(g.informationText), findsOneWidget);
          expect(
            tester.getTopLeft(find.byKey(ValueKey('jma_tsunami_${g.key}'))).dy,
            before[g.key],
          );
        }
        for (final cell in tester.widgetList<Container>(
          find.byKey(const ValueKey('jma_tsunami_cell_none_1')),
        )) {
          expect(cell.constraints!.maxHeight, 76);
        }
      }
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (capture.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        File(
          'tmp/tsunami_live_20261024/live-cards.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
      map.dispose();
    },
  );
}
