import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/app_edition.dart';
import 'package:flutterrhythmquake/models/source_status.dart';
import 'package:flutterrhythmquake/models/source_credential_info.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sources/chinaeew_icl_service.dart';
import 'package:flutterrhythmquake/services/sources/jian_icl_service.dart';
import 'package:flutterrhythmquake/services/sources/kma_pews_eew_service.dart';
import 'package:flutterrhythmquake/services/sources/source_manager.dart';
import 'package:flutterrhythmquake/widgets/map/quake_map_view.dart';
import 'package:flutterrhythmquake/widgets/map/source_dashboard.dart';
import 'package:flutterrhythmquake/widgets/ui/station_dashboard.dart';
import 'package:provider/provider.dart';

class _StatusProvider extends ChangeNotifier implements QuakeProvider {
  @override
  final sourceStatusListenable = ValueNotifier<int>(0);
  final statuses = <String, SourceStatus>{};

  @override
  Map<String, SourceStatus> get sourceStatuses => statuses;

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
  const sources = [
    'Wolfx',
    'FAN',
    'FSSN',
    'WHEWS',
    'Jian Project',
    'NowQuake',
    'P2P',
  ];
  const labels = [
    'Wolfx',
    'FAN（未认证）',
    'FSSN',
    'WHEWS',
    'Jian（待确认）',
    'NowQuake',
    'P2PQ',
  ];

  for (final mobile in [false, true]) {
    testWidgets(
      'Rhythm has one API label and KMA keeps its station name / $mobile',
      (tester) async {
        final manager = SourceManager();
        final direct = KmaPewsEewService();
        final rhythm = RhythmKmaEewService();
        final stationEnabled = QuakeMapView.kmaPewsEnabledNotifier;
        final stationSource = QuakeMapView.kmaSourceNotifier;
        final oldEnabled = stationEnabled.value;
        final oldSource = stationSource.value;
        addTearDown(() {
          manager.reset();
          direct.dispose();
          rhythm.dispose();
          stationEnabled.value = oldEnabled;
          stationSource.value = oldSource;
        });
        manager.registerSource(direct);
        manager.registerSource(rhythm);
        final provider = _StatusProvider();
        addTearDown(provider.dispose);
        provider.statuses[direct.name] = SourceStatus.connected;
        provider.statuses[rhythm.name] = SourceStatus.error;
        provider.statuses['SASMEX'] = SourceStatus.connected;
        stationEnabled.value = true;
        stationSource.value = 'pews';
        Finder stationLabel(String name) =>
            find.textContaining('$name:', findRichText: true);

        await tester.pumpWidget(
          ChangeNotifierProvider<QuakeProvider>.value(
            value: provider,
            child: MaterialApp(
              home: Scaffold(
                body: Stack(children: [SourceDashboard(mobile: mobile)]),
              ),
            ),
          ),
        );
        expect(stationLabel('KMA'), findsOneWidget);
        expect(stationLabel('Rhythm'), findsNothing);
        expect(find.text('Rhythm'), findsOneWidget);
        expect(find.text(rhythm.name), findsNothing);
        expect(
          tester.widget<Text>(find.text(direct.name)).style?.color,
          const Color(0xFF008000),
        );
        expect(
          tester.widget<Text>(find.text('Rhythm')).style?.color,
          const Color(0xFFFFFF00),
        );

        for (final (sasmexStatus, kmaStatus, color) in [
          (
            SourceStatus.connected,
            SourceStatus.connected,
            const Color(0xFF008000),
          ),
          (
            SourceStatus.connected,
            SourceStatus.connecting,
            const Color(0xFF008000),
          ),
          (SourceStatus.error, SourceStatus.connected, const Color(0xFFFFFF00)),
          (
            SourceStatus.disconnected,
            SourceStatus.connected,
            const Color(0xFFFFFF00),
          ),
          (SourceStatus.error, SourceStatus.error, const Color(0xFFFF0000)),
          (
            SourceStatus.error,
            SourceStatus.connecting,
            const Color(0xFFFFFF00),
          ),
          (
            SourceStatus.synchronizing,
            SourceStatus.error,
            const Color(0xFFFFFF00),
          ),
          (SourceStatus.disconnected, SourceStatus.disconnected, Colors.white),
        ]) {
          provider.statuses['SASMEX'] = sasmexStatus;
          provider.statuses[rhythm.name] = kmaStatus;
          provider.sourceStatusListenable.value++;
          await tester.pump();
          expect(find.text('Rhythm'), findsOneWidget);
          expect(find.text(rhythm.name), findsNothing);
          expect(tester.widget<Text>(find.text('Rhythm')).style?.color, color);
          expect(
            tester.widget<Text>(find.text(direct.name)).style?.color,
            const Color(0xFF008000),
          );
        }

        for (final source in ['pews_local', 'fan', 'whews', 'jian', 'pews']) {
          stationSource.value = source;
          await tester.pump();
          expect(stationLabel('KMA'), findsOneWidget);
          expect(stationLabel('Rhythm'), findsNothing);
          expect(stationLabel('KMA-PEWS'), findsNothing);
          expect(stationLabel('FAN'), findsNothing);
          expect(stationLabel('WHEWS'), findsNothing);
          expect(stationLabel('Jian'), findsNothing);
        }

        stationSource.value = 'pews_local';
        manager.setSourceEnabled(rhythm.name, false);
        provider.statuses['SASMEX'] = SourceStatus.connected;
        provider.sourceStatusListenable.value++;
        await tester.pump();
        expect(stationLabel('Rhythm'), findsNothing);
        expect(stationLabel('KMA'), findsOneWidget);
        expect(find.text('Rhythm'), findsOneWidget);
        expect(
          tester.widget<Text>(find.text('Rhythm')).style?.color,
          const Color(0xFF008000),
        );
        expect(find.text(rhythm.name), findsNothing);
        expect(find.text(direct.name), findsOneWidget);

        manager.setSourceEnabled('SASMEX', false);
        manager.setSourceEnabled(rhythm.name, true);
        provider.statuses[rhythm.name] = SourceStatus.error;
        provider.sourceStatusListenable.value++;
        await tester.pump();
        expect(find.text('Rhythm'), findsOneWidget);
        expect(
          tester.widget<Text>(find.text('Rhythm')).style?.color,
          const Color(0xFFFF0000),
        );

        manager.setSourceEnabled(rhythm.name, false);
        provider.sourceStatusListenable.value++;
        await tester.pump();
        expect(find.text('Rhythm'), findsNothing);
        expect(stationLabel('KMA'), findsOneWidget);
        expect(find.text(direct.name), findsOneWidget);

        stationEnabled.value = false;
        await tester.pump();
        expect(stationLabel('KMA'), findsNothing);
        expect(find.text(direct.name), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final width in [800.0, 1280.0, 1600.0, 1920.0]) {
    for (final textScale in [1.0, 1.25]) {
      testWidgets('desktop status shares station panel edges $width / $textScale', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final provider = _StatusProvider();
        await tester.pumpWidget(ChangeNotifierProvider<QuakeProvider>.value(
          value: provider,
          child: MaterialApp(home: MediaQuery(
            data: MediaQueryData(size: Size(width, 900), textScaler: TextScaler.linear(textScale)),
            child: Scaffold(body: Stack(children: [
              StationDashboard(data: StationSummaryData()),
              const SourceDashboard(),
            ])),
          )),
        ));
        final station = tester.getRect(find.descendant(
          of: find.byType(StationDashboard), matching: find.byType(ClipRRect),
        ).first);
        final content = find.descendant(
          of: find.byKey(const ValueKey('source-dashboard-scale')),
          matching: find.byType(ConstrainedBox),
        ).first;
        final box = tester.renderObject<RenderBox>(content);
        final status = Rect.fromPoints(box.localToGlobal(Offset.zero),
          box.localToGlobal(box.size.bottomRight(Offset.zero)));
        expect(status.left, closeTo(station.left, .01));
        expect(status.right, closeTo(station.right, .01));
        expect(find.text('本地注入'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        provider.dispose();
      });
    }
  }

  for (final (size, mobile) in [
    (const Size(320, 640), true),
    (const Size(800, 900), false),
  ]) {
    testWidgets('FSSN follows enabled state and connection colors at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final manager = SourceManager();
      final enabled = manager.isSourceEnabled('FSSN');
      addTearDown(() => manager.setSourceEnabled('FSSN', enabled));
      manager.setSourceEnabled('FSSN', true);
      final provider = _StatusProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider<QuakeProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: Stack(children: [SourceDashboard(mobile: mobile)]),
            ),
          ),
        ),
      );
      for (final (status, color) in [
        (SourceStatus.disconnected, Colors.white),
        (SourceStatus.connecting, const Color(0xFFFFFF00)),
        (SourceStatus.connected, const Color(0xFF008000)),
        (SourceStatus.error, const Color(0xFFFF0000)),
      ]) {
        provider.statuses['FSSN'] = status;
        provider.sourceStatusListenable.value++;
        await tester.pump();
        expect(find.text('FSSN'), findsOneWidget);
        expect(tester.widget<Text>(find.text('FSSN')).style?.color, color);
      }
      manager.setSourceEnabled('FSSN', false);
      provider.sourceStatusListenable.value++;
      await tester.pump();
      expect(find.text('FSSN'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
    });

    testWidgets('ICL API statuses follow source state at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      JianIclService().disconnect();
      ChinaEewIclService().disconnect();
      final provider = _StatusProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider<QuakeProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: Stack(children: [SourceDashboard(mobile: mobile)]),
            ),
          ),
        ),
      );
      expect(find.text('Jian_ICL'), findsNothing);
      expect(find.text('China_EEW_ICL'), findsNothing);

      provider.statuses[JianIclService.sourceName] = SourceStatus.connected;
      provider.statuses[ChinaEewIclService.sourceName] =
          SourceStatus.connecting;
      provider.sourceStatusListenable.value++;
      await tester.pump();
      if (AppEdition.hasIcl) {
        expect(find.text('Jian_ICL'), findsOneWidget);
        expect(find.text('China_EEW_ICL'), findsOneWidget);
        expect(
          tester.widget<Text>(find.text('Jian_ICL')).style?.color,
          const Color(0xFF008000),
        );
        expect(
          tester.widget<Text>(find.text('China_EEW_ICL')).style?.color,
          const Color(0xFFFFFF00),
        );
        for (final label in ['Jian_ICL', 'China_EEW_ICL']) {
          final rect = tester.getRect(find.text(label));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
        }
      } else {
        expect(find.text('Jian_ICL'), findsNothing);
        expect(find.text('China_EEW_ICL'), findsNothing);
      }

      provider.statuses[JianIclService.sourceName] = SourceStatus.disconnected;
      provider.statuses[ChinaEewIclService.sourceName] =
          SourceStatus.disconnected;
      provider.sourceStatusListenable.value++;
      await tester.pump();
      expect(find.text('Jian_ICL'), findsNothing);
      expect(find.text('China_EEW_ICL'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
    });
  }

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
    for (final count in [0, 1, 4, 5, 6, 7]) {
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
          expect(rect.right, lessThanOrEqualTo(width));
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
