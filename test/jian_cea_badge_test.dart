import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/intensity_calculator.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CapturedEventProvider extends QuakeProvider {
  _CapturedEventProvider(UnifiedQuakeData event) : unifiedEvents = [event];

  @override
  final List<UnifiedQuakeData> unifiedEvents;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const previewFont = String.fromEnvironment('BADGE_PREVIEW_FONT');
  setUpAll(() async {
    if (previewFont.isNotEmpty) {
      final loader = FontLoader('BadgePreview')
        ..addFont(File(previewFont).readAsBytes().then(ByteData.sublistView));
      await loader.load();
    }
  });
  final captured =
      jsonDecode(
            File(
              'test/fixtures/jian/all.json',
            ).readAsStringSync(encoding: utf8),
          )
          as Map;
  Map<String, dynamic> rawFor(String type) => Map<String, dynamic>.from(
    (captured['source：$type'] as Map)['Data'] as Map,
  );
  UnifiedQuakeData eventFor(String type) =>
      QuakeEventAdapter.convertJian(type, rawFor(type))!;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final type in ['cea', 'cea-pr', 'sa']) {
    test(
      'original $type gets a badge-only estimate without rewriting data',
      () {
        final raw = rawFor(type);
        final original = jsonEncode(raw);
        final event = QuakeEventAdapter.convertJian(type, raw)!;
        final originalEvent = jsonEncode(event.toMap());
        final notification = UnifiedEventPresentation.fromEvent(
          event,
        ).notificationBody;

        expect(event.maxIntensity, '-');
        expect(
          estimatedNewApiEewBadgeIntensity(event),
          IntensityCalculator.calcCsisLevel(event.magnitude, event.depth, 0),
        );
        expect(jsonEncode(raw), original);
        expect(event.sourcePayload, raw);
        expect(jsonEncode(event.toMap()), originalEvent);
        expect(UnifiedEventPresentation.fromEvent(event).intensityValue, '-');
        expect(
          UnifiedEventPresentation.fromEvent(event).notificationBody,
          notification,
        );
        expect(event.isWarn, isFalse);
      },
    );
  }

  test('other original Jian EEW badges are not changed', () {
    for (final type in ['jma-eew', 'cwa-eew', 'kma-eew']) {
      expect(
        estimatedNewApiEewBadgeIntensity(eventFor(type)),
        isNull,
        reason: type,
      );
    }
  });

  test(
    'validation cases preserve reported values and reject invalid estimates',
    () {
      // Deliberate model-level edge cases, separate from the unmodified captures.
      final event = eventFor('cea');
      for (final value in ['0', '3.5', 'Ⅵ', 'VI', '?', '不明']) {
        expect(
          estimatedNewApiEewBadgeIntensity(event.copyWith(maxIntensity: value)),
          isNull,
        );
      }
      for (final invalid in [
        event.copyWith(apiTypeLabel: 'FAN'),
        event.copyWith(isEew: false),
        event.copyWith(useShindo: true),
        event.copyWith(isCanceled: true),
        event.copyWith(isAssumption: true),
        event.copyWith(isHistory: true),
        event.copyWith(magnitude: -1),
        event.copyWith(magnitude: 0),
        event.copyWith(magnitude: double.nan),
        event.copyWith(magnitude: double.infinity),
        event.copyWith(depth: -1),
        event.copyWith(depth: double.nan),
        event.copyWith(depth: double.infinity),
      ]) {
        expect(estimatedNewApiEewBadgeIntensity(invalid), isNull);
      }
    },
  );

  for (final size in [
    const Size(320, 720),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1280, 900),
  ]) {
    for (final type in ['cea', 'cea-pr', 'sa']) {
      testWidgets('$type badge keeps its box and fits at $size', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        Future<void> show(UnifiedQuakeData event) async {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<QuakeProvider>(
                  create: (_) => _CapturedEventProvider(event),
                ),
                ChangeNotifierProvider(create: (_) => MapStateProvider()),
              ],
              child: MaterialApp(
                theme: ThemeData(
                  fontFamily: previewFont.isEmpty ? null : 'BadgePreview',
                ),
                home: const Scaffold(
                  body: SingleChildScrollView(child: AlertModule()),
                ),
              ),
            ),
          );
        }

        Finder badgeBox(String label) => find
            .ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container &&
                    widget.constraints?.minWidth ==
                        widget.constraints?.minHeight &&
                    widget.constraints?.minWidth ==
                        widget.constraints?.maxWidth &&
                    widget.constraints?.minHeight ==
                        widget.constraints?.maxHeight,
              ),
            )
            .first;

        final original = eventFor(type);
        await show(original);
        expect(find.text('预估烈度'), findsOneWidget);
        final estimate = estimatedNewApiEewBadgeIntensity(original)!;
        expect(
          find.text(unifiedRomanIntensityLabel('$estimate')),
          findsOneWidget,
        );
        final estimatedBoxSize = tester.getSize(badgeBox('预估烈度'));
        final labelRect = tester.getRect(find.text('预估烈度'));
        final boxRect = tester.getRect(badgeBox('预估烈度'));
        expect(boxRect.contains(labelRect.topLeft), isTrue);
        expect(boxRect.contains(labelRect.bottomRight), isTrue);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE_BADGE_PREVIEW') &&
            type == 'cea' &&
            size.height != 390) {
          await tester.pump();
          final card = find.byKey(
            ValueKey(
              'unified_card_${original.source}_${original.eventId}_${original.reportNumText}',
            ),
          );
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find
                .descendant(of: card, matching: find.byType(RepaintBoundary))
                .first,
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            image.dispose();
            final file = File(
              'build/test-previews/jian_cea_${size.width.toInt()}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
          });
        }

        // Original unknown badge geometry, with only estimation disabled.
        await show(original.copyWith(apiTypeLabel: 'FAN'));
        expect(find.text('预估烈度'), findsNothing);
        expect(tester.getSize(badgeBox('烈度')), estimatedBoxSize);
        expect(tester.takeException(), isNull);
        await show(original.copyWith(maxIntensity: '3.0'));
        expect(find.text('预估烈度'), findsNothing);
        expect(find.text('III'), findsOneWidget);
        expect(tester.getSize(badgeBox('烈度')), estimatedBoxSize);
        expect(tester.takeException(), isNull);
        await show(original.copyWith(maxIntensity: '0.0'));
        expect(find.text('预估烈度'), findsNothing);
        expect(find.text('0'), findsOneWidget);
        expect(tester.getSize(badgeBox('烈度')), estimatedBoxSize);
        expect(tester.takeException(), isNull);
        // Model-level WHEWS display cases, not modified source captures.
        await show(original.copyWith(apiTypeLabel: 'WHEWS'));
        expect(find.text('预估烈度'), findsOneWidget);
        expect(tester.getSize(badgeBox('预估烈度')), estimatedBoxSize);
        for (final (value, label) in [('6.49', 'VI'), ('6.5', 'VII')]) {
          await show(
            original.copyWith(apiTypeLabel: 'WHEWS', maxIntensity: value),
          );
          expect(find.text('预估烈度'), findsNothing);
          expect(find.text(label), findsOneWidget);
          expect(tester.getSize(badgeBox('烈度')), estimatedBoxSize);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
