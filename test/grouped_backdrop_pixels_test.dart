import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final sigma in [8.0, 10.0]) {
    testWidgets(
      'separate shared backdrops retain blur, alpha and clip pixels $sigma',
      (tester) async {
        tester.view.physicalSize = const Size(600, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: RepaintBoundary(
              key: key,
              child: BackdropGroup(
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: CustomPaint(painter: _Backdrop()),
                    ),
                    for (final top in [30.0, 192.0])
                      Positioned(
                        top: top,
                        left: 200,
                        width: 220,
                        height: 150,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: BackdropFilter.grouped(
                            filter: ui.ImageFilter.blur(
                              sigmaX: sigma,
                              sigmaY: sigma,
                            ),
                            child: const ColoredBox(color: Color(0x73000000)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        Future<List<int>> pixels() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return data!.buffer.asUint8List().toList();
        }

        final shared = await tester.runAsync(pixels);
        for (final element in find.byType(BackdropFilter).evaluate()) {
          (element.renderObject! as RenderBackdropFilter).backdropKey = null;
        }
        await tester.pump();
        expect(await tester.runAsync(pixels), shared);
      },
    );
  }
}

class _Backdrop extends CustomPainter {
  const _Backdrop();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF202124),
    );
    for (var y = 0; y < size.height; y += 13) {
      canvas.drawLine(
        Offset.zero.translate(0, y.toDouble()),
        Offset(size.width, y + 150),
        Paint()
          ..color = const Color(0xFF44BB66)
          ..strokeWidth = 4,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Backdrop oldDelegate) => false;
}
