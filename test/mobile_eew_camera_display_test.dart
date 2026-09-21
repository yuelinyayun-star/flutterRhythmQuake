import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/volcano_event_data.dart';
import 'package:flutterrhythmquake/widgets/map/desktop_event_camera_focus.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

UnifiedQuakeData event(String id, {bool eew = true, String source = 'cea'}) {
  final now = DateTime.now().toUtc();
  return UnifiedQuakeData(
    source: source,
    origin: 0,
    eventId: id,
    isEew: eew,
    timeZone: 0,
    titleText: eew ? '地震预警' : '地震信息',
    reportNumText: '第1报',
    useShindo: false,
    maxIntensity: '3',
    className: 'orange',
    hypocenter: id,
    originTime: now,
    reportTime: now,
    magnitude: 5,
    depth: 10,
    depthText: '10km',
    lat: source == 'cea' ? 30 : 37,
    lng: source == 'cea' ? 105 : 142,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
  });
  tearDown(() => SoundEffectService().enabled = true);

  Future<QuakeProvider> mount(WidgetTester tester, {bool phone = true}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = phone
        ? const Size(390, 844)
        : const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = QuakeProvider()..configureMobileEewCarousel(phone);
    final map = MapStateProvider();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<QuakeProvider>(create: (_) => provider),
          ChangeNotifierProvider<MapStateProvider>(create: (_) => map),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: AlertModule())),
        ),
      ),
    );
    await tester.pump();
    return provider;
  }

  testWidgets(
    'phone rotates only EEW and card follows the shared camera index',
    (tester) async {
      final provider = await mount(tester);
      provider.handleUnifiedEventForTest(event('EEW-A'));
      provider.handleUnifiedEventForTest(
        event('INFO', eew: false, source: 'emscEqlist'),
      );
      await tester.pump();
      expect(provider.unifiedEvents, hasLength(2));
      expect(find.text('EEW-A'), findsOneWidget);
      expect(find.text('INFO'), findsNothing);
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('EEW-A'), findsOneWidget);
      expect(find.text('INFO'), findsNothing);
      provider.handleUnifiedEventForTest(event('EEW-B', source: 'jma'));
      await tester.pump();
      expect(provider.unifiedEvents, hasLength(3));
      for (var i = 0; i < 4; i++) {
        expect(provider.currentUnifiedEvent!.isEew, isTrue);
        expect(
          find.text(provider.currentUnifiedEvent!.hypocenter),
          findsOneWidget,
        );
        expect(find.text('INFO'), findsNothing);
        expect(
          find.text('${provider.currentUnifiedIndex + 1}/2'),
          findsOneWidget,
        );
        final previous = provider.currentUnifiedEvent!.eventId;
        await tester.pump(const Duration(seconds: 5));
        expect(provider.currentUnifiedEvent!.eventId, isNot(previous));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final phone in [false, true]) {
    testWidgets('earthquake and volcano share the carousel, phone=$phone', (
      tester,
    ) async {
      final provider = await mount(tester, phone: phone);
      provider.handleUnifiedEventForTest(event('INFO', eew: false));
      final eruption = event('VOLCANO', eew: false, source: 'whews_va')
          .copyWith(
            magnitude: -1,
            depth: -1,
            volcanoEvent: VolcanoEventData.fromMap(const {
              'kindCode': 'VFVO52',
              'volcanoName': '桜島',
              'volcanoCode': '506',
              'latitude': 31.5925,
              'longitude': 130.6567,
            }),
          );
      provider.handleUnifiedEventForTest(eruption);
      await tester.pump();
      expect(provider.unifiedEventCount, 2);
      final selector = DesktopEventCameraFocus();
      final visited = <bool>{};
      for (var i = 0; i < 4; i++) {
        final current = provider.currentUnifiedEvent!;
        visited.add(current.isVolcanoEvent);
        final candidates = [
          for (var index = 0; index < provider.unifiedEvents.length; index++)
            DesktopCameraCandidate.fromEvent(
              provider.unifiedEvents[index],
              index: index,
            )!,
        ];
        final target = selector.select(
          candidates: candidates,
          requestedIndex: provider.currentUnifiedIndex,
          isVisible: (_) => false,
        )!;
        expect(target.isVolcano, current.isVolcanoEvent);
        if (phone) {
          expect(
            find.text(current.isVolcanoEvent ? '桜島' : 'INFO'),
            findsOneWidget,
          );
        }
        await tester.pump(const Duration(seconds: 5));
        expect(provider.currentUnifiedEvent!.eventId, isNot(current.eventId));
      }
      expect(visited, {false, true});
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('camera info focus overrides EEW carousel only while active', (
    tester,
  ) async {
    final provider = await mount(tester);
    final info = event('INFO', eew: false, source: 'emscEqlist');
    provider.handleUnifiedEventForTest(event('EEW-A'));
    provider.handleUnifiedEventForTest(event('EEW-B', source: 'jma'));
    provider.handleUnifiedEventForTest(info);
    provider.setMobileCameraInfoFocus(info);
    await tester.pump();
    expect(find.text('INFO'), findsOneWidget);
    expect(find.text('1/2'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('INFO'), findsOneWidget);
    expect(provider.currentUnifiedEvent!.isEew, isTrue);
    provider.setMobileCameraInfoFocus(null);
    await tester.pump();
    expect(find.text('INFO'), findsNothing);
    expect(find.text(provider.currentUnifiedEvent!.hypocenter), findsOneWidget);
    provider.setMobileCameraInfoFocus(info);
    provider.dismissUnifiedEventForTest(info);
    await tester.pump();
    expect(find.text('INFO'), findsNothing);
    expect(find.text(provider.currentUnifiedEvent!.hypocenter), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'new EEW takes over info focus and no EEW restores information cards',
    (tester) async {
      final provider = await mount(tester);
      final a = event('EEW-A');
      final b = event('EEW-B', source: 'jma');
      final info = event('INFO', eew: false, source: 'emscEqlist');
      provider.handleUnifiedEventForTest(a);
      provider.handleUnifiedEventForTest(info);
      provider.setMobileCameraInfoFocus(info);
      await tester.pump();
      expect(find.text('INFO'), findsOneWidget);
      provider.handleUnifiedEventForTest(b);
      await tester.pump();
      expect(find.text('EEW-B'), findsOneWidget);
      expect(find.text('INFO'), findsNothing);
      provider.dismissUnifiedEventForTest(a);
      provider.dismissUnifiedEventForTest(b);
      await tester.pump();
      expect(find.text('INFO'), findsOneWidget);
      expect(provider.mobileEewDisplayEvent, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('desktop retains information cards and mixed event carousel', (
    tester,
  ) async {
    final provider = await mount(tester, phone: false);
    final info = event('INFO', eew: false, source: 'emscEqlist');
    provider.handleUnifiedEventForTest(event('EEW-A'));
    provider.handleUnifiedEventForTest(info);
    provider.setMobileCameraInfoFocus(info);
    await tester.pump();
    expect(find.text('EEW-A'), findsOneWidget);
    expect(find.text('INFO'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(provider.currentUnifiedEvent!.isEew, isFalse);
    expect(find.text('EEW-A'), findsOneWidget);
    expect(find.text('INFO'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'phone information cards use the map carousel index without EEW',
    (tester) async {
      final provider = await mount(tester);
      provider.handleUnifiedEventForTest(
        event('INFO-A', eew: false, source: 'emscEqlist'),
      );
      await tester.pump(const Duration(seconds: 2));
      provider.handleUnifiedEventForTest(
        event('INFO-B', eew: false, source: 'jma'),
      );
      await tester.pump();
      expect(provider.unifiedEvents, hasLength(2));
      for (var i = 0; i < 4; i++) {
        provider.nextUnified();
        await tester.pump();
        final selected = provider.currentUnifiedEvent!;
        expect(find.text(selected.hypocenter), findsOneWidget);
        expect(
          find.text('${provider.currentUnifiedIndex + 1}/2'),
          findsOneWidget,
        );
        final other = provider.unifiedEvents.firstWhere(
          (e) => e.eventId != selected.eventId,
        );
        expect(find.text(other.hypocenter), findsNothing);
        await tester.pump(const Duration(milliseconds: 1100));
        expect(
          find.text(provider.currentUnifiedEvent!.hypocenter),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'information area focus holds its card across rotation and expires',
    (tester) async {
      final provider = await mount(tester);
      final area = event('AREA-INFO', eew: false, source: 'jma');
      final other = event('OTHER-INFO', eew: false, source: 'emscEqlist');
      provider.handleUnifiedEventForTest(area);
      provider.handleUnifiedEventForTest(other);
      provider.setMobileCameraInfoFocus(area);
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        expect(find.text('AREA-INFO'), findsOneWidget);
        expect(find.text('OTHER-INFO'), findsNothing);
        await tester.pump(const Duration(seconds: 5));
      }
      provider.setMobileCameraInfoFocus(other);
      await tester.pump();
      expect(find.text('OTHER-INFO'), findsOneWidget);
      expect(find.text('AREA-INFO'), findsNothing);
      provider.dismissUnifiedEventForTest(other);
      await tester.pump();
      expect(find.text('AREA-INFO'), findsOneWidget);
      expect(find.text('OTHER-INFO'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
