import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/widgets/ui/map_backdrop_cache.dart';

void main() {
  for (final ratio in [1.0, 1.25]) {
    testWidgets(
      'nested moving map matches current native frame at DPR $ratio',
      (tester) async {
        tester.view.devicePixelRatio = ratio;
        tester.view.physicalSize = Size(600 * ratio, 400 * ratio);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final phase = ValueNotifier(0.0);
        addTearDown(phase.dispose);
        final key = GlobalKey();
        Widget scene(bool cached) {
          final content = Stack(
            children: [
              Positioned.fill(
                child: MapBackdropSource(
                  child: ClipRect(
                    child: ValueListenableBuilder<double>(
                      valueListenable: phase,
                      child: const RepaintBoundary(
                        child: CustomPaint(painter: _Stripes()),
                      ),
                      builder: (_, value, child) => Transform.translate(
                        offset: Offset(value, value / 3),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 130,
                top: 80,
                width: 230,
                height: 180,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: CachedMapBackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: const ColoredBox(color: Color(0x73000000)),
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
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: ratio);
          try {
            return (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List().toList();
          } finally {
            image.dispose();
          }
        }

        const phases = [3.0, 11.0, 26.0, 7.0, 35.0, 0.0];
        final reference = <List<int>>[];
        await tester.pumpWidget(scene(false));
        for (final value in phases) {
          phase.value = value;
          await tester.pump(const Duration(milliseconds: 16));
          reference.add((await tester.runAsync(pixels))!);
        }
        await tester.pumpWidget(scene(true));
        for (var index = 0; index < phases.length; index++) {
          final before = MapBackdropCacheHost.diagnostics['captures'] as int;
          phase.value = phases[index];
          await tester.pump(const Duration(milliseconds: 16));
          final state = MapBackdropCacheHost.diagnostics;
          expect(state['captures'], greaterThan(before));
          expect(state['imageRevision'], state['mapRevision']);
          expect(state['staleSamples'], 0);
          expect(state['captureFailure'], isNull);
          // No second pump, post-frame callback, delay, or manual camera hint.
          expect((await tester.runAsync(pixels))!, reference[index]);
        }
        final settled = MapBackdropCacheHost.diagnostics['captures'];
        await tester.pump(const Duration(seconds: 2));
        expect(MapBackdropCacheHost.diagnostics['captures'], settled);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(MapBackdropCacheHost.diagnostics['textures'], 0);
      },
    );
  }
}

class _Stripes extends CustomPainter {
  const _Stripes();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xFF202124), BlendMode.src);
    for (var x = -400; x < size.width + 400; x += 21) {
      canvas.drawLine(
        Offset(x.toDouble(), 0),
        Offset(x + 300, size.height),
        Paint()
          ..color = Colors.green
          ..strokeWidth = 6,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Stripes oldDelegate) => false;
}
