import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/core/app_edition.dart';
import 'package:flutterrhythmquake/services/sources/cwa_station_service.dart';
import 'package:flutterrhythmquake/services/sources/kma_monitor.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/palert_service.dart';
import 'package:flutterrhythmquake/services/sources/seisjs_service.dart';
import 'package:flutterrhythmquake/widgets/ui/station_dashboard.dart';

// Isolated typography fixtures, never injected into live station sources.
StationSummaryData summary(int level, int index, double shindo) =>
    StationSummaryData()
      ..niedMaxStation = NiedStation(
        id: 0,
        code: 'TEST',
        name: 'TEST',
        coordinate: const LatLng(0, 0),
        network: 'TEST',
        prefecture: '',
        expireSeconds: 10,
        level: level,
      )
      ..snetTopStations = [
        SnetTopStation(code: 'TEST', shindo: shindo, jmaIndex: index),
      ]
      ..treaMaxStation = CwaStation(
        id: 'TEST',
        code: 0,
        net: 'TEST',
        coordinate: const LatLng(0, 0),
        work: true,
        intensity: shindo,
      )
      ..pAlertMaxStation = PAlertStation(
        id: 'TEST',
        network: 'TEST',
        name: 'TEST',
        area: '',
        coordinate: const LatLng(0, 0),
        heldLevel: level,
      )
      ..kmaMaxStation = KmaStation(
        id: 0,
        coordinate: const LatLng(0, 0),
        intensity: 6,
      )
      ..seisJsMaxStation = SeisJsStation(
        id: 'TEST',
        region: '',
        coordinate: const LatLng(0, 0),
        intensity: 5,
      );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'MPLUSRounded1c',
    )..addFont(rootBundle.load('assets/fonts/MPLUSRounded1c-Bold.ttf'))).load();
  });
  for (final (size, textScale) in [
    (const Size(320, 640), 1.0),
    (const Size(390, 844), 1.3),
    (const Size(1280, 720), 1.0),
    (const Size(1920, 1080), 1.3),
  ]) {
    testWidgets('station shindo superscripts preserve layout $size/$textScale', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final boundary = GlobalKey();
      final phone = size.width < 600;
      final sources = [
        'NIED',
        'S-net',
        'TREM',
        if (AppEdition.hasPAlertStations) 'P-Alert',
      ];
      final originalRects = <String, Rect>{};
      Future<void> mount(StationSummaryData data) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'MPLUSRounded1c'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: RepaintBoundary(
              key: boundary,
              child: Scaffold(
                backgroundColor: const Color(0xFF303030),
                body: Stack(
                  children: [
                    if (phone)
                      Positioned(
                        right: 12,
                        top: 60,
                        width: 75,
                        height: 420,
                        child: StationDashboard(data: data, phoneMode: true),
                      )
                    else
                      StationDashboard(data: data),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        if (phone) {
          final orderedSources = [
            'NIED',
            'S-net',
            'KMA',
            'SeisJS',
            'TREM',
            if (AppEdition.hasPAlertStations) 'P-Alert',
          ];
          for (var i = 0; i < orderedSources.length; i++) {
            final card = find.byKey(
              ValueKey('station-max-${orderedSources[i]}'),
            );
            final frame = find
                .ancestor(of: card, matching: find.byType(ClipRRect))
                .first;
            expect(
              tester.getRect(frame),
              Rect.fromLTWH(size.width - 87, 63 + i * 70, 75, 64),
              reason:
                  'outer frame size/position must not expand when a source is hidden',
            );
          }
        }
      }

      for (final (level, index, shindo, label) in [
        (16, 5, 4.6, '5-'),
        (17, 6, 5.1, '5+'),
        (18, 7, 5.6, '6-'),
        (19, 8, 6.1, '6+'),
        (20, 9, 6.6, '7'),
      ]) {
        final data = summary(level, index, shindo);
        await mount(data);
        for (final source in sources) {
          final card = find.byKey(ValueKey('station-max-$source'));
          final rect = tester.getRect(card);
          originalRects.putIfAbsent(source, () => rect);
          expect(
            rect,
            originalRects[source],
            reason: 'no card shift for $source/$label',
          );
          final main = find.descendant(of: card, matching: find.text(label[0]));
          expect(main, findsOneWidget);
          if (label.length == 2) {
            final suffix = find.descendant(
              of: card,
              matching: find.text(label[1]),
            );
            expect(suffix, findsOneWidget);
            final mainRect = tester.getRect(main),
                suffixRect = tester.getRect(suffix);
            expect(suffixRect.left, greaterThanOrEqualTo(mainRect.right - .01));
            expect(suffixRect.center.dy, lessThan(mainRect.center.dy));
            expect(suffixRect.height, lessThan(mainRect.height * .7));
            expect(rect.contains(suffixRect.bottomRight), isTrue);
            final mainStyle = tester.widget<Text>(main).style!;
            final suffixStyle = tester.widget<Text>(suffix).style!;
            expect(suffixStyle.color, mainStyle.color);
            expect(suffixStyle.fontWeight, mainStyle.fontWeight);
            expect(
              find.descendant(
                of: card,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Semantics && widget.properties.label == label,
                ),
              ),
              findsOneWidget,
            );
          }
        }
        for (final (source, value) in [('KMA', '6'), ('SeisJS', '5')]) {
          final card = find.byKey(ValueKey('station-max-$source'));
          expect(
            find.descendant(of: card, matching: find.text(value)),
            findsOneWidget,
          );
          expect(
            find.descendant(of: card, matching: find.text('+')),
            findsNothing,
          );
          expect(
            find.descendant(of: card, matching: find.text('-')),
            findsNothing,
          );
        }
        expect(data.niedMaxStation!.level, level);
        expect(data.treaMaxStation!.intensity, shindo);
        if (label == '6+') {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final png = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            final dir = Directory('tmp/station_dashboard_shindo')
              ..createSync(recursive: true);
            await File(
              '${dir.path}/${AppEdition.name}-${size.width.toInt()}-$textScale.png',
            ).writeAsBytes(png.buffer.asUint8List());
            image.dispose();
          });
        }
      }
      await mount(StationSummaryData());
      for (final source in sources) {
        final card = find.byKey(ValueKey('station-max-$source'));
        expect(
          find.descendant(of: card, matching: find.text('--')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.text('-')),
          findsNothing,
        );
        expect(tester.getRect(card), originalRects[source]);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
