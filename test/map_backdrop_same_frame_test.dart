import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/widgets/ui/map_backdrop_cache.dart';
import 'package:flutterrhythmquake/widgets/ui/ui_runtime_flags.dart';

void main() {
  setUp(() {
    final previousNative =
        MapBackdropCacheHost.nativeFiltersForDiagnostics.value;
    MapBackdropCacheHost.nativeFiltersForDiagnostics.value = false;
    final previous = UiRuntimeFlags.mapDragGlassModeNotifier.value;
    UiRuntimeFlags.mapDragGlassModeNotifier.value =
        UiRuntimeFlags.mapDragGlassFull;
    addTearDown(
      () => MapBackdropCacheHost.nativeFiltersForDiagnostics.value =
          previousNative,
    );
    addTearDown(() => UiRuntimeFlags.mapDragGlassModeNotifier.value = previous);
  });

  testWidgets('every moving background frame matches freshly blurred pixels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    final motion = ValueNotifier(0);
    addTearDown(motion.dispose);

    Widget page(bool cached) {
      final content = Stack(
        children: [
          Positioned.fill(
            child: MapBackdropSource(
              child: ValueListenableBuilder<int>(
                valueListenable: motion,
                builder: (_, frame, _) => RepaintBoundary(
                  child: CustomPaint(painter: _MovingBackground(frame)),
                ),
              ),
            ),
          ),
          Positioned(
            left: 70,
            top: 50,
            width: 180,
            height: 140,
            child: ClipRect(
              child: CachedMapBackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: const ColoredBox(color: Color(0x33000000)),
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

    Future<List<int>> pixels() async {
      final image =
          await (key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      try {
        return (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List().toList();
      } finally {
        image.dispose();
      }
    }

    final expected = <List<int>>[];
    await tester.pumpWidget(page(false));
    for (var frame = 0; frame < 16; frame++) {
      motion.value = frame;
      await tester.pump();
      expected.add((await tester.runAsync(pixels))!);
    }
    motion.value = 0;
    await tester.pumpWidget(page(true));
    await tester.pumpAndSettle();
    for (var frame = 0; frame < 16; frame++) {
      motion.value = frame;
      await tester.pump(const Duration(milliseconds: 16));
      final diagnostics = MapBackdropCacheHost.diagnostics;
      expect(diagnostics['imageRevision'], diagnostics['mapRevision']);
      expect(diagnostics['staleSamples'], 0);
      expect(
        (await tester.runAsync(pixels))!,
        expected[frame],
        reason: 'frame $frame must contain only the current background',
      );
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

class _MovingBackground extends CustomPainter {
  const _MovingBackground(this.frame);
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
  bool shouldRepaint(_MovingBackground oldDelegate) =>
      oldDelegate.frame != frame;
}
