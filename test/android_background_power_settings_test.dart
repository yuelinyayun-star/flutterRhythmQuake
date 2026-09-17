import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/android_background_settings.dart';
import 'package:flutterrhythmquake/widgets/ui/android_background_power_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutterrhythmquake/system_settings');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];
  Map<String, Object?> status = {};
  bool failRead = false;
  bool openResult = true;

  setUp(() {
    calls.clear();
    status = {
      'batteryOptimizationExempt': false,
      'powerSaveMode': true,
      'backgroundRestricted': true,
    };
    failRead = false;
    openResult = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'getBackgroundPowerStatus') {
        if (failRead) throw PlatformException(code: 'UNAVAILABLE');
        return status;
      }
      return openResult;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> mount(WidgetTester tester, {double width = 360}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: const AndroidBackgroundPowerSettings(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('missing and malformed status fields remain unknown', () {
    final parsed = AndroidBackgroundPowerStatus.fromMap({
      'batteryOptimizationExempt': 'true',
      'backgroundRestricted': 0,
    });
    expect(parsed.batteryOptimizationExempt, isNull);
    expect(parsed.backgroundRestricted, isNull);
    expect(parsed.powerSaveMode, isNull);
  });

  test('bridge preserves true, false and unavailable status', () async {
    status = {
      'batteryOptimizationExempt': true,
      'powerSaveMode': false,
      'backgroundRestricted': null,
    };
    final parsed = await AndroidBackgroundSettings().readStatus();
    expect(parsed.batteryOptimizationExempt, isTrue);
    expect(parsed.powerSaveMode, isFalse);
    expect(parsed.backgroundRestricted, isNull);
  });

  testWidgets(
    'renders actual restrictions without claiming vendor authorization',
    (tester) async {
      await mount(tester);
      expect(find.text('电池优化：未豁免', findRichText: true), findsOneWidget);
      expect(find.text('系统省电模式：已开启', findRichText: true), findsOneWidget);
      expect(find.text('系统后台限制：受限制', findRichText: true), findsOneWidget);
      expect(find.text('厂商自启动权限：需在系统中确认', findRichText: true), findsOneWidget);
      expect(calls, ['getBackgroundPowerStatus']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('opening settings never marks exemption as granted', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byTooltip('打开系统电池优化设置'));
    await tester.pumpAndSettle();
    expect(calls.last, 'openBatteryOptimizationSettings');
    expect(find.text('电池优化：未豁免', findRichText: true), findsOneWidget);
    await tester.tap(find.byTooltip('打开应用系统设置'));
    await tester.pumpAndSettle();
    expect(calls.last, 'openAppSettings');
  });

  testWidgets('returning from system settings refreshes permissions', (
    tester,
  ) async {
    await mount(tester);
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.inactive,
    );
    status['batteryOptimizationExempt'] = true;
    status['backgroundRestricted'] = false;
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pumpAndSettle();
    expect(find.text('电池优化：已豁免', findRichText: true), findsOneWidget);
    expect(find.text('系统后台限制：未受限制', findRichText: true), findsOneWidget);
    expect(
      calls.where((method) => method == 'getBackgroundPowerStatus'),
      hasLength(2),
    );
  });

  testWidgets('failed refresh clears previously successful status', (
    tester,
  ) async {
    status['batteryOptimizationExempt'] = true;
    await mount(tester);
    failRead = true;
    await tester.tap(find.byTooltip('刷新后台状态'));
    await tester.pumpAndSettle();
    expect(find.text('系统后台状态：读取失败', findRichText: true), findsOneWidget);
    expect(find.text('电池优化：未知', findRichText: true), findsOneWidget);
    expect(find.text('电池优化：已豁免', findRichText: true), findsNothing);
  });

  testWidgets('unavailable settings reports failure', (tester) async {
    openResult = false;
    await mount(tester);
    await tester.tap(find.byTooltip('打开应用系统设置'));
    await tester.pumpAndSettle();
    expect(find.text('无法打开系统设置，请在手机设置中查看本应用。'), findsOneWidget);
  });

  testWidgets('narrow layout with large text does not overflow', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await mount(tester, width: 280);
    expect(tester.takeException(), isNull);
  });
}
