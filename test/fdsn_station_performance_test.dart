import 'dart:convert';
import 'dart:io';
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

// Controlled rendering fixtures only, never injected into production sources.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'MPLUSRounded1c',
    )..addFont(rootBundle.load('assets/fonts/MPLUSRounded1c-Bold.ttf'))).load();
  });
  for (final size in [const Size(1280, 720), const Size(390, 844)]) {
    testWidgets(
      'global 5000-station rendering equivalence and workload $size',
      (tester) async {
        const phase = String.fromEnvironment('FDSN_RENDER_PHASE');
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(() => FdsnIntensity.scale.value = FdsnIntensityScale.mmi);
        final map = MapController();
        final boundary = GlobalKey();
        final diagnostics = FdsnLayerDiagnostics();
        final now = DateTime.now();
        final stations = ValueNotifier([
          for (var i = 0; i < 5000; i++)
            FdsnStation(
              network: 'XX',
              station: 'LOAD$i',
              location: '',
              source: 'EarthScope',
              coordinate: LatLng(
                -70 + (i ~/ 100) * 2.8,
                -179 + (i % 100) * 3.6,
              ),
              intensity: i % 11 == 0 ? null : (i % 10 + 1).toDouble(),
              pga: (i % 300 + 1).toDouble(),
              pgv: (i % 70 + 1).toDouble(),
              lastMotionUpdate: now,
            ),
        ]);
        await tester.pumpWidget(
          MaterialApp(
            home: RepaintBoundary(
              key: boundary,
              child: FlutterMap(
                mapController: map,
                options: const MapOptions(
                  initialCenter: LatLng(30, 105),
                  initialZoom: 8,
                  backgroundColor: Color(0xff242424),
                ),
                children: [
                  ValueListenableBuilder<List<FdsnStation>>(
                    valueListenable: stations,
                    builder: (_, value, _) => FdsnStationLayer(
                      stations: value,
                      diagnostics: diagnostics,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        final dir = Directory('tmp/fdsn_map_performance')
          ..createSync(recursive: true);
        final timings = <String, int>{};
        final frames = [
          (const LatLng(30, 105), 8.0, 0.0, 1.0),
          (const LatLng(0, 179), 1.13, 0.0, 1.0),
          (const LatLng(0, -179), 3.57, 37.0, 1.25),
          (const LatLng(-24, -70), 6.23, 90.0, 2.0),
        ];
        for (final scale in FdsnIntensityScale.values) {
          FdsnIntensity.scale.value = scale;
          for (var index = 0; index < frames.length; index++) {
            final (center, zoom, rotation, ratio) = frames[index];
            tester.view.devicePixelRatio = ratio;
            tester.view.physicalSize = size * ratio;
            map.moveAndRotate(center, zoom, rotation);
            await tester.pump();
            if (phase.isEmpty) continue;
            await tester.runAsync(() async {
              final shot =
                  await (boundary.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: ratio);
              final bytes = (await shot.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!.buffer.asUint8List();
              final file = File(
                '${dir.path}/${size.width.toInt()}-${scale.name}-$index.rgba',
              );
              if (phase == 'before') {
                await file.writeAsBytes(bytes);
                final png = (await shot.toByteData(
                  format: ui.ImageByteFormat.png,
                ))!;
                await File(
                  '${file.path}.png',
                ).writeAsBytes(png.buffer.asUint8List());
              } else {
                final original = await file.readAsBytes();
                expect(bytes.length, original.length);
                var changed = 0;
                for (var i = 0; i < bytes.length; i++) {
                  if (bytes[i] != original[i]) changed++;
                }
                expect(changed, 0, reason: 'pixel changes: ${file.path}');
              }
              shot.dispose();
            });
          }
        }
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        FdsnIntensity.scale.value = FdsnIntensityScale.mmi;
        map.moveAndRotate(const LatLng(30, 105), 8, 0);
        await tester.pump();
        for (var warm = 0; warm < 20; warm++) {
          map.move(LatLng(30 + warm * .001, 105), 8 + warm * .001);
          await tester.pump();
        }
        final visits = diagnostics.selectionVisits;
        final projections = diagnostics.projections;
        final indexBuilds = diagnostics.spatialIndexBuilds;
        final watch = Stopwatch()..start();
        for (var i = 0; i < 120; i++) {
          map.move(LatLng(30 + i * .001, 105), 8 + i * .002);
          await tester.pump();
        }
        timings['localZoomUsPerPump'] = watch.elapsedMicroseconds ~/ 120;
        if (phase != 'before') {
          expect(diagnostics.projections, projections);
          expect(diagnostics.spatialIndexBuilds, indexBuilds);
          expect(diagnostics.selectionVisits - visits, lessThan(120 * 100));
          debugPrint(
            'FDSN local zoom candidates over 120 frames: '
            '${diagnostics.selectionVisits - visits} (full scan: 600000)',
          );
        }
        watch
          ..reset()
          ..start();
        int? glyphs, recordings, allocations, builds;
        for (var i = 0; i < 30; i++) {
          stations.value = [
            for (final s in stations.value)
              s.copyWith(
                intensity: (s.intensity ?? 1) + .00001,
                pga: s.pga! + .001,
                lastMotionUpdate: now,
              ),
          ];
          await tester.pump();
          if (i == 0) {
            glyphs = diagnostics.glyphCreations;
            recordings = diagnostics.pictureRecordings;
            allocations = diagnostics.bufferAllocations;
            builds = diagnostics.spatialIndexBuilds;
          } else if (phase != 'before') {
            expect(diagnostics.glyphCreations, glyphs);
            expect(diagnostics.pictureRecordings, recordings);
            expect(diagnostics.bufferAllocations, allocations);
            expect(diagnostics.spatialIndexBuilds, builds);
          }
        }
        timings['sameLevelUpdateUsPerPump'] = watch.elapsedMicroseconds ~/ 30;
        debugPrint('FDSN GLOBAL BENCH ${size.width.toInt()}: $timings');
        if (phase.isNotEmpty) {
          File(
            '${dir.path}/$phase-${size.width.toInt()}.json',
          ).writeAsStringSync(jsonEncode(timings));
        }
        // Removing/reordering stations must not discard survivors' projected
        // coordinates or styles; their input order still controls overlap.
        if (phase != 'before') {
          stations.value = stations.value.skip(1).toList().reversed.toList();
          await tester.pump();
          expect(diagnostics.projections, projections);
          expect(diagnostics.glyphCreations, glyphs);
        }
        await tester.pumpWidget(const SizedBox());
        stations.dispose();
        map.dispose();
      },
    );
  }
}
