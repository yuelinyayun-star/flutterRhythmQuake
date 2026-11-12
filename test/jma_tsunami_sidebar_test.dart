import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/models/jma_tsunami_list.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:flutterrhythmquake/services/native_jma_tsunami.dart';
import 'package:flutterrhythmquake/widgets/ui/jma_tsunami_sidebar.dart';
import 'package:flutterrhythmquake/widgets/ui/jma_tsunami_list_card.dart';
import 'package:flutterrhythmquake/widgets/ui/eqlist_panel.dart';
import 'jma_tsunami_left_list_test.dart' as originalLeft;

class _CapturedHistoryProvider extends QuakeProvider {
  _CapturedHistoryProvider(this.rows)
    : super(startCatalogServices: false, nativeUnifiedEvents: false);
  final List<QuakeMessage> rows;
  @override
  List<QuakeMessage> get historyList => rows;
  @override
  Map<String, List<QuakeMessage>> get historyBySource => {'earlyEst': rows};
}

List<JmaTsunamiListGroup> protocolGroups(int count) => [
  // Explicit UI stress cases, not observations or messages injected into the app.
  JmaTsunamiListGroup.fromMap({
    'key': 'protocol-stations',
    'grade': 'observation',
    'label': '观测',
    'caption': 'JMA 津波情報',
    'className': 'blue',
    'reportNumber': 1,
    'reportTime': '2026-08-11 05:30:00',
    'headline': 'protocol bulletin',
    'regionCount': count,
    'rows': [
      for (var i = 0; i < count; i++)
        {
          'name': 'station $i',
          'regionName': '地域A',
          'stationCode': '$i',
          'height': '0.8m',
          'arrivalTime': '2026-08-11 05:25:00',
          'arrivalLabel': '',
          'condition': '',
          'secondary': [
            {'label': '第1波', 'time': '2026-08-11 05:20:00', 'text': '押し'},
          ],
          'details': [
            {'label': '仪器', 'time': '', 'text': 'ＧＮＳＳ波浪計'},
          ],
        },
    ],
  }),
];
Finder get viewport =>
    find.byKey(const ValueKey('jma_tsunami_sidebar_viewport'));
Finder get page => find.byKey(const ValueKey('jma_tsunami_sidebar_page'));
Finder get rowLines => find.byWidgetPredicate(
  (w) =>
      w is Row &&
      w.key is ValueKey<String> &&
      (w.key as ValueKey<String>).value.startsWith('jma_tsunami_sidebar_line_'),
);
Finder get stationCells => find.byWidgetPredicate(
  (w) =>
      w is Container &&
      w.key is ValueKey<String> &&
      (w.key as ValueKey<String>).value.startsWith('jma_tsunami_cell_'),
);
Future<void> ready(WidgetTester tester, {Finder? target}) async {
  for (var i = 0; i < 150; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if ((target ?? viewport).evaluate().isNotEmpty) return;
    if (tester.takeException() case final Object error) throw error;
  }
  fail('Native sidebar did not finish');
}

Future<void> build(
  WidgetTester tester,
  List<JmaTsunamiListGroup> groups, {
  Size screen = const Size(1700, 1000),
  double width = 420,
  double height = 440,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: screen,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: JmaTsunamiSidebar(
                  groups: groups,
                  scale: 1,
                  maxHeight: height,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await ready(tester);
}

void main() {
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
  testWidgets('original source examples show region and station together', (
    tester,
  ) async {
    final fixtureRoot = 'test/fixtures/jma_tsunami';
    final forecast =
        jsonDecode(
              File(
                '$fixtureRoot/whews.forecast_stations.documented.json',
              ).readAsStringSync(),
            )
            as Map;
    final observation =
        jsonDecode(
              '{${File('$fixtureRoot/whews.observations.documented.fragment.txt').readAsStringSync()}}',
            )
            as Map;
    final originals = [jsonEncode(forecast), jsonEncode(observation)];
    final groups = <JmaTsunamiListGroup>[];
    await tester.runAsync(() async {
      for (final payload in [forecast['Data'], observation]) {
        final parsed = await NativeJmaTsunami.prepareAsync({
          'op': 'parse',
          'transport': 'whews',
          'payload': payload,
        });
        final view = await NativeJmaTsunami.prepareAsync({
          'op': 'project',
          'message': parsed,
          'nowMs': 0,
        });
        groups.addAll([
          for (final value in view['groups'] as List)
            JmaTsunamiListGroup.fromMap(value as Map),
        ]);
      }
    });
    await build(tester, groups, height: 550);
    expect(find.text('有明・八代海'), findsOneWidget);
    expect(find.text('岩手県'), findsOneWidget);
    expect(find.text('大牟田市三池'), findsNothing);
    expect(find.text('岩手山田沖'), findsNothing);
    expect(find.byType(Tooltip), findsNothing);
    expect(find.text('0.8m'), findsOneWidget);
    expect(find.text('1m'), findsOneWidget);
    expect(find.text('实测'), findsNWidgets(2));
    expect(find.text('预计'), findsNWidgets(2));
    expect(find.textContaining('第1波 '), findsNothing);
    expect(find.textContaining('满潮 '), findsNothing);
    for (final cell in tester.widgetList<Container>(stationCells)) {
      expect(cell.decoration, isNull);
      expect(cell.padding, isNull);
    }
    await tester.tap(find.text('岩手県'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第1波 '), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect([jsonEncode(forecast), jsonEncode(observation)], originals);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final phone in [false, true]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        '${phone ? 'phone' : 'desktop'} UI uses ${phone ? 1 : 2} cells per row at text scale $textScale',
        (tester) async {
          await build(
            tester,
            protocolGroups(20),
            screen: phone ? const Size(390, 850) : const Size(1700, 1000),
            width: phone ? 390 : 420,
            height: 440,
            textScale: textScale,
          );
          expect(rowLines, findsWidgets);
          for (final row in tester.widgetList<Row>(rowLines)) {
            expect(row.children.whereType<Expanded>().length, phone ? 1 : 2);
          }
          expect(tester.getSize(viewport).height, lessThanOrEqualTo(440));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
  testWidgets(
    'right sidebar fits the captured 203.5 by 194.5 viewport without overflow',
    (tester) async {
      await build(tester, protocolGroups(30), width: 203.5, height: 194.5);
      expect(tester.getSize(viewport).height, 194.5);
      expect(tester.takeException(), isNull);
      final first = tester.widget<Text>(page).data;
      await tester.pump(const Duration(seconds: 12));
      expect(tester.widget<Text>(page).data, isNot(first));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'more available height fits more rows; resize rebuilds measured pages',
    (tester) async {
      final groups = protocolGroups(40);
      await build(tester, groups, height: 250);
      final small = rowLines.evaluate().length;
      await build(tester, groups, height: 500);
      expect(rowLines.evaluate().length, greaterThan(small));
      expect(tester.getSize(viewport).height, lessThanOrEqualTo(500));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'shared page changes at twelve seconds, hover and reading pause it',
    (tester) async {
      await build(tester, protocolGroups(30), height: 320);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(790, 590));
      final first = tester.widget<Text>(page).data;
      await tester.pump(const Duration(seconds: 11));
      expect(tester.widget<Text>(page).data, first);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<Text>(page).data, isNot(first));
      await mouse.moveTo(const Offset(40, 40));
      final hovered = tester.widget<Text>(page).data;
      await tester.pump(const Duration(seconds: 24));
      expect(tester.widget<Text>(page).data, hovered);
      await mouse.moveTo(const Offset(790, 590));
      await tester.tap(
        find.byKey(const ValueKey('jma_tsunami_sidebar_bulletin')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('protocol bulletin'), findsWidgets);
      await tester.pump(const Duration(seconds: 24));
      expect(tester.widget<Text>(page).data, hovered);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 12));
      expect(tester.widget<Text>(page).data, isNot(hovered));
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('single page shrinks naturally so history can follow below', (
    tester,
  ) async {
    await build(tester, protocolGroups(1), height: 500);
    expect(stationCells, findsOneWidget);
    expect(tester.getSize(viewport).height, lessThan(500));
    expect(tester.widget<Text>(page).data, '1/1');
    await tester.pump(const Duration(seconds: 24));
    expect(tester.widget<Text>(page).data, '1/1');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'left information list retains the original grade cards before scrolling history',
    (tester) async {
      final originals =
          jsonDecode(
                File(
                  'test/fixtures/early_est_history_20261009.original.json',
                ).readAsStringSync(),
              )
              as List;
      final rows = [
        for (final raw in originals)
          QuakeMessage.fromMap(Map<String, dynamic>.from(raw as Map)),
      ];
      final provider = _CapturedHistoryProvider(rows), map = MapStateProvider();
      final originalForecast = originalLeft
          .groups(originalLeft.official('02'))
          .first;
      provider.jmaTsunamiListenable.value = [
        originalForecast,
        ...protocolGroups(30),
      ];
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<QuakeProvider>.value(value: provider),
            ChangeNotifierProvider<MapStateProvider>.value(value: map),
          ],
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(size: Size(1700, 1000)),
              child: const Scaffold(
                body: SizedBox(
                  width: 420,
                  height: 250,
                  child: EqlistPanel(embedded: true),
                ),
              ),
            ),
          ),
        ),
      );
      await ready(
        tester,
        target: find.byKey(
          ValueKey('jma_tsunami_page_${originalForecast.grade}'),
        ),
      );
      expect(find.byType(JmaTsunamiSidebar), findsNothing);
      final oldCard = find.byType(JmaTsunamiListCard);
      expect(oldCard, findsOneWidget);
      expect(
        tester.widget<JmaTsunamiListCard>(oldCard).group,
        same(originalForecast),
      );
      final list = find.byType(ListView), top = tester.getTopLeft(oldCard).dy;
      expect(
        tester.widget<ListView>(list).childrenDelegate.estimatedChildCount,
        rows.length + 1,
      );
      await tester.drag(list, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(oldCard).dy, lessThan(top - 1));
      expect(
        find
            .byKey(
              ValueKey(
                'catalog_${rows.first.source.name}_${rows.first.eventId}',
              ),
            )
            .hitTestable(),
        findsOneWidget,
      );
      await tester.drag(list, const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(oldCard).dy, closeTo(top, 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
      map.dispose();
    },
  );
}
