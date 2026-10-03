import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutterrhythmquake/models/source_status.dart';
import 'package:flutterrhythmquake/models/source_credential_info.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_motion_service.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_source_status.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_source_catalog.dart';
import 'package:flutterrhythmquake/services/sources/source_manager.dart';
import 'package:flutterrhythmquake/widgets/map/source_dashboard.dart';
import 'package:flutterrhythmquake/widgets/map/global_station_status_row.dart';
import 'package:flutterrhythmquake/widgets/map/quake_map_view.dart';
import 'package:flutterrhythmquake/widgets/ui/station_dashboard.dart';

class _Provider extends ChangeNotifier implements QuakeProvider {
  @override
  final sourceStatusListenable = ValueNotifier<int>(0);
  @override
  Map<String, SourceStatus> get sourceStatuses => {
    'Wolfx': SourceStatus.connected,
  };
  @override
  String? sourceAuthenticationStatus(String source) => null;
  @override
  SourceCredentialInfo? sourceCredentialInfo(String source) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  void dispose() {
    sourceStatusListenable.dispose();
    super.dispose();
  }
}

void main() {
  const preview = bool.fromEnvironment('SOURCE_UI_PREVIEW');
  setUpAll(() async {
    await (FontLoader('JetBrainsMono')
          ..addFont(rootBundle.load('assets/fonts/JetBrainsMono-Variable.ttf')))
        .load();
    if (!preview) return;
    await (FontLoader('Microsoft YaHei')..addFont(
          Future.value(
            ByteData.sublistView(
              await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
            ),
          ),
        ))
        .load();
  });
  for (final (size, mobile) in [
    (const Size(320, 640), true),
    (const Size(390, 844), true),
    (const Size(844, 390), true),
    (const Size(800, 900), false),
    (const Size(1600, 900), false),
  ]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        'global source counts stay separate and fit $size / $textScale',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final enabled = QuakeMapView.fdsnSeedLinkEnabledNotifier.value;
          final nied = QuakeMapView.niedMonitorEnabledNotifier.value;
          final wolfx = SourceManager().isSourceEnabled('Wolfx');
          final service = FdsnMotionService();
          final old = service.sourceStatusesNotifier.value;
          addTearDown(() {
            QuakeMapView.fdsnSeedLinkEnabledNotifier.value = enabled;
            QuakeMapView.niedMonitorEnabledNotifier.value = nied;
            SourceManager().setSourceEnabled('Wolfx', wolfx);
            service.acceptSourceStatuses(old);
          });
          QuakeMapView.fdsnSeedLinkEnabledNotifier.value = true;
          QuakeMapView.niedMonitorEnabledNotifier.value = true;
          SourceManager().setSourceEnabled('Wolfx', true);
          // UI fixtures only, no connection or waveform input.
          final statuses = [
            for (var i = 0; i < FdsnSourceCatalog.sources.length; i++)
              FdsnSourceStatus(
                source: FdsnSourceCatalog.sources[i].name,
                state: i == 5
                    ? FdsnSourceConnectionState.failed
                    : i == 6
                    ? FdsnSourceConnectionState.idle
                    : FdsnSourceConnectionState.streaming,
                selected: 100,
                timely: 100 - i * 15,
                stale: i * 15,
              ),
          ];
          service.acceptSourceStatuses(statuses.reversed.toList());
          final provider = _Provider();
          final boundary = GlobalKey();
          await tester.pumpWidget(
            ChangeNotifierProvider<QuakeProvider>.value(
              value: provider,
              child: MaterialApp(
                theme: preview
                    ? ThemeData(fontFamilyFallback: const ['Microsoft YaHei'])
                    : null,
                home: MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: TextScaler.linear(textScale),
                  ),
                  child: Scaffold(
                    backgroundColor: const Color(0xFF202124),
                    body: RepaintBoundary(
                      key: boundary,
                      child: Stack(
                        children: [
                          if (!mobile)
                            StationDashboard(data: StationSummaryData()),
                          SourceDashboard(mobile: mobile),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          final group = find.byKey(const ValueKey('global-station-statuses'));
          expect(group, findsOneWidget);
          final left = tester.getTopLeft(group).dx;
          final sourceRect = tester.getRect(find.text('Wolfx'));
          final rowWidget = tester.widget<GlobalStationStatusRow>(
            find.byType(GlobalStationStatusRow),
          );
          await tester.pump(const Duration(seconds: 1));
          expect(
            identical(
              rowWidget,
              tester.widget<GlobalStationStatusRow>(
                find.byType(GlobalStationStatusRow),
              ),
            ),
            isTrue,
            reason: 'Clock ticks must not rebuild global station text',
          );
          final stationLine = find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText().startsWith('強震モニタ:'),
          );
          final timeRect = tester.getRect(stationLine);
          expect(left, closeTo(timeRect.left, .01));
          final paragraph = tester.renderObject<RenderParagraph>(stationLine);
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(
              baseOffset: 0,
              extentOffset: paragraph.text.toPlainText().length,
            ),
          );
          expect(
            boxes.map((box) => box.top).toSet(),
            hasLength(1),
            reason: 'The timestamp and UTC must remain on the same line',
          );
          expect(
            tester.getRect(group).top,
            greaterThanOrEqualTo(tester.getRect(stationLine).bottom - .01),
          );
          expect(
            tester.getRect(group).top,
            greaterThan(tester.getRect(find.text('Wolfx')).bottom),
          );
          final texts = tester
              .widgetList<Text>(
                find.descendant(of: group, matching: find.byType(Text)),
              )
              .toList();
          expect(texts.map((t) => t.data), [
            for (final s in statuses)
              '${s.source}(${s.linked})',
          ]);
          for (final s in statuses) {
            final text = find.byKey(ValueKey('global-station-${s.source}'));
            final rect = tester.getRect(text);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(size.width));
            expect(rect.bottom, lessThanOrEqualTo(size.height));
            expect(
              tester.widget<Text>(text).style!.color,
              globalStationStatusColor(s),
            );
            expect(find.descendant(of: group, matching: text), findsOneWidget);
          }
          expect(
            texts.any(
              (t) => t.data!.contains('UTC') || t.data!.contains('FDSN'),
            ),
            isFalse,
          );
          expect(tester.takeException(), isNull);
          if (preview &&
              textScale == 1 &&
              (size.width == 390 || size.width == 1600)) {
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage();
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                'build/ui-previews/global-stations-${size.width.toInt()}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(png!.buffer.asUint8List());
              image.dispose();
            });
          }
          service.acceptSourceStatuses([statuses.first]);
          await tester.pump();
          expect(tester.getTopLeft(group).dx, closeTo(left, .01));
          expect(
            tester.getRect(find.text('Wolfx')).left,
            closeTo(sourceRect.left, .01),
          );
          expect(tester.getRect(stationLine).size, timeRect.size);
          expect(
            find.byKey(const ValueKey('global-station-GeoNet')),
            findsNothing,
          );
          QuakeMapView.fdsnSeedLinkEnabledNotifier.value = false;
          await tester.pump();
          expect(group, findsNothing);
          expect(
            tester.getRect(find.text('Wolfx')).left,
            closeTo(sourceRect.left, .01),
          );
          expect(tester.getRect(stationLine).left, closeTo(timeRect.left, .01));
          expect(tester.getRect(stationLine).size, timeRect.size);
          await tester.pumpWidget(const SizedBox());
          provider.dispose();
        },
      );
    }
  }
}
