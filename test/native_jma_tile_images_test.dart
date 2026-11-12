import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/native_jma_tile_owner.dart';
import 'package:flutterrhythmquake/services/sources/jma_radar_service.dart';
import 'package:flutterrhythmquake/services/sources/jma_satellite_cloud_service.dart';
import 'package:flutterrhythmquake/widgets/map/native_jma_tile_provider.dart';
import 'native_jma_tile_runtime_test.dart'
    show serve, respond, endpoint, until, fixtures;

Map<String, dynamic> tileFixture(bool satellite) =>
    (jsonDecode(File('$fixtures/tiles.manifest.json').readAsStringSync())
            as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((e) => e['kind'] == (satellite ? 'satellite' : 'radar'));
void main() {
  final enabled = NativeJmaTileOwner.supported;
  for (final satellite in [false, true]) {
    test(
      'native ${satellite ? 'satellite' : 'radar'} service returns original image bytes and releases request bodies',
      () async {
        final spec = tileFixture(satellite),
            bytes = File(
              '$fixtures/${tileFixture(satellite)['file']}',
            ).readAsBytesSync();
        final index = File(
          '$fixtures/${satellite ? 'satellite' : 'radar'}.targetTimes.original.json',
        ).readAsBytesSync();
        final server = await serve(
          (r) => respond(r, r.uri.path == spec['path'] ? bytes : index),
        );
        addTearDown(() => server.close(force: true));
        final cancel = Completer<void>();
        if (satellite) {
          final service = JmaSatelliteCloudService.forNativeTest(
            endpoint: endpoint(server),
          );
          service.start();
          await until(() => service.latestFrame != null);
          final result = await service.loadNativeTile(
            Uri.parse('https://www.jma.go.jp${spec['path']}'),
            cancel.future,
          );
          expect(sha256.convert(result!).toString(), spec['sha256']);
          final diagnostics = await service.nativeDiagnostics();
          expect(diagnostics['imagesPending'], 0);
          expect(diagnostics['imageBytes'], 0);
          expect(diagnostics['imagesCompleted'], 1);
          cancel.complete();
          await service.dispose();
        } else {
          final service = JmaRadarService.forNativeTest(
            endpoint: endpoint(server),
          );
          service.start(startupAttempts: 1);
          await until(() => service.latestFrame != null);
          final result = await service.loadNativeTile(
            Uri.parse('https://www.jma.go.jp${spec['path']}'),
            cancel.future,
          );
          expect(sha256.convert(result!).toString(), spec['sha256']);
          final diagnostics = await service.nativeDiagnostics();
          expect(diagnostics['imagesPending'], 0);
          expect(diagnostics['imageBytes'], 0);
          expect(diagnostics['imagesCompleted'], 1);
          cancel.complete();
          await service.dispose();
        }
      },
      skip: !enabled,
    );
  }

  test(
    'native image concurrency is eight; cancellation clears active and queued work',
    () async {
      final spec = tileFixture(false),
          bytes = File(
            '$fixtures/${tileFixture(false)['file']}',
          ).readAsBytesSync();
      final index = File(
        '$fixtures/radar.targetTimes.original.json',
      ).readAsBytesSync();
      final gate = Completer<void>();
      var images = 0;
      final server = await serve((r) async {
        if (r.uri.path == spec['path']) {
          images++;
          await gate.future;
          await respond(r, bytes);
        } else {
          await respond(r, index);
        }
      });
      addTearDown(() => server.close(force: true));
      Map<String, dynamic>? frame;
      final owner = NativeJmaTileOwner(
        satellite: false,
        onFrame: (value) => frame = value,
      );
      owner.start(
        interval: const Duration(hours: 1),
        testEndpoint: endpoint(server),
      );
      await until(() => frame != null);
      final cancels = [for (var i = 0; i < 12; i++) Completer<void>()];
      final results = [
        for (final cancel in cancels) owner.tile(spec['path'], cancel.future),
      ];
      await until(() => images == 8);
      expect((await owner.diagnostics())['imagesActive'], 8);
      for (final i in [0, 1, 11]) {
        cancels[i].complete();
      }
      for (final i in [0, 1, 11]) {
        expect(await results[i], isNull);
      }
      expect((await owner.diagnostics())['imagesActive'], lessThanOrEqualTo(8));
      gate.complete();
      final all = await Future.wait(results);
      expect(all.where((e) => e != null), hasLength(9));
      for (final value in all.whereType<List<int>>()) {
        expect(sha256.convert(value).toString(), spec['sha256']);
      }
      final diag = await owner.diagnostics();
      expect(diag['imagesPending'], 0);
      expect(diag['imageBytes'], 0);
      expect(diag['imagesCancelled'], 3);
      for (final cancel in cancels) {
        if (!cancel.isCompleted) cancel.complete();
      }
      owner.dispose();
    },
    skip: !enabled,
  );

  test(
    'native image HTTP retry delays and terminal HTTP errors preserve policy',
    () async {
      final spec = tileFixture(false),
          bytes = File(
            '$fixtures/${tileFixture(false)['file']}',
          ).readAsBytesSync();
      final index = File(
        '$fixtures/radar.targetTimes.original.json',
      ).readAsBytesSync();
      final watch = Stopwatch()..start();
      final times = <int>[];
      var status = 503;
      final server = await serve((r) async {
        if (r.uri.path == spec['path']) {
          times.add(watch.elapsedMilliseconds);
          await respond(r, bytes, status: times.length <= 2 ? status : 200);
        } else {
          await respond(r, index);
        }
      });
      addTearDown(() => server.close(force: true));
      Map<String, dynamic>? frame;
      final owner = NativeJmaTileOwner(
        satellite: false,
        onFrame: (value) => frame = value,
      );
      owner.start(
        interval: const Duration(hours: 1),
        testEndpoint: endpoint(server),
      );
      await until(() => frame != null);
      final cancel = Completer<void>();
      final result = await owner.tile(spec['path'], cancel.future);
      expect(sha256.convert(result!).toString(), spec['sha256']);
      expect(times, hasLength(3));
      expect(times[1] - times[0], greaterThanOrEqualTo(450));
      expect(times[2] - times[1], greaterThanOrEqualTo(950));
      times.clear();
      status = 404;
      await expectLater(
        owner.tile(spec['path'], cancel.future),
        throwsStateError,
      );
      expect(times, hasLength(1));
      cancel.complete();
      owner.dispose();
    },
    skip: !enabled,
  );

  testWidgets(
    'original JMA PNG reaches Flutter codec and shared tile cancellation',
    (tester) async {
      final spec = tileFixture(false),
          bytes = File(
            '$fixtures/${tileFixture(false)['file']}',
          ).readAsBytesSync();
      final index = File(
        '$fixtures/radar.targetTimes.original.json',
      ).readAsBytesSync();
      late HttpServer server;
      late JmaRadarService service;
      late NativeJmaTileProvider provider;
      var imageRequests = 0;
      await tester.runAsync(() async {
        server = await serve((r) async {
          if (r.uri.path == spec['path']) {
            imageRequests++;
            await respond(r, bytes);
          } else {
            await respond(r, index);
          }
        });
        service = JmaRadarService.forNativeTest(endpoint: endpoint(server));
        service.start(startupAttempts: 1);
        await until(() => service.latestFrame != null);
        provider = NativeJmaTileProvider(service.loadNativeTile);
      });
      final a = Completer<void>(), b = Completer<void>();
      final options = TileLayer(
        urlTemplate: 'https://www.jma.go.jp${spec['path']}',
      );
      const coords = TileCoordinates(56, 25, 6);
      final first = provider.getImageWithCancelLoadingSupport(
        coords,
        options,
        a.future,
      );
      final second = provider.getImageWithCancelLoadingSupport(
        coords,
        options,
        b.future,
      );
      expect(identical(first, second), isTrue);
      late ImageInfo info;
      await tester.runAsync(() async {
        final loaded = Completer<ImageInfo>();
        final stream = first.resolve(ImageConfiguration.empty);
        final listener = ImageStreamListener(
          (image, synchronousCall) => loaded.complete(image),
          onError: (Object e, StackTrace? s) => loaded.completeError(e, s),
        );
        stream.addListener(listener);
        info = await loaded.future.timeout(const Duration(seconds: 5));
        stream.removeListener(listener);
      });
      expect(imageRequests, 1);
      expect(info.image.width, 256);
      expect(info.image.height, 256);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RawImage(image: info.image),
        ),
      );
      expect(find.byType(RawImage), findsOneWidget);
      expect(tester.takeException(), isNull);
      a.complete();
      await tester.pump();
      b.complete();
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      info.dispose();
      await tester.runAsync(() async {
        await service.dispose();
        await server.close(force: true);
      });
    },
    skip: !enabled,
  );
}
