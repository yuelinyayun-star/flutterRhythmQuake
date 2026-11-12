import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/models/jma_lpgm_bulletin.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/services/native_jma_eew.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'package:flutterrhythmquake/widgets/ui/unified_alert_card.dart';
import 'package:flutterrhythmquake/widgets/ui/jma_eew_long_period_footer.dart';
import 'support/unified_ui_fonts.dart';
import 'unified_card_layout_test.dart' show capturedCards;

Map<String, dynamic> readOriginal(String path) =>
    jsonDecode(File(path).readAsStringSync(encoding: utf8))
        as Map<String, dynamic>;
final jianRaw =
    readOriginal(
          'test/fixtures/jma_plum_20261106/jian_documented_non_plum.json',
        )['Data']
        as Map<String, dynamic>;
final whewsRaw =
    readOriginal(
          'test/fixtures/jma_eew_long_period_20261106/whews_documented.json',
        )['Data']
        as Map<String, dynamic>;
UnifiedQuakeData jian() => QuakeEventAdapter.convertJian('jma-eew', jianRaw)!;
UnifiedQuakeData whews() =>
    QuakeEventAdapter.convertWhews('jma_eew', whewsRaw)!;

class _Cards extends QuakeProvider {
  _Cards() : super(startCatalogServices: false);
  UnifiedQuakeData? shown;
  @override
  List<UnifiedQuakeData> get unifiedEvents => [?shown];
  @override
  UnifiedQuakeData? get mobileCameraDisplayEvent => shown;
  void show(UnifiedQuakeData event) {
    shown = event;
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
    'original two API examples retain all data through handoff and expose predicted classes',
    () {
      if (Platform.environment.containsKey('RQ_STATION_CORE_LIBRARY')) {
        expect(NativeJmaEew.supported, isTrue);
      }
      for (final pair in [(jian(), jianRaw, 1), (whews(), whewsRaw, 2)]) {
        final (event, original, level) = pair;
        final before = jsonEncode(event.toMap());
        expect(event.eewLongPeriodClass, level);
        expect(event.sourcePayload, original);
        expect(
          UnifiedQuakeData.fromMap(event.toMap()).eewLongPeriodClass,
          level,
        );
        expect(event.copyWith(apiTypeLabel: '回放').eewLongPeriodClass, level);
        expect(jsonEncode(event.toMap()), before);
      }
      // Real captured WHEWS report supplies class 0, rather than missing data.
      final rows =
          jsonDecode(
                File(
                  'test/fixtures/catalog_20260917/whews_all.json',
                ).readAsStringSync(encoding: utf8),
              )
              as List;
      final raw =
          rows.cast<Map>().firstWhere((r) => r['source'] == 'jma_eew')['Data']
              as Map;
      expect(
        QuakeEventAdapter.convertWhews(
          'jma_eew',
          Map<String, dynamic>.from(raw),
        )!.eewLongPeriodClass,
        isNull,
      );
    },
  );

  test(
    'class decoding separates absent from zero and cannot affect other products',
    () {
      // Protocol scalar cases; no captured report is edited or injected.
      for (var level = 0; level <= 4; level++) {
        expect(
          NativeJmaEew.longPeriodClass(
            source: 'jmaEew',
            isEew: true,
            value: '$level',
          ),
          level,
        );
      }
      for (final value in [
        null,
        '',
        '不明',
        'NaN',
        -1,
        5,
        2.5,
        true,
        <String, int>{'value': 3},
      ]) {
        expect(
          NativeJmaEew.longPeriodClass(
            source: 'jmaEew',
            isEew: true,
            value: value,
          ),
          isNull,
        );
      }
      for (final source in ['cwaEew', 'jmaEqlist', 'p2pJmaEqlist', 'ceaEew']) {
        expect(
          NativeJmaEew.longPeriodClass(source: source, isEew: true, value: '3'),
          isNull,
        );
      }
      expect(
        NativeJmaEew.longPeriodClass(
          source: 'jmaEew',
          isEew: false,
          value: '3',
        ),
        isNull,
      );
      expect(
        jian().copyWith(source: 'jmaEqlist', isEew: false).eewLongPeriodClass,
        isNull,
      );
    },
  );

  for (final width in [390.0, 1700.0]) {
    testWidgets(
      'only bottom badge area changes at width $width; missing and other products keep prior label',
      (tester) async {
        await tester.runAsync(loadUnifiedUiFonts);
        tester.view.physicalSize = Size(width, 650);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final provider = _Cards();
        final state = MapStateProvider()..setShowEstimatedEpicenter(false);
        for (final event in [
          jian(),
          whews(),
          capturedCards()['WHEWS jma']!,
          capturedCards()['Jian cea']!,
        ]) {
          final before = jsonEncode(event.toMap());
          provider.show(event);
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<QuakeProvider>.value(value: provider),
                ChangeNotifierProvider<MapStateProvider>.value(value: state),
              ],
              child: MaterialApp(
                theme: unifiedUiTestTheme(),
                home: const Scaffold(body: AlertModule()),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          final level = event.eewLongPeriodClass;
          if (level == null) {
            expect(find.byType(JmaEewLongPeriodFooter), findsNothing);
          } else {
            final footer = find.byType(JmaEewLongPeriodFooter);
            expect(footer, findsOneWidget);
            expect(find.text('长周期 $level'), findsOneWidget);
            final footerLabel = tester.widget<Text>(find.text('长周期 $level'));
            expect(footerLabel.style!.color, Colors.white);
            final footerRect = tester.getRect(footer);
            final main = find.text(event.maxIntensity.substring(0, 1)).first;
            expect(
              tester.getRect(main).bottom,
              lessThanOrEqualTo(footerRect.top + .1),
            );
            final footerBox = tester.widget<Container>(
              find.byKey(const ValueKey('jma-eew-long-period-footer')),
            );
            expect(
              (footerBox.decoration as BoxDecoration).color,
              jmaLpgmClassColor(level).withValues(alpha: .28),
            );
            // The unchanged upper number and badge border retain the ordinary intensity color.
            final text = tester.widget<Text>(main);
            final ancestor = find
                .ancestor(of: main, matching: find.byType(Container))
                .evaluate()
                .map((e) => e.widget)
                .whereType<Container>()
                .firstWhere(
                  (c) =>
                      c.decoration is BoxDecoration &&
                      (c.decoration as BoxDecoration).border != null,
                );
            final decoration = ancestor.decoration as BoxDecoration;
            expect(decoration.color, text.style!.color!.withValues(alpha: .12));
            expect(
              (decoration.border as Border).top.color,
              text.style!.color!.withValues(alpha: .3),
            );
            expect(
              footerRect.height,
              lessThan(tester.getRect(find.byWidget(ancestor)).height * .3),
            );
          }
          expect(jsonEncode(event.toMap()), before);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        provider.dispose();
        state.dispose();
        await tester.pump(const Duration(seconds: 1));
      },
    );
  }

  testWidgets('render original JIAN/WHEWS examples and footer-only palette', (
    tester,
  ) async {
    await tester.runAsync(loadUnifiedUiFonts);
    tester.view.physicalSize = const Size(1200, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = MapStateProvider()..setShowEstimatedEpicenter(false);
    final providers = [_Cards()..show(jian()), _Cards()..show(whews())];
    await tester.pumpWidget(
      ChangeNotifierProvider<MapStateProvider>.value(
        value: state,
        child: MaterialApp(
          theme: unifiedUiTestTheme(),
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey('long-period-preview'),
              child: ColoredBox(
                color: const Color(0xff202124),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'JMA EEW · 长周期徽章（上游文档原报文）',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < 2; i++)
                            Expanded(
                              child:
                                  ChangeNotifierProvider<QuakeProvider>.value(
                                    value: providers[i],
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          i == 0
                                              ? 'JIAN：震度 2 / 长周期 1'
                                              : 'WHEWS：震度 6+ / 长周期 2',
                                        ),
                                        const SizedBox(height: 8),
                                        const AlertModule(),
                                        const SizedBox(height: 12),
                                        UnifiedAlertCard(
                                          event: providers[i].shown!,
                                        ),
                                      ],
                                    ),
                                  ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      const Text('底部区域配色示意（0–4）'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (var level = 0; level <= 4; level++)
                            Padding(
                              padding: const EdgeInsets.only(right: 14),
                              child: SizedBox(
                                width: 90,
                                child: JmaEewLongPeriodFooter(
                                  level: level,
                                  height: 24,
                                  radius: 8,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('long-period-preview')),
          )
          .toImage(pixelRatio: 1.5);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          'tmp/jma_eew_long_period_badge_20261106/preview.png',
        ).writeAsBytesSync(data!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
    await tester.pumpWidget(const SizedBox.shrink());
    for (final p in providers) {
      p.dispose();
    }
    state.dispose();
    await tester.pump(const Duration(seconds: 1));
  });
}
