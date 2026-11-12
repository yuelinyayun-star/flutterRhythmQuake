import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/jma_lpgm_bulletin.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/sources/jma_lpgm_service.dart';
import 'package:flutterrhythmquake/widgets/ui/jma_lpgm_sidebar_panel.dart';

void main() {
  UnifiedQuakeData earthquake({
    String source = 'jmaEqlist',
    bool isEew = false,
    bool isJmaLpgm = false,
    String title = '震源・震度に関する情報',
    String report = '第2报',
  }) => UnifiedQuakeData(
    source: source,
    origin: 2,
    eventId: '20261108215040',
    isEew: isEew,
    isJmaLpgm: isJmaLpgm,
    timeZone: 9,
    titleText: title,
    reportNumText: report,
    useShindo: !isJmaLpgm,
    maxIntensity: isJmaLpgm ? '1' : '5+',
    className: isJmaLpgm ? 'yellow' : 'dark-orange',
    hypocenter: '静岡県西部',
  );

  test(
    'VXSE53 heading omits Chinese/Japanese report numbers only for JMA info',
    () {
      for (final source in ['jmaEqlist', 'p2pJmaEqlist']) {
        for (final report in ['第2报', '第2報', '第２報', '第 2 报']) {
          final e = earthquake(source: source, report: report);
          expect(
            UnifiedEventPresentation.fromEvent(e).title,
            '震源・震度に関する情報',
            reason: '$source $report',
          );
          expect(
            e.reportNumText,
            report,
            reason: 'keep report metadata for ordering',
          );
        }
        expect(
          UnifiedEventPresentation.fromEvent(
            earthquake(source: source, report: '第2报（訂正）'),
          ).title,
          '震源・震度に関する情報 訂正',
        );
        expect(
          UnifiedEventPresentation.fromEvent(
            earthquake(source: source, report: '取消'),
          ).title,
          '震源・震度に関する情報 取消',
        );
      }
    },
  );

  test('VXSE62 heading stays exact JMA observation name across updates', () {
    for (final report in ['第1报', '第2报', '第3報']) {
      final e = earthquake(
        source: 'jmaLpgm',
        title: '长周期地震动',
        report: report,
        isJmaLpgm: true,
      );
      expect(
        UnifiedEventPresentation.fromEvent(e).title,
        jmaLpgmObservationTitle,
      );
      expect(
        e.reportNumText,
        report,
        reason: 'serial still drives revision handling',
      );
    }
  });

  test(
    'regression: report serials still display for EEW and other bulletins',
    () {
      for (final scenario in [
        (source: 'jmaEew', isEew: true),
        (source: 'cwaEew', isEew: true),
        (source: 'cwaEqlist', isEew: false),
        (source: 'usgsEqlist', isEew: false),
        (source: 'emsc', isEew: false),
      ]) {
        final event = earthquake(
          source: scenario.source,
          isEew: scenario.isEew,
          title: '特殊情报',
          report: '第3报',
        );
        expect(
          UnifiedEventPresentation.fromEvent(event).title,
          '特殊情报 第3报',
          reason: 'unrelated source ${scenario.source} must keep its serial',
        );
      }
      final noSerial = earthquake(source: 'jmaEew', isEew: true, report: '第4報');
      expect(
        UnifiedEventPresentation.fromEvent(noSerial).title,
        '震源・震度に関する情報 第4報',
        reason: 'JMA EEW must not inherit ordinary observation suppression',
      );
    },
  );

  testWidgets(
    'real VXSE62 sidebar shows exact title but not the second serial',
    (tester) async {
      final service = JmaLpgmService();
      final bulletin = service.parseDetailForTesting(
        File(
          'test/fixtures/jma_lpgm_20261108/20261107161354_0_VXSE62_010000.xml',
        ).readAsStringSync(),
      )!;
      service.dispose();

      final updated = JmaLpgmBulletin.fromMap({
        ...bulletin.toMap(),
        'serial': 2,
      });
      expect(updated.serial, 2);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 234,
              height: 274,
              child: JmaLpgmSidebarPanel(bulletin: updated, scale: (n) => n),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(jmaLpgmObservationTitle), findsOneWidget);
      expect(
        tester.widget<Text>(find.text(jmaLpgmObservationTitle)).maxLines,
        2,
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('第 2 报'), findsNothing);
      expect(find.textContaining('JMA · VXSE62'), findsOneWidget);
    },
  );
}
