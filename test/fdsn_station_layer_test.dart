import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/core/fdsn_intensity.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_station_service.dart';
import 'package:flutterrhythmquake/widgets/map/fdsn_station_layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('MPLUSRounded1c')
      ..addFont(rootBundle.load('assets/fonts/MPLUSRounded1c-Bold.ttf'));
    await font.load();
  });
  testWidgets('World copies stay on their coordinates during fractional zoom', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = MapController();
    final key = GlobalKey();
    const location = LatLng(0, 105);
    List<int>? centeredPixels;
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: FlutterMap(
            mapController: controller,
            options: const MapOptions(
              backgroundColor: Colors.black,
              initialCenter: location,
              initialZoom: 1,
            ),
            children: [
              FdsnStationLayer(
                stations: [
                  FdsnStation(
                    network: 'XX',
                    station: 'POSITION',
                    location: '',
                    source: 'EarthScope',
                    coordinate: location,
                    lastMotionUpdate: DateTime.now(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    for (final zoom in [1.0, 1.13, 1.27, 1.05, 7.123, 15.317, 18.913]) {
      controller.move(location, zoom);
      await tester.pump();
      await tester.runAsync(() async {
        final shot =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = (await shot.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final centerPixels = <int>[
          for (var y = 354; y < 367; y++)
            for (var x = 634; x < 647; x++)
              bytes.getUint8((y * shot.width + x) * 4 + 2),
        ];
        if (centeredPixels != null) {
          expect(
            centerPixels,
            orderedEquals(centeredPixels!),
            reason: 'zoom anchor must not wobble or change size at $zoom',
          );
        }
        centeredPixels = centerPixels;
        final world = controller.camera.getWorldWidthAtZoom();
        for (var copy = -2; copy <= 2; copy++) {
          final x = 640 + copy * world;
          if (x < 8 || x >= 1272) continue;
          var weight = 0.0, weightedX = 0.0, weightedY = 0.0;
          for (var y = 354; y < 367; y++) {
            for (var px = x.floor() - 6; px <= x.ceil() + 6; px++) {
              final blue = bytes.getUint8((y * shot.width + px) * 4 + 2);
              weight += blue;
              weightedX += (px + .5) * blue;
              weightedY += (y + .5) * blue;
            }
          }
          expect(
            weight,
            greaterThan(0),
            reason: 'missing world $copy at $zoom',
          );
          if (weight > 0) {
            expect(weightedX / weight, closeTo(x, .25), reason: 'x at $zoom');
            expect(weightedY / weight, closeTo(360, .25), reason: 'y at $zoom');
          }
        }
        shot.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('5000 station camera and timestamp update workload', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = MapController();
    final diagnostics = FdsnLayerDiagnostics();
    final now = DateTime.now();
    final stations = ValueNotifier([
      for (var i = 0; i < 5000; i++)
        FdsnStation(
          network: 'XX',
          station: 'LOAD$i',
          location: '',
          source: 'EarthScope',
          coordinate: LatLng(28 + (i ~/ 100) * .08, 101 + (i % 100) * .08),
          intensity: (i % 10 + 1).toDouble(),
          lastMotionUpdate: now,
        ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: FlutterMap(
          mapController: controller,
          options: const MapOptions(
            initialCenter: LatLng(30, 105),
            initialZoom: 7.5,
          ),
          children: [
            ValueListenableBuilder<List<FdsnStation>>(
              valueListenable: stations,
              builder: (_, value, _) =>
                  FdsnStationLayer(stations: value, diagnostics: diagnostics),
            ),
          ],
        ),
      ),
    );
    final watch = Stopwatch()..start();
    for (var i = 0; i < 60; i++) {
      controller.move(LatLng(30 + i * .001, 105), 7.5);
      await tester.pump();
    }
    watch.stop();
    debugPrint('FDSN 5000 pan: ${watch.elapsedMicroseconds ~/ 60} us/pump');
    watch.reset();
    watch.start();
    final preparedBefore = diagnostics.preparationMicros;
    for (var i = 0; i < 20; i++) {
      stations.value = [
        for (final s in stations.value)
          s.copyWith(
            lastMotionUpdate: now.subtract(Duration(milliseconds: i + 1)),
          ),
      ];
      await tester.pump();
    }
    watch.stop();
    debugPrint(
      'FDSN 5000 timestamp refresh: ${watch.elapsedMicroseconds ~/ 20} us/pump',
    );
    debugPrint(
      'FDSN timestamp layer preparation: '
      '${(diagnostics.preparationMicros - preparedBefore) ~/ 20} us/update',
    );
    expect(diagnostics.projections, 5000);
    expect(diagnostics.pictureRecordings, 1);
    expect(diagnostics.recordedStations, 5000);
    expect(diagnostics.paints, 1);
    final zoomWatch = Stopwatch()..start();
    for (var i = 0; i < 60; i++) {
      controller.move(const LatLng(30, 105), 7.5 + i * .005);
      await tester.pump();
    }
    zoomWatch.stop();
    debugPrint(
      'FDSN 5000 zoom: ${zoomWatch.elapsedMicroseconds ~/ 60} us/pump',
    );
    expect(diagnostics.atlasBuilds, 1);
    expect(diagnostics.atlasDraws, diagnostics.pictureRecordings);
    debugPrint(
      'FDSN layer paints: ${diagnostics.paints}, recordings: ${diagnostics.pictureRecordings}',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    stations.dispose();
    controller.dispose();
  });
  testWidgets(
    'Offscreen changes do not repaint until their viewport is shown',
    (tester) async {
      final diagnostics = FdsnLayerDiagnostics();
      final controller = MapController();
      final now = DateTime.now();
      final stations = ValueNotifier([
        FdsnStation(
          network: 'XX',
          station: 'NEAR',
          location: '',
          source: 'EarthScope',
          coordinate: const LatLng(30, 105),
          intensity: 1,
          lastMotionUpdate: now,
        ),
        FdsnStation(
          network: 'XX',
          station: 'FAR',
          location: '',
          source: 'EarthScope',
          coordinate: const LatLng(40, -100),
          intensity: 1,
          lastMotionUpdate: now,
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterMap(
            mapController: controller,
            options: const MapOptions(
              initialCenter: LatLng(30, 105),
              initialZoom: 7,
            ),
            children: [
              ValueListenableBuilder<List<FdsnStation>>(
                valueListenable: stations,
                builder: (_, value, _) =>
                    FdsnStationLayer(stations: value, diagnostics: diagnostics),
              ),
            ],
          ),
        ),
      );
      expect(diagnostics.paints, 1);
      expect(diagnostics.recordedStations, 1);
      stations.value = [
        stations.value.first,
        stations.value.last.copyWith(intensity: 9),
      ];
      await tester.pump();
      expect(diagnostics.paints, 1);
      expect(diagnostics.pictureRecordings, 1);
      controller.move(const LatLng(40, -100), 7);
      await tester.pump();
      expect(diagnostics.paints, 2);
      expect(diagnostics.pictureRecordings, 2);
      expect(diagnostics.recordedStations, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      stations.dispose();
      controller.dispose();
    },
  );

  testWidgets(
    'Atlas follows device density without moving or resizing markers',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final diagnostics = FdsnLayerDiagnostics();
      final key = GlobalKey();
      final stations = [
        FdsnStation(
          network: 'XX',
          station: 'DENSITY',
          location: '',
          source: 'EarthScope',
          coordinate: const LatLng(0, 0),
          intensity: 10,
          lastMotionUpdate: DateTime.now(),
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(0, 0),
                initialZoom: 7,
                backgroundColor: Colors.black,
              ),
              children: [
                FdsnStationLayer(stations: stations, diagnostics: diagnostics),
              ],
            ),
          ),
        ),
      );
      for (final ratio in [1.0, 2.0, 3.0, 1.25]) {
        tester.view.devicePixelRatio = ratio;
        tester.view.physicalSize = Size(390 * ratio, 844 * ratio);
        await tester.pump();
        await tester.runAsync(() async {
          final shot =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: ratio);
          final bytes = (await shot.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          var left = shot.width, right = 0, top = shot.height, bottom = 0;
          for (var y = (412 * ratio).floor(); y < 432 * ratio; y++) {
            for (var x = (185 * ratio).floor(); x < 205 * ratio; x++) {
              final p = (y * shot.width + x) * 4;
              if (bytes.getUint8(p) <= 20 &&
                  bytes.getUint8(p + 1) <= 20 &&
                  bytes.getUint8(p + 2) <= 20) {
                continue;
              }
              left = math.min(left, x);
              right = math.max(right, x);
              top = math.min(top, y);
              bottom = math.max(bottom, y);
            }
          }
          expect((left + right + 1) / (2 * ratio), closeTo(195, .5));
          expect((top + bottom + 1) / (2 * ratio), closeTo(422, .5));
          expect((right - left + 1) / ratio, closeTo(15, 2));
          expect((bottom - top + 1) / ratio, closeTo(15, 2));
          shot.dispose();
        });
      }
      expect(diagnostics.atlasBuilds, 4);
      expect(diagnostics.projections, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Station beyond 1200 visible glyphs is still drawn', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: FlutterMap(
            options: const MapOptions(
              backgroundColor: Color(0xFF242424),
              initialCenter: LatLng(30, 105),
              initialZoom: 7.5,
            ),
            children: [
              FdsnStationLayer(
                stations: [
                  for (var i = 0; i < 1201; i++)
                    FdsnStation(
                      network: 'XX',
                      station: 'FIXTURE$i',
                      location: '',
                      source: 'EarthScope',
                      coordinate: i == 1200
                          ? const LatLng(30, 105)
                          : const LatLng(30, 104),
                      intensity: i == 1200 ? null : 10,
                      lastMotionUpdate: now,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() async {
      final shot =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final rgba = (await shot.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final pixel = (300 * shot.width + 400) * 4;
      expect(rgba.getUint8(pixel + 2), greaterThan(36));
      shot.dispose();
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Cached viewport matches fresh drawing through camera changes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = MapController();
    final key = GlobalKey();
    final revision = ValueNotifier(0);
    final stations = [
      for (var i = 0; i < 60; i++)
        FdsnStation(
          network: 'XX',
          station: 'WRAP$i',
          location: '',
          source: 'EarthScope',
          coordinate: LatLng(
            30 + i % 5 * .1,
            i.isEven ? 179 + i * .01 : -179 - i * .01,
          ),
          intensity: i % 11 == 0 ? null : (i % 10 + 1).toDouble(),
          lastMotionUpdate: DateTime.now(),
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: FlutterMap(
            mapController: controller,
            options: const MapOptions(
              initialCenter: LatLng(30, 179),
              initialZoom: 7,
            ),
            children: [
              ValueListenableBuilder<int>(
                valueListenable: revision,
                builder: (_, value, _) =>
                    FdsnStationLayer(key: ValueKey(value), stations: stations),
              ),
            ],
          ),
        ),
      ),
    );
    Future<List<int>> pixels() async {
      late List<int> result;
      await tester.runAsync(() async {
        final shot =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        result = (await shot.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List().toList();
        shot.dispose();
      });
      return result;
    }

    for (final (center, zoom, rotation) in [
      (const LatLng(30.01, 179.1), 7.0, 0.0),
      (const LatLng(30.02, 179.2), 7.0, 35.0),
      (const LatLng(30.02, -179), 7.0, 35.0),
      (const LatLng(30.02, -179.01), 8.0, 0.0),
      (const LatLng(30.02, 179), 1.0, 0.0),
      (const LatLng(30.02, 170), 1.0, 0.0),
    ]) {
      controller.move(center, zoom);
      controller.rotate(rotation);
      await tester.pump();
      final cached = await pixels();
      revision.value++;
      await tester.pump();
      final fresh = await pixels();
      var differing = 0;
      for (var i = 0; i < cached.length; i++) {
        if ((cached[i] - fresh[i]).abs() > 4) differing++;
      }
      expect(
        differing / cached.length,
        lessThan(.001),
        reason: '$center zoom=$zoom rotation=$rotation',
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    revision.dispose();
    controller.dispose();
  });

  testWidgets(
    'Changed level invalidates pixels and expired stations leave cache',
    (tester) async {
      final diagnostics = FdsnLayerDiagnostics();
      final station = FdsnStation(
        network: 'XX',
        station: 'CHANGE',
        location: '',
        source: 'EarthScope',
        coordinate: const LatLng(30, 105),
        intensity: 1,
        lastMotionUpdate: DateTime.now(),
      );
      final stations = ValueNotifier([station]);
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(30, 105),
              initialZoom: 7,
            ),
            children: [
              ValueListenableBuilder<List<FdsnStation>>(
                valueListenable: stations,
                builder: (_, value, _) =>
                    FdsnStationLayer(stations: value, diagnostics: diagnostics),
              ),
            ],
          ),
        ),
      );
      expect(diagnostics.pictureRecordings, 1);
      stations.value = [station.copyWith(intensity: 2.49)];
      await tester.pump();
      final belowHalf = diagnostics.pictureRecordings;
      stations.value = [station.copyWith(intensity: 2.50)];
      await tester.pump();
      expect(diagnostics.pictureRecordings, belowHalf + 1);
      stations.value = [station.copyWith(intensity: 3.09)];
      await tester.pump();
      expect(diagnostics.pictureRecordings, belowHalf + 1,
          reason: '2.50 and 3.09 must share the same digit and color');
      stations.value = [station.copyWith(intensity: 8)];
      await tester.pump();
      expect(diagnostics.pictureRecordings, belowHalf + 2);
      expect(diagnostics.projections, 1);
      stations.value = [
        station.copyWith(
          lastMotionUpdate: DateTime.now().subtract(const Duration(minutes: 4)),
        ),
      ];
      await tester.pump();
      final recordings = diagnostics.pictureRecordings;
      stations.value = [
        station.copyWith(intensity: 10, lastMotionUpdate: DateTime.now()),
      ];
      await tester.pump();
      expect(diagnostics.pictureRecordings, recordings + 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      stations.dispose();
    },
  );
  testWidgets('Timestamp-only refresh reschedules expiry without redrawing', (
    tester,
  ) async {
    final diagnostics = FdsnLayerDiagnostics();
    FdsnStation nearExpiry() => FdsnStation(
      network: 'XX',
      station: 'EXPIRY',
      location: '',
      source: 'EarthScope',
      coordinate: const LatLng(30, 105),
      intensity: 1,
      lastMotionUpdate: DateTime.now().subtract(
        FdsnStation.motionRetention - const Duration(seconds: 1),
      ),
    );
    final stations = ValueNotifier([nearExpiry()]);
    await tester.pumpWidget(
      MaterialApp(
        home: FlutterMap(
          options: const MapOptions(
            initialCenter: LatLng(30, 105),
            initialZoom: 7,
          ),
          children: [
            ValueListenableBuilder<List<FdsnStation>>(
              valueListenable: stations,
              builder: (_, value, _) =>
                  FdsnStationLayer(stations: value, diagnostics: diagnostics),
            ),
          ],
        ),
      ),
    );
    Finder paintedLayer() => find.descendant(
      of: find.byType(FdsnStationLayer),
      matching: find.byType(CustomPaint),
    );
    expect(paintedLayer(), findsOneWidget);
    stations.value = [
      stations.value.single.copyWith(lastMotionUpdate: DateTime.now()),
    ];
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.pump(const Duration(milliseconds: 1100));
    expect(paintedLayer(), findsOneWidget);
    expect(diagnostics.pictureRecordings, 1);
    stations.value = [nearExpiry()];
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.pump(const Duration(milliseconds: 1100));
    expect(paintedLayer(), findsNothing);
    expect(diagnostics.pictureRecordings, 1);
    await tester.pumpWidget(const SizedBox());
    stations.dispose();
  });
  for (final size in [const Size(390, 844), const Size(1280, 720)]) {
    testWidgets('FDSN canvas, scale switch, gestures and two-digit size $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => FdsnIntensity.scale.value = FdsnIntensityScale.mmi);
      final controller = MapController();
      final key = GlobalKey();
      final stations = [
        for (var n = 1; n <= 12; n++)
          FdsnStation(
            network: 'XX',
            station: 'TEST$n',
            location: '',
            source: 'EarthScope',
            coordinate: LatLng(
              30.7 - ((n - 1) ~/ 4) * .65,
              104.1 + ((n - 1) % 4) * .6,
            ),
            intensity: n <= 10 ? n.toDouble() : null,
            pga: 100 * math.pow(10, (n - 6.59) / 3.17).toDouble(),
            pgv: 100 * math.pow(10, (n - 9.77) / 3).toDouble(),
            lastMotionUpdate: DateTime.now(),
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: FlutterMap(
              mapController: controller,
              options: const MapOptions(
                backgroundColor: Color(0xFF242424),
                initialCenter: LatLng(30, 105),
                initialZoom: 7.5,
              ),
              children: [
                const ColoredBox(color: Color(0xFF242424)),
                FdsnStationLayer(stations: stations),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(MarkerLayer), findsNothing);
      final images = <List<int>>[];
      for (final scale in FdsnIntensityScale.values) {
        FdsnIntensity.scale.value = scale;
        await tester.pump();
        await tester.runAsync(() async {
          final shot =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final rgba = (await shot.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          images.add(rgba.buffer.asUint8List().toList());
          final png = (await shot.toByteData(format: ui.ImageByteFormat.png))!;
          final dir = Directory('tmp/fdsn_review')..createSync(recursive: true);
          await File(
            '${dir.path}/${scale.name}-${size.width.toInt()}.png',
          ).writeAsBytes(png.buffer.asUint8List());
          shot.dispose();
        });
      }
      expect(images[0], isNot(orderedEquals(images[1])));
      final before = controller.camera.center;
      await tester.drag(find.byType(FlutterMap), const Offset(50, 30));
      await tester.pumpAndSettle();
      expect(controller.camera.center, isNot(before));
      final watch = Stopwatch()..start();
      for (var i = 0; i < 30; i++) {
        controller.move(LatLng(30 + i * .001, 105), 7.5);
        await tester.pump();
      }
      watch.stop();
      // Diagnostic only; test engine timing is not a Release frame-rate claim.
      debugPrint(
        'FDSN camera pumps ($size): ${watch.elapsedMicroseconds ~/ 30} us average',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
}
