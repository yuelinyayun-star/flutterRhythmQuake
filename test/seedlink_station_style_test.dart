import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/core/seedlink_station_style.dart';
import 'package:flutterrhythmquake/core/fdsn_intensity.dart';
import 'package:flutterrhythmquake/core/seedlink_activity.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_motion_service.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_station_service.dart';
import 'package:flutterrhythmquake/widgets/map/fdsn_station_layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FdsnIntensity.scale.value = FdsnIntensityScale.gq);
  tearDown(() => FdsnIntensity.scale.value = FdsnIntensityScale.mmi);
  setUpAll(() async {
    final font = FontLoader('MPLUSRounded1c')
      ..addFont(rootBundle.load('assets/fonts/MPLUSRounded1c-Bold.ttf'));
    await font.load();
    final calibri = File('C:/Windows/Fonts/calibri.ttf');
    await (FontLoader('Calibri')..addFont(
          calibri.existsSync()
              ? calibri.readAsBytes().then((b) => ByteData.sublistView(b))
              : rootBundle.load('assets/fonts/MPLUSRounded1c-Bold.ttf'),
        ))
        .load();
  });
  tearDown(() => SeedLinkStationStyle.shape.value = SeedLinkShapeMode.circle);

  test('legacy metric preferences and bounded continuous zoom size', () {
    expect(FdsnIntensity.parseScale(null), FdsnIntensityScale.gq);
    expect(FdsnIntensity.parseScale('invalid'), FdsnIntensityScale.gq);
    expect(SeedLinkStationStyle.parseMode(null), SeedLinkShapeMode.circle);
    for (final metric in FdsnIntensityScale.values) {
      expect(FdsnIntensity.parseScale(metric.name), metric);
    }
    expect(
      FdsnIntensity.displayLevel(
        FdsnIntensityScale.gq,
        pgaGal: 100,
        pgvCms: 10,
      ),
      isNull,
    );
    expect(SeedLinkStationStyle.markerScale(1) * 14, 7);
    expect(SeedLinkStationStyle.markerScale(5), .5);
    expect(SeedLinkStationStyle.markerScale(7), 1);
    expect(SeedLinkStationStyle.markerScale(18), 1);
    for (var zoom = 5.0; zoom < 7; zoom += .01) {
      final current = SeedLinkStationStyle.markerScale(zoom);
      final next = SeedLinkStationStyle.markerScale(zoom + .01);
      expect(next, greaterThan(current));
      expect(next - current, lessThan(.004));
    }
  });

  test('sensor classification uses response units and preserves unknown', () {
    for (final unit in ['M/S**2', 'm / s^2', 'M/SEC/SEC']) {
      expect(
        SeedLinkSensorType.fromUnit(unit),
        SeedLinkSensorType.acceleration,
      );
    }
    expect(SeedLinkSensorType.fromUnit('M/S'), SeedLinkSensorType.velocity);
    expect(SeedLinkSensorType.fromUnit('M'), SeedLinkSensorType.displacement);
    for (final unit in ['', 'COUNTS', 'PA', 'M/SOMETHING']) {
      expect(SeedLinkSensorType.fromUnit(unit), SeedLinkSensorType.unknown);
    }
    for (final mode in SeedLinkShapeMode.values) {
      expect(SeedLinkStationStyle.parseMode(mode.name), mode);
    }
    expect(SeedLinkStationStyle.parseMode(null), SeedLinkShapeMode.circle);
    expect(SeedLinkStationStyle.parseMode('invalid'), SeedLinkShapeMode.circle);
    for (final type in SeedLinkSensorType.values) {
      expect(
        SeedLinkStationStyle.resolve(SeedLinkShapeMode.triangle, type),
        SeedLinkMarkerShape.triangle,
      );
      expect(
        SeedLinkStationStyle.resolve(SeedLinkShapeMode.circle, type),
        SeedLinkMarkerShape.circle,
      );
    }
    expect(
      SeedLinkSensorType.values.map(
        (type) =>
            SeedLinkStationStyle.resolve(SeedLinkShapeMode.sensorType, type),
      ),
      [
        SeedLinkMarkerShape.circle,
        SeedLinkMarkerShape.triangle,
        SeedLinkMarkerShape.invertedTriangle,
        SeedLinkMarkerShape.square,
      ],
    );
  });

  test('foreground transfer and copies retain actual sensor type', () {
    for (final type in SeedLinkSensorType.values) {
      final sample = FdsnMotionSample(
        source: 'EarthScope',
        network: 'TEST',
        station: 'TYPE',
        channel: 'HHZ',
        timestamp: DateTime.utc(2026, 10, 4),
        sensorType: type,
        activity: const SeedLinkActivity(ratio: 2000.5, event: true),
        pgv: 0.2,
      );
      final wire = ForegroundStationPayload.fdsnMotion(sample);
      expect(ForegroundStationPayload.decodeFdsnMotion(wire)!.sensorType, type);
      expect(
        ForegroundStationPayload.decodeFdsnMotion(wire)!.activity,
        sample.activity,
      );
      wire.remove('sensorType');
      expect(
        ForegroundStationPayload.decodeFdsnMotion(wire)!.sensorType,
        SeedLinkSensorType.unknown,
      );
      final station = FdsnStation(
        network: 'TEST',
        station: 'TYPE',
        location: '',
        coordinate: const LatLng(0, 0),
        source: 'EarthScope',
        sensorType: type,
        activity: const SeedLinkActivity(ratio: 2000.5, event: true),
      ).copyWith(intensity: 3);
      final encoded = ForegroundStationPayload.fdsnStations('EarthScope', [
        station,
      ]);
      final decoded = ForegroundStationPayload.decodeFdsnStations(
        encoded['stations'],
      );
      expect(decoded.single.sensorType, type);
      expect(decoded.single.intensity, 3);
      expect(decoded.single.activity, station.activity);
    }
  });

  for (final size in [const Size(390, 844), const Size(1280, 720)]) {
    testWidgets(
      'independent metrics and shapes retain colors and update caches $size',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey();
        final diagnostics = FdsnLayerDiagnostics();
        // Isolated rendering fixture, never a production observation.
        final original = FdsnStation(
          network: 'TEST',
          station: 'METRIC',
          location: '',
          source: 'EarthScope',
          coordinate: const LatLng(0, 0),
          intensity: 5.9,
          pga: 10,
          pgv: 1,
          activity: const SeedLinkActivity(ratio: 20000),
          sensorType: SeedLinkSensorType.acceleration,
          lastMotionUpdate: DateTime.now(),
        );
        final stations = ValueNotifier([original]);
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
        final labels = <FdsnIntensityScale, List<int>>{};
        for (final metric in FdsnIntensityScale.values) {
          FdsnIntensity.scale.value = metric;
          final expected = switch (metric) {
            FdsnIntensityScale.mmi =>
              0xFFFFD200, // Rounded MMI 6, original palette.
            FdsnIntensityScale.csis =>
              0xFF4499FF, // CSIS 4 from PGA/PGV, not MMI.
            FdsnIntensityScale.gq => 0xFFFB0000,
          };
          for (final shape in SeedLinkShapeMode.values) {
            SeedLinkStationStyle.shape.value = shape;
            await tester.pump();
            await tester.runAsync(() async {
              final image =
                  await (key.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage();
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              final cx = size.width ~/ 2, cy = size.height ~/ 2;
              final offset = (cy * image.width + cx) * 4;
              expect(bytes.getUint8(offset), (expected >> 16) & 255);
              expect(bytes.getUint8(offset + 1), (expected >> 8) & 255);
              expect(bytes.getUint8(offset + 2), expected & 255);
              final label = [
                for (var y = cy + 12; y < cy + 25; y++)
                  for (var x = cx - 30; x < cx + 30; x++)
                    bytes.getUint8((y * image.width + x) * 4),
              ];
              expect(label.any((v) => v > 30), isTrue);
              if (labels.containsKey(metric)) {
                expect(
                  label,
                  orderedEquals(labels[metric]!),
                  reason: 'shape cannot change numeric mode',
                );
              } else {
                labels[metric] = label;
              }
              final directory = Directory('tmp/seedlink_shapes')
                ..createSync(recursive: true);
              final png = (await image.toByteData(
                format: ui.ImageByteFormat.png,
              ))!;
              await File(
                '${directory.path}/${metric.name}-${shape.name}-${size.width.toInt()}.png',
              ).writeAsBytes(png.buffer.asUint8List());
              image.dispose();
            });
            expect(FdsnIntensity.scale.value, metric);
          }
        }
        expect(
          labels[FdsnIntensityScale.mmi],
          isNot(orderedEquals(labels[FdsnIntensityScale.csis]!)),
        );
        expect(
          labels[FdsnIntensityScale.gq],
          isNot(orderedEquals(labels[FdsnIntensityScale.mmi]!)),
        );
        for (final metric in FdsnIntensityScale.values) {
          stations.value = [original];
          FdsnIntensity.scale.value = metric;
          await tester.pump();
          final before = diagnostics.pictureRecordings;
          stations.value = [
            switch (metric) {
              FdsnIntensityScale.mmi => original.copyWith(
                activity: const SeedLinkActivity(ratio: 20),
                pga: 100,
              ),
              FdsnIntensityScale.csis => original.copyWith(
                activity: const SeedLinkActivity(ratio: 20),
                intensity: 9,
              ),
              FdsnIntensityScale.gq => original.copyWith(
                intensity: 9,
                pga: 100,
                pgv: 10,
              ),
            },
          ];
          await tester.pump();
          expect(
            diagnostics.pictureRecordings,
            before,
            reason: 'inactive metric updates must not redraw',
          );
          stations.value = [
            switch (metric) {
              FdsnIntensityScale.mmi => original.copyWith(intensity: 8),
              FdsnIntensityScale.csis => original.copyWith(pga: 100, pgv: 10),
              FdsnIntensityScale.gq => original.copyWith(
                activity: const SeedLinkActivity(ratio: 2),
              ),
            },
          ];
          await tester.pump();
          expect(
            diagnostics.pictureRecordings,
            before + 1,
            reason: 'active metric updates must redraw',
          );
        }
        expect(diagnostics.atlasBuilds, 1);
        expect(diagnostics.atlasSlots, 18);
        expect(diagnostics.projections, 1);
        expect(original.intensity, 5.9);
        expect(original.pga, 10);
        expect(original.pgv, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        stations.dispose();
      },
    );

    testWidgets('shape pixels, external labels and cached switches $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      final controller = MapController();
      final diagnostics = FdsnLayerDiagnostics();
      final stations = ValueNotifier([
        FdsnStation(
          network: 'TEST',
          station: 'SHAPE',
          location: '',
          source: 'EarthScope',
          coordinate: const LatLng(0, 0),
          intensity: 10,
          activity: const SeedLinkActivity(ratio: 20000),
          sensorType: SeedLinkSensorType.velocity,
          lastMotionUpdate: DateTime.now(),
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: FlutterMap(
              mapController: controller,
              options: const MapOptions(
                initialCenter: LatLng(0, 0),
                initialZoom: 7,
                backgroundColor: Colors.black,
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
      Future<Uint8List> capture(String name) async {
        late Uint8List pixels;
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          pixels = Uint8List.fromList(
            (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List(),
          );
          final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
          final directory = Directory('tmp/seedlink_shapes')
            ..createSync(recursive: true);
          await File(
            '${directory.path}/$name-${size.width.toInt()}.png',
          ).writeAsBytes(png.buffer.asUint8List());
          image.dispose();
        });
        return pixels;
      }

      int colored(Uint8List pixels, int top, int bottom, {bool white = false}) {
        var count = 0;
        for (var y = top; y < bottom; y++) {
          for (var x = -12; x <= 12; x++) {
            final offset =
                (((size.height ~/ 2) + y) * size.width.toInt() +
                    size.width ~/ 2 +
                    x) *
                4;
            if (white ? pixels[offset + 1] > 30 : pixels[offset] > 30) count++;
          }
        }
        return count;
      }

      final circle = await capture('circle');
      expect(colored(circle, 12, 24, white: true), greaterThan(0));
      expect(
        colored(circle, -6, 6, white: true),
        0,
        reason: 'no white outline or number inside the solid marker',
      );
      final before = diagnostics.pictureRecordings;
      SeedLinkStationStyle.shape.value = SeedLinkShapeMode.triangle;
      await tester.pump();
      final triangle = await capture('triangle');
      expect(colored(triangle, 3, 8), greaterThan(colored(triangle, -8, -3)));
      expect(diagnostics.pictureRecordings, before + 1);
      SeedLinkStationStyle.shape.value = SeedLinkShapeMode.sensorType;
      await tester.pump();
      expect(
        diagnostics.pictureRecordings,
        before + 1,
        reason: 'velocity type retains exactly the same triangle',
      );
      stations.value = [
        stations.value.single.copyWith(
          sensorType: SeedLinkSensorType.acceleration,
        ),
      ];
      await tester.pump();
      final inverted = await capture('acceleration');
      expect(colored(inverted, -8, -3), greaterThan(colored(inverted, 3, 8)));
      stations.value = [
        stations.value.single.copyWith(
          sensorType: SeedLinkSensorType.displacement,
        ),
      ];
      await tester.pump();
      final square = await capture('displacement');
      expect(colored(square, -7, 7), greaterThan(colored(circle, -7, 7)));
      stations.value = [
        stations.value.single.copyWith(sensorType: SeedLinkSensorType.unknown),
      ];
      await tester.pump();
      expect(await capture('unknown'), orderedEquals(circle));
      controller.move(const LatLng(0, 0), 5);
      await tester.pump();
      final far = await capture('overview');
      expect(colored(far, 12, 24, white: true), 0);
      expect(colored(far, -7, 7), greaterThan(0));
      controller.move(const LatLng(0, 0), 7);
      stations.value = [
        stations.value.single.copyWith(
          activity: const SeedLinkActivity(ratio: 20000, event: true),
        ),
      ];
      await tester.pump();
      final event = await capture('event');
      expect(colored(event, 12, 24, white: true), greaterThan(0));
      final recordings = diagnostics.pictureRecordings;
      final paints = diagnostics.paints;
      final flashes = diagnostics.eventPaints;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(diagnostics.eventPaints, greaterThan(flashes));
      expect(
        diagnostics.paints,
        paints,
        reason: 'blinking must not repaint base stations',
      );
      expect(diagnostics.pictureRecordings, recordings);
      expect(diagnostics.atlasBuilds, 1);
      expect(diagnostics.atlasSlots, 18);
      expect(diagnostics.projections, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      stations.dispose();
      controller.dispose();
    });
  }
}
