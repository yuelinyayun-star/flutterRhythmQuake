import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/widgets/ui/map_backdrop_cache.dart';
import 'package:flutterrhythmquake/widgets/ui/ui_runtime_flags.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    final previousNative =
        MapBackdropCacheHost.nativeFiltersForDiagnostics.value;
    MapBackdropCacheHost.nativeFiltersForDiagnostics.value = false;
    final previousMode = UiRuntimeFlags.mapDragGlassModeNotifier.value;
    final previousMotion = MapBackdropCacheHost.mapMotionActive.value;
    addTearDown(
      () => MapBackdropCacheHost.nativeFiltersForDiagnostics.value =
          previousNative,
    );
    MapBackdropCacheHost.mapMotionActive.value = false;
    addTearDown(() {
      UiRuntimeFlags.mapDragGlassModeNotifier.value = previousMode;
      MapBackdropCacheHost.mapMotionActive.value = previousMotion;
    });
  });

  test('saved quality values restore the two supported modes', () async {
    for (final mode in [0, 2]) {
      SharedPreferences.setMockInitialValues({
        UiRuntimeFlags.mapDragGlassModeKey: mode,
      });
      UiRuntimeFlags.restoreMapDragGlassMode(
        await SharedPreferences.getInstance(),
      );
      expect(UiRuntimeFlags.mapDragGlassModeNotifier.value, mode);
    }
    SharedPreferences.setMockInitialValues({
      UiRuntimeFlags.mapDragGlassModeKey: 1,
    });
    UiRuntimeFlags.restoreMapDragGlassMode(
      await SharedPreferences.getInstance(),
    );
    expect(
      UiRuntimeFlags.mapDragGlassModeNotifier.value,
      UiRuntimeFlags.mapDragGlassOff,
    );
  });

  for (final ratio in [1.0, 1.25]) {
    testWidgets('quality switches apply immediately at rest DPR $ratio', (
      tester,
    ) async {
      configureView(tester, ratio);
      final phase = ValueNotifier(0);
      addTearDown(phase.dispose);
      final key = GlobalKey();
      UiRuntimeFlags.mapDragGlassModeNotifier.value = 0;
      await tester.pumpWidget(scene(key, phase));
      final fullBytes = MapBackdropCacheHost.diagnostics['imageBytes'] as int;
      expect(fullBytes, greaterThan(0));

      for (final mode in [2, 0, 2, 0]) {
        UiRuntimeFlags.mapDragGlassModeNotifier.value = mode;
        await tester.pump();
        final state = MapBackdropCacheHost.diagnostics;
        if (mode == 2) {
          expect(state['textures'], 0);
          expect(state['imageBytes'], 0);
          expect(backdropLayerCount(tester), 0);
        } else {
          expect(state['imageRevision'], state['mapRevision']);
          expect(state['staleSamples'], 0);
          expect(state['captureFailure'], isNull);
          final bytes = state['imageBytes'] as int;
          expect(bytes, mode == 0 ? fullBytes : 0);
          expect(bytes, greaterThan(0));
        }
        final captures = state['captures'];
        final image = (await tester.runAsync(() => pixels(key, ratio)))!;
        for (final moving in [true, false]) {
          MapBackdropCacheHost.mapMotionActive.value = moving;
          await tester.pump(const Duration(milliseconds: 300));
          expect(MapBackdropCacheHost.diagnostics['captures'], captures);
          expect((await tester.runAsync(() => pixels(key, ratio)))!, image);
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(MapBackdropCacheHost.diagnostics['textures'], 0);
    });

    for (final cached in [true, false]) {
      testWidgets(
        'frosted surface matches live tint DPR $ratio cache $cached',
        (tester) async {
          configureView(tester, ratio);
          final phase = ValueNotifier(0);
          addTearDown(phase.dispose);
          final key = GlobalKey();
          UiRuntimeFlags.mapDragGlassModeNotifier.value = 2;
          final reference = <Uint8List>[];
          await tester.pumpWidget(
            scene(key, phase, reference: true, cached: cached),
          );
          for (var frame = 0; frame < 12; frame++) {
            phase.value = frame;
            await tester.pump();
            reference.add((await tester.runAsync(() => pixels(key, ratio)))!);
          }
          await tester.pumpWidget(const SizedBox());
          phase.value = 0;
          await tester.pumpWidget(scene(key, phase, cached: cached));
          for (var frame = 0; frame < 12; frame++) {
            phase.value = frame;
            MapBackdropCacheHost.mapMotionActive.value = frame.isEven;
            await tester.pump();
            expect(
              (await tester.runAsync(() => pixels(key, ratio)))!,
              reference[frame],
            );
            expect(MapBackdropCacheHost.diagnostics['captures'], 0);
            expect(MapBackdropCacheHost.diagnostics['textures'], 0);
            expect(backdropLayerCount(tester), 0);
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        },
      );
    }

    testWidgets('full resolution refreshes each resting frame DPR $ratio', (
      tester,
    ) async {
      configureView(tester, ratio);
      final phase = ValueNotifier(0);
      addTearDown(phase.dispose);
      final key = GlobalKey();
      UiRuntimeFlags.mapDragGlassModeNotifier.value = 0;
      final reference = <Uint8List>[];
      for (var frame = 0; frame < 12; frame++) {
        phase.value = frame;
        await tester.pumpWidget(scene(key, phase));
        reference.add((await tester.runAsync(() => pixels(key, ratio)))!);
        await tester.pumpWidget(const SizedBox());
      }
      phase.value = 0;
      await tester.pumpWidget(scene(key, phase));
      for (var frame = 0; frame < 12; frame++) {
        final before = MapBackdropCacheHost.diagnostics['captures'] as int;
        phase.value = frame;
        await tester.pump();
        final state = MapBackdropCacheHost.diagnostics;
        if (frame > 0) expect(state['captures'], before + 1);
        expect(state['imageRevision'], state['mapRevision']);
        expect(state['staleSamples'], 0);
        expect(state['captureFailure'], isNull);
        expect(
          (await tester.runAsync(() => pixels(key, ratio)))!,
          reference[frame],
        );
      }
      final captures = MapBackdropCacheHost.diagnostics['captures'];
      await tester.pump(const Duration(seconds: 3));
      expect(MapBackdropCacheHost.diagnostics['captures'], captures);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }
}

void configureView(WidgetTester tester, double ratio) {
  tester.view.devicePixelRatio = ratio;
  tester.view.physicalSize = Size(320 * ratio, 240 * ratio);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Widget scene(
  GlobalKey key,
  ValueNotifier<int> phase, {
  bool reference = false,
  bool cached = true,
}) {
  const foreground = ColoredBox(color: Color(0x33000000));
  const frostedPanel = DecoratedBox(
    decoration: BoxDecoration(color: Color(0xCC141416)),
    child: foreground,
  );
  final content = Stack(
    children: [
      Positioned.fill(
        child: MapBackdropSource(
          child: ValueListenableBuilder<int>(
            valueListenable: phase,
            builder: (_, frame, _) => RepaintBoundary(
              child: CustomPaint(painter: _Background(frame)),
            ),
          ),
        ),
      ),
      Positioned(
        left: 70,
        top: 50,
        width: 180,
        height: 140,
        child: RepaintBoundary(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: reference
                ? frostedPanel
                : CachedMapBackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: frostedPanel,
                  ),
          ),
        ),
      ),
    ],
  );
  return MaterialApp(
    home: RepaintBoundary(
      key: key,
      child: cached ? MapBackdropCacheHost(child: content) : content,
    ),
  );
}

Future<Uint8List> pixels(GlobalKey key, double ratio) async {
  final image =
      await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
          .toImage(pixelRatio: ratio);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

int backdropLayerCount(WidgetTester tester) {
  var count = 0;
  void visit(Layer layer) {
    if (layer is BackdropFilterLayer) count++;
    if (layer is ContainerLayer) {
      var child = layer.firstChild;
      while (child != null) {
        visit(child);
        child = child.nextSibling;
      }
    }
  }

  for (final view in tester.binding.renderViews) {
    visit(view.debugLayer!);
  }
  return count;
}

class _Background extends CustomPainter {
  const _Background(this.frame);
  final int frame;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    final paint = Paint()..color = frame.isEven ? Colors.white : Colors.green;
    for (var x = -80.0 + frame * 7; x < size.width; x += 80) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 30, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_Background oldDelegate) => oldDelegate.frame != frame;
}
