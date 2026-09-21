import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/source_status.dart';
import 'package:flutterrhythmquake/models/source_credential_info.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sources/source_manager.dart';
import 'package:flutterrhythmquake/widgets/map/source_dashboard.dart';
import 'package:provider/provider.dart';

class _StatusProvider extends ChangeNotifier implements QuakeProvider {
  @override
  final sourceStatusListenable = ValueNotifier<int>(0);

  @override
  Map<String, SourceStatus> get sourceStatuses => const {};

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
    if (preview) {
      final font = FontLoader('JetBrainsMono');
      font.addFont(rootBundle.load('assets/fonts/JetBrainsMono-Variable.ttf'));
      await font.load();
      final chinese = FontLoader('Microsoft YaHei');
      chinese.addFont(
        Future.value(
          ByteData.sublistView(
            await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
          ),
        ),
      );
      await chinese.load();
    }
  });
  const sources = ['Wolfx', 'FAN', 'WHEWS', 'Jian Project', 'NowQuake', 'P2P'];
  const labels = [
    'Wolfx',
    'FAN（未认证）',
    'WHEWS',
    'Jian（待确认）',
    'NowQuake',
    'P2PQ',
  ];

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(430, 932),
    const Size(844, 390),
  ]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets('mobile sources stay bottom-right at $size / $textScale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final manager = SourceManager();
        final enabled = [
          for (final source in sources) manager.isSourceEnabled(source),
        ];
        for (final source in sources) {
          manager.setSourceEnabled(source, true);
        }
        addTearDown(() {
          for (var i = 0; i < sources.length; i++) {
            manager.setSourceEnabled(sources[i], enabled[i]);
          }
        });
        final provider = _StatusProvider();
        var tapped = false;
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
                    key: const ValueKey('mobile-source-preview'),
                    child: Stack(
                      children: [
                        const SourceDashboard(mobile: true),
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => tapped = true,
                            child: const SizedBox(width: 40, height: 40),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final scaled = find.byKey(const ValueKey('source-dashboard-scale'));
        final transform = tester.widget<Transform>(scaled);
        expect(transform.transform.storage[0], .75);
        expect(transform.transform.storage[5], .75);
        expect(transform.alignment, Alignment.bottomRight);
        final content = find
            .descendant(of: scaled, matching: find.byType(ConstrainedBox))
            .first;
        final box = tester.renderObject<RenderBox>(content);
        final rect = Rect.fromPoints(
          box.localToGlobal(Offset.zero),
          box.localToGlobal(box.size.bottomRight(Offset.zero)),
        );
        expect(rect.right, closeTo(size.width - 6, .01));
        expect(rect.bottom, closeTo(size.height - 6, .01));
        expect(rect.left, greaterThanOrEqualTo(5.9));
        for (final label in labels) {
          expect(find.text(label), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.tapAt(Offset(size.width - 15, size.height - 15));
        expect(tapped, isTrue);
        if (preview && size.width == 390 && textScale == 1) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('mobile-source-preview')),
            );
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('build/ui-previews/mobile-source-dashboard.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
        provider.dispose();
      });
    }
  }

  for (final width in [800.0, 1600.0]) {
    for (final count in [0, 1, 4, 5, 6]) {
      testWidgets('$count APIs wrap after five at width $width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final manager = SourceManager();
        final enabled = [
          for (final source in sources) manager.isSourceEnabled(source),
        ];
        addTearDown(() {
          for (var i = 0; i < sources.length; i++) {
            manager.setSourceEnabled(sources[i], enabled[i]);
          }
        });
        for (var i = 0; i < sources.length; i++) {
          manager.setSourceEnabled(sources[i], i < count);
        }
        final provider = _StatusProvider();
        await tester.pumpWidget(
          ChangeNotifierProvider<QuakeProvider>.value(
            value: provider,
            child: const MaterialApp(
              home: Scaffold(body: Stack(children: [SourceDashboard()])),
            ),
          ),
        );
        for (var i = 0; i < labels.length; i++) {
          expect(
            find.text(labels[i]),
            i < count ? findsOneWidget : findsNothing,
          );
          if (i >= count) continue;
          final rect = tester.getRect(find.text(labels[i]));
          final rowStart = tester.getRect(find.text(labels[(i ~/ 5) * 5]));
          expect(rect.top, closeTo(rowStart.top, 0.01));
          if (i >= 5) {
            expect(
              rect.top,
              greaterThan(tester.getRect(find.text(labels[0])).bottom),
            );
          }
        }
        final stationLines = find.byWidgetPredicate(
          (widget) =>
              widget is RichText && widget.text.toPlainText().contains('(UTC'),
        );
        if (count > 0 && stationLines.evaluate().isNotEmpty) {
          expect(
            tester.getRect(stationLines.first).top,
            greaterThanOrEqualTo(
              tester.getRect(find.text(labels[count - 1])).bottom - 0.01,
            ),
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        provider.dispose();
      });
    }
  }
}
