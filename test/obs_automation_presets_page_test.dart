import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutterrhythmquake/models/obs_automation_builtin_presets.dart';
import 'package:flutterrhythmquake/models/obs_automation_preset.dart';
import 'package:flutterrhythmquake/providers/page_background_provider.dart';
import 'package:flutterrhythmquake/services/obs_automation_runtime_service.dart';
import 'package:flutterrhythmquake/services/obs_websocket_service.dart';
import 'package:flutterrhythmquake/widgets/ui/obs_automation_presets_page.dart';
import 'package:flutterrhythmquake/widgets/ui/app_page_background.dart';
import 'package:flutterrhythmquake/widgets/ui/obs_recording_form.dart';
import 'package:flutterrhythmquake/widgets/ui/settings_page.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/providers/notification_settings_provider.dart';
import 'package:flutterrhythmquake/providers/background_settings_provider.dart';
import 'support/unified_ui_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadUnifiedUiFonts();
    await AppPageBackground.cachedBytes();
    await (FontLoader('MaterialIcons')..addFont(
          File(
            'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
  });
  var sequence = 0;
  ObsAutomationPreset builtIn() =>
      buildEewRecordingPreset(nextId: (prefix) => '$prefix-${sequence++}');
  Future<void> pumpPage(
    WidgetTester tester,
    Size size, {
    ObsAutomationPreset? preset,
  }) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues(
      preset == null
          ? {}
          : {
              obsAutomationPresetsPreferenceKey: jsonEncode(
                ObsAutomationPresetDocument(presets: [preset]).toJson(),
              ),
            },
    );
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => PageBackgroundProvider(),
        child: RepaintBoundary(
          key: const ValueKey('obs-page-render'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: unifiedUiTestTheme(),
            home: const ObsAutomationPresetsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> savedAutomatically(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  Future<Map<String, dynamic>> saved() async {
    final prefs = await SharedPreferences.getInstance();
    return jsonDecode(prefs.getString(obsAutomationPresetsPreferenceKey)!)
        as Map<String, dynamic>;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('obs-page-render')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final file = File('tmp/obs_settings_table_20261103/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'recording form uses fixed institutions, one unit selector, one end selector and autosave',
    (tester) async {
      await pumpPage(tester, const Size(1600, 1000));
      await savedAutomatically(tester);
      final table = tester.widget<DataTable>(
        find.byKey(const ValueKey('obs-rules-table')),
      );
      expect(table.rows.length, builtIn().stacks.length + 1);
      expect(table.columns, hasLength(5));
      expect(find.text('CEA-EEW'), findsOneWidget);
      expect(find.text('JMA-EEW'), findsOneWidget);
      expect(find.text('ShakeAlert-EEW'), findsOneWidget);
      expect(find.text('CENC 自动测定'), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(table.rows.length));
      expect(
        find.byType(DropdownButton<ObsAutomationBlockType>),
        findsNWidgets(table.rows.length - 1),
      );
      expect(find.byKey(const ValueKey('obs-save')), findsNothing);
      expect(find.text('保存'), findsNothing);
      for (final removed in [
        '自动化预设',
        '启用预设',
        '添加规则',
        '添加阈值',
        '事件阶段',
        '同事件一次',
        '触发频次',
        '同震时差 / 秒',
        '同震距离 / km',
      ]) {
        expect(find.text(removed), findsNothing, reason: removed);
      }
      expect(find.text('连接●录制设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'obs-settings-desktop');
    },
  );

  testWidgets(
    'SASMEX exposes detection and warning options instead of numeric thresholds and autosaves only its trigger',
    (tester) async {
      final preset = builtIn();
      final original = preset.stacks.singleWhere(obsRecordingUsesAlertTrigger);
      await pumpPage(tester, const Size(1600, 1000), preset: preset);
      await savedAutomatically(tester);
      expect(
        find.byKey(ValueKey('obs-trigger-unit-${original.id}')),
        findsNothing,
      );
      final selector = find.byKey(ValueKey('obs-alert-trigger-${original.id}'));
      expect(
        find.descendant(of: selector, matching: find.text('检出或警报')),
        findsOneWidget,
      );
      for (final choice in ['warning', 'detection', 'all']) {
        await tester.tap(selector);
        await tester.pumpAndSettle();
        if (choice == 'warning') {
          await capture(tester, 'obs-sasmex-options');
        }
        await tester.tap(find.text(obsRecordingAlertTriggers[choice]!).last);
        await savedAutomatically(tester);
        final after = ObsAutomationPresetDocument.fromJson(
          await saved(),
        ).presets.single;
        final changed = after.stacks.singleWhere(obsRecordingUsesAlertTrigger);
        expect(obsRecordingAlertTrigger(changed), choice);
        final start = changed.blocks.indexWhere(
          (block) => block.type == ObsAutomationBlockType.startRecord,
        );
        final originalStart = original.blocks.indexWhere(
          (block) => block.type == ObsAutomationBlockType.startRecord,
        );
        expect(
          changed.blocks.skip(start).map((b) => b.toJson()).toList(),
          original.blocks.skip(originalStart).map((b) => b.toJson()).toList(),
        );
        for (final other in preset.stacks.where(
          (rule) => rule.id != original.id,
        )) {
          expect(
            after.stacks.singleWhere((rule) => rule.id == other.id).toJson(),
            other.toJson(),
          );
        }
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'OBS recording is a main settings category above advanced and renders inside the shared settings panel',
    (tester) async {
      SharedPreferences.setMockInitialValues({'tts_enabled': false});
      FlutterSecureStorage.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final quake = QuakeProvider();
      final map = MapStateProvider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: quake),
            ChangeNotifierProvider.value(value: map),
            ChangeNotifierProvider(create: (_) => PageBackgroundProvider()),
            ChangeNotifierProvider(
              create: (_) => NotificationSettingsProvider(),
            ),
            ChangeNotifierProvider(create: (_) => BackgroundSettingsProvider()),
          ],
          child: RepaintBoundary(
            key: const ValueKey('obs-page-render'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: unifiedUiTestTheme(),
              home: const SettingsPage(),
            ),
          ),
        ),
      );
      for (var i = 0; i < 40 && find.text('OBS 录制').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('OBS 录制'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('OBS 录制')).dy,
        lessThan(tester.getTopLeft(find.text('高级')).dy),
      );
      await tester.tap(find.text('OBS 录制'));
      await savedAutomatically(tester);
      expect(find.byKey(const ValueKey('obs-rules-table')), findsOneWidget);
      expect(
        tester
            .widget<ObsAutomationPresetsPage>(
              find.byType(ObsAutomationPresetsPage),
            )
            .embedded,
        isTrue,
      );
      expect(find.text('自动保存'), findsNothing);
      expect(find.text('OBS 自动录制'), findsNothing);
      expect(find.text('应用设置'), findsOneWidget);
      await capture(tester, 'obs-in-main-settings');
      await tester.tap(find.text('高级'));
      await tester.pumpAndSettle();
      expect(find.byType(ObsAutomationPresetsPage), findsNothing);
      expect(find.text('录制设置'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      quake.dispose();
      map.dispose();
    },
  );

  testWidgets(
    'one click enables one agency without affecting another agency or its fixed steps',
    (tester) async {
      final preset = builtIn();
      await pumpPage(tester, const Size(1600, 1000), preset: preset);
      await savedAutomatically(tester);
      expect(
        tester
            .widgetList<Switch>(find.byType(Switch))
            .every((widget) => !widget.value),
        isTrue,
      );
      await tester.tap(
        find.byKey(ValueKey('obs-rule-enabled-${preset.stacks.first.id}')),
      );
      await savedAutomatically(tester);
      final after = ObsAutomationPresetDocument.fromJson(
        await saved(),
      ).presets.single;
      expect(after.enabled, isTrue);
      expect(after.stacks.first.enabled, isTrue);
      expect(after.stacks.skip(1).every((stack) => !stack.enabled), isTrue);
      for (var index = 0; index < preset.stacks.length; index++) {
        expect(
          after.stacks[index].blocks.map((block) => block.toJson()).toList(),
          preset.stacks[index].blocks.map((block) => block.toJson()).toList(),
        );
      }
      expect(tester.takeException(), isNull);
      ObsAutomationRuntimeService().runner.configure(const []);
    },
  );

  testWidgets(
    'trigger unit and value autosave to one existing condition only',
    (tester) async {
      final preset = builtIn();
      final first = preset.stacks.first;
      await pumpPage(tester, const Size(1600, 1000), preset: preset);
      await savedAutomatically(tester);
      await tester.tap(find.byKey(ValueKey('obs-trigger-unit-${first.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('烈度').last);
      await tester.pumpAndSettle();
      final field = find.byKey(
        ValueKey('obs-trigger-${first.id}-estimatedIntensity'),
      );
      await tester.enterText(field, '6.0');
      await savedAutomatically(tester);
      final after = ObsAutomationPresetDocument.fromJson(
        await saved(),
      ).presets.single.stacks.first;
      expect(
        after.blocks.where(
          (block) => block.type == ObsAutomationBlockType.magnitude,
        ),
        isEmpty,
      );
      final condition = after.blocks.singleWhere(
        (block) => block.type == ObsAutomationBlockType.estimatedIntensity,
      );
      expect(condition.parameters, {
        'operator': 'greaterThanOrEqual',
        'value': '6.0',
      });
      expect(
        after.blocks
            .where((block) => block.id != condition.id)
            .map((block) => block.toJson())
            .toList(),
        first.blocks.map((block) => block.toJson()).toList(),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'end type is single-select and changing to CENC CMT preserves matching, delay and stop steps',
    (tester) async {
      final preset = builtIn();
      final first = preset.stacks.first;
      await pumpPage(tester, const Size(1600, 1000), preset: preset);
      await savedAutomatically(tester);
      await tester.tap(find.byKey(ValueKey('obs-end-${first.id}')));
      await tester.pumpAndSettle();
      expect(find.text('CENC-CMT'), findsOneWidget);
      expect(find.text('USGS ShakeMap 烈度速报'), findsNothing);
      await tester.tap(
        find.ancestor(
          of: find.text('CENC-CMT'),
          matching: find.byType(CheckedPopupMenuItem<String>),
        ),
      );
      await savedAutomatically(tester);
      final after = ObsAutomationPresetDocument.fromJson(
        await saved(),
      ).presets.single.stacks.first;
      expect(after.endConditionId, 'cencCmt');
      expect(
        after.blocks
            .singleWhere((block) => block.type == ObsAutomationBlockType.source)
            .parameters,
        {'operator': 'equals', 'value': 'cencCmt'},
      );
      for (final type in [
        ObsAutomationBlockType.sameEarthquakeAsVariable,
        ObsAutomationBlockType.wait,
        ObsAutomationBlockType.stopRecord,
        ObsAutomationBlockType.stopScript,
      ]) {
        expect(
          after.blocks.singleWhere((block) => block.type == type).toJson(),
          first.blocks.singleWhere((block) => block.type == type).toJson(),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'connection recording settings autosave matching, timeout and expanded source selection',
    (tester) async {
      final preset = builtIn();
      await pumpPage(tester, const Size(1600, 1000), preset: preset);
      await savedAutomatically(tester);
      await tester.tap(find.text('连接●录制设置'));
      await tester.pumpAndSettle();
      expect(find.text('保存'), findsNothing);
      await capture(tester, 'obs-connection-recording-settings');
      await tester.tap(find.byKey(const ValueKey('obs-expand-end-sources')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('obs-common-maxSeconds')),
        '120',
      );
      await tester.enterText(
        find.byKey(const ValueKey('obs-common-maxDistanceKm')),
        '80',
      );
      await tester.enterText(
        find.byKey(const ValueKey('obs-common-timeoutSeconds')),
        '1800',
      );
      await savedAutomatically(tester);
      await capture(tester, 'obs-connection-recording-settings-edited');
      await tester.tap(find.text('关闭'));
      await savedAutomatically(tester);
      final after = ObsAutomationPresetDocument.fromJson(
        await saved(),
      ).presets.single;
      for (final rule in after.stacks) {
        for (final block in rule.blocks) {
          if (block.type == ObsAutomationBlockType.sameEarthquakeAsVariable) {
            expect(block.parameters['maxSeconds'], '120');
            expect(block.parameters['maxDistanceKm'], '80');
          }
          if (block.type == ObsAutomationBlockType.waitForUnifiedEvent) {
            expect(block.parameters['timeoutSeconds'], '1800');
          }
        }
      }
      final gq = after.stacks.singleWhere(
        (rule) => obsRecordingAgency(rule) == 'globalQuake',
      );
      expect(
        gq.blocks
            .singleWhere((block) => block.type == ObsAutomationBlockType.wait)
            .parameters['seconds'],
        '1800',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('obs_recording_extended_end_sources'), isTrue);
      await tester.tap(
        find.byKey(ValueKey('obs-end-${after.stacks.first.id}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('USGS ShakeMap 烈度速报'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(15, 15));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'CENC information row has the requested defaults and only information trigger',
    (tester) async {
      await pumpPage(tester, const Size(1600, 1000));
      await savedAutomatically(tester);
      final preset = ObsAutomationPresetDocument.fromJson(
        await saved(),
      ).presets.single;
      final rule = preset.stacks.singleWhere(obsIsCencInformationRule);
      expect(rule.enabled, isFalse);
      expect(
        rule.blocks
            .singleWhere(
              (block) => block.type == ObsAutomationBlockType.magnitude,
            )
            .parameters['value'],
        '5.0',
      );
      expect(
        rule.blocks.where(
          (block) => block.type == ObsAutomationBlockType.isEew,
        ),
        isEmpty,
      );
      expect(rule.endConditionId, 'cenc-reviewed');
      expect(obsRecordingDelay(rule), '20');
      final field = find.byKey(ValueKey('obs-trigger-${rule.id}-magnitude'));
      expect(tester.widget<TextFormField>(field).initialValue, '5.0');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('narrow settings table scrolls without overflow', (tester) async {
    await pumpPage(tester, const Size(430, 900));
    await savedAutomatically(tester);
    expect(find.text('OBS 自动录制'), findsOneWidget);
    expect(find.byKey(const ValueKey('obs-rules-table')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'obs-settings-narrow');
  });

  testWidgets('OBS connection state remains live', (tester) async {
    final notifier = ObsAutomationRuntimeService().obs.connectionStateNotifier;
    notifier.value = ObsConnectionState.connected;
    addTearDown(() => notifier.value = ObsConnectionState.disconnected);
    await pumpPage(tester, const Size(1280, 800));
    await savedAutomatically(tester);
    expect(find.text('OBS 已连接'), findsOneWidget);
    notifier.value = ObsConnectionState.reconnecting;
    await tester.pump();
    expect(find.text('OBS 重连中'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
