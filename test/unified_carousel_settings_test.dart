import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/widgets/ui/ui_runtime_flags.dart';
import 'package:flutterrhythmquake/widgets/ui/unified_carousel_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'map_card_viewport_sync_test.dart' show mount, item;

Finder cards() => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('unified_card_'),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UiRuntimeFlags.desktopUnifiedPageSizeNotifier.value = 4;
    SoundEffectService().enabled = false;
  });
  tearDown(() {
    UiRuntimeFlags.desktopUnifiedPageSizeNotifier.value = 4;
    SoundEffectService().enabled = true;
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final phone in [false, true]) {
      testWidgets('setting follows UI layout on $platform phone=$phone', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = phone
            ? const Size(390, 844)
            : const Size(1280, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: UnifiedCarouselSettings())),
        );
        expect(find.text('统一 UI 每页卡片数'), phone ? findsNothing : findsOneWidget);
        if (!phone) {
          await tester.tap(find.byType(DropdownButtonFormField<int>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('1 条').last);
          await tester.pumpAndSettle();
          expect(UiRuntimeFlags.desktopUnifiedPageSizeNotifier.value, 1);
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getInt(UiRuntimeFlags.desktopUnifiedPageSizeKey), 1);
          UiRuntimeFlags.desktopUnifiedPageSizeNotifier.value = 4;
          UiRuntimeFlags.restoreDesktopUnifiedPageSize(prefs);
          expect(UiRuntimeFlags.desktopUnifiedPageSizeNotifier.value, 1);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }

  test('saved values restore, with four as the initial default', () async {
    final prefs = await SharedPreferences.getInstance();
    UiRuntimeFlags.restoreDesktopUnifiedPageSize(prefs);
    expect(UiRuntimeFlags.desktopUnifiedPageSizeNotifier.value, 4);
    for (var size = 1; size <= 4; size++) {
      await UiRuntimeFlags.setDesktopUnifiedPageSize(size);
      UiRuntimeFlags.desktopUnifiedPageSizeNotifier.value = 4;
      UiRuntimeFlags.restoreDesktopUnifiedPageSize(prefs);
      expect(UiRuntimeFlags.desktopUnifiedPageSizeNotifier.value, size);
    }
  });

  for (var size = 1; size <= 4; size++) {
    testWidgets('page boundary is exactly $size cards in desktop UI', (
      tester,
    ) async {
      UiRuntimeFlags.desktopUnifiedPageSizeNotifier.value = size;
      final provider = await mount(tester);
      for (var i = 0; i < size; i++) {
        provider.handleUnifiedEventForTest(item(i, eew: false));
      }
      provider.setMobileCameraInfoFocus(provider.currentUnifiedEvent);
      await tester.pump();
      expect(cards(), findsNWidgets(size));
      expect(find.text('1/2'), findsNothing);
      provider.handleUnifiedEventForTest(item(size, eew: false));
      provider.setMobileCameraInfoFocus(provider.currentUnifiedEvent);
      await tester.pump();
      expect(cards(), findsNWidgets(size));
      expect(find.text('1/2'), findsOneWidget);
      provider.setCurrentUnifiedIndex(size);
      provider.setMobileCameraInfoFocus(provider.currentUnifiedEvent);
      await tester.pump();
      expect(cards(), findsOneWidget);
      expect(find.text('2/2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'desktop pages of $size preserve admission and map-selected cards',
      (tester) async {
        UiRuntimeFlags.desktopUnifiedPageSizeNotifier.value = size;
        final provider = await mount(tester);
        for (var i = 0; i < 5; i++) {
          provider.handleUnifiedEventForTest(item(i, eew: false));
        }
        final original = List.of(provider.unifiedEvents);
        final seen = <String>{};
        for (var turn = 0; turn < 6; turn++) {
          final selected = provider.currentUnifiedEvent!;
          provider.setMobileCameraInfoFocus(selected);
          await tester.pump();
          expect(find.text(selected.hypocenter), findsOneWidget);
          expect(cards().evaluate().length, inInclusiveRange(1, size));
          for (final event in original) {
            if (find.text(event.hypocenter).evaluate().isNotEmpty) {
              seen.add(event.eventId);
            }
          }
          await tester.pump(const Duration(seconds: 5));
        }
        expect(seen, hasLength(5));
        expect(provider.unifiedEvents, original);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'changing page size applies immediately without changing event admission',
    (tester) async {
      final provider = await mount(tester);
      for (var i = 0; i < 5; i++) {
        provider.handleUnifiedEventForTest(item(i, eew: false));
      }
      final original = List.of(provider.unifiedEvents);
      final selected = provider.currentUnifiedEvent!;
      provider.setMobileCameraInfoFocus(selected);
      await tester.pump();
      expect(cards(), findsNWidgets(4));
      for (final size in [1, 3, 2, 4]) {
        UiRuntimeFlags.desktopUnifiedPageSizeNotifier.value = size;
        await tester.pump();
        expect(cards(), findsNWidgets(size));
        expect(find.text(selected.hypocenter), findsOneWidget);
        expect(provider.unifiedEvents, original);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('phone cards stay single regardless of the desktop preference', (
    tester,
  ) async {
    final provider = await mount(tester, phone: true);
    provider.handleUnifiedEventForTest(item(0, eew: true));
    provider.handleUnifiedEventForTest(item(1, eew: true));
    for (var size = 1; size <= 4; size++) {
      UiRuntimeFlags.desktopUnifiedPageSizeNotifier.value = size;
      final selected = provider.currentUnifiedEvent!;
      provider.setMobileCameraInfoFocus(selected);
      await tester.pump();
      expect(cards(), findsOneWidget);
      expect(find.text(selected.hypocenter), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
