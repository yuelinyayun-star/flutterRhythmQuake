import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:flutterrhythmquake/services/sources/fan_radar_service.dart';
import 'package:flutterrhythmquake/widgets/map/fan_radar_layer.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'validated radar pixels are reused and retired overlay cache is released',
    (tester) async {
      final bytes = File(
        'test/fixtures/cma_radar/ACHN_QREF_20260921_221200.png',
      ).readAsBytesSync();
      final list = File(
        'test/fixtures/cma_radar/radar_list_20260921.jsonp',
      ).readAsBytesSync();
      final client = MockClient(
        (request) async => http.Response.bytes(
          request.url.path.endsWith('radar_list.json') ? list : bytes,
          200,
        ),
      );
      final service = FanRadarService.forTesting(client: client);
      addTearDown(() {
        service.stop(clear: true);
        client.close();
      });
      await tester.runAsync(() => service.start(startupAttempts: 1));
      final frame = service.latestFrame!;
      final provider = RadarFrameImage(frame);
      // A failing decoder proves that the foreground consumes validated pixels.
      // ignore: invalid_use_of_protected_member
      final completer = provider.loadImage(
        provider,
        (buffer, {getTargetSize}) =>
            throw StateError('The validated frame must not decode twice'),
      );
      ImageInfo? info;
      final listener = ImageStreamListener((image, _) => info = image);
      completer.addListener(listener);
      await tester.pump();
      expect(info, isNotNull);
      expect(info!.image.width, frame.width);
      expect(frame.validatedImage!.take(), isNull);
      // Seed the same completer that the map would resolve on first display.
      PaintingBinding.instance.imageCache.putIfAbsent(
        provider,
        () => completer,
      );
      completer.removeListener(listener);
      info!.dispose();

      final selected = ValueNotifier<FanRadarFrame?>(frame);
      addTearDown(selected.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(34, 105),
                initialZoom: 3,
              ),
              children: [
                ValueListenableBuilder<FanRadarFrame?>(
                  valueListenable: selected,
                  builder: (_, value, _) => FanRadarLayer(frame: value),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<List<int>> pixels() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return data!.buffer.asUint8List().toList();
      }

      final before = await tester.runAsync(pixels);
      final colors = <int>{};
      for (var i = 0; i < before!.length; i += 4) {
        colors.add((before[i] << 16) | (before[i + 1] << 8) | before[i + 2]);
      }
      expect(
        colors.length,
        greaterThan(5),
        reason: 'The comparison must include visible radar pixels',
      );
      expect(PaintingBinding.instance.imageCache.containsKey(provider), isTrue);
      // Replay the same original handoff with a separate byte buffer. Source
      // timestamps, bounds and PNG pixels are unchanged.
      final handedOff = ForegroundStationPayload.decodeFanRadar(
        ForegroundStationPayload.fanRadar(frame),
      )!;
      selected.value = handedOff;
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(await tester.runAsync(pixels), before);
      expect(
        PaintingBinding.instance.imageCache.containsKey(provider),
        isFalse,
      );
      expect(
        PaintingBinding.instance.imageCache.containsKey(
          RadarFrameImage(handedOff),
        ),
        isTrue,
      );
      expect(
        PaintingBinding.instance.imageCache.currentSizeBytes,
        frame.width * frame.height * 4,
      );
      selected.value = null;
      await tester.pumpAndSettle();
      expect(
        PaintingBinding.instance.imageCache.containsKey(
          RadarFrameImage(handedOff),
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'background collection validates PNG without retaining native pixels',
    () async {
      final bytes = File(
        'test/fixtures/cma_radar/ACHN_QREF_20260921_221200.png',
      ).readAsBytesSync();
      final list = File(
        'test/fixtures/cma_radar/radar_list_20260921.jsonp',
      ).readAsBytesSync();
      final client = MockClient(
        (r) async => http.Response.bytes(
          r.url.path.endsWith('radar_list.json') ? list : bytes,
          200,
        ),
      );
      final service = FanRadarService.forTesting(client: client);
      try {
        await service.start(startupAttempts: 1, retainDecodedImage: false);
        expect(service.latestFrame!.imageBytes, bytes);
        expect(service.latestFrame!.validatedImage, isNull);
        final handoff = ForegroundStationPayload.decodeFanRadar(
          ForegroundStationPayload.fanRadar(service.latestFrame!),
        )!;
        expect(handoff.imageBytes, bytes);
        expect(handoff.validatedImage, isNull);
        service.stop(clear: true);
        await service.start(startupAttempts: 1);
        final foreground = service.latestFrame!;
        expect(foreground.validatedImage, isNotNull);
        service.stop();
        expect(service.latestFrame, same(foreground));
        expect(foreground.imageBytes, bytes);
        expect(
          foreground.validatedImage!.take(),
          isNull,
          reason: 'Stopping preserves PNG, not an unconsumed native image',
        );
      } finally {
        service.stop(clear: true);
        client.close();
      }
    },
  );
}
