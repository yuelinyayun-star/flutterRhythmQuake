import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';
import 'package:flutterrhythmquake/models/jma_tsunami_list.dart';
import 'package:flutterrhythmquake/models/tsunami_message.dart';
import 'package:flutterrhythmquake/services/native_jma_tsunami.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:flutterrhythmquake/widgets/ui/jma_tsunami_list_card.dart';
import 'package:flutterrhythmquake/widgets/ui/eqlist_panel.dart';

const root = 'test/fixtures/jma_tsunami';
// Read the original official XML. Tests never change source IDs, times or heights.
Map<String, dynamic> official(String suffix) {
  final raw = File(
    '$root/32-39_11_${suffix}_250206_VTSE41.original.xml',
  ).readAsStringSync();
  final xml = XmlDocument.parse(raw),
      head = XmlDocument.parse(raw).findAllElements('Head').single;
  String h(String tag) => head.findElements(tag).firstOrNull?.innerText ?? '';
  final areas = <Map<String, dynamic>>[];
  for (final item
      in xml.findAllElements('Forecast').single.findElements('Item')) {
    final height = item
        .findElements('MaxHeight')
        .firstOrNull
        ?.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'TsunamiHeight')
        .firstOrNull;
    final rawHeight = double.tryParse(height?.innerText ?? '');
    final first = item.findElements('FirstHeight').firstOrNull;
    areas.add({
      'name': item
          .findElements('Area')
          .single
          .findElements('Name')
          .single
          .innerText,
      'grade': jmaTsunamiGradeFromKind(
        item
            .findElements('Category')
            .single
            .findElements('Kind')
            .single
            .findElements('Name')
            .single
            .innerText,
      ).name,
      'height': rawHeight?.isFinite == true ? rawHeight : null,
      'description': height?.getAttribute('description') ?? '',
      'arrivalTime':
          first?.findElements('ArrivalTime').firstOrNull?.innerText ?? '',
      'condition':
          first?.findElements('Condition').firstOrNull?.innerText ?? '',
    });
  }
  return {
    'source': 'jma',
    'eventId': h('EventID'),
    'title': h('Title'),
    'titleText':
        head
            .findElements('Headline')
            .firstOrNull
            ?.findElements('Text')
            .firstOrNull
            ?.innerText ??
        '',
    'reportTime': h('ReportDateTime'),
    'expires': h('ValidDateTime'),
    'grade': areas.any((a) => a['grade'] == 'majorWarning')
        ? 'majorWarning'
        : 'forecast',
    'reportNumber': int.tryParse(h('Serial')),
    'areas': areas,
    'sourcePayload': {'xml': raw},
  };
}

Map<String, dynamic> project(Map<String, dynamic> m, {int? nowMs}) =>
    NativeJmaTsunami.prepare({
      'op': 'project',
      'message': m,
      'nowMs':
          nowMs ??
          DateTime.parse(m['reportTime'] as String).millisecondsSinceEpoch,
    });
List<JmaTsunamiListGroup> groups(Map<String, dynamic> m) => [
  for (final v in project(m)['groups'] as List)
    JmaTsunamiListGroup.fromMap(v as Map),
];

Finder cellFor(String grade) => find.byWidgetPredicate(
  (w) =>
      w is Container &&
      w.key is ValueKey<String> &&
      (w.key as ValueKey<String>).value.startsWith(
        'jma_tsunami_cell_${grade}_',
      ),
);
Future<void> waitForLayout(WidgetTester tester, String grade) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (cellFor(grade).evaluate().isNotEmpty) return;
    if (tester.takeException() case final Object error) throw error;
  }
  fail('Native tsunami layout did not finish');
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
      skip: 'Set RQ_STATION_CORE_LIBRARY to test the actual Rust path',
    );
    return;
  }
  test(
    'original fully cleared WHEWS report removes previous left cards',
    () async {
      // Original restored APP snapshot from the reported stuck-card case.
      final raw =
          jsonDecode(
                File(
                  '$root/whews.cleared_20261018.original.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final before = jsonEncode(raw);
      final cleared = await TsunamiMessage.parseJmaSourceAsync('whews', raw);
      expect(cleared.isDisplayableAt(DateTime.now()), false);
      expect(project(cleared.toMap())['groups'], isEmpty);
      expect(cleared.sourcePayload, raw);
      expect(jsonEncode(raw), before);

      final provider = QuakeProvider(
        startCatalogServices: false,
        nativeUnifiedEvents: false,
      );
      addTearDown(provider.dispose);
      await provider.eewHistoryReadyForTest;
      provider.handleTsunamiEventForTest(
        TsunamiMessage.fromMap(official('02')),
      );
      await provider.jmaTsunamiListReadyForTest;
      expect(provider.jmaTsunamiListenable.value, isNotEmpty);
      provider.handleTsunamiEventForTest(cleared);
      await provider.jmaTsunamiListReadyForTest;
      expect(provider.jmaTsunamiListenable.value, isEmpty);
      expect(provider.jmaTsunami, same(cleared));
    },
  );
  test(
    'current documented Jian array preserves original and marks cleared areas',
    () async {
      final raw =
          (jsonDecode(
                    File(
                      '$root/jian.documented_20261019.json',
                    ).readAsStringSync(),
                  )
                  as Map)['Data']
              as Map<String, dynamic>;
      final before = jsonEncode(raw);
      final message = await TsunamiMessage.parseJmaSourceAsync('jian', raw);
      expect(jsonEncode(raw), before);
      expect(message.sourcePayload, raw);
      expect(message.eventId, raw['id']);
      expect(message.reportNumber, raw['number']);
      expect(
        message.reportInstantUtc!.millisecondsSinceEpoch,
        raw['originTime'],
      );
      expect(message.displayUntilUtc!.millisecondsSinceEpoch, raw['endTime']);
      expect(message.areas.single.name, '北海道太平洋沿岸東部');
      expect(message.areas.single.grade, TsunamiGrade.none);
      expect(message.isActive, false);
      expect(
        project(message.toMap(), nowMs: (raw['endTime'] as int) + 1)['groups'],
        isEmpty,
      );
    },
  );
  test(
    'official forecast is grouped once per grade without losing any region',
    () {
      final raw = official('02'), before = jsonEncode(official('02'));
      final view = project(raw), cards = groups(raw);
      expect(jsonEncode(raw), before);
      expect(cards.map((g) => g.grade), [
        'majorWarning',
        'warning',
        'watch',
        'forecast',
      ]);
      expect(cards.map((g) => g.caption), [
        'JMA 大津波警報',
        'JMA 津波警報',
        'JMA 津波注意報',
        'JMA 津波予報',
      ]);
      expect(cards.expand((g) => g.rows).length, (raw['areas'] as List).length);
      expect(
        cards.expand((g) => g.rows).map((r) => r.name).toSet(),
        (raw['areas'] as List).map((r) => r['name']).toSet(),
      );
      expect(cards.first.rows.first.height, '巨大');
      expect(cards[1].rows.first.height, '高い');
      expect(cards.first.rows.first.condition, '津波到達中と推測');
      expect(cards.first.rows[1].arrivalTime, '2011-03-11T15:00:00+09:00');
      expect(view['groups'], hasLength(4));
    },
  );
  test(
    'legacy original Jian text stays compatible and bounded height is not a reading',
    () {
      final raw =
          (jsonDecode(File('$root/jian.documented.json').readAsStringSync())
                  as Map)['Data']
              as Map<String, dynamic>;
      final message = TsunamiMessage.parseJianJmaTsunami(raw);
      final cards = groups(message.toMap());
      expect(cards.map((g) => g.grade), ['warning', 'watch', 'forecast']);
      expect(cards.last.rows.single.height, '0.2m未満');
      expect(message.areas.last.height, isNull);
      expect(message.sourcePayload, raw);
    },
  );
  test(
    'partial clearance is not whole cancellation; no heights inferred from grade',
    () {
      // Explicit protocol edge fixture. It is not a real earthquake/tsunami report.
      final raw = <String, dynamic>{
        'id': 'protocol-edge',
        'originTime': 1,
        'level': '津波警報',
        'cleared': true,
        'cancel': false,
        'area': [
          {
            'name': 'active protocol region',
            'kind': '津波警報',
            'maxHeight': '',
            'maxHeightDesc': '',
          },
          {'name': 'cleared protocol region', 'kind': '津波なし', 'cleared': true},
        ],
      };
      final parsed = NativeJmaTsunami.prepare({
        'op': 'parse',
        'transport': 'jian',
        'payload': raw,
      });
      final cards = groups(parsed);
      expect(parsed['grade'], 'warning');
      expect(cards.map((g) => g.grade), ['warning', 'none']);
      expect(cards.first.rows.single.height, '未知');
      expect(cards.last.rows.single.height, '');
    },
  );
  testWidgets('P2P immediate-only report uses the existing arrival cell', (tester) async {
    // Protocol edge fixture, not a live bulletin or a modified archive.
    final raw = {
      'issue': {'time': '2026/10/19 12:00:00'},
      'areas': [
        {
          'name': 'protocol region',
          'grade': 'Warning',
          'immediate': true,
          'maxHeight': {'value': 3, 'description': '３ｍ'},
        },
      ],
    };
    final parsed = NativeJmaTsunami.prepare({
      'op': 'parse', 'transport': 'p2p', 'payload': raw,
    });
    expect(parsed['sourcePayload'], raw);
    final message = TsunamiMessage.fromMap(parsed);
    expect(message.areas.single.condition, 'ただちに津波来襲と予測');
    final card = groups(message.toMap()).single;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(
      width: 390,
      child: JmaTsunamiListCard(group: card, scale: 1),
    ))));
    await waitForLayout(tester, 'warning');
    expect(find.text('すぐ来る'), findsOneWidget);
    expect(find.text('3m'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('P2P sentinel and wave bounds preserve the source meaning', () {
    // Explicit P2P protocol edge fixture, not a live bulletin.
    final raw = {
      'issue': {'time': '2026/10/19 12:00:00'},
      'areas': [
        {
          'name': 'protocol region',
          'grade': 'MajorWarning',
          'maxHeight': {'value': -1},
        },
        {
          'name': 'bounded region',
          'grade': 'MajorWarning',
          'maxHeight': {'value': -1, 'description': '１０ｍ超'},
        },
      ],
    };
    final parsed = NativeJmaTsunami.prepare({
      'op': 'parse',
      'transport': 'p2p',
      'payload': raw,
    });
    final cards = groups(parsed);
    expect(cards.single.rows.map((r) => r.height), ['10m超', '10m超']);
  });
  test(
    'accepted original warning reaches left list; expired forecast and late old warning cannot restore it',
    () async {
      final provider = QuakeProvider(
        startCatalogServices: false,
        nativeUnifiedEvents: false,
      );
      addTearDown(provider.dispose);
      await provider.eewHistoryReadyForTest;
      final warning = TsunamiMessage.fromMap(official('02'));
      final forecast = TsunamiMessage.fromMap(official('13'));
      provider.handleTsunamiEventForTest(warning);
      await provider.jmaTsunamiListReadyForTest;
      expect(provider.jmaTsunamiListenable.value.map((g) => g.grade), [
        'majorWarning',
        'warning',
        'watch',
        'forecast',
      ]);
      provider.handleTsunamiEventForTest(forecast);
      await provider.jmaTsunamiListReadyForTest;
      expect(provider.jmaTsunamiListenable.value, isEmpty);
      provider.handleTsunamiEventForTest(warning);
      await provider.jmaTsunamiListReadyForTest;
      expect(provider.jmaTsunami, same(forecast));
      expect(provider.jmaTsunamiListenable.value, isEmpty);
    },
  );
  for (final width in [220.0, 390.0, 420.0]) {
    for (final textScale in [1.0, 1.6, 2.0]) {
      testWidgets(
        'grade cells keep all regions, no overflow at $width x$textScale',
        (tester) async {
          tester.view.physicalSize = Size(width, 950);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final cards = groups(official('02'));
          for (final card in cards) {
            await tester.pumpWidget(
              MaterialApp(
                home: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 950),
                    textScaler: TextScaler.linear(textScale),
                  ),
                  child: Scaffold(
                    body: Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: width,
                        child: JmaTsunamiListCard(group: card, scale: 1),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await waitForLayout(tester, card.grade);
            expect(tester.takeException(), isNull);
            expect(
              find.text('${card.caption} · ${card.regionCount}区域'),
              findsOneWidget,
            );
            final cell = cellFor(card.grade);
            expect([76.0, 152.0], contains(tester.getSize(cell).height));
            final counter = tester
                .widget<Text>(
                  find.byKey(ValueKey('jma_tsunami_page_${card.grade}')),
                )
                .data!;
            final totalPages = counter.isEmpty
                ? 1
                : int.parse(counter.split('/').last);
            final seen = <String>{};
            for (var page = 0; page < totalPages; page++) {
              final visible = card.rows
                  .where(
                    (row) => find
                        .byKey(
                          ValueKey(
                            'jma_tsunami_region_${card.grade}_${row.name}',
                          ),
                        )
                        .evaluate()
                        .isNotEmpty,
                  )
                  .toList();
              expect(visible, isNotEmpty);
              final bounds = tester.getRect(cell);
              for (final row in visible) {
                final rect = tester.getRect(
                  find.byKey(
                    ValueKey('jma_tsunami_region_${card.grade}_${row.name}'),
                  ),
                );
                expect(rect.bottom, lessThanOrEqualTo(bounds.bottom + .01));
                expect(rect.right, lessThanOrEqualTo(bounds.right + .01));
                seen.add(row.name);
              }
              // Every rendered grid line contains two blocks except its final odd row.
              if (visible.length > 1) {
                final first = tester.getRect(
                  find.byKey(
                    ValueKey(
                      'jma_tsunami_region_${card.grade}_${visible[0].name}',
                    ),
                  ),
                );
                final second = tester.getRect(
                  find.byKey(
                    ValueKey(
                      'jma_tsunami_region_${card.grade}_${visible[1].name}',
                    ),
                  ),
                );
                expect(first.top, closeTo(second.top, .01));
                expect(second.left, greaterThan(first.right));
              }
              if (page + 1 < totalPages) {
                await tester.pump(const Duration(seconds: 12));
              }
            }
            expect(seen, card.rows.map((r) => r.name).toSet());
            expect(
              find.descendant(
                of: find.byType(JmaTsunamiListCard),
                matching: find.byType(Scrollable),
              ),
              findsNothing,
            );
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }
  testWidgets('slow paging waits twelve seconds and returns to first page', (
    tester,
  ) async {
    final card = groups(official('02')).last;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 390,
              child: JmaTsunamiListCard(group: card, scale: 1),
            ),
          ),
        ),
      ),
    );
    await waitForLayout(tester, card.grade);
    final counter = find.byKey(ValueKey('jma_tsunami_page_${card.grade}'));
    final first = tester.widget<Text>(counter).data!;
    expect(first, startsWith('1/'));
    final count = int.parse(first.split('/').last);
    expect(count, greaterThan(1));
    await tester.pump(const Duration(seconds: 11));
    expect(tester.widget<Text>(counter).data, first);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<Text>(counter).data, '2/$count');
    for (var i = 1; i < count; i++) {
      await tester.pump(const Duration(seconds: 12));
    }
    expect(tester.widget<Text>(counter).data, first);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'reading hover pauses paging and leaving starts a fresh interval',
    (tester) async {
      final card = groups(official('02')).last;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 390,
                child: JmaTsunamiListCard(group: card, scale: 1),
              ),
            ),
          ),
        ),
      );
      await waitForLayout(tester, card.grade);
      final counter = find.byKey(ValueKey('jma_tsunami_page_${card.grade}'));
      final first = tester.widget<Text>(counter).data!;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(700, 550));
      await mouse.moveTo(tester.getCenter(cellFor(card.grade)));
      await tester.pump(const Duration(seconds: 30));
      expect(tester.widget<Text>(counter).data, first);
      await mouse.moveTo(const Offset(700, 550));
      await tester.pump(const Duration(seconds: 11));
      expect(tester.widget<Text>(counter).data, first);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<Text>(counter).data, isNot(first));
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('arrival clocks use local hours and minutes only, source untouched', () {
    const clock = TsunamiMessage(source: TsunamiSource.jma);
    const raw = '2011-03-11T15:00:00+09:00';
    final local = DateTime.parse(raw).toLocal();
    expect(
      clock.formatLocalHourMinute(raw),
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}',
    );
    expect(clock.formatLocalHourMinute(''), '未知');
    final cards = groups(official('02'));
    expect(cards.first.rows.first.arrivalLabel, '到達と推測');
    expect(cards.first.rows.first.condition, '津波到達中と推測');
  });
  testWidgets(
    'left list shows tsunami without quake history and source toggle works',
    (tester) async {
      final provider = QuakeProvider(
            startCatalogServices: false,
            nativeUnifiedEvents: false,
          ),
          map = MapStateProvider();

      provider.jmaTsunamiListenable.value = groups(official('02'));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: provider),
            ChangeNotifierProvider.value(value: map),
          ],
          child: const MaterialApp(
            home: Scaffold(body: EqlistPanel(embedded: true)),
          ),
        ),
      );
      await waitForLayout(tester, 'majorWarning');
      expect(find.textContaining('JMA 大津波警報'), findsOneWidget);
      expect(find.text('暂无地震记录'), findsNothing);
      provider.toggleSource('jmaEqlist');
      await tester.pump();
      expect(find.textContaining('JMA 大津波警報'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
      map.dispose();
    },
  );
  testWidgets('save actual widget preview from original official warning', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(440, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final font = FontLoader('JmaPreview');
      font.addFont(
        Future.value(
          ByteData.sublistView(
            File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync(),
          ),
        ),
      );
      await font.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(
        Future.value(
          ByteData.sublistView(
            File(
              'D:/flutter_windows_3.41.1-stable/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytesSync(),
          ),
        ),
      );
      await icons.load();
    });
    final capture = GlobalKey(), cards = groups(official('02'));
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark().copyWith(
            textTheme: ThemeData.dark().textTheme.apply(
              fontFamily: 'JmaPreview',
            ),
          ),
          home: Scaffold(
            backgroundColor: const Color(0xFF17191B),
            body: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'JMA 官方样本 · 2011-03-11（非实时）',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                  for (final card in cards)
                    JmaTsunamiListCard(group: card, scale: 1),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    for (final card in cards) {
      await waitForLayout(tester, card.grade);
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image =
          await (capture.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final out = File(
        'tmp/jma_tsunami_left_list_20261019/left_list_official_sample.png',
      );
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
