import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/volcano_icon_assets.dart';
import 'package:flutterrhythmquake/models/jma_volcano_site.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/volcano_event_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:flutterrhythmquake/services/sources/jma_volcano_map_service.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'package:flutterrhythmquake/widgets/ui/volcano_sidebar_panel.dart';
import 'package:provider/provider.dart';

// Fields from the reported VFVO52 bulletin and JMA's standing warning for 506.
final _observation = VolcanoEventData.fromMap({
  'kindCode': 'VFVO52',
  'kindName': '喷发相关火山观测报',
  'infoKind': '噴火に関する火山観測報',
  'infoTypeName': '発表',
  'volcanoCode': '506',
  'volcanoName': '桜島',
  'craterName': '南岳山頂火口',
  'reportTime': '2026-09-20T22:46:00',
});

JmaVolcanoSite _site({
  String code = '506',
  int level = 3,
  String warningTime = '2022-07-27T20:00:00+09:00',
}) => JmaVolcanoSite(
  code: code,
  nameJp: '桜島',
  nameEn: 'Sakurajima',
  latitude: 31.5925,
  longitude: 130.6567,
  levelOperation: true,
  alertLevel: level,
  hasWarning: true,
  hasRecentInfo: false,
  hasRecentEruption: false,
  warningReportTime: DateTime.parse(warningTime),
);

void main() {
  test(
    'VFVO52 inherits standing Lv3 without changing the original bulletin',
    () {
      final raw = _observation.toMap();
      expect(_observation.parsedAlertLevel, isNull);
      final level = VolcanoIconAssets.levelForVolcanoEvent(
        _observation,
        officialSite: _site(),
      );
      expect(level, 3);
      expect(
        VolcanoIconAssets.forVolcanoEvent(_observation, officialSite: _site()),
        VolcanoIconAssets.forSite(_site().copyWith(alertLevel: level)),
      );
      expect(_observation.toMap(), raw);
      expect(_observation.parsedAlertLevel, isNull);
    },
  );

  test('unknown and mismatched volcano codes never inherit another level', () {
    expect(
      VolcanoIconAssets.forVolcanoEvent(_observation),
      VolcanoIconAssets.generic,
    );
    for (final code in ['', '503']) {
      expect(
        VolcanoIconAssets.forVolcanoEvent(
          _observation,
          officialSite: _site(code: code),
        ),
        VolcanoIconAssets.generic,
      );
    }
    final noCode = VolcanoEventData.fromMap({
      ..._observation.toMap(),
      'volcanoCode': '',
    });
    expect(
      VolcanoIconAssets.forVolcanoEvent(noCode, officialSite: _site()),
      VolcanoIconAssets.generic,
    );
  });

  test('a newer explicit level can downgrade the standing level', () {
    final report = VolcanoEventData.fromMap({
      ..._observation.toMap(),
      'headline': '噴火警戒レベル２',
    });
    expect(
      VolcanoIconAssets.levelForVolcanoEvent(report, officialSite: _site()),
      2,
    );
  });

  test(
    'official changes supersede older bulletin levels using JST instants',
    () {
      final report = VolcanoEventData.fromMap({
        ..._observation.toMap(),
        'headline': '噴火警戒レベル４',
      });
      expect(
        VolcanoIconAssets.levelForVolcanoEvent(
          report,
          officialSite: _site(warningTime: '2026-09-20T22:47:00+09:00'),
        ),
        3,
      );
      expect(
        VolcanoIconAssets.levelForVolcanoEvent(
          report,
          officialSite: _site(warningTime: '2026-09-20T22:45:00+09:00'),
        ),
        4,
      );
    },
  );

  test('cancellation does not replace the standing warning level', () {
    final report = VolcanoEventData.fromMap({
      ..._observation.toMap(),
      'headline': '噴火警戒レベル５',
      'infoTypeName': '取消',
    });
    expect(
      VolcanoIconAssets.levelForVolcanoEvent(report, officialSite: _site()),
      3,
    );
  });

  test(
    'a failed warning refresh retains the last successful official level',
    () async {
      var failWarning = false;
      var clearWarning = false;
      final service = JmaVolcanoMapService.forTesting((url) async {
        if (url.contains('volcano_list')) {
          return [
            {
              'code': '506',
              'latlon': ['31.5925', '130.6567'],
              'name_jp': '桜島',
              'name_en': 'Sakurajima',
              'levelOperation': true,
            },
          ];
        }
        if (url.contains('warning')) {
          if (failWarning) throw Exception('warning unavailable');
          if (clearWarning) return [];
          return [
            {
              'eventId': '506',
              'reportDatetime': '2022-07-27T20:00:00+09:00',
              'volcanoInfos': [
                {
                  'type': '噴火警報・予報（対象火山）',
                  'items': [
                    {
                      'name': 'レベル３（入山規制）',
                      'code': '13',
                      'lastCode': '15',
                      'areas': [
                        {'name': '桜島', 'code': '506'},
                      ],
                    },
                  ],
                },
              ],
            },
          ];
        }
        return [];
      });
      addTearDown(service.dispose);
      var notifications = 0;
      service.addListener(() => notifications++);
      await service.fetchNow();
      expect(service.siteForCode('506')?.alertLevel, 3);
      failWarning = true;
      await service.fetchNow();
      expect(service.siteForCode('506')?.alertLevel, 3);
      expect(notifications, 2);
      expect(service.siteForCode(''), isNull);
      expect(service.siteForCode('503'), isNull);
      service.acceptSitesSnapshot([
        _site(level: 2, warningTime: '2026-09-20T22:47:00+09:00'),
      ]);
      await service.fetchNow();
      expect(service.siteForCode('506')?.alertLevel, 2);
      expect(notifications, 4);
      failWarning = false;
      clearWarning = true;
      await service.fetchNow();
      expect(service.siteForCode('506')?.alertLevel, 0);
    },
  );

  for (final size in [const Size(900, 600), const Size(390, 844)]) {
    testWidgets(
      'card and sidebar react to a hosted warning with overlay off at $size',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final service = JmaVolcanoMapService();
        final previousSites = service.sites;
        service.acceptSitesSnapshot([]);
        addTearDown(() => service.acceptSitesSnapshot(previousSites));
        final provider = QuakeProvider();
        final mapState = MapStateProvider()..setShowEstimatedEpicenter(false);
        mapState.setOverlayEnabled('volcanoLayer', false);
        final now = DateTime.now();
        final event = UnifiedQuakeData(
          source: 'whews_va',
          origin: 9,
          eventId: 'VFVO52_20260920224600_506',
          isEew: false,
          timeZone: 9,
          titleText: '日本气象厅火山情报',
          reportNumText: '喷发相关火山观测报',
          useShindo: false,
          maxIntensity: '',
          className: 'red',
          hypocenter: '桜島 南岳山頂火口',
          originTime: now,
          reportTime: now,
          arrivedAt: now,
          volcanoEvent: _observation,
        );
        provider.handleUnifiedEventForTest(event);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<QuakeProvider>.value(value: provider),
              ChangeNotifierProvider<MapStateProvider>.value(value: mapState),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    const AlertModule(),
                    Expanded(
                      child: VolcanoSidebarPanel(event: event, scale: (n) => n),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        String asset(String key) =>
            (tester.widget<Image>(find.byKey(ValueKey(key))).image
                    as AssetImage)
                .assetName;
        expect(asset('volcano_badge_icon'), VolcanoIconAssets.generic);
        expect(asset('volcano_sidebar_icon'), VolcanoIconAssets.generic);

        final payload = ForegroundStationPayload.volcanoSites([_site()]);
        service.acceptSitesSnapshot(
          ForegroundStationPayload.decodeVolcanoSites(payload['sites']),
        );
        await tester.pump();
        expect(asset('volcano_badge_icon'), VolcanoIconAssets.forLevel(3));
        expect(asset('volcano_sidebar_icon'), VolcanoIconAssets.forLevel(3));
        expect(mapState.isOverlayEnabled('volcanoLayer'), isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        provider.dispose();
        mapState.dispose();
        await tester.pump();
      },
    );
  }
}
