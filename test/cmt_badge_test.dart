import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/cmt_moment_tensor.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/widgets/map/fssn_cmt_layer.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'package:flutterrhythmquake/widgets/ui/cmt_badge.dart';
import 'package:flutterrhythmquake/widgets/ui/unified_alert_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Reuse the nodal-plane regression inputs in cenc_cmt_unified_test.dart.
UnifiedQuakeData _event(String source) => UnifiedQuakeData(
  source: source,
  origin: 0,
  eventId: 'cmt-badge-regression',
  isEew: false,
  timeZone: 8,
  titleText: 'CMT 震源机制解',
  reportNumText: '',
  useShindo: false,
  maxIntensity: '-',
  className: 'gray',
  hypocenter: 'CMT UI 回归检查',
  nodalPlane1: '112/66/102',
  nodalPlane2: '264/26/65',
);

class _CmtProvider extends QuakeProvider {
  _CmtProvider(UnifiedQuakeData event) : unifiedEvents = [event];

  @override
  final List<UnifiedQuakeData> unifiedEvents;

  void replace(UnifiedQuakeData event) {
    unifiedEvents[0] = event;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader('MPLUSRounded1c')
      ..addFont(rootBundle.load('assets/fonts/MPLUSRounded1c-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/MPLUSRounded1c-Bold.ttf'));
    await fonts.load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const captureKey = ValueKey('cmt_card_capture');

  Future<void> pumpModule(
    WidgetTester tester,
    _CmtProvider provider,
    Size viewport,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = viewport;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<QuakeProvider>(create: (_) => provider),
          ChangeNotifierProvider(create: (_) => MapStateProvider()),
        ],
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            fontFamily: 'MPLUSRounded1c',
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: captureKey,
                child: Container(
                  color: const Color(0xFF202020),
                  padding: const EdgeInsets.all(12),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [AlertModule()],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final size in [const Size(390, 844), const Size(1600, 900)]) {
    for (final source in [
      'fssnCmt',
      'cencCmt',
      'usgsCmt',
      'jmaCmt',
      'fnetCmt',
      'hinetAquaCmt',
    ]) {
      testWidgets('$source uses its mechanism badge at $size', (tester) async {
        final event = _event(source);
        await pumpModule(tester, _CmtProvider(event), size);
        expect(find.byType(CmtBadge), findsOneWidget);
        expect(find.byType(CmtBeachball), findsOneWidget);
        expect(find.text('烈度'), findsNothing);
        expect(find.text('震度'), findsNothing);
        final ball = tester.widget<CmtBeachball>(find.byType(CmtBeachball));
        expect(ball.nodalPlane, event.nodalPlane1);
        expect(ball.nodalPlane2, event.nodalPlane2);
        final badgeRect = tester.getRect(find.byType(CmtBadge));
        final ballRect = tester.getRect(find.byType(CmtBeachball));
        expect(badgeRect.contains(ballRect.topLeft), isTrue);
        expect(badgeRect.contains(ballRect.bottomRight), isTrue);
        expect(tester.takeException(), isNull);
        if (source == 'cencCmt' &&
            const bool.fromEnvironment('WRITE_CMT_BADGE_PREVIEW')) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(captureKey),
            );
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/cmt_badge_preview_${size.width.toInt()}.png',
            );
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('mechanism revision repaints without requiring a new event ID', (
    tester,
  ) async {
    final provider = _CmtProvider(_event('cencCmt'));
    await pumpModule(tester, provider, const Size(390, 844));
    final revised = _event('cencCmt').copyWith(nodalPlane1: '110/70/100');
    provider.replace(revised);
    await tester.pump();
    expect(
      tester.widget<CmtBeachball>(find.byType(CmtBeachball)).nodalPlane,
      revised.nodalPlane1,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ordinary earthquake badges are unchanged', (tester) async {
    await pumpModule(
      tester,
      _CmtProvider(_event('cencEqlist')),
      const Size(390, 844),
    );
    expect(find.byType(CmtBadge), findsNothing);
    expect(find.text('烈度'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final inputs in [
    <String, dynamic>{},
    {'nodalPlane1': 'invalid', 'nodalPlane2': '112/91/102'},
    {'nodalPlane2': '264/26/65'},
    {
      'momentTensor': const CmtMomentTensor(
        mnn: 1,
        mee: -1,
        mdd: 0,
        mne: 0,
        mnd: 0,
        med: 0,
      ).toMap(),
    },
  ]) {
    testWidgets('shared badge handles mechanism inputs $inputs', (
      tester,
    ) async {
      final raw = _event('cencCmt').toMap()
        ..remove('nodalPlane1')
        ..remove('nodalPlane2')
        ..remove('momentTensor')
        ..addAll(inputs);
      final event = UnifiedQuakeData.fromMap(raw);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: UnifiedAlertCard(event: event)),
        ),
      );
      final renderable =
          inputs.containsKey('momentTensor') ||
          inputs['nodalPlane2'] == '264/26/65';
      expect(
        find.byType(CmtBeachball),
        renderable ? findsOneWidget : findsNothing,
      );
      expect(find.text('CMT'), findsOneWidget);
      expect(find.text('烈度'), findsNothing);
      if (renderable) {
        final ball = tester.widget<CmtBeachball>(find.byType(CmtBeachball));
        expect(ball.momentTensor, same(event.momentTensor));
        expect(ball.nodalPlane2, event.nodalPlane2);
      } else {
        expect(find.text('--'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
