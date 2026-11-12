import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/core/utils/alert_voice_helper.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/fan_service.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/eqlist_manager.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'package:flutterrhythmquake/widgets/ui/cmt_badge.dart';

import 'support/unified_ui_fonts.dart';

void main() {
  for (final source in ['fssn', 'fssn-cmt']) {
    testWidgets('captured $source renders existing unified UI and API label', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      SoundEffectService().enabled = false;
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final raw =
          jsonDecode(
                File(
                  'test/fixtures/fssn_direct_20261017/initial_all.original.json',
                ).readAsStringSync(encoding: utf8),
              )[source]['Data']
              as Map<String, dynamic>;
      final decoded = FanService.decodeFssnPayload(
        raw,
        cmt: source == 'fssn-cmt',
      )!;
      final before = jsonEncode(raw);
      final provider = (await tester.runAsync(
        () async => QuakeProvider(startCatalogServices: false),
      ))!;
      final mapState = MapStateProvider();
      provider.selectHistoryMapProducts(
        decoded.message.copyWith(isHistory: true),
      );
      var effects = 0;
      provider.onUnifiedEventNotified = (_, _) => effects++;
      await tester.runAsync(loadUnifiedUiFonts);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<QuakeProvider>.value(value: provider),
            ChangeNotifierProvider.value(value: mapState),
          ],
          child: MaterialApp(
            theme: unifiedUiTestTheme(),
            home: const Scaffold(body: AlertModule()),
          ),
        ),
      );
      await tester.pump();
      final displayed = provider.unifiedDisplayEvents.single;
      expect(displayed.source, source == 'fssn' ? 'fssnEqlist' : 'fssnCmt');
      expect(displayed.apiTypeLabel, 'FSSN');
      expect(find.text('FSSN'), findsOneWidget);
      expect(find.textContaining(displayed.hypocenter), findsWidgets);
      if (source == 'fssn-cmt') expect(find.byType(CmtBadge), findsOneWidget);
      expect(
        AlertVoiceHelper.generateUnifiedEventText(
          decoded.unified,
          phase: 'first',
        ),
        contains('FSSN'),
      );
      expect(effects, 0);
      expect(jsonEncode(raw), before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
      mapState.dispose();
      SoundEffectService().enabled = true;
      for (final rows in EqlistManager().getAllBuckets().values) {
        rows.clear();
      }
    });
  }
}
