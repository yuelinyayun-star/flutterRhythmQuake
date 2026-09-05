import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/volcano_event_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'package:provider/provider.dart';

void main() {
  for (final size in [const Size(900, 500), const Size(390, 844)]) {
    testWidgets('foreign eruption badge reuses volcano artwork at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      final provider = QuakeProvider();
      final mapState = MapStateProvider()..setShowEstimatedEpicenter(false);
      final event = UnifiedQuakeData(
        source: 'jmaEqlist',
        origin: 2,
        eventId: 'foreign_eruption_badge',
        isEew: false,
        timeZone: 9,
        titleText: '遠地噴火に関する情報',
        reportNumText: '',
        useShindo: true,
        maxIntensity: '不明',
        className: 'gray',
        hypocenter: 'カムチャツカ半島',
        originTime: now,
        reportTime: now,
        arrivedAt: now,
      );
      provider.handleUnifiedEventForTest(event);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<QuakeProvider>.value(value: provider),
            ChangeNotifierProvider<MapStateProvider>.value(value: mapState),
          ],
          child: const MaterialApp(home: Scaffold(body: AlertModule())),
        ),
      );
      await tester.pump();
      final image = tester.widget<Image>(
        find.byKey(const ValueKey('volcano_badge_icon')),
      );
      expect(
        (image.image as AssetImage).assetName,
        'assets/images/volcano/vol.png',
      );
      expect(find.text('噴火'), findsOneWidget);
      expect(event.volcanoEvent, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
      mapState.dispose();
      await tester.pump();
    });
  }

  testWidgets('compact volcano card reuses the map icon without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final now = DateTime.now();
    final provider = QuakeProvider();
    final mapState = MapStateProvider()..setShowEstimatedEpicenter(false);
    final event = UnifiedQuakeData(
      source: 'whews_va',
      origin: 9,
      eventId: 'VFVO53_card_test',
      isEew: false,
      timeZone: 9,
      titleText: '日本气象厅火山情报',
      reportNumText: '降灰预报（定时）',
      useShindo: false,
      maxIntensity: '-',
      className: 'yellow',
      hypocenter: '雌阿寒岳',
      originTime: now,
      reportTime: now,
      apiTypeLabel: 'WHEWS',
      arrivedAt: now,
      volcanoEvent: VolcanoEventData(
        updates: 1,
        kindCode: 'VFVO53',
        kindName: '降灰预报（定时）',
        infoKind: '降灰予報（定時）',
        infoTypeName: '発表',
        title: '雌阿寒岳 降灰予報（定時）',
        volcanoName: '雌阿寒岳',
        volcanoCode: '101',
        craterName: '',
        headline: '',
        activity: '',
        prevention: '',
        nextAdvisory: '',
        plumeDirection: '',
        observation: '',
        winds: const [],
        publishingOffice: '札幌管区気象台',
        reportTime: now,
        targetTime: now.add(const Duration(hours: 3)),
        ashfallWindows: [
          VolcanoAshfallWindow(
            label: '予報 ３時間後',
            startTime: now,
            endTime: now.add(const Duration(hours: 3)),
            items: const [
              VolcanoAshfallItem(
                phenomenon: '降灰',
                phenomenonCode: '70',
                areaNames: ['北海道釧路市', '北海道足寄町', '北海道白糠町'],
                areaCodes: ['01206', '01647', '01668'],
                plumeDirection: '',
                polygons: [],
              ),
            ],
          ),
        ],
      ),
    );
    provider.handleUnifiedEventForTest(event);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<QuakeProvider>.value(value: provider),
          ChangeNotifierProvider<MapStateProvider>.value(value: mapState),
        ],
        child: const MaterialApp(home: Scaffold(body: AlertModule())),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(
      find.byKey(const ValueKey('volcano_badge_icon')),
    );
    expect(image.image, isA<AssetImage>());
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/volcano/vol.png',
    );
    expect(find.text('予報 ３時間後：降灰 北海道釧路市、北海道足寄町'), findsOneWidget);
    expect(find.textContaining('WHEWS'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
    mapState.dispose();
    await tester.pump();
  });

  testWidgets('provisional volcano card uses Temp.png badge icon', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final now = DateTime.now();
    final provider = QuakeProvider();
    final mapState = MapStateProvider()..setShowEstimatedEpicenter(false);
    final event = UnifiedQuakeData(
      source: 'whews_va',
      origin: 9,
      eventId: 'VFVO51_503_test',
      isEew: false,
      timeZone: 9,
      titleText: '日本气象厅火山情报',
      reportNumText: '火山状况解说信息',
      useShindo: false,
      maxIntensity: '-',
      className: 'yellow',
      hypocenter: '阿蘇山',
      originTime: now,
      reportTime: now,
      apiTypeLabel: 'WHEWS',
      arrivedAt: now,
      volcanoEvent: VolcanoEventData(
        updates: 12,
        kindCode: 'VFVO51',
        kindName: '火山状况解说信息',
        infoKind: '火山の状況に関する解説情報（臨時）',
        infoTypeName: '発表',
        title: '阿蘇山 火山の状況に関する解説情報（臨時）',
        volcanoName: '阿蘇山',
        volcanoCode: '503',
        latitude: 32.88433,
        longitude: 131.10383,
        craterName: '',
        headline: '＜火口周辺警報（噴火警戒レベル２、火口周辺規制）が継続＞',
        activity: '',
        prevention: '',
        nextAdvisory: '',
        plumeDirection: '',
        observation: '',
        winds: const [],
        publishingOffice: '福岡管区気象台',
        reportTime: now,
      ),
    );
    provider.handleUnifiedEventForTest(event);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<QuakeProvider>.value(value: provider),
          ChangeNotifierProvider<MapStateProvider>.value(value: mapState),
        ],
        child: const MaterialApp(home: Scaffold(body: AlertModule())),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(
      find.byKey(const ValueKey('volcano_badge_icon')),
    );
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/volcano/Temp.png',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
    mapState.dispose();
    await tester.pump();
  });
}
