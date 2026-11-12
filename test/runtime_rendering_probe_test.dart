import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/debug/runtime_rendering_probe.dart';

void main() {
  tearDown(RuntimeRenderingProbe.reset);

  test(
    'invalid camera commands are atomic; reset restores original camera',
    () {
      final owner = Object();
      var camera = (
        latitude: 35.0,
        longitude: 135.0,
        zoom: 5.0,
        autoFollow: true,
      );
      RuntimeRenderingProbe.bind(
        owner,
        read: () => camera,
        move: (value) => camera = value,
        restore: (value) => camera = value,
      );
      addTearDown(() => RuntimeRenderingProbe.unbind(owner));
      expect(
        () => RuntimeRenderingProbe.configure({
          'painting': 'none',
          'freezeCamera': {'latitude': double.nan, 'longitude': 0, 'zoom': 5},
        }),
        throwsFormatException,
      );
      expect(RuntimeRenderingProbe.painting.value, ProbePainting.all);
      RuntimeRenderingProbe.configure({
        'painting': 'overlays',
        'freezeCamera': {'latitude': 34, 'longitude': 108, 'zoom': 4},
      });
      expect(camera.autoFollow, isFalse);
      RuntimeRenderingProbe.configure({
        'freezeCamera': {'latitude': 30, 'longitude': 120, 'zoom': 6},
      });
      RuntimeRenderingProbe.reset();
      expect(camera, (
        latitude: 35.0,
        longitude: 135.0,
        zoom: 5.0,
        autoFollow: true,
      ));
    },
  );

  testWidgets('painting isolation keeps the same mounted state and listeners', (
    tester,
  ) async {
    final updates = ValueNotifier(0);
    var received = 0, paints = 0;
    void listener() => received++;
    updates.addListener(listener);
    addTearDown(updates.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RuntimePaintGate(
          mapOnly: true,
          child: ValueListenableBuilder<int>(
            valueListenable: updates,
            builder: (_, value, _) =>
                CustomPaint(painter: _PaintCounter(() => paints++)),
          ),
        ),
      ),
    );
    final initialPaints = paints;
    RuntimeRenderingProbe.configure({'painting': 'overlays'});
    await tester.pump();
    for (var i = 1; i <= 5; i++) {
      updates.value = i;
      await tester.pump();
    }
    expect(received, 5);
    expect(paints, initialPaints);
    expect(
      find.byType(ValueListenableBuilder<int>, skipOffstage: false),
      findsOneWidget,
    );
    RuntimeRenderingProbe.reset();
    await tester.pump();
    expect(paints, greaterThan(initialPaints));
  });

  testWidgets('backdrop isolation restores enabled and disabled filters', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: const SizedBox(width: 20, height: 20),
            ),
            BackdropFilter(
              enabled: false,
              filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: const SizedBox(width: 10, height: 10),
            ),
          ],
        ),
      ),
    );
    final filters = tester
        .renderObjectList<RenderBackdropFilter>(find.byType(BackdropFilter))
        .toList();
    expect(filters.map((filter) => filter.enabled), [true, false]);
    RuntimeRenderingProbe.configure({'painting': 'withoutBlur'});
    expect(filters.every((filter) => !filter.enabled), isTrue);
    RuntimeRenderingProbe.reset();
    expect(filters.map((filter) => filter.enabled), [true, false]);
    await tester.pump();
  });

  testWidgets('per-source isolation leaves other station drawing active', (
    tester,
  ) async {
    final updates = ValueNotifier(0);
    final paints = [0, 0];
    addTearDown(updates.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            for (var i = 0; i < 2; i++)
              RuntimePaintGate(
                mapOnly: false,
                hideWhen: ProbePainting.withoutStations,
                additionalHideWhen: i == 0
                    ? ProbePainting.withoutNiedStations
                    : ProbePainting.withoutSnetStations,
                child: ValueListenableBuilder<int>(
                  valueListenable: updates,
                  builder: (_, value, _) =>
                      CustomPaint(painter: _PaintCounter(() => paints[i]++)),
                ),
              ),
          ],
        ),
      ),
    );
    RuntimeRenderingProbe.configure({'painting': 'withoutNiedStations'});
    await tester.pump();
    final before = paints.toList();
    updates.value++;
    await tester.pump();
    expect(paints[0], before[0]);
    expect(paints[1], greaterThan(before[1]));
    RuntimeRenderingProbe.configure({'painting': 'withoutStations'});
    await tester.pump();
    final hidden = paints.toList();
    updates.value++;
    await tester.pump();
    expect(paints, hidden);
    RuntimeRenderingProbe.reset();
    await tester.pump();
    expect(paints[0], greaterThan(hidden[0]));
    expect(paints[1], greaterThan(hidden[1]));
  });
}

class _PaintCounter extends CustomPainter {
  _PaintCounter(this.count);
  final VoidCallback count;
  @override
  void paint(Canvas canvas, Size size) => count();
  @override
  bool shouldRepaint(covariant _PaintCounter oldDelegate) => true;
}
