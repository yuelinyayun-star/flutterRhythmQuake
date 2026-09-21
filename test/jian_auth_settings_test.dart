import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutterrhythmquake/services/jian_auth_service.dart';
import 'package:flutterrhythmquake/widgets/ui/jian_auth_settings.dart';
import 'package:flutterrhythmquake/widgets/ui/settings_controls.dart';

// Controlled protocol inputs, not live credentials or earthquake data.
class RetryStore extends JianCredentialStore {
  int writes = 0;
  @override
  Future<void> write(String token, {DateTime? expiresAt}) async {
    if (++writes == 1) throw StateError('private storage detail');
    await super.write(token, expiresAt: expiresAt);
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final size in [
    const Size(1280, 900),
    const Size(390, 844),
    const Size(320, 568),
  ]) {
    testWidgets('configure and remove credential at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var reloads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JianAuthSettings(
              onChanged: () async {
                reloads++;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('未配置 · 需要鉴权'), findsOneWidget);
      await tester.tap(find.byTooltip('配置凭证'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );
      await tester.enterText(find.byType(TextField), 'rt_ui_test');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(await JianCredentialStore().read(), 'rt_ui_test');
      expect(find.text('长期凭证已保存'), findsOneWidget);
      expect(reloads, 1);
      await tester.tap(find.byTooltip('移除凭证'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await JianCredentialStore().read(), 'rt_ui_test');
      expect(reloads, 1);
      await tester.tap(find.byTooltip('移除凭证'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除'));
      await tester.pumpAndSettle();
      expect(await JianCredentialStore().read(), isEmpty);
      expect(reloads, 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('one-time exchange survives failed secure write and cancel', (
    tester,
  ) async {
    var exchanges = 0;
    final auth = JianAuthService(
      client: MockClient((_) async {
        exchanges++;
        return http.Response(
          jsonEncode({
            'ok': true,
            'token': 'rt_ui_test',
            'expires_after_min': 60,
          }),
          200,
        );
      }),
    );
    addTearDown(auth.close);
    final store = RetryStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JianAuthSettings(
            store: store,
            auth: auth,
            onChanged: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('配置凭证'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'lk_ui_test');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('安全保存失败，凭证暂留本窗口，请重试保存。'), findsOneWidget);
    expect(exchanges, 1);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的凭证？'), findsOneWidget);
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(exchanges, 1);
    expect(store.writes, 2);
    expect(await store.read(), 'rt_ui_test');
    expect((await store.readCredential()).expiresAt, isNotNull);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'invalid access token input makes no request; busy exchange blocks closing',
    (tester) async {
      var exchanges = 0;
      final pending = Completer<http.Response>();
      final auth = JianAuthService(
        client: MockClient((_) {
          exchanges++;
          return pending.future;
        }),
      );
      addTearDown(auth.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JianAuthSettings(auth: auth, onChanged: () async {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('配置凭证'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'at_ui_test');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(exchanges, 0);
      await tester.enterText(find.byType(TextField), 'lk_ui_test');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(exchanges, 1);
      expect(
        tester
            .widget<SettingsGlassAction>(
              find.widgetWithText(SettingsGlassAction, '取消'),
            )
            .onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(Dialog), findsOneWidget);
      pending.complete(
        http.Response(
          '{"ok":true,"token":"rt_ui_test","expires_after_min":60}',
          200,
        ),
      );
      await tester.pumpAndSettle();
      expect(await JianCredentialStore().read(), 'rt_ui_test');
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
