import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/core/travel_time_service.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/services/ntp_service.dart';
import 'package:latlong2/latlong.dart';

Future<void> finishMove(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 45)),
    );
    await tester.pump(const Duration(milliseconds: 45));
  }
}

void main() {
  for (final size in [const Size(1584, 796), const Size(430, 900)]) {
    testWidgets('original Jan Mayen fourth EEW stays centered $size', (
      tester,
    ) async {
      final file = File(
        'test/fixtures/eew_camera_20261101/gq_jan_mayen_report4.original.json',
      );
      final bytes = file.readAsBytesSync();
      expect(
        sha256.convert(bytes).toString(),
        '38c470ef640394487845753d229ded1009be6ff8e808444a89b38393a7273be8',
      );
      final raw = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final event = QuakeMessage.fromMap(
        Map<String, dynamic>.from(raw['rawEvent'] as Map),
      );
      await tester.runAsync(() => TravelTimeService().ensureLoaded());
      final epicenter = LatLng(event.latitude, event.longitude);
      final ntp = NtpService();
      final old = (ntp.deviceOffset, ntp.lastSyncedAt, ntp.isSynced);
      // Reproduce the screenshot clock; never rewrite the saved report times.
      ntp.restoreClockSample(
        DateTime(
          2026,
          11,
          1,
          19,
          12,
          6,
        ).difference(DateTime.now()).inMilliseconds,
        DateTime.now(),
        true,
      );
      addTearDown(() => ntp.restoreClockSample(old.$1, old.$2, old.$3));
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = MapController();
      final provider = MapStateProvider();
      addTearDown(provider.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterMap(
            mapController: controller,
            options: MapOptions(initialCenter: epicenter, initialZoom: 6),
            children: const [],
          ),
        ),
      );
      provider.setController(controller, const TestVSync());
      provider.smartMoveToEvents(
        [event],
        waveEvents: [event],
        padding: 0.8,
        minZoom: 4.5,
        maxZoom: 8,
        force: true,
        continuousFollow: true,
      );
      await finishMove(tester);
      final pixel = controller.camera.latLngToScreenOffset(epicenter);
      final error = (pixel - size.center(Offset.zero)).distance;
      final result = {
        'size': '${size.width}x${size.height}',
        'epicenterPixel': [pixel.dx, pixel.dy],
        'errorPx': error,
        'zoom': controller.camera.zoom,
        'center': [
          controller.camera.center.latitude,
          controller.camera.center.longitude,
        ],
      };
      final out = Directory('tmp/eew_camera_20261101')
        ..createSync(recursive: true);
      File(
        '${out.path}/${Platform.environment['RQ_EEW_PHASE'] ?? 'result'}-${size.width.toInt()}.json',
      ).writeAsStringSync(jsonEncode(result));
      debugPrint('JAN_MAYEN_CAMERA ${jsonEncode(result)}');
      expect(error, lessThan(1));
      expect(sha256.convert(file.readAsBytesSync()), sha256.convert(bytes));
    });
  }
}
