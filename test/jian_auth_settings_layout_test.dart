import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/widgets/ui/jian_auth_settings.dart';
import 'package:flutterrhythmquake/widgets/ui/settings_controls.dart';

const _preview = bool.fromEnvironment('JIAN_UI_PREVIEW');

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (!_preview) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/ui-previews/jian-$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final scenario in [
    (name: 'desktop', size: const Size(1280, 900), scale: 1.0, keyboard: 0.0),
    (name: 'phone', size: const Size(390, 844), scale: 1.0, keyboard: 0.0),
    (name: 'large-text', size: const Size(320, 568), scale: 2.0, keyboard: 0.0),
    (name: 'keyboard', size: const Size(568, 320), scale: 1.0, keyboard: 140.0),
  ]) {
    testWidgets(
      'shared settings style and reachable actions: ${scenario.name}',
      (tester) async {
        tester.view.physicalSize = scenario.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        if (_preview) {
          await tester.runAsync(() async {
            final loader = FontLoader('JianPreview')
              ..addFont(
                File(
                  '${Platform.environment['SystemRoot']}/Fonts/msyh.ttc',
                ).readAsBytes().then(ByteData.sublistView),
              );
            await loader.load();
            final icons = FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
            await icons.load();
          });
        }
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                brightness: Brightness.dark,
                fontFamily: _preview ? 'JianPreview' : null,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scenario.scale)),
                child: child!,
              ),
              home: Scaffold(
                backgroundColor: const Color(0xFF202024),
                body: Stack(
                  children: [
                    if (_preview)
                      Positioned.fill(
                        child: Opacity(
                          opacity: 0.35,
                          child: Image.asset(
                            'assets/images/madoka_bg.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    Center(
                      child: SizedBox(
                        width: 900,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                '账号与 API 授权',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 18),
                              JianAuthSettings(onChanged: () async {}),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (_preview) {
          await tester.runAsync(
            () => precacheImage(
              const AssetImage('assets/images/madoka_bg.png'),
              key.currentContext!,
            ),
          );
          await tester.pumpAndSettle();
        }
        expect(find.byType(SettingsControlRow), findsOneWidget);
        expect(find.byType(SettingsGlassAction), findsOneWidget);
        final row = tester.widget<SettingsControlRow>(
          find.byType(SettingsControlRow),
        );
        expect(row.leading, Icons.key_outlined);
        await _capture(tester, key, '${scenario.name}-row');
        await tester.tap(find.byTooltip('配置凭证'));
        await tester.pumpAndSettle();
        tester.view.viewInsets = FakeViewPadding(bottom: scenario.keyboard);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(BackdropFilter), findsOneWidget);
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.decoration!.fillColor, SettingsControlStyle.field);
        expect(field.style!.color, Colors.white);
        expect(field.obscureText, isTrue);
        await _capture(tester, key, '${scenario.name}-dialog');
        final save = find.widgetWithText(SettingsGlassAction, '保存');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(find.text('登录密钥无效或已过期，请重新申请。'), findsOneWidget);
        final cancel = find.widgetWithText(SettingsGlassAction, '取消');
        await tester.ensureVisible(cancel);
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
