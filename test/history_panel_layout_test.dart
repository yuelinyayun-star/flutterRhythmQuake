import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/widgets/ui/history_panel.dart';
import 'package:provider/provider.dart';

class HistoryProvider extends ChangeNotifier implements QuakeProvider {
  @override
  final historyListenable = ValueNotifier<int>(0);
  @override
  final List<EewEventGroup> eewHistory;
  HistoryProvider(this.eewHistory);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  void dispose() {
    historyListenable.dispose();
    super.dispose();
  }
}

// Controlled layout samples, not earthquake observations or incoming reports.
EewEventGroup sample(
  String id, {
  int reports = 1,
  bool long = false,
  bool api = true,
}) {
  final event = UnifiedQuakeData(
    source: 'jmaEew',
    origin: 3,
    eventId: id,
    isEew: true,
    timeZone: 9,
    titleText: long ? '緊急地震速報（予報）と長い情報タイトルの表示確認' : '地震预警',
    reportNumText: reports > 1 ? '第$reports报（最终）' : '',
    useShindo: true,
    maxIntensity: '4',
    className: 'yellow',
    hypocenter: long ? '奄美大島近海・非常に長い地域名の表示確認' : '日向灘',
    originTime: DateTime.utc(2026, 9, 21, 13, 38),
    magnitude: 4.8,
    depth: 30,
    depthText: '深さ：30km',
    apiTypeLabel: api ? 'WHEWS' : '',
  );
  return EewEventGroup(
    eventId: id,
    firstArrivedAt: DateTime.utc(2026, 9, 21),
    reports: [
      event,
      for (var n = reports - 1; n > 0; n--)
        event.copyWith(reportNumText: '第$n报'),
    ],
  );
}

void main() {
  const preview = bool.fromEnvironment('HISTORY_UI_PREVIEW');
  setUpAll(() async {
    if (preview) {
      final font = FontLoader('HistoryTest');
      font.addFont(
        Future.value(
          ByteData.sublistView(
            await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
          ),
        ),
      );
      await font.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
  });
  for (final width in [280.0, 350.0, 430.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'equal collapsed cards and working expansion at $width / $scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final provider = HistoryProvider([
            sample('single', api: false),
            sample('multiple', reports: 7, long: true),
            sample('another', reports: 12),
          ]);
          addTearDown(provider.dispose);
          await tester.pumpWidget(
            ChangeNotifierProvider<QuakeProvider>.value(
              value: provider,
              child: MaterialApp(
                theme: ThemeData.dark().copyWith(
                  textTheme: ThemeData.dark().textTheme.apply(
                    fontFamily: preview ? 'HistoryTest' : null,
                  ),
                ),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 1100),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: const Scaffold(
                    body: RepaintBoundary(
                      key: ValueKey('preview'),
                      child: HistoryPanel(),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          Finder card(String id) => find
              .ancestor(
                of: find.byKey(ValueKey('history-summary-$id')),
                matching: find.byType(Material),
              )
              .first;
          final single = tester.getSize(card('single'));
          expect(tester.getSize(card('multiple')), single);
          expect(tester.getSize(card('another')), single);
          expect(tester.takeException(), isNull);
          expect(find.byIcon(Icons.expand_more), findsNWidgets(2));
          if (preview && width == 350) {
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('preview')),
              );
              final image = await boundary.toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File('build/ui-previews/history-$scale.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.tap(find.text('7报'));
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.expand_less), findsOneWidget);
          expect(
            tester.getSize(card('multiple')).height,
            greaterThan(single.height),
          );
          expect(tester.getSize(card('single')), single);
          await tester.tap(find.text('7报'));
          await tester.pumpAndSettle();
          expect(tester.getSize(card('multiple')), single);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
