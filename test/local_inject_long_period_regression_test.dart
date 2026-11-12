import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/debug/local_inject_decoder.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'package:flutterrhythmquake/widgets/ui/unified_alert_card.dart';
import 'package:flutterrhythmquake/widgets/ui/jma_eew_long_period_footer.dart';

class _Cards extends QuakeProvider {
  _Cards() : super(startCatalogServices: false);
  UnifiedQuakeData? shown;
  @override
  List<UnifiedQuakeData> get unifiedEvents => [?shown];
  @override
  UnifiedQuakeData? get mobileCameraDisplayEvent => shown;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
  });
  tearDown(() => SoundEffectService().enabled = true);

  final frame =
      jsonDecode(
            File(
              'exports/mock_whews_jma_eew_long_period_3_20261107.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  test(
    'WHEWS direct versus Mock envelope retains exact report and class 3',
    () {
      final before = jsonEncode(frame);
      final raw = Map<String, dynamic>.from(frame['Data'] as Map);
      final direct = QuakeEventAdapter.convertWhews('jma_eew', raw)!;
      final mock = LocalInjectDecoder.decode(
        frame,
        format: 'whews',
      ).events.single;
      for (final e in [direct, mock, UnifiedQuakeData.fromMap(mock.toMap())]) {
        expect(e.source, 'jmaEew');
        expect(e.useShindo, isTrue);
        expect(e.eewLongPeriodClass, 3);
        expect(UnifiedEventPresentation.fromEvent(e).intensityLabel, '震度');
      }
      expect(mock.apiTypeLabel, 'Mock');
      expect(mock.sourcePayload, frame);
      expect(jsonEncode(frame), before);
      expect(raw['maxLgInt'], '3');
      for (final level in [null, '0', '1', '2', '3', '4']) {
        final copy = Map<String, dynamic>.from(frame);
        final body = Map<String, dynamic>.from(frame['Data'] as Map);
        if (level == null) {
          body.remove('maxLgInt');
        } else {
          body['maxLgInt'] = level;
        }
        copy['Data'] = body;
        final value = LocalInjectDecoder.decode(
          copy,
          format: 'whews',
        ).events.single;
        expect(
          value.eewLongPeriodClass,
          level == null || level == '0' ? null : int.parse(level),
        );
        expect(value.sourcePayload, copy);
      }
    },
  );

  test('Wolfx JMA assumed hypocenter and optional long-period input', () {
    final raw = <String, dynamic>{
      'type': 'jma_eew',
      'Title': '緊急地震速報（警報）',
      'EventID': 'test-wolfx-plum-20261107',
      'Serial': 1,
      'OriginTime': '2026-11-07 17:00:00',
      'AnnouncedTime': '2026-11-07 17:00:05',
      'Hypocenter': '仮定震源の模擬テスト',
      'Latitude': 37.5,
      'Longitude': 137.3,
      'Magnitude': 1.0,
      'Magunitude': 1.0,
      'Depth': 10.0,
      'MaxIntensity': '4',
      'isWarn': true,
      'isAssumption': true,
      'isTraining': false,
    };
    final wolfx = LocalInjectDecoder.decode(raw, format: 'wolfx').events.single;
    expect(wolfx.isAssumption, isTrue);
    expect(wolfx.isJmaPlumEew, isTrue);
    expect(wolfx.displayTitleText, contains('（PLUM）'));
    expect(
      wolfx.eewLongPeriodClass,
      isNull,
    ); // Wolfx documented fields do not include prediction.
    final optional = Map<String, dynamic>.from(raw)..['maxLgInt'] = '4';
    final supplemented = LocalInjectDecoder.decode(
      optional,
      format: 'wolfx',
    ).events.single;
    expect(supplemented.eewLongPeriodClass, 4);
    expect(supplemented.sourcePayload, optional);
  });

  testWidgets('Mock event displays long-period footer in real unified cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final event = LocalInjectDecoder.decode(
      frame,
      format: 'whews',
    ).events.single;
    final provider = _Cards()..shown = event;
    final state = MapStateProvider()..setShowEstimatedEpicenter(false);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<QuakeProvider>.value(value: provider),
          ChangeNotifierProvider<MapStateProvider>.value(value: state),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const AlertModule(),
                UnifiedAlertCard(event: event),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(JmaEewLongPeriodFooter), findsNWidgets(2));
    expect(find.text('长周期 3'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
    state.dispose();
    await tester.pump(const Duration(seconds: 1));
  });
}
