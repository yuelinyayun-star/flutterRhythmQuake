import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/widgets/ui/map_backdrop_cache.dart';

void main() {
  for (final ratio in [1.0, 1.25]) {
    for (final layout in [
      (5.0, 50.0),
      (5.0, 100.0),
      (8.0, 50.0),
      (10.0, 50.0),
      (10.0, 5.0),
    ]) {
      final (sigma, gap) = layout;
      testWidgets(
        'cached shared map backdrop retains pixels DPR $ratio sigma $sigma gap $gap',
        (tester) async {
          tester.view.physicalSize = const Size(600, 600);
          tester.view.devicePixelRatio = ratio;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final key = GlobalKey();
          var mapPaints = 0;
          final text = ValueNotifier(0);
          addTearDown(text.dispose);
          Widget content({double? onlyTop}) => Stack(
            children: [
              Positioned.fill(
                child: MapBackdropSource(
                  child: CustomPaint(painter: _Background(() => mapPaints++)),
                ),
              ),
              for (final top in [40.0, 190.0 + gap])
                if (onlyTop == null || onlyTop == top)
                  Positioned(
                    top: top,
                    left: 70,
                    width: 220,
                    height: 150,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedMapBackdropFilter.grouped(
                        filter: ui.ImageFilter.blur(
                          sigmaX: top == 40 || sigma == 5
                              ? sigma
                              : (sigma == 8 ? 10 : 8),
                          sigmaY: top == 40 || sigma == 5
                              ? sigma
                              : (sigma == 8 ? 10 : 8),
                        ),
                        child: ColoredBox(
                          color: const Color(0x73000000),
                          child: ValueListenableBuilder<int>(
                            valueListenable: text,
                            builder: (_, value, _) => Text(
                              '$value',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          );
          Widget page(bool cached, {double? onlyTop}) => MaterialApp(
            home: RepaintBoundary(
              key: key,
              child: BackdropGroup(
                child: cached
                    ? MapBackdropCacheHost(child: content())
                    : content(onlyTop: onlyTop),
              ),
            ),
          );
          Future<List<int>> pixels() async {
            final boundary =
                key.currentContext!.findRenderObject() as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: ratio);
            try {
              final data = await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              return data!.buffer.asUint8List().toList();
            } finally {
              image.dispose();
            }
          }

          // Each native reference samples the map alone. Neighbouring UI is
          // intentionally absent from the input of a shared map backdrop.
          await tester.pumpWidget(page(false, onlyTop: 40));
          await tester.pumpAndSettle();
          final original = (await tester.runAsync(pixels))!;
          await tester.pumpWidget(page(false, onlyTop: 190 + gap));
          await tester.pumpAndSettle();
          final second = (await tester.runAsync(pixels))!;
          final stride = tester.view.physicalSize.width.toInt();
          for (
            var y = ((190 + gap) * ratio).floor();
            y < ((340 + gap) * ratio).ceil();
            y++
          ) {
            final start = (y * stride + (70 * ratio).floor()) * 4;
            final end = (y * stride + (290 * ratio).ceil()) * 4;
            original.setRange(start, end, second, start);
          }
          await tester.pumpWidget(page(true));
          for (var i = 0; i < 12; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 15)),
            );
            await tester.pump();
          }
          final cached = await tester.runAsync(pixels);
          expect(MapBackdropCacheHost.diagnostics['images'], greaterThan(0));
          expect(MapBackdropCacheHost.diagnostics['captures'], greaterThan(0));
          if (sigma == 5 && gap == 100) {
            expect(MapBackdropCacheHost.diagnostics['regions'], 2);
            expect(
              MapBackdropCacheHost.diagnostics['imageBytes'] as int,
              lessThan((220 * ratio).ceil() * (400 * ratio).ceil() * 4),
              reason: 'the empty gap between distant panels is not blurred',
            );
          }
          var maxDifference = 0, changed = 0, totalDifference = 0;
          for (var i = 0; i < cached!.length; i++) {
            final difference = (cached[i] - original[i]).abs();
            if (difference > maxDifference) maxDifference = difference;
            if (difference != 0) changed++;
            totalDifference += difference;
          }
          debugPrint(
            'DPR $ratio: max=$maxDifference changed=$changed/${cached.length} total=$totalDifference',
          );
          expect(cached, original);
          final before = mapPaints;
          final capturesBefore = MapBackdropCacheHost.diagnostics['captures'];
          text.value++;
          await tester.pump();
          expect(
            mapPaints,
            before,
            reason: 'text updates must not recapture the map',
          );
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump();
          expect(MapBackdropCacheHost.diagnostics['captures'], capturesBefore);
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        },
      );
    }
  }

  testWidgets(
    'nested repaint boundaries refresh glass and release its images',
    (tester) async {
      tester.view.physicalSize = const Size(600, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final color = ValueNotifier(Colors.green);
      addTearDown(color.dispose);
      addTearDown(
        () => MapBackdropCacheHost.nativeFiltersForDiagnostics.value = false,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MapBackdropCacheHost(
            child: Stack(
              children: [
                Positioned.fill(
                  child: MapBackdropSource(
                    child: ValueListenableBuilder<Color>(
                      valueListenable: color,
                      builder: (_, value, _) =>
                          RepaintBoundary(child: ColoredBox(color: value)),
                    ),
                  ),
                ),
                Positioned(
                  top: 100,
                  left: 100,
                  width: 220,
                  height: 150,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedMapBackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: const ColoredBox(color: Color(0x73000000)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 12; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await tester.pump();
        }
      }

      await settle();
      final before = MapBackdropCacheHost.diagnostics['captures'] as int;
      final scenesBefore =
          MapBackdropCacheHost.diagnostics['mapSceneChanges'] as int;
      expect(before, greaterThan(0));
      color.value = Colors.blue;
      await tester.pump();
      expect(
        MapBackdropCacheHost.diagnostics['mapSceneChanges'],
        greaterThan(scenesBefore),
        reason: 'nested map changes are tracked independently of foreground',
      );
      expect(
        MapBackdropCacheHost.diagnostics['captures'],
        greaterThan(before),
        reason: 'glass must update in the same scene as the changed map',
      );
      final beforeGesture = MapBackdropCacheHost.diagnostics['captures'] as int;
      color.value = Colors.red;
      await tester.pump();
      expect(
        MapBackdropCacheHost.diagnostics['captures'],
        greaterThan(beforeGesture),
        reason: 'automatic data changes cannot wait for a camera gesture',
      );
      MapBackdropCacheHost.cameraMoved(
        tester.element(find.byType(MapBackdropSource)),
      );
      await settle();
      expect(
        MapBackdropCacheHost.diagnostics['captures'],
        greaterThan(beforeGesture),
        reason: 'manual camera invalidation must not wait for an interval',
      );
      MapBackdropCacheHost.nativeFiltersForDiagnostics.value = true;
      await tester.pump();
      expect(MapBackdropCacheHost.diagnostics['images'], 0);
      MapBackdropCacheHost.nativeFiltersForDiagnostics.value = false;
      await settle();
      expect(MapBackdropCacheHost.diagnostics['images'], 1);
      final scenesAfterCapture =
          MapBackdropCacheHost.diagnostics['mapSceneChanges'] as int;
      await settle();
      expect(
        MapBackdropCacheHost.diagnostics['mapSceneChanges'],
        scenesAfterCapture,
        reason: 'offscreen cache capture does not count as a map submission',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(MapBackdropCacheHost.diagnostics['images'], 0);
    },
  );
}

class _Background extends CustomPainter {
  const _Background(this.onPaint);
  final VoidCallback onPaint;
  @override
  void paint(Canvas canvas, Size size) {
    onPaint();
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF202124),
    );
    for (var y = 0; y < size.height; y += 13) {
      canvas.drawLine(
        Offset(0, y.toDouble()),
        Offset(size.width, y + 150),
        Paint()
          ..color = const Color(0xFF44BB66)
          ..strokeWidth = 4,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Background oldDelegate) => false;
}
