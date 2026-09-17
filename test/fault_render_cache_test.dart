import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/china_fault_service.dart';
import 'package:flutterrhythmquake/services/japan_fault_service.dart';
import 'package:flutterrhythmquake/widgets/map/cached_fault_layer.dart';
import 'package:flutterrhythmquake/widgets/map/china_fault_layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final china = parseChinaFaults(
    File(ChinaFaultService.assetPath).readAsStringSync(),
  );
  final japan = parseJapanFaults(
    File(JapanFaultService.assetPath).readAsBytesSync(),
  );
  final lines = [
    for (final line in china)
      FaultStroke(points: line.points, color: chinaFaultColor(line.age)),
    for (final line in japan)
      FaultStroke(points: line.points, color: Color(line.colorArgb)),
  ];

  Widget oldLayer({double tolerance = 0.5}) => IgnorePointer(
    child: RepaintBoundary(
      child: PolylineLayer<Object>(
        polylines: [
          for (final line in lines)
            Polyline<Object>(
              points: line.points,
              color: line.color,
              strokeWidth: 1.5,
            ),
        ],
        cullingMargin: 10,
        simplificationTolerance: tolerance,
        drawInSingleWorld: true,
      ),
    ),
  );

  Future<Uint8List> pixels(WidgetTester tester, GlobalKey key) async {
    late Uint8List result;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      result = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      image.dispose();
    });
    return result;
  }

  testWidgets(
    'cached paths match original geometry after pan, zoom, rotation and wrap',
    (tester) async {
      tester.view.physicalSize = const Size(430, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = MapController();
      addTearDown(controller.dispose);
      final key = GlobalKey();
      final cached = CachedFaultLayer(lines: lines);
      // Keep both renderers mounted so movement exercises the warmed cache.
      final useCached = ValueNotifier(true);
      addTearDown(useCached.dispose);
      final original = oldLayer(tolerance: 0);
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: FlutterMap(
              mapController: controller,
              options: const MapOptions(
                initialCenter: LatLng(35, 110),
                initialZoom: 4,
                backgroundColor: Colors.white,
              ),
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: useCached,
                  builder: (_, value, _) => Stack(
                    children: [
                      Offstage(offstage: !value, child: cached),
                      Offstage(offstage: value, child: original),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final pose in [
        (const LatLng(35, 110), 4.0, 0.0),
        (const LatLng(35, 111), 4.0, 0.0),
        (const LatLng(35, 137), 7.0, 33.0),
        (const LatLng(35, 137.01), 7.0, 33.0),
        (const LatLng(37, 141), 7.0, 33.0),
        (const LatLng(35, 137), 7.0, 0.0),
        (japan.first.points.first, 12.3, 20.0),
        (china.first.points.first, 12.3, 0.0),
        (const LatLng(35, -223), 7.0, 0.0),
      ]) {
        controller.move(pose.$1, pose.$2);
        controller.rotate(pose.$3);
        useCached.value = true;
        await tester.pumpAndSettle();
        final actual = await pixels(tester, key);
        useCached.value = false;
        await tester.pumpAndSettle();
        final expected = await pixels(tester, key);
        var ink = 0, missed = 0, extra = 0;
        bool colored(Uint8List bytes, int pixel) =>
            bytes[pixel * 4] != bytes[pixel * 4 + 1];
        bool near(Uint8List bytes, int x, int y) {
          for (var dy = -2; dy <= 2; dy++) {
            for (var dx = -2; dx <= 2; dx++) {
              final xx = x + dx, yy = y + dy;
              if (xx >= 0 &&
                  xx < 430 &&
                  yy >= 0 &&
                  yy < 850 &&
                  colored(bytes, yy * 430 + xx)) {
                return true;
              }
            }
          }
          return false;
        }

        for (var i = 0; i < 430 * 850; i++) {
          if (colored(expected, i)) {
            ink++;
            if (!near(actual, i % 430, i ~/ 430)) missed++;
          }
          if (colored(actual, i) && !near(expected, i % 430, i ~/ 430)) extra++;
        }
        expect(ink, greaterThan(30), reason: 'reference must render at $pose');
        expect(
          missed / ink,
          lessThan(0.015),
          reason: 'missing traces at $pose',
        );
        expect(
          extra / ink,
          lessThan(0.015),
          reason: 'misaligned traces at $pose',
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('real-data steady pan CPU benchmark, both fault datasets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final results = <String, List<int>>{};
    for (final cached in [false, true]) {
      final controller = MapController();
      final layer = cached ? CachedFaultLayer(lines: lines) : oldLayer();
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterMap(
            key: ValueKey(cached),
            mapController: controller,
            options: const MapOptions(
              initialCenter: LatLng(35, 120),
              initialZoom: 4,
            ),
            children: [layer],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final timings = <int>[];
      for (var i = 0; i < 90; i++) {
        final stopwatch = Stopwatch()..start();
        controller.move(LatLng(35 + i * 0.004, 120 + i * 0.01), 4);
        await tester.pump();
        stopwatch.stop();
        if (i >= 10) timings.add(stopwatch.elapsedMicroseconds);
      }
      timings.sort();
      results[cached ? 'cached' : 'previous'] = timings;
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
    final report = results.entries
        .map(
          (entry) =>
              '${entry.key}: median=${entry.value[entry.value.length ~/ 2]} us, '
              'p95=${entry.value[(entry.value.length * .95).floor()]} us',
        )
        .join('\n');
    // Debug widget-test UI work only, not device raster timings or an FPS claim.
    debugPrint(report);
    final dir = Directory('tmp/china_fault_review')
      ..createSync(recursive: true);
    File('${dir.path}/pan-benchmark.txt').writeAsStringSync(report);
    expect(tester.takeException(), isNull);
  });
}
