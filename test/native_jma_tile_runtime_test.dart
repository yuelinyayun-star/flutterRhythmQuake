import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/jma_radar_service.dart';
import 'package:flutterrhythmquake/services/sources/jma_satellite_cloud_service.dart';
import 'package:flutterrhythmquake/services/sources/native_jma_tile_owner.dart';

const fixtures = 'test/fixtures/jma_tile_runtime_20261019';
Future<void> until(
  bool Function() ready, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final watch = Stopwatch()..start();
  while (!ready()) {
    if (watch.elapsed > timeout) {
      throw TimeoutException('Native JMA source did not publish');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<HttpServer> serve(Future<void> Function(HttpRequest) handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((r) => unawaited(handler(r)));
  return server;
}

Future<void> respond(HttpRequest r, List<int> bytes, {int status = 200}) async {
  try {
    r.response.statusCode = status;
    r.response.headers.contentType = ContentType.json;
    r.response.add(bytes);
    await r.response.close();
  } on IOException {
    /* Explicit cancellation closes pending offline requests. */
  }
}

Uri endpoint(HttpServer s) =>
    Uri.parse('http://127.0.0.1:${s.port}/original-index');
void main() {
  final enabled = NativeJmaTileOwner.supported;
  test(
    'clear after pausing before the first frame releases both source workers',
    () async {
      final workers = NativeJmaTileOwner.workers;
      final gate = Completer<void>();
      var requests = 0;
      final server = await serve((r) async {
        requests++;
        await gate.future;
        await respond(r, []);
      });
      addTearDown(() => server.close(force: true));
      final radar = JmaRadarService.forNativeTest(endpoint: endpoint(server));
      final satellite = JmaSatelliteCloudService.forNativeTest(
        endpoint: endpoint(server),
      );
      radar.start(startupAttempts: 1);
      satellite.start();
      await until(() => requests == 2);
      radar.stop();
      satellite.stop();
      expect(radar.latestFrame, isNull);
      expect(satellite.latestFrame, isNull);
      radar.stop(clear: true);
      satellite.stop(clear: true);
      expect(NativeJmaTileOwner.workers, workers);
      gate.complete();
      await radar.dispose();
      await satellite.dispose();
    },
    skip: !enabled,
  );
  test(
    'live production JMA radar and satellite use native owners',
    () async {
      final radar = JmaRadarService();
      final satellite = JmaSatelliteCloudService();
      expect(radar.usesNativeBackend, isTrue);
      expect(satellite.usesNativeBackend, isTrue);
      final workers = NativeJmaTileOwner.workers;
      radar.start(startupAttempts: 1);
      satellite.start();
      try {
        await until(
          () => radar.latestFrame != null && satellite.latestFrame != null,
          timeout: const Duration(seconds: 25),
        );
        final values = {
          'radar': {
            'basetime': radar.latestFrame!.basetime,
            'validtime': radar.latestFrame!.validtime,
            'time': radar.latestFrame!.time.toIso8601String(),
            'native': await radar.nativeDiagnostics(),
          },
          'satellite': {
            'basetime': satellite.latestFrame!.basetime,
            'validtime': satellite.latestFrame!.validtime,
            'time': satellite.latestFrame!.time.toIso8601String(),
            'native': await satellite.nativeDiagnostics(),
          },
        };
        final file = File(
          'tmp/jma_tile_runtime_20261019/live_native_frames.json',
        );
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(values),
        );
        expect(radar.latestFrame!.tileUrlTemplate, contains('/surf/hrpns/'));
        expect(satellite.latestFrame!.tileUrlTemplate, contains('/B13/TBB/'));
        final cancel = Completer<void>();
        final radarUrl = Uri.parse(
          radar.latestFrame!.tileUrlTemplate
              .replaceAll('{z}', '6')
              .replaceAll('{x}', '56')
              .replaceAll('{y}', '25'),
        );
        final satelliteUrl = Uri.parse(
          satellite.latestFrame!.tileUrlTemplate
              .replaceAll('{z}', '3')
              .replaceAll('{x}', '7')
              .replaceAll('{y}', '3'),
        );
        final images = await Future.wait([
          radar.loadNativeTile(radarUrl, cancel.future),
          satellite.loadNativeTile(satelliteUrl, cancel.future),
        ]);
        for (var i = 0; i < images.length; i++) {
          expect(images[i], isNotNull);
          final codec = await ui.instantiateImageCodec(images[i]!);
          final decoded = await codec.getNextFrame();
          expect(decoded.image.width, 256);
          expect(decoded.image.height, 256);
          decoded.image.dispose();
          codec.dispose();
          File(
            'tmp/jma_tile_runtime_20261019/live.${i == 0 ? 'radar.png' : 'satellite.jpg'}',
          ).writeAsBytesSync(images[i]!);
        }
        cancel.complete();
        values['radar']!['native'] = await radar.nativeDiagnostics();
        values['satellite']!['native'] = await satellite.nativeDiagnostics();
        file.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(values),
        );
      } finally {
        radar.stop(clear: true);
        satellite.stop(clear: true);
      }
      expect(NativeJmaTileOwner.workers, workers);
    },
    skip: !enabled || Platform.environment['RQ_JMA_TILE_LIVE'] != '1',
  );
  for (final satellite in [false, true]) {
    test(
      'native ${satellite ? 'satellite' : 'radar'} raw HTTP bytes to matching UI frame, dedupe and stop',
      () async {
        final workers = NativeJmaTileOwner.workers;
        final file = File(
          '$fixtures/${satellite ? 'satellite' : 'radar'}.targetTimes.original.json',
        );
        final raw = file.readAsBytesSync();
        final hash = sha256.convert(raw);
        var requests = 0;
        final server = await serve((r) async {
          requests++;
          expect(r.uri.path, '/original-index');
          if (!satellite) {
            expect(
              r.headers.value('referer'),
              'https://www.jma.go.jp/bosai/nowc/',
            );
            expect(
              r.headers.value('accept'),
              'application/json, text/plain, */*',
            );
          }
          await respond(r, raw);
        });
        addTearDown(() => server.close(force: true));
        if (satellite) {
          final expected = jmaSatelliteFrameFromTargetTimes(
            jsonDecode(utf8.decode(raw)),
          )!;
          final service = JmaSatelliteCloudService.forNativeTest(
            endpoint: endpoint(server),
          );
          final views = <JmaSatelliteCloudFrame?>[];
          final sub = service.frameStream.listen(views.add);
          service.start();
          await until(() => service.latestFrame != null);
          expect(service.usesNativeBackend, isTrue);
          expect(service.latestFrame!.time, expected.time);
          expect(service.latestFrame!.time.isUtc, isTrue);
          expect(
            service.latestFrame!.tileUrlTemplate,
            expected.tileUrlTemplate,
          );
          await service.fetchNow();
          await service.fetchNow();
          await until(() => requests == 3);
          expect(views, hasLength(1));
          final diagnostics = await service.nativeDiagnostics();
          expect(diagnostics['retainedBodyBytes'], 0);
          service.stop(clear: true);
          await service.nativeDiagnostics();
          expect(service.latestFrame, isNull);
          expect(service.isRunning, isFalse);
          final stopped = requests;
          await service.fetchNow();
          await Future<void>.delayed(const Duration(milliseconds: 60));
          expect(requests, stopped);
          await sub.cancel();
          await service.dispose();
        } else {
          final expected = jmaRadarFrameFromTargetTimes(
            jsonDecode(utf8.decode(raw)),
          )!;
          final service = JmaRadarService.forNativeTest(
            endpoint: endpoint(server),
          );
          final views = <JmaRadarFrame?>[];
          final sub = service.frameStream.listen(views.add);
          service.start(startupAttempts: 1);
          await until(() => service.latestFrame != null);
          expect(service.usesNativeBackend, isTrue);
          expect(service.latestFrame!.time, expected.time);
          expect(service.latestFrame!.time.isUtc, isFalse);
          expect(
            service.latestFrame!.tileUrlTemplate,
            expected.tileUrlTemplate,
          );
          await service.fetchNow();
          await service.fetchNow();
          await until(() => requests == 3);
          expect(views, hasLength(1));
          expect((await service.nativeDiagnostics())['retainedBodyBytes'], 0);
          service.stop(clear: true);
          await service.nativeDiagnostics();
          expect(service.latestFrame, isNull);
          expect(service.isRunning, isFalse);
          final stopped = requests;
          await service.fetchNow();
          await Future<void>.delayed(const Duration(milliseconds: 60));
          expect(requests, stopped);
          await sub.cancel();
          await service.dispose();
        }
        expect(sha256.convert(file.readAsBytesSync()), hash);
        expect(NativeJmaTileOwner.workers, workers);
      },
      skip: !enabled,
    );
  }

  test(
    'native satellite keeps original older/duplicate/malformed/error policy',
    () async {
      // These two entries are retained from the pre-migration test's observed
      // 2026-09-22 index. Controlled replies test ordering, not a live event.
      final newer = utf8.encode(
        '[{"basetime":"20260922051000","validtime":"20260922051000"}]',
      );
      final older = utf8.encode(
        '[{"basetime":"20260922050000","validtime":"20260922050000"}]',
      );
      var body = newer, status = 200;
      final server = await serve((r) => respond(r, body, status: status));
      addTearDown(() => server.close(force: true));
      final service = JmaSatelliteCloudService.forNativeTest(
        endpoint: endpoint(server),
      );
      final frames = <JmaSatelliteCloudFrame?>[];
      final sub = service.frameStream.listen(frames.add);
      service.start();
      await until(() => service.latestFrame != null);
      for (final reply in [
        newer,
        older,
        utf8.encode('[]'),
        utf8.encode('<html>unavailable</html>'),
      ]) {
        body = reply;
        await service.fetchNow();
      }
      status = 503;
      await service.fetchNow();
      expect(frames, hasLength(1));
      expect(service.latestFrame!.validtime, '20260922051000');
      final diagnostics = await service.nativeDiagnostics();
      expect(diagnostics['failures'], 3);
      await sub.cancel();
      await service.dispose();
    },
    skip: !enabled,
  );

  test(
    'native stop and immediate restart cancel an old request without stale UI',
    () async {
      final raw = File(
        '$fixtures/satellite.targetTimes.original.json',
      ).readAsBytesSync();
      final pending = Completer<void>();
      var requests = 0;
      final server = await serve((r) async {
        requests++;
        if (requests == 1) await pending.future;
        await respond(r, raw);
      });
      addTearDown(() => server.close(force: true));
      final service = JmaSatelliteCloudService.forNativeTest(
        endpoint: endpoint(server),
      );
      final frames = <JmaSatelliteCloudFrame?>[];
      final sub = service.frameStream.listen(frames.add);
      service.start();
      await until(() => requests == 1);
      service.stop(clear: true);
      service.start();
      await until(() => service.latestFrame != null);
      pending.complete();
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(requests, 2);
      expect(frames.whereType<JmaSatelliteCloudFrame>(), hasLength(1));
      expect((await service.nativeDiagnostics())['pending'], isFalse);
      await sub.cancel();
      await service.dispose();
    },
    skip: !enabled,
  );

  test(
    'native timeout cancels pending network input and restart recovers',
    () async {
      final raw = File(
        '$fixtures/satellite.targetTimes.original.json',
      ).readAsBytesSync();
      final pending = Completer<void>();
      var requests = 0;
      final server = await serve((r) async {
        requests++;
        if (requests == 1) await pending.future;
        await respond(r, raw);
      });
      addTearDown(() => server.close(force: true));
      final service = JmaSatelliteCloudService.forNativeTest(
        endpoint: endpoint(server),
        timeout: const Duration(milliseconds: 70),
      );
      service.start();
      await until(() => requests == 1);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final diagnostic = await service.nativeDiagnostics();
      expect(diagnostic['pending'], isFalse);
      expect(diagnostic['failures'], 1);
      expect(service.latestFrame, isNull);
      await service.fetchNow();
      expect(service.latestFrame, isNotNull);
      pending.complete();
      await service.dispose();
    },
    skip: !enabled,
  );

  test(
    'native startup retry and periodic refresh do not need a Dart timer',
    () async {
      final raw = File(
        '$fixtures/radar.targetTimes.original.json',
      ).readAsBytesSync();
      var requests = 0;
      final watch = Stopwatch()..start();
      final starts = <int>[];
      final server = await serve((r) async {
        starts.add(watch.elapsedMilliseconds);
        requests++;
        await respond(r, raw, status: requests == 1 ? 503 : 200);
      });
      addTearDown(() => server.close(force: true));
      final service = JmaRadarService.forNativeTest(endpoint: endpoint(server));
      service.start(interval: const Duration(hours: 1), startupAttempts: 2);
      await until(() => service.latestFrame != null);
      expect(requests, 2);
      expect(starts[1] - starts[0], greaterThanOrEqualTo(1900));
      expect((await service.nativeDiagnostics())['failures'], 1);
      service.stop(clear: true);
      await service.nativeDiagnostics();
      service.start(
        interval: const Duration(milliseconds: 100),
        startupAttempts: 1,
      );
      final at = requests;
      await until(() => requests >= at + 3);
      service.stop(clear: true);
      await service.nativeDiagnostics();
      final count = requests;
      await Future<void>.delayed(const Duration(milliseconds: 230));
      expect(requests, count);
      await service.dispose();
    },
    skip: !enabled,
  );
}
