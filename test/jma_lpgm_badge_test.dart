import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/sources/jma_lpgm_service.dart';
import 'package:flutterrhythmquake/widgets/ui/unified_alert_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'ordinary JMA badge retains shindo and adds observed LPGM EEW-style footer',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 850));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      final parser = JmaLpgmService();
      final bulletin = parser.parseDetailForTesting(
        File(
          'test/fixtures/jma_lpgm_20261108/20261107161354_0_VXSE62_010000.xml',
        ).readAsStringSync(),
      )!;
      parser.dispose();
      final ordinary = UnifiedQuakeData(
        source: 'jmaEqlist',
        origin: 1,
        eventId: bulletin.eventId,
        isEew: false,
        timeZone: 9,
        titleText: '震源・震度に関する情報',
        reportNumText: '第2报',
        useShindo: true,
        maxIntensity: '4',
        className: 'yellow',
        hypocenter: '静岡県西部',
        magnitude: 5.7,
        depth: 40,
        depthText: '40km',
        originTime: DateTime(2026, 11, 8, 1, 4),
        reportTime: DateTime(2026, 11, 8, 1, 12),
        jmaLpgmBulletin: bulletin,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: UnifiedAlertCard(event: ordinary)),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('jma-eew-long-period-footer')),
        findsOneWidget,
      );
      expect(find.text('长周期 1'), findsOneWidget);

      final standalone = ordinary.copyWith(isJmaLpgm: true, useShindo: false);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: UnifiedAlertCard(event: standalone)),
          ),
        ),
      );
      expect(find.text('1'), findsWidgets);
      expect(find.text('长周期'), findsWidgets);
    },
  );
}
