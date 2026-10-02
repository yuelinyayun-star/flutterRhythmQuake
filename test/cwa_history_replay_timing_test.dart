import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutterrhythmquake/core/travel_time_service.dart';
import 'package:flutterrhythmquake/core/utils/quake_time.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/services/ntp_service.dart';
import 'package:flutterrhythmquake/widgets/map/wave_layer.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

String captured(String name) =>
    File('test/fixtures/history_replay/$name.rqreplay').readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'unmodified CWA capture uses actual arrival times for conflicting reports',
    () {
      final original = jsonDecode(captured('cwa_1150074')) as Map;
      final package = HistoryReplayPackage.decode(jsonEncode(original));
      expect(package.timing, HistoryReplayTiming.arrival);
      expect(package.usesDeviceArrivalTimeZone, isTrue);
      expect(package.reports.map((e) => e.reportNumText), [
        '第1報',
        '第2報',
        '第3報',
        '第4報',
      ]);
      expect(package.duration, const Duration(microseconds: 7418597));
      final before = {
        for (final r in original['reports']) r['reportNumText']: r,
      };
      for (var i = 0; i < package.reports.length; i++) {
        final report = package.reports[i];
        expect(report.toMap(), before[report.reportNumText]);
        expect(package.times[i], report.arrivedAt!.toUtc());
        expect(
          package.times[i]
              .difference(QuakeTime.unifiedInstantUtc(report))
              .isNegative,
          isFalse,
        );
      }
    },
  );

  test('export carries UTC arrival metadata without rewriting reports', () {
    final package = HistoryReplayPackage.decode(captured('cwa_1150074'));
    final exported = package.encode();
    final restored = HistoryReplayPackage.decode(exported);
    expect(restored.usesDeviceArrivalTimeZone, isFalse);
    expect(restored.times, package.times);
    expect(
      restored.reports.map((e) => e.toMap()),
      package.reports.map((e) => e.toMap()),
    );
    final map = jsonDecode(exported) as Map<String, dynamic>;
    map['arrivalInstantsUtc'] = [];
    expect(
      () => HistoryReplayPackage.decode(jsonEncode(map)),
      throwsFormatException,
    );
  });

  test(
    'CWA scheduler delivers all four saved reports at recorded arrival intervals',
    () {
      final package = HistoryReplayPackage.decode(captured('cwa_1150074'));
      fakeAsync((async) {
        final output = <String>[];
        final clock = async.getClock(DateTime.utc(2026, 10, 2));
        final controller =
            HistoryReplayController(
                onReport: (report) => output.add(report.reportNumText),
                onClear: (_) {},
                now: clock.now,
              )
              ..load(package)
              ..play();
        expect(output, ['第1報']);
        async.elapse(package.duration);
        expect(output, ['第1報', '第2報', '第3報', '第4報']);
        expect(controller.holding, isTrue);
        async.elapse(const Duration(seconds: 30));
        expect(controller.active, isTrue);
        async.elapse(
          package.playbackDuration -
              package.duration -
              const Duration(seconds: 30),
        );
        expect(controller.active, isFalse);
        controller.dispose();
      });
    },
  );

  test('second uploaded capture is CEA and has valid source timing', () {
    final original = jsonDecode(captured('cea_202609290220')) as Map;
    final package = HistoryReplayPackage.decode(jsonEncode(original));
    expect(package.reports.single.source, 'ceaEew');
    expect(package.timing, HistoryReplayTiming.report);
    expect(
      package.times.single,
      QuakeTime.unifiedInstantUtc(package.reports.single),
    );
    expect(package.reports.single.toMap(), original['reports'].single);
  });

  for (final size in [const Size(1000, 720), const Size(390, 700)]) {
    testWidgets('CWA replay paints P/S rings at ${size.width}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final provider = QuakeProvider();
      var disposed = false;
      addTearDown(() {
        if (!disposed) provider.dispose();
      });
      final package = HistoryReplayPackage.decode(captured('cwa_1150074'));
      await tester.runAsync(TravelTimeService().ensureLoaded);
      provider.historyReplay.load(package);
      provider.historyReplay.play();
      final event = provider.unifiedMapEvents.single;
      final elapsed =
          NtpService().now
              .toUtc()
              .difference(QuakeTime.eventInstantUtc(event))
              .inMicroseconds /
          1e6;
      final expected =
          package.times.first
              .difference(QuakeTime.unifiedInstantUtc(package.reports.first))
              .inMicroseconds /
          1e6;
      expect(elapsed, closeTo(expected, .5));
      final travel = TravelTimeService();
      expect(
        travel.calcWaveDistance('jma2001', true, event.depth, elapsed).radius,
        greaterThan(0),
      );
      expect(
        travel.calcWaveDistance('jma2001', false, event.depth, elapsed).radius,
        greaterThan(0),
      );
      final map = MapController();
      addTearDown(map.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterMap(
            mapController: map,
            options: MapOptions(
              initialCenter: LatLng(event.latitude, event.longitude),
              initialZoom: 7,
            ),
            children: const [],
          ),
        ),
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      WavePainter(
        event: event,
        camera: map.camera,
        pWaveColor: Colors.cyan,
        sWaveColor: Colors.orange,
        showCrosshair: false,
        showEpicenterLabel: false,
      ).paint(canvas, size);
      final picture = recorder.endRecording();
      final image = await tester.runAsync(
        () => picture.toImage(size.width.toInt(), size.height.toInt()),
      );
      final pixels = await tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      var cyan = 0;
      var orange = 0;
      final bytes = pixels!.buffer.asUint8List();
      for (var i = 0; i < bytes.length; i += 4) {
        if (bytes[i + 3] < 100) continue;
        if (bytes[i] < 30 && bytes[i + 1] > 120 && bytes[i + 2] > 120) cyan++;
        if (bytes[i] > 200 && bytes[i + 1] > 80 && bytes[i + 2] < 30) orange++;
      }
      expect(cyan, greaterThan(20), reason: 'P ring pixels');
      expect(orange, greaterThan(20), reason: 'S ring pixels');
      final png = await tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.png),
      );
      await tester.runAsync(() async {
        final output = Directory('build/diagnostics/history_replay');
        await output.create(recursive: true);
        await File(
          '${output.path}/cwa_waves_${size.width.toInt()}.png',
        ).writeAsBytes(png!.buffer.asUint8List());
      });
      image!.dispose();
      picture.dispose();
      provider.historyReplay.stop();
      provider.dispose();
      disposed = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
    });
  }
}
