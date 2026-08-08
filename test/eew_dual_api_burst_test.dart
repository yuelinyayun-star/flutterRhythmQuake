import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
  });

  tearDown(() => SoundEffectService().enabled = true);

  test(
    'Wolfx and FAN keep two interleaved 24-report events complete and current',
    () async {
      final provider = QuakeProvider();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final wolfxRawReports = [
        for (var report = 1; report <= 24; report++)
          _wolfxRaw(
            eventId: 'WOLFX-20260728152718',
            report: report,
            hypocenter: '熊本県熊本地方 第$report報',
          ),
      ];
      final fanRawReports = [
        for (var report = 1; report <= 24; report++)
          _fanRaw(
            eventId: 'FAN-20260728152800',
            report: report,
            hypocenter: '日向灘 第$report報',
          ),
      ];
      final rawBefore = jsonEncode({
        'wolfx': wolfxRawReports,
        'fan': fanRawReports,
      });

      var listenerCalls = 0;
      final effects = <UnifiedQuakeData>[];
      provider.addListener(() => listenerCalls++);
      provider.onUnifiedEventNotified = (event, _) => effects.add(event);

      for (var index = 0; index < 24; index++) {
        provider.handleUnifiedEventForTest(_adaptWolfx(wolfxRawReports[index]));
        provider.handleUnifiedEventForTest(_adaptFan(fanRawReports[index]));
      }

      // 两个 API 的原始 Map 在适配和处理后必须保持逐字节等价的 JSON 内容。
      expect(
        jsonEncode({'wolfx': wolfxRawReports, 'fan': fanRawReports}),
        rawBefore,
      );
      expect(wolfxRawReports, hasLength(24));
      expect(fanRawReports, hasLength(24));
      expect(provider.unifiedEvents, hasLength(2));
      expect(provider.eewHistory, hasLength(2));

      final wolfxCurrent = _current(provider, 'WOLFX-20260728152718');
      expect(wolfxCurrent.origin, 0);
      expect(wolfxCurrent.apiTypeLabel, 'Wolfx');
      expect(wolfxCurrent.reportNumText, '第24報');
      expect(wolfxCurrent.hypocenter, '熊本県熊本地方 第24報');
      expect(wolfxCurrent.magnitude, closeTo(7.4, 0.000001));
      expect(wolfxCurrent.depth, 34);
      expect(wolfxCurrent.lat, closeTo(32.624, 0.000001));
      expect(wolfxCurrent.lng, closeTo(130.724, 0.000001));
      expect(wolfxCurrent.maxIntensity, '7');
      expect(wolfxCurrent.warnArea, contains('熊本県熊本'));

      final fanCurrent = _current(provider, 'FAN-20260728152800');
      expect(fanCurrent.origin, 1);
      expect(fanCurrent.apiTypeLabel, 'FAN');
      expect(fanCurrent.reportNumText, '第24報');
      expect(fanCurrent.hypocenter, '日向灘 第24報');
      expect(fanCurrent.magnitude, closeTo(6.4, 0.000001));
      expect(fanCurrent.depth, 44);
      expect(fanCurrent.lat, closeTo(31.824, 0.000001));
      expect(fanCurrent.lng, closeTo(131.824, 0.000001));
      expect(fanCurrent.maxIntensity, '6+');

      final wolfxHistory = _history(provider, 'WOLFX-20260728152718');
      final fanHistory = _history(provider, 'FAN-20260728152800');
      expect(wolfxHistory.reportCount, 24);
      expect(fanHistory.reportCount, 24);
      expect(
        wolfxHistory.reports.map((event) => event.reportNumText),
        orderedEquals(_descendingReportLabels(24)),
      );
      expect(
        fanHistory.reports.map((event) => event.reportNumText),
        orderedEquals(_descendingReportLabels(24)),
      );

      // 两个事件首报各立即发布；46 个普通更新共享一个 UI 最新快照。
      expect(listenerCalls, 2);
      expect(effects, hasLength(2));
      expect(effects.map((event) => event.reportNumText), everyElement('第1報'));

      await Future<void>.delayed(const Duration(milliseconds: 160));
      expect(listenerCalls, 3);
      expect(_current(provider, 'WOLFX-20260728152718').reportNumText, '第24報');
      expect(_current(provider, 'FAN-20260728152800').reportNumText, '第24報');

      await Future<void>.delayed(const Duration(milliseconds: 180));
      expect(effects, hasLength(4));
      expect(
        effects.where(
          (event) =>
              event.eventId == 'WOLFX-20260728152718' &&
              event.reportNumText == '第24報' &&
              event.apiTypeLabel == 'Wolfx',
        ),
        hasLength(1),
      );
      expect(
        effects.where(
          (event) =>
              event.eventId == 'FAN-20260728152800' &&
              event.reportNumText == '第24報' &&
              event.apiTypeLabel == 'FAN',
        ),
        hasLength(1),
      );

      provider.dispose();
    },
  );

  test(
    'Wolfx and FAN duplicate 24-report streams never let stale API data win',
    () async {
      final provider = QuakeProvider();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      const eventId = 'DUAL-API-20260728152718';
      final wolfxRawReports = [
        for (var report = 1; report <= 24; report++)
          _wolfxRaw(
            eventId: eventId,
            report: report,
            hypocenter: 'Wolfx 熊本修正 第$report報',
            isFinal: report == 24,
          ),
      ];
      final fanRawReports = [
        for (var report = 1; report <= 24; report++)
          _fanRaw(
            eventId: eventId,
            report: report,
            hypocenter: 'FAN 熊本修正 第$report報',
            isFinal: report == 24,
          ),
      ];
      final rawBefore = jsonEncode({
        'wolfx': wolfxRawReports,
        'fan': fanRawReports,
      });

      var listenerCalls = 0;
      final effects = <UnifiedQuakeData>[];
      provider.addListener(() => listenerCalls++);
      provider.onUnifiedEventNotified = (event, _) => effects.add(event);

      for (var index = 0; index < 24; index++) {
        final report = index + 1;
        if (report.isOdd) {
          provider.handleUnifiedEventForTest(
            _adaptWolfx(wolfxRawReports[index]),
          );
          provider.handleUnifiedEventForTest(_adaptFan(fanRawReports[index]));
        } else {
          provider.handleUnifiedEventForTest(_adaptFan(fanRawReports[index]));
          provider.handleUnifiedEventForTest(
            _adaptWolfx(wolfxRawReports[index]),
          );
        }
      }

      // 第24报之后再次送入另一个 API 的第23报，验证旧报不能回写显示。
      provider.handleUnifiedEventForTest(_adaptWolfx(wolfxRawReports[22]));

      expect(
        jsonEncode({'wolfx': wolfxRawReports, 'fan': fanRawReports}),
        rawBefore,
      );
      expect(wolfxRawReports, hasLength(24));
      expect(fanRawReports, hasLength(24));
      expect(provider.unifiedEvents, hasLength(1));
      expect(provider.eewHistory, hasLength(1));

      // 偶数报由 FAN 先到；第24报及全部显示字段必须保持 FAN 原始值。
      final current = provider.unifiedEvents.single;
      expect(current.eventId, eventId);
      expect(current.origin, 1);
      expect(current.apiTypeLabel, 'FAN');
      expect(current.reportNumText, '第24報（最終）');
      expect(current.isFinal, isTrue);
      expect(current.hypocenter, 'FAN 熊本修正 第24報');
      expect(current.magnitude, closeTo(6.4, 0.000001));
      expect(current.depth, 44);
      expect(current.lat, closeTo(31.824, 0.000001));
      expect(current.lng, closeTo(131.824, 0.000001));
      expect(current.maxIntensity, '6+');

      // 同一事件同一报号跨 API 去重；24 个不同报号一个不少。
      final history = provider.eewHistory.single;
      expect(history.reportCount, 24);
      expect(
        history.reports.map((event) => event.reportNumText),
        orderedEquals(['第24報（最終）', ..._descendingReportLabels(23)]),
      );
      expect(history.reports[0].apiTypeLabel, 'FAN');
      expect(history.reports[1].apiTypeLabel, 'Wolfx');

      // 首报和最终报立即发布；中间普通更新不会在最终报后补执行。
      expect(listenerCalls, 2);
      expect(effects, hasLength(2));
      expect(effects.first.apiTypeLabel, 'Wolfx');
      expect(effects.first.reportNumText, '第1報');
      expect(effects.last.apiTypeLabel, 'FAN');
      expect(effects.last.reportNumText, '第24報（最終）');

      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(listenerCalls, 2);
      expect(effects, hasLength(2));
      expect(provider.unifiedEvents.single.reportNumText, '第24報（最終）');
      expect(provider.unifiedEvents.single.apiTypeLabel, 'FAN');

      provider.dispose();
    },
  );

  test(
    'Wolfx regional report-suffixed IDs update the first card in place',
    () async {
      final provider = QuakeProvider();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final first = _wolfxRegionalRaw(
        eventId: '20260807130830.0001_1',
        report: 1,
        magnitude: 4.8,
      );
      final second = _wolfxRegionalRaw(
        eventId: '20260807130830.0001_2',
        report: 2,
        magnitude: 5.4,
      );
      final rawBefore = jsonEncode([first, second]);

      final firstEvent = QuakeEventAdapter.convert('scEew', first, 0);
      final secondEvent = QuakeEventAdapter.convert('scEew', second, 0);
      expect(firstEvent, isNotNull);
      expect(secondEvent, isNotNull);
      expect(firstEvent!.eventId, '20260807130830.0001');
      expect(secondEvent!.eventId, '20260807130830.0001');

      provider.handleUnifiedEventForTest(firstEvent);
      provider.handleUnifiedEventForTest(secondEvent);
      provider.handleUnifiedEventForTest(firstEvent);

      expect(provider.unifiedEvents, hasLength(1));
      expect(provider.unifiedEvents.single.eventId, '20260807130830.0001');
      expect(provider.unifiedEvents.single.reportNumText, '第2報');
      expect(provider.unifiedEvents.single.magnitude, 5.4);
      expect(provider.eewHistory, hasLength(1));
      expect(provider.eewHistory.single.reportCount, 2);
      expect(
        provider.eewHistory.single.reports.map((event) => event.reportNumText),
        orderedEquals(['第2報', '第1報']),
      );

      final other = _wolfxRegionalRaw(
        eventId: '20260807130945.0001_1',
        report: 1,
        magnitude: 3.9,
      );
      provider.handleUnifiedEventForTest(
        QuakeEventAdapter.convert('scEew', other, 0)!,
      );
      expect(provider.unifiedEvents, hasLength(2));

      final fjEvent = QuakeEventAdapter.convert(
        'fjEew',
        _wolfxRegionalRaw(
          eventId: '20260807131000.0001_3',
          report: 3,
          magnitude: 4.1,
        ),
        0,
      );
      expect(fjEvent, isNotNull);
      expect(fjEvent!.eventId, '20260807131000.0001');

      expect(jsonEncode([first, second]), rawBefore);
      provider.dispose();
    },
  );

  testWidgets(
    'AlertModule renders both APIs latest report fields after a 48-message burst',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final provider = QuakeProvider();
      final mapState = MapStateProvider()..setShowEstimatedEpicenter(false);
      await tester.pump();
      await tester.pump();

      final wolfxRawReports = [
        for (var report = 1; report <= 24; report++)
          _wolfxRaw(
            eventId: 'UI-WOLFX-20260728152718',
            report: report,
            hypocenter: '熊本県熊本地方 第$report報',
          ),
      ];
      final fanRawReports = [
        for (var report = 1; report <= 24; report++)
          _fanRaw(
            eventId: 'UI-FAN-20260728152800',
            report: report,
            hypocenter: '日向灘 第$report報',
          ),
      ];
      final rawBefore = jsonEncode({
        'wolfx': wolfxRawReports,
        'fan': fanRawReports,
      });

      for (var index = 0; index < 24; index++) {
        provider.handleUnifiedEventForTest(_adaptWolfx(wolfxRawReports[index]));
        provider.handleUnifiedEventForTest(_adaptFan(fanRawReports[index]));
      }

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

      // 两张真实 UI 卡片都必须显示各自最新报，而不是第1报或中间报。
      expect(find.text('緊急地震速報（警報） 第24報'), findsNWidgets(2));
      expect(find.text('熊本県熊本地方 第24報'), findsOneWidget);
      expect(find.text('日向灘 第24報'), findsOneWidget);
      expect(find.text('M7.4  ·  深さ: 34km'), findsOneWidget);
      expect(find.text('M6.4  ·  深さ: 44km'), findsOneWidget);
      expect(find.text('Wolfx'), findsOneWidget);
      expect(find.text('FAN'), findsOneWidget);

      // Widget 渲染也不得反向修改两个 API 的原始输入。
      expect(
        jsonEncode({'wolfx': wolfxRawReports, 'fan': fanRawReports}),
        rawBefore,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
      mapState.dispose();
      await tester.pump();
    },
  );
}

UnifiedQuakeData _adaptWolfx(Map<String, dynamic> raw) {
  final event = QuakeEventAdapter.convert('jmaEew', raw, 0);
  expect(event, isNotNull);
  return event!;
}

UnifiedQuakeData _adaptFan(Map<String, dynamic> raw) {
  final event = QuakeEventAdapter.convert('jmaEew', raw, 1);
  expect(event, isNotNull);
  return event!;
}

Map<String, dynamic> _wolfxRaw({
  required String eventId,
  required int report,
  required String hypocenter,
  bool isFinal = false,
}) {
  return {
    'type': 'jma_eew',
    'EventID': eventId,
    'Serial': report,
    'Title': '緊急地震速報（警報）',
    'OriginTime': _freshJstWallTime(),
    'Hypocenter': hypocenter,
    'Magunitude': 5.0 + report / 10,
    'Depth': 10 + report,
    'Latitude': 32.6 + report / 1000,
    'Longitude': 130.7 + report / 1000,
    'MaxIntensity': report == 24 ? '7' : '6弱',
    'isWarn': true,
    'isFinal': isFinal,
    'isCancel': false,
    'WarnArea': {
      'Chiiki': ['熊本県熊本', '熊本県天草・芦北'],
      'Shindo1': [report == 24 ? '7' : '6弱', '5強'],
    },
  };
}

Map<String, dynamic> _fanRaw({
  required String eventId,
  required int report,
  required String hypocenter,
  bool isFinal = false,
}) {
  return {
    'eventId': eventId,
    'updates': report,
    'infoTypeName': '警報',
    'originTime': _freshJstWallTime(),
    'location': hypocenter,
    'magnitude': 4.0 + report / 10,
    'depth': 20 + report,
    'latitude': 31.8 + report / 1000,
    'longitude': 131.8 + report / 1000,
    'jmaShindo': report == 24 ? '6強' : '5強',
    'isWarn': true,
    'isFinal': isFinal,
    'isCancel': false,
  };
}

Map<String, dynamic> _wolfxRegionalRaw({
  required String eventId,
  required int report,
  required double magnitude,
}) {
  return {
    'type': 'sc_eew',
    'EventID': eventId,
    'ReportNum': report,
    'ReportTime': _freshCstWallTime(),
    'OriginTime': _freshCstWallTime(),
    'HypoCenter': '四川宜宾市高县',
    'Magunitude': magnitude,
    'Depth': report == 1 ? 4 : 0,
    'Latitude': 28.42,
    'Longitude': 104.56,
    'MaxIntensity': 7,
  };
}

String _freshJstWallTime() {
  return DateTime.now().toUtc().add(const Duration(hours: 9)).toIso8601String();
}

String _freshCstWallTime() {
  return DateTime.now().toUtc().add(const Duration(hours: 8)).toIso8601String();
}

UnifiedQuakeData _current(QuakeProvider provider, String eventId) {
  return provider.unifiedEvents.singleWhere(
    (event) => event.eventId == eventId,
  );
}

EewEventGroup _history(QuakeProvider provider, String eventId) {
  return provider.eewHistory.singleWhere((group) => group.eventId == eventId);
}

List<String> _descendingReportLabels(int maxReport) {
  return [for (var report = maxReport; report >= 1; report--) '第$report報'];
}
