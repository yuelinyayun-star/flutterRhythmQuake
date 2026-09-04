import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart' show kMiddleMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutterrhythmquake/providers/page_background_provider.dart';
import 'package:flutterrhythmquake/services/obs_automation_runtime_service.dart';
import 'package:flutterrhythmquake/services/obs_websocket_service.dart';
import 'package:flutterrhythmquake/widgets/ui/obs_automation_presets_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPage(
    WidgetTester tester,
    Size size, {
    Map<String, Object> preferences = const {},
    bool seedBlankPreset = true,
  }) async {
    final effectivePreferences = preferences.isEmpty && seedBlankPreset
        ? <String, Object>{
            'obs_automation_presets_v1': jsonEncode({
              'schemaVersion': 3,
              'presets': [
                {
                  'id': 'test-blank-preset',
                  'name': '测试空白预设',
                  'enabled': false,
                  'stacks': const [],
                },
              ],
            }),
          }
        : preferences;
    SharedPreferences.setMockInitialValues(effectivePreferences);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => PageBackgroundProvider(),
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const ObsAutomationPresetsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dragTo(WidgetTester tester, Finder source, Offset target) async {
    final start = tester.getCenter(source);
    await tester.dragFrom(start, target - start, touchSlopY: 0, touchSlopX: 0);
    await tester.pumpAndSettle();
  }

  Future<void> dragValueTo(
    WidgetTester tester,
    Finder source,
    Offset target,
  ) async {
    final gesture = await tester.startGesture(tester.getCenter(source));
    await gesture.moveBy(const Offset(2, 2));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(target, timeStamp: const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> scrollPaletteCategoryIntoView(
    WidgetTester tester,
    String label,
  ) async {
    final categoryNames = <String, String>{
      '事件': 'events',
      '逻辑': 'logic',
      '运算': 'operators',
      'UI 数据': 'uiConditions',
      '测站数据': 'stationConditions',
      '变量': 'variables',
      '控制': 'control',
      'OBS': 'obs',
    };
    final category = find.byKey(
      ValueKey('palette-category-${categoryNames[label]}'),
    );
    final categoryStrip = find.byKey(const ValueKey('palette-category-scroll'));
    await tester.drag(categoryStrip, const Offset(1000, 0));
    await tester.pumpAndSettle();
    for (
      var attempt = 0;
      attempt < 10 && category.hitTestable().evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(categoryStrip, const Offset(-100, 0));
      await tester.pumpAndSettle();
    }
    expect(category.hitTestable(), findsOneWidget);
  }

  Future<void> selectPaletteCategory(WidgetTester tester, String label) async {
    await scrollPaletteCategoryIntoView(tester, label);
    final categoryNames = <String, String>{
      '事件': 'events',
      '逻辑': 'logic',
      '运算': 'operators',
      'UI 数据': 'uiConditions',
      '测站数据': 'stationConditions',
      '变量': 'variables',
      '控制': 'control',
      'OBS': 'obs',
    };
    await tester.tap(
      find
          .byKey(ValueKey('palette-category-${categoryNames[label]}'))
          .hitTestable(),
    );
    await tester.pumpAndSettle();
  }

  Finder valueSocket({required Finder within, required String parameter}) {
    return find.descendant(
      of: within,
      matching: find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('value-socket-') &&
            !key.value.startsWith('value-socket-picker-') &&
            key.value.endsWith('-$parameter');
      }),
    );
  }

  Finder expressionSocket({required Finder within, required String path}) {
    return find.descendant(
      of: within,
      matching: find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('expression-socket-') &&
            key.value.endsWith('-$path');
      }),
    );
  }

  testWidgets('desktop palette blocks drag, snap and save as one stack', (
    tester,
  ) async {
    await pumpPage(tester, const Size(1280, 800));

    final eventTemplate = find.byKey(const ValueKey('palette-unifiedEvent'));
    expect(eventTemplate, findsOneWidget);
    expect(
      find.byKey(const ValueKey('palette-networkDetection')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('palette-stationChange')), findsOneWidget);
    await dragTo(tester, eventTemplate, const Offset(560, 250));

    final eventBlock = find.byKey(const ValueKey('canvas-block-unifiedEvent'));
    expect(eventBlock, findsOneWidget);
    expect(
      find.descendant(
        of: eventBlock,
        matching: find.byType(DropdownButton<String>),
      ),
      findsNothing,
    );

    await selectPaletteCategory(tester, 'OBS');
    final recordTemplate = find.byKey(const ValueKey('palette-startRecord'));
    expect(recordTemplate, findsOneWidget);
    final eventTopLeft = tester.getTopLeft(eventBlock);
    await dragTo(tester, recordTemplate, eventTopLeft + const Offset(92, 78));

    expect(
      find.byKey(const ValueKey('canvas-block-startRecord')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    final attachedAction = find.byKey(
      const ValueKey('canvas-block-startRecord'),
    );
    final detachHandle = find.descendant(
      of: attachedAction,
      matching: find.byTooltip('从这里拆开并拖动'),
    );
    await dragTo(tester, detachHandle, const Offset(1030, 430));
    expect(tester.getTopLeft(attachedAction).dx, greaterThan(850));

    final looseHandle = find.descendant(
      of: attachedAction,
      matching: find.byTooltip('拖动积木堆'),
    );
    await dragTo(
      tester,
      looseHandle,
      tester.getTopLeft(eventBlock) + const Offset(48, 78),
    );
    expect(
      (tester.getTopLeft(attachedAction).dx - tester.getTopLeft(eventBlock).dx)
          .abs(),
      lessThan(2),
    );

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('obs_automation_presets_v1');
    expect(raw, isNotNull);
    final root = jsonDecode(raw!) as Map<String, dynamic>;
    final presets = root['presets'] as List<dynamic>;
    final savedPreset = presets.cast<Map<String, dynamic>>().singleWhere(
      (item) => item['id'] == 'test-blank-preset',
    );
    final stacks = savedPreset['stacks'] as List<dynamic>;
    expect(stacks, hasLength(1));
    final blocks =
        (stacks.single as Map<String, dynamic>)['blocks'] as List<dynamic>;
    expect(blocks.map((item) => (item as Map<String, dynamic>)['type']), [
      'unifiedEvent',
      'startRecord',
    ]);
  });

  testWidgets('station input hats fit inside desktop canvas blocks', (
    tester,
  ) async {
    await pumpPage(tester, const Size(1280, 800));

    await dragTo(
      tester,
      find.byKey(const ValueKey('palette-networkDetection')),
      const Offset(560, 250),
    );
    await dragTo(
      tester,
      find.byKey(const ValueKey('palette-stationChange')),
      const Offset(560, 390),
    );

    final networkBlock = find.byKey(
      const ValueKey('canvas-block-networkDetection'),
    );
    final stationBlock = find.byKey(
      const ValueKey('canvas-block-stationChange'),
    );
    expect(networkBlock, findsOneWidget);
    expect(stationBlock, findsOneWidget);
    expect(tester.takeException(), isNull);

    expect(
      find.descendant(
        of: networkBlock,
        matching: find.byType(DropdownButton<String>),
      ),
      findsOneWidget,
    );

    final stationDropdowns = find.descendant(
      of: stationBlock,
      matching: find.byType(DropdownButton<String>),
    );
    expect(stationDropdowns, findsOneWidget);
    await tester.tap(stationDropdowns.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('FDSN/SeedLink').last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('condition branches connect as input AND conditions OR input', (
    tester,
  ) async {
    await pumpPage(tester, const Size(1280, 800));

    await dragTo(
      tester,
      find.byKey(const ValueKey('palette-networkDetection')),
      const Offset(560, 210),
    );
    final networkBlock = find.byKey(
      const ValueKey('canvas-block-networkDetection'),
    );
    final stackTopLeft = tester.getTopLeft(networkBlock);

    await selectPaletteCategory(tester, '测站数据');
    await selectPaletteCategory(tester, '逻辑');
    await dragTo(
      tester,
      find.byKey(const ValueKey('palette-compareValues')),
      stackTopLeft + const Offset(92, 78),
    );
    expect(find.byKey(const ValueKey('palette-andBranch')), findsOneWidget);
    await dragTo(
      tester,
      find.byKey(const ValueKey('palette-orBranch')),
      stackTopLeft + const Offset(92, 130),
    );

    await selectPaletteCategory(tester, '事件');
    await dragTo(
      tester,
      find.byKey(const ValueKey('palette-unifiedEvent')),
      stackTopLeft + const Offset(92, 182),
    );

    await selectPaletteCategory(tester, 'UI 数据');
    await selectPaletteCategory(tester, '逻辑');
    await dragTo(
      tester,
      find.byKey(const ValueKey('palette-compareValues')),
      stackTopLeft + const Offset(92, 234),
    );

    await selectPaletteCategory(tester, 'OBS');
    await dragTo(
      tester,
      find.byKey(const ValueKey('palette-startRecord')),
      stackTopLeft + const Offset(92, 286),
    );

    expect(find.byKey(const ValueKey('canvas-block-orBranch')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('canvas-block-compareValues')),
      findsNWidgets(2),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final root =
        jsonDecode(prefs.getString('obs_automation_presets_v1')!)
            as Map<String, dynamic>;
    final preset = (root['presets'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .singleWhere((item) => item['id'] == 'test-blank-preset');
    final stacks = preset['stacks'] as List<dynamic>;
    expect(stacks, hasLength(1));
    final blocks =
        (stacks.single as Map<String, dynamic>)['blocks'] as List<dynamic>;
    expect(blocks.map((item) => (item as Map<String, dynamic>)['type']), [
      'networkDetection',
      'compareValues',
      'orBranch',
      'unifiedEvent',
      'compareValues',
      'startRecord',
    ]);
  });

  testWidgets('EEW agency condition lists every normalized institution', (
    tester,
  ) async {
    final raw = jsonEncode({
      'schemaVersion': 3,
      'presets': [
        {
          'id': 'preset-eew-agency',
          'name': 'EEW 机构测试',
          'enabled': false,
          'stacks': [
            {
              'id': 'stack-eew-agency',
              'x': 40.0,
              'y': 40.0,
              'blocks': [
                {
                  'id': 'block-eew-agency',
                  'type': 'eewAgency',
                  'parameters': {'operator': 'equals', 'value': 'jma'},
                },
              ],
            },
          ],
        },
      ],
    });
    await pumpPage(
      tester,
      const Size(1280, 800),
      preferences: {'obs_automation_presets_v1': raw},
    );

    final agencyBlock = find.byKey(const ValueKey('canvas-block-eewAgency'));
    final dropdowns = find.descendant(
      of: agencyBlock,
      matching: find.byType(DropdownButton<String>),
    );
    expect(dropdowns, findsNWidgets(2));
    await tester.tap(dropdowns.last);
    await tester.pumpAndSettle();

    for (final label in const [
      'JMA',
      'CWA',
      'CEA',
      '四川省地震局',
      '福建省地震局',
      '重庆市地震局',
      'KMA',
      'ShakeAlert',
      'GlobalQuake',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('value reporters feed variable and comparison sockets', (
    tester,
  ) async {
    await pumpPage(tester, const Size(1280, 800));

    await selectPaletteCategory(tester, '变量');
    expect(find.byKey(const ValueKey('palette-variableValue')), findsOneWidget);
    await dragTo(
      tester,
      find.byKey(const ValueKey('palette-setVariable')),
      const Offset(560, 210),
    );
    final setVariable = find.byKey(const ValueKey('canvas-block-setVariable'));
    final setValueSocket = valueSocket(
      within: setVariable,
      parameter: 'valueKind',
    );
    expect(setValueSocket, findsOneWidget);
    expect(
      find.descendant(of: setVariable, matching: find.text('拖入数值')),
      findsOneWidget,
    );

    await selectPaletteCategory(tester, 'UI 数据');
    final uiReporter = find.byKey(
      const ValueKey('palette-uiConditions-inputFieldValue'),
    );
    expect(uiReporter, findsOneWidget);
    expect(uiReporter.hitTestable(), findsOneWidget);
    final uiSelector = find.byKey(
      const ValueKey('palette-field-selector-unified'),
    );
    expect(uiSelector.hitTestable(), findsOneWidget);
    await tester.tap(find.text('事件类型').hitTestable().last);
    await tester.pumpAndSettle();
    expect(find.text('震级'), findsWidgets);
    expect(find.text('最大震度/烈度'), findsWidgets);
    expect(find.text('测站编号'), findsNothing);
    await tester.tap(find.text('震级').last);
    await tester.pumpAndSettle();
    await dragValueTo(tester, uiReporter, tester.getCenter(setValueSocket));
    expect(
      find.descendant(of: setVariable, matching: find.text('拖入数值')),
      findsNothing,
    );
    final insertedKindLabel = find.descendant(
      of: setVariable,
      matching: find.text('字段'),
    );
    final insertedValueLabel = find.descendant(
      of: setVariable,
      matching: find.text('震级'),
    );
    expect(insertedKindLabel, findsOneWidget);
    expect(insertedValueLabel, findsOneWidget);
    expect(tester.getSize(insertedKindLabel).width, greaterThan(20));
    expect(tester.getSize(insertedValueLabel).width, greaterThan(20));
    final setVariableRect = tester.getRect(setVariable);
    expect(
      setVariableRect.contains(tester.getCenter(insertedKindLabel)),
      isTrue,
    );
    expect(
      setVariableRect.contains(tester.getCenter(insertedValueLabel)),
      isTrue,
    );
    expect(tester.takeException(), isNull);

    await selectPaletteCategory(tester, '逻辑');
    expect(find.byKey(const ValueKey('palette-compareValues')), findsOneWidget);
    await dragTo(
      tester,
      find.byKey(const ValueKey('palette-compareValues')),
      const Offset(560, 390),
    );
    final compare = find.byKey(const ValueKey('canvas-block-compareValues'));
    expect(
      find.descendant(of: compare, matching: find.text('拖入数值')),
      findsNWidgets(2),
    );
    final leftSocket = valueSocket(within: compare, parameter: 'leftKind');
    await tester.tap(leftSocket);
    await tester.pumpAndSettle();
    expect(find.text('常量'), findsOneWidget);
    expect(find.text('输入字段'), findsOneWidget);
    expect(find.text('变量'), findsWidgets);
    await tester.tap(find.text('常量'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: compare, matching: find.text('拖入数值')),
      findsOneWidget,
    );
    final rightSocket = valueSocket(within: compare, parameter: 'rightKind');
    expect(rightSocket, findsOneWidget);

    await selectPaletteCategory(tester, '变量');
    await dragValueTo(
      tester,
      find.byKey(const ValueKey('palette-variableValue')),
      tester.getCenter(rightSocket),
    );
    expect(
      find.descendant(of: compare, matching: find.text('拖入数值')),
      findsNothing,
    );

    await selectPaletteCategory(tester, '测站数据');
    expect(
      find.byKey(
        const ValueKey('palette-stationConditions-inputFieldCondition'),
      ),
      findsOneWidget,
    );
    final stationReporter = find.byKey(
      const ValueKey('palette-stationConditions-inputFieldValue'),
    );
    expect(stationReporter, findsOneWidget);
    final stationSelector = find.byKey(
      const ValueKey('palette-field-selector-station'),
    );
    expect(stationSelector.hitTestable(), findsOneWidget);
    await tester.tap(find.text('台网').hitTestable().last);
    await tester.pumpAndSettle();
    expect(find.text('测站编号'), findsWidgets);
    expect(find.text('当前测站震度'), findsWidgets);
    await tester.tapAt(const Offset(1000, 700));
    await tester.pumpAndSettle();
    await dragValueTo(tester, stationReporter, const Offset(1040, 650));
    expect(
      find.byKey(const ValueKey('canvas-block-inputFieldValue')),
      findsNothing,
    );

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final root =
        jsonDecode(prefs.getString('obs_automation_presets_v1')!)
            as Map<String, dynamic>;
    final preset = (root['presets'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .singleWhere((item) => item['id'] == 'test-blank-preset');
    final stacks = preset['stacks'] as List<dynamic>;
    final blocks = stacks
        .expand(
          (stack) => (stack as Map<String, dynamic>)['blocks'] as List<dynamic>,
        )
        .cast<Map<String, dynamic>>()
        .toList();
    final setParameters = blocks.singleWhere(
      (block) => block['type'] == 'setVariable',
    )['parameters'];
    expect(setParameters['valueKind'], 'inputField');
    expect(setParameters['value'], 'magnitude');
    expect(setParameters['valueFamily'], 'unified');
    final compareParameters = blocks.singleWhere(
      (block) => block['type'] == 'compareValues',
    )['parameters'];
    expect(compareParameters['rightKind'], 'variable');
    expect(compareParameters['rightValue'], '变量');
    expect(tester.takeException(), isNull);
  });

  testWidgets('OBS text action accepts exact UI field reporters', (
    tester,
  ) async {
    await pumpPage(tester, const Size(1280, 800));

    await selectPaletteCategory(tester, 'OBS');
    expect(
      find.byKey(const ValueKey('palette-setTextSourceText')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('palette-setCurrentProgramScene')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('palette-setSceneItemEnabled')),
      findsOneWidget,
    );
    await dragTo(
      tester,
      find.byKey(const ValueKey('palette-setTextSourceText')),
      const Offset(560, 230),
    );
    final textAction = find.byKey(
      const ValueKey('canvas-block-setTextSourceText'),
    );
    final textSocket = valueSocket(within: textAction, parameter: 'textKind');
    expect(textSocket, findsOneWidget);
    expect(
      find.descendant(of: textAction, matching: find.text('拖入数值')),
      findsOneWidget,
    );

    await selectPaletteCategory(tester, 'UI 数据');
    await tester.tap(find.text('事件类型').hitTestable().last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('UI 顶部标题').last);
    await tester.pumpAndSettle();
    await dragValueTo(
      tester,
      find.byKey(const ValueKey('palette-uiConditions-inputFieldValue')),
      tester.getCenter(textSocket),
    );

    expect(
      find.descendant(of: textAction, matching: find.text('UI 顶部标题')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: textAction, matching: find.text('拖入数值')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Scratch operators nest fields and operators in value sockets', (
    tester,
  ) async {
    await pumpPage(tester, const Size(1280, 800));

    await selectPaletteCategory(tester, '变量');
    await dragTo(
      tester,
      find.byKey(const ValueKey('palette-setVariable')),
      const Offset(620, 210),
    );
    final setVariable = find.byKey(const ValueKey('canvas-block-setVariable'));
    final rootSocket = valueSocket(within: setVariable, parameter: 'valueKind');

    await selectPaletteCategory(tester, '运算');
    for (final type in const [
      'arithmeticValue',
      'randomValue',
      'moduloValue',
      'roundValue',
      'mathValue',
      'textJoinValue',
      'textLengthValue',
      'textContainsValue',
      'comparisonValue',
      'booleanValue',
      'notValue',
    ]) {
      expect(find.byKey(ValueKey('palette-$type')), findsOneWidget);
    }
    await dragValueTo(
      tester,
      find.byKey(const ValueKey('palette-arithmeticValue')),
      tester.getCenter(rootSocket),
    );
    expect(expressionSocket(within: setVariable, path: '0'), findsOneWidget);
    expect(expressionSocket(within: setVariable, path: '1'), findsOneWidget);

    await selectPaletteCategory(tester, 'UI 数据');
    final uiReporter = find.byKey(
      const ValueKey('palette-uiConditions-inputFieldValue'),
    );
    await tester.tap(find.text('事件类型').hitTestable().last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('震级').last);
    await tester.pumpAndSettle();
    await dragValueTo(
      tester,
      uiReporter,
      tester.getCenter(expressionSocket(within: setVariable, path: '0')),
    );
    expect(
      find.descendant(of: setVariable, matching: find.text('震级')),
      findsOneWidget,
    );

    await selectPaletteCategory(tester, '运算');
    await dragValueTo(
      tester,
      find.byKey(const ValueKey('palette-roundValue')),
      tester.getCenter(expressionSocket(within: setVariable, path: '1')),
    );
    expect(expressionSocket(within: setVariable, path: '1-0'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final root =
        jsonDecode(prefs.getString('obs_automation_presets_v1')!)
            as Map<String, dynamic>;
    final preset = (root['presets'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .singleWhere((item) => item['id'] == 'test-blank-preset');
    final stacks = preset['stacks'] as List<dynamic>;
    final blocks = stacks
        .expand(
          (stack) => (stack as Map<String, dynamic>)['blocks'] as List<dynamic>,
        )
        .cast<Map<String, dynamic>>();
    final parameters =
        blocks.singleWhere(
              (block) => block['type'] == 'setVariable',
            )['parameters']
            as Map<String, dynamic>;
    expect(parameters['valueKind'], 'expression');
    final expression = jsonDecode(parameters['value'] as String);
    expect(expression['value'], 'arithmetic');
    expect(expression['arguments'][0]['kind'], 'inputField');
    expect(expression['arguments'][0]['value'], 'magnitude');
    expect(expression['arguments'][1]['value'], 'round');
  });

  testWidgets('all second-layer condition editors render without overflow', (
    tester,
  ) async {
    const conditionTypes = [
      'orBranch',
      'unifiedPhase',
      'isEew',
      'isInformation',
      'eewAgency',
      'informationAgency',
      'informationReviewType',
      'sameEarthquakeAsVariable',
      'valueVariableCondition',
      'inputFieldMatchesVariable',
      'inputFieldCondition',
      'compareValues',
      'networkPhase',
      'stationPhase',
      'eventType',
      'source',
      'magnitude',
      'estimatedIntensity',
      'reportNumber',
      'isFinal',
      'networkMaxIntensity',
      'detectedStationCount',
      'stationId',
      'stationName',
      'currentStationIntensity',
      'previousStationIntensity',
    ];
    final stacks = [
      for (var index = 0; index < conditionTypes.length; index++)
        {
          'id': 'stack-$index',
          'x': 40.0,
          'y': 40.0 + index * 68.0,
          'blocks': [
            {'id': 'block-$index', 'type': conditionTypes[index]},
          ],
        },
    ];
    final raw = jsonEncode({
      'schemaVersion': 3,
      'presets': [
        {
          'id': 'preset-conditions',
          'name': '条件布局测试',
          'enabled': false,
          'stacks': stacks,
        },
      ],
    });

    await pumpPage(
      tester,
      const Size(1280, 800),
      preferences: {'obs_automation_presets_v1': raw},
    );

    for (final type in conditionTypes) {
      expect(find.byKey(ValueKey('canvas-block-$type')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('generic data blocks render without overflow', (tester) async {
    const dataTypes = [
      'setEventVariable',
      'setValueVariable',
      'setVariable',
      'changeVariable',
      'valueVariableCondition',
      'inputFieldMatchesVariable',
      'inputFieldCondition',
      'createRecordChapter',
    ];
    final raw = jsonEncode({
      'schemaVersion': 3,
      'presets': [
        {
          'id': 'preset-data-blocks',
          'name': '数据积木布局测试',
          'enabled': false,
          'stacks': [
            for (var index = 0; index < dataTypes.length; index++)
              {
                'id': 'data-stack-$index',
                'x': 40.0,
                'y': 40.0 + index * 68.0,
                'blocks': [
                  {'id': 'data-block-$index', 'type': dataTypes[index]},
                ],
              },
          ],
        },
      ],
    });

    await pumpPage(
      tester,
      const Size(1280, 800),
      preferences: {'obs_automation_presets_v1': raw},
    );

    for (final type in dataTypes) {
      expect(find.byKey(ValueKey('canvas-block-$type')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('built-in EEW M5 recording preset is added disabled and saved', (
    tester,
  ) async {
    await pumpPage(tester, const Size(1280, 800), seedBlankPreset: false);

    expect(find.text('EEW M5 分机构自动录制'), findsOneWidget);
    final enabledSwitch = tester.widget<Switch>(find.byType(Switch));
    expect(enabledSwitch.value, isFalse);
    expect(
      find.byKey(const ValueKey('canvas-block-startRecord')),
      findsNWidgets(7),
    );
    expect(
      find.byKey(const ValueKey('canvas-block-stopRecord')),
      findsNWidgets(7),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('添加 EEW M5 分机构自动录制预设'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final root =
        jsonDecode(prefs.getString('obs_automation_presets_v1')!)
            as Map<String, dynamic>;
    final presets = root['presets'] as List<dynamic>;
    expect(
      presets.cast<Map<String, dynamic>>().where(
        (item) => item['name'] == 'EEW M5 分机构自动录制',
      ),
      hasLength(1),
    );
    final preset = presets.cast<Map<String, dynamic>>().singleWhere(
      (item) => item['name'] == 'EEW M5 分机构自动录制',
    );
    expect(preset['enabled'], isFalse);
    expect(preset['stacks'], hasLength(7));
  });

  testWidgets(
    'every block used by the built-in preset is available in palette',
    (tester) async {
      await pumpPage(tester, const Size(1280, 800), seedBlankPreset: false);

      await selectPaletteCategory(tester, 'UI 数据');
      for (final type in const [
        'inputFieldCondition',
        'unifiedPhase',
        'isEew',
        'isInformation',
        'eewAgency',
        'informationAgency',
        'informationReviewType',
        'eventType',
        'magnitude',
      ]) {
        final key = type == 'inputFieldCondition'
            ? 'palette-uiConditions-$type'
            : 'palette-$type';
        expect(find.byKey(ValueKey(key)), findsOneWidget);
      }

      await selectPaletteCategory(tester, '变量');
      for (final type in const [
        'setEventVariable',
        'setValueVariable',
        'sameEarthquakeAsVariable',
      ]) {
        expect(find.byKey(ValueKey('palette-$type')), findsOneWidget);
      }

      await selectPaletteCategory(tester, '控制');
      expect(
        find.byKey(const ValueKey('palette-waitForUnifiedEvent')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('middle mouse drag pans the canvas on both axes', (tester) async {
    await pumpPage(tester, const Size(1280, 800), seedBlankPreset: false);

    final surface = find.byKey(const ValueKey('automation-canvas-pan-surface'));
    final scrollables = find.descendant(
      of: surface,
      matching: find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.restorationId == null,
      ),
    );
    expect(scrollables, findsNWidgets(2));
    for (var index = 0; index < 2; index++) {
      expect(
        tester.state<ScrollableState>(scrollables.at(index)).position.pixels,
        0,
      );
    }

    final gesture = await tester.startGesture(
      tester.getCenter(surface),
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await gesture.moveBy(const Offset(-120, -90));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    for (var index = 0; index < 2; index++) {
      expect(
        tester.state<ScrollableState>(scrollables.at(index)).position.pixels,
        greaterThan(0),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('toolbar shows live OBS connection state', (tester) async {
    final notifier = ObsAutomationRuntimeService().obs.connectionStateNotifier;
    notifier.value = ObsConnectionState.connected;
    addTearDown(() => notifier.value = ObsConnectionState.disconnected);

    await pumpPage(tester, const Size(1280, 800));

    expect(find.byKey(const ValueKey('obs-connection-status')), findsOneWidget);
    expect(find.text('OBS 已连接'), findsOneWidget);

    notifier.value = ObsConnectionState.reconnecting;
    await tester.pump();
    expect(find.text('OBS 重连中'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile keeps the module palette left of the canvas', (
    tester,
  ) async {
    await pumpPage(tester, const Size(420, 820));

    final eventTemplate = find.byKey(const ValueKey('palette-unifiedEvent'));
    expect(eventTemplate, findsOneWidget);
    expect(find.text('画布为空'), findsOneWidget);
    expect(
      tester.getTopLeft(eventTemplate).dx,
      lessThan(tester.getTopLeft(find.text('画布为空')).dx),
    );

    expect(find.text('OBS'), findsNothing);
    await scrollPaletteCategoryIntoView(tester, 'OBS');
    expect(find.text('OBS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
