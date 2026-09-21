import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/volcano_event_data.dart';
import 'package:flutterrhythmquake/widgets/ui/volcano_sidebar_panel.dart';

void main() {
  test('selector follows the currently selected volcano event', () {
    final older = _event(eventId: 'old', arrivedAt: DateTime(2026, 8, 7, 10));
    final newer = _event(eventId: 'new', arrivedAt: DateTime(2026, 8, 7, 11));

    expect(selectVolcanoSidebarEvent([newer, older], 1)?.eventId, 'old');
  });

  test('selector falls back to the newest active volcano event', () {
    final older = _event(eventId: 'old', arrivedAt: DateTime(2026, 8, 7, 10));
    final newer = _event(eventId: 'new', arrivedAt: DateTime(2026, 8, 7, 11));
    const nonVolcano = UnifiedQuakeData(
      source: 'test',
      origin: 0,
      eventId: 'quake',
      isEew: false,
      timeZone: 8,
      titleText: '地震信息',
      reportNumText: '',
      useShindo: false,
      maxIntensity: '-',
      className: 'gray',
      hypocenter: '测试',
    );

    expect(
      selectVolcanoSidebarEvent([older, nonVolcano, newer], 1)?.eventId,
      'new',
    );
  });

  testWidgets('VFVO60 panel shows plume and wind source fields', (
    tester,
  ) async {
    final event = _event(
      eventId: 'VFVO60-1',
      volcano: _volcano(
        kindCode: 'VFVO60',
        kindName: '推定喷烟流向报',
        craterName: '南岳山顶火口',
        plumeDirection: '东北',
        plumeHeight: 1200,
        windTime: DateTime(2026, 8, 7, 12),
        winds: const [
          VolcanoWindProfile(heightFt: 5000, degree: 20, speedKt: 11),
        ],
      ),
    );

    await _pumpPanel(tester, event);

    final icon = tester.widget<Image>(
      find.byKey(const ValueKey('volcano_sidebar_icon')),
    );
    expect((icon.image as AssetImage).assetName, 'assets/images/volcano/vol.png');
    expect(find.byIcon(Icons.local_fire_department), findsNothing);
    expect(find.text('推定喷烟流向报'), findsOneWidget);
    expect(find.textContaining('火口：南岳山顶火口'), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -500),
    );
    await tester.pump();
    expect(find.textContaining('方向：东北'), findsOneWidget);
    expect(find.textContaining('火口上高度：1200 m'), findsOneWidget);
    expect(find.textContaining('风场时刻：2026-08-07 12:00:00 JST'), findsOneWidget);
    expect(find.text('5000 FT   020°   11 kt'), findsOneWidget);
  });

  testWidgets('ashfall panel shows windows, areas and polygon count', (
    tester,
  ) async {
    final event = _event(
      eventId: 'VFVO54-1',
      volcano: _volcano(
        kindCode: 'VFVO54',
        kindName: '快速降灰预报',
        ashfallWindows: [
          VolcanoAshfallWindow(
            label: '予報１時間後',
            startTime: DateTime.utc(2026, 8, 7, 3),
            endTime: DateTime.utc(2026, 8, 7, 4),
            items: const [
              VolcanoAshfallItem(
                phenomenon: '降灰',
                phenomenonCode: 'ashfall',
                areaNames: ['鹿児島市', '垂水市'],
                areaCodes: ['46201', '46214'],
                plumeDirection: '東',
                distanceKm: 30,
                sizeCm: 1,
                polygons: [
                  [
                    VolcanoAshfallCoordinate(latitude: 31.5, longitude: 130.5),
                    VolcanoAshfallCoordinate(latitude: 31.6, longitude: 130.6),
                    VolcanoAshfallCoordinate(latitude: 31.5, longitude: 130.7),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );

    await _pumpPanel(tester, event);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -800),
    );
    await tester.pump();

    expect(find.text('降灰预报'), findsOneWidget);
    expect(find.textContaining('时间窗：予報１時間後'), findsOneWidget);
    expect(find.textContaining('开始：2026-08-07 12:00:00 JST'), findsOneWidget);
    expect(find.textContaining('结束：2026-08-07 13:00:00 JST'), findsOneWidget);
    expect(find.textContaining('现象：降灰'), findsOneWidget);
    expect(find.textContaining('区域：鹿児島市、垂水市'), findsOneWidget);
    expect(find.textContaining('方向：東'), findsOneWidget);
    expect(find.textContaining('距离：30 km'), findsOneWidget);
    expect(find.textContaining('尺寸：1 cm'), findsOneWidget);
    expect(find.textContaining('多边形：1 个'), findsOneWidget);
  });

  testWidgets('missing values do not create placeholder or zero rows', (
    tester,
  ) async {
    final event = _event(
      eventId: '',
      volcano: _volcano(
        kindCode: 'VFVO50',
        kindName: '喷火警报',
        volcanoCode: '',
        craterName: '',
      ),
    );

    await _pumpPanel(tester, event);

    expect(find.textContaining('--'), findsNothing);
    expect(find.textContaining('第 0 报'), findsNothing);
    expect(find.textContaining('火山代码：'), findsNothing);
    expect(find.textContaining('火口：'), findsNothing);
  });
}

Future<void> _pumpPanel(WidgetTester tester, UnifiedQuakeData event) {
  return tester.pumpWidget(
    MaterialApp(
      home: SizedBox(
        width: 260,
        height: 430,
        child: VolcanoSidebarPanel(event: event, scale: (value) => value),
      ),
    ),
  );
}

UnifiedQuakeData _event({
  required String eventId,
  DateTime? arrivedAt,
  VolcanoEventData? volcano,
}) {
  final data = volcano ?? _volcano();
  return UnifiedQuakeData(
    source: 'whews_va',
    origin: 3,
    eventId: eventId,
    isEew: false,
    timeZone: 9,
    titleText: '日本气象厅火山情报',
    reportNumText: data.kindName,
    useShindo: false,
    maxIntensity: '',
    className: 'red',
    hypocenter: data.displayLocation,
    reportTime: data.reportTime,
    volcanoEvent: data,
    arrivedAt: arrivedAt,
  );
}

VolcanoEventData _volcano({
  String kindCode = 'VFVO52',
  String kindName = '喷发相关火山观测报',
  String volcanoCode = '506',
  String craterName = '南岳山顶火口',
  String plumeDirection = '',
  double? plumeHeight,
  DateTime? windTime,
  List<VolcanoWindProfile> winds = const [],
  List<VolcanoAshfallWindow> ashfallWindows = const [],
}) {
  return VolcanoEventData(
    updates: 2,
    kindCode: kindCode,
    kindName: kindName,
    infoKind: '噴火に関する火山観測報',
    infoTypeName: '発表',
    title: '火山名 桜島',
    volcanoName: '桜島',
    volcanoCode: volcanoCode,
    latitude: 31.5925,
    longitude: 130.6567,
    elevation: 1117,
    craterName: craterName,
    headline: '',
    activity: '',
    prevention: '',
    nextAdvisory: '',
    plumeDirection: plumeDirection,
    plumeHeight: plumeHeight,
    observation: '',
    reportTime: DateTime(2026, 8, 7, 12, 1),
    windTime: windTime,
    winds: winds,
    publishingOffice: '鹿児島地方気象台',
    ashfallWindows: ashfallWindows,
  );
}
