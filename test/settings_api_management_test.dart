import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/page_background_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/jian_auth_service.dart';
import 'package:flutterrhythmquake/services/sources/kma_pews_eew_service.dart';
import 'package:flutterrhythmquake/services/sources/sasmex_service.dart';
import 'package:flutterrhythmquake/services/sources/source_manager.dart';
import 'package:flutterrhythmquake/services/wauth_credential_store.dart';
import 'package:flutterrhythmquake/widgets/ui/settings_controls.dart';
import 'package:flutterrhythmquake/widgets/ui/settings_page.dart';
import 'package:flutterrhythmquake/widgets/ui/app_page_background.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/unified_ui_fonts.dart';

const preview = bool.fromEnvironment('SETTINGS_API_PREVIEW');

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (!preview) return;
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/ui-previews/api-management-$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Finder settingRow(String title) => find.byWidgetPredicate(
  (widget) => widget is SettingsControlRow && widget.title == title,
);

void main() {
  for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
    testWidgets('API groups, source separation and persisted controls at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rhythmInitiallyEnabled = size.width >= 600;
      SharedPreferences.setMockInitialValues({
        SasmexService.enabledPreferenceKey: rhythmInitiallyEnabled,
        'api_source_rhythm_kma_eew_enabled': !rhythmInitiallyEnabled,
        KmaPewsEewService.enabledPreferenceKey: false,
        if (size.width < 600) ...{
          'jian_default_server_index': 1,
          'whews_default_server_index': 1,
        },
      });
      FlutterSecureStorage.setMockInitialValues({});
      // UI-only credentials in mocked storage; no real authentication requests.
      await JianCredentialStore().write('rt_settings_ui_case');
      await WAuthCredentialStore().writeApiToken(apiToken: 'settings-ui-case');
      final quake = QuakeProvider(startCatalogServices: false);
      final map = MapStateProvider();
      final background = PageBackgroundProvider();
      final key = GlobalKey();
      if (preview) {
        await tester.runAsync(() async {
          await loadUnifiedUiFonts();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
      }
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: quake),
            ChangeNotifierProvider.value(value: map),
            ChangeNotifierProvider.value(value: background),
          ],
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: preview ? unifiedUiTestTheme() : ThemeData.dark(),
              home: const SettingsPage(),
            ),
          ),
        ),
      );
      // The real settings entry loads preferences and the native voice probe.
      for (var i = 0; i < 60 && find.text('API 管理').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      if (preview) {
        await tester.runAsync(
          () => precacheImage(
            const AssetImage(AppPageBackground.assetPath),
            key.currentContext!,
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('API 管理'), findsNWidgets(size.width >= 600 ? 2 : 1));
      expect(find.text('API与数据源'), findsNothing);
      final scrollable = find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first;
      final suffix = size.width > 600 ? 'desktop' : 'phone';
      await capture(tester, key, '$suffix-top');

      for (final (id, title, rows) in [
        (
          'fan',
          '启用 FAN Studio API',
          ['FAN Studio API Key', 'FAN Studio 默认服务器'],
        ),
        ('wolfx', '启用 Wolfx API', ['Wolfx SeisJS']),
        (
          'whews',
          '启用 WHEWS API',
          [
            'WAuth API Token',
            'WAuth 账号授权',
            '退出 WAuth 授权',
            'WHEWS 默认服务器',
            'WHEWS NIED 实时测站',
            'WHEWS S-Net 实时测站',
            'WHEWS KMA 实时测站',
          ],
        ),
        (
          'jian',
          '启用 JIAN API',
          ['Jian 个人鉴权', '查看长期 Token', '移除凭证', 'JIAN 默认服务器'],
        ),
        ('rhythm', '启用 Rhythm API', <String>[]),
      ]) {
        final group = find.byKey(ValueKey('settings-api-$id'));
        // ListView lays out this section lazily; reach it by its first row.
        await tester.scrollUntilVisible(
          settingRow(title),
          160,
          scrollable: scrollable,
        );
        expect(group, findsOneWidget);
        for (final row in [title, ...rows]) {
          expect(
            find.descendant(of: group, matching: settingRow(row)),
            findsOneWidget,
          );
        }
        final toggle = find.descendant(
          of: settingRow(title),
          matching: find.byType(Switch),
        );
        await Scrollable.ensureVisible(tester.element(toggle), alignment: 0.5);
        await tester.pumpAndSettle();
        final before = tester.widget<Switch>(toggle).value;
        if (id == 'rhythm') {
          final manager = SourceManager();
          expect(
            find.descendant(of: group, matching: find.byType(Switch)),
            findsOneWidget,
          );
          expect(before, rhythmInitiallyEnabled);
          expect(manager.isSourceEnabled(SasmexService.sourceName), before);
          expect(
            manager.isSourceEnabled(RhythmKmaEewService.sourceName),
            before,
          );
        }
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        final prefs = await SharedPreferences.getInstance();
        final preferenceKey = switch (id) {
          'jian' => 'api_source_jian_enabled',
          'rhythm' => 'api_source_sasmex_enabled',
          _ => 'api_source_${id}_enabled',
        };
        expect(prefs.getBool(preferenceKey), !before, reason: id);
        if (id == 'rhythm') {
          final manager = SourceManager();
          expect(manager.isSourceEnabled(SasmexService.sourceName), !before);
          expect(
            manager.isSourceEnabled(RhythmKmaEewService.sourceName),
            !before,
          );
          expect(
            manager.isSourceEnabled(KmaPewsEewService.sourceName),
            isFalse,
          );
        }
        if (id == 'whews' || id == 'jian') {
          final serverRow = settingRow('${id.toUpperCase()} 默认服务器');
          final dropdown = find.descendant(
            of: serverRow,
            matching: find.byType(PopupMenuButton<int>),
          );
          final primary = id == 'jian' ? 'api.sismotide.top' : 'api.2v8.cn';
          final backup = id == 'jian'
              ? 'api.jianproject.cloud'
              : 'api.beecld.com';
          final displayed = size.width < 600 ? backup : primary;
          expect(
            find.descendant(of: serverRow, matching: find.text(displayed)),
            findsOneWidget,
            reason: 'Restore the saved preferred server on settings entry',
          );
          await Scrollable.ensureVisible(
            tester.element(dropdown),
            alignment: 0.5,
          );
          await tester.pumpAndSettle();
          await tester.tap(dropdown);
          await tester.pumpAndSettle();
          final host = backup;
          await tester.tap(find.text(host).last);
          await tester.pumpAndSettle();
          expect(prefs.getInt('${id}_default_server_index'), 1);
          expect(
            find.descendant(of: serverRow, matching: find.text(host)),
            findsOneWidget,
          );
          await capture(tester, key, '$suffix-$id');
        }
      }

      for (final (id, title) in [
        ('p2p', 'P2PQuake'),
        ('fssn', 'FSSN 地震情报/震源机制解'),
        ('nowquake', 'NowQuake'),
        ('cenc-cmt', 'CENC 震源机制解 (CMT)'),
        ('nied', 'NIED 強震モニタ'),
      ]) {
        await tester.scrollUntilVisible(
          settingRow(title),
          160,
          scrollable: scrollable,
        );
        expect(
          find.descendant(
            of: find.byKey(ValueKey('settings-api-$id')),
            matching: settingRow(title),
          ),
          findsOneWidget,
        );
      }
      await tester.scrollUntilVisible(
        settingRow('EarthScope'),
        160,
        scrollable: scrollable,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('settings-api-seedlink')),
          matching: settingRow('EarthScope'),
        ),
        findsOneWidget,
      );
      final earthScopeToggle = find.descendant(
        of: settingRow('EarthScope'),
        matching: find.byType(Switch),
      );
      await Scrollable.ensureVisible(
        tester.element(earthScopeToggle),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(earthScopeToggle);
      await tester.pumpAndSettle();
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'map_overlay_fdsnEarthScope',
        ),
        isTrue,
      );
      expect(map.isOverlayEnabled('fdsnEarthScope'), isTrue);
      await tester.scrollUntilVisible(
        settingRow('KMA 实时测站'),
        -160,
        scrollable: scrollable,
      );
      final kmaGroup = find.byKey(const ValueKey('settings-api-kma'));
      expect(
        find.descendant(of: kmaGroup, matching: settingRow('KMA 实时测站数据源')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        settingRow('NIED 強震モニタ'),
        160,
        scrollable: scrollable,
      );
      final niedGroup = find.byKey(const ValueKey('settings-api-nied'));
      expect(
        find.descendant(of: niedGroup, matching: settingRow('NIED 強震モニタ 数据源')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: niedGroup, matching: settingRow('NIED 回放')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: kmaGroup, matching: settingRow('KMA 加速度保持')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        settingRow('EarthScope'),
        160,
        scrollable: scrollable,
      );
      final seedLinkGroup = find.byKey(const ValueKey('settings-api-seedlink'));
      for (final title in ['连接上限', 'SeedLink测站显示样式', 'SeedLink测站数值与配色']) {
        expect(
          find.descendant(of: seedLinkGroup, matching: settingRow(title)),
          findsOneWidget,
          reason: title,
        );
      }
      await tester.tap(find.text('预警及信息设置').first);
      await tester.pumpAndSettle();
      expect(find.text('预警接收开关'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-eew-channels')),
        findsOneWidget,
      );
      final jmaEewSwitch = find.byKey(
        const ValueKey('eew-channel-switch-jmaEew'),
      );
      expect(jmaEewSwitch, findsOneWidget);
      expect(tester.widget<Switch>(jmaEewSwitch).value, isTrue);
      await tester.tap(jmaEewSwitch);
      await tester.pumpAndSettle();
      expect(quake.isEewChannelEnabled('jmaEew'), isFalse);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'eew_channel_enabled_jmaEew',
        ),
        isFalse,
      );
      await tester.tap(jmaEewSwitch);
      await tester.pumpAndSettle();
      expect(quake.isEewChannelEnabled('jmaEew'), isTrue);
      expect(find.byKey(const ValueKey('settings-api-fan')), findsNothing);
      expect(find.text('FAN Studio API Key'), findsNothing);
      await capture(tester, key, '$suffix-sources');
      final dataScrollable = find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('信息情报接收过滤设置'),
        200,
        scrollable: dataScrollable,
      );
      expect(find.text('信息情报接收过滤设置'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-info-mag-filter')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      quake.dispose();
      map.dispose();
      background.dispose();
    });
  }
}
