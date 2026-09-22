import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:flutterrhythmquake/services/sources/nsmc_satellite_cloud_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

// Entries captured from the official NSMC list, in deliberately reversed order.
const entries = [
  {'dataDate': '20260922', 'dataTime': '050000', 'endTime': ''},
  {'dataDate': '20260922', 'dataTime': '040000', 'endTime': ''},
];
http.Response times() =>
    http.Response(jsonEncode({'returnCode': 0, 'ds': entries}), 200);

void main() {
  test('parses latest UTC observation and official WMS parameters', () {
    final time = nsmcSatelliteLatestTime({'returnCode': 0, 'ds': entries})!;
    expect(time, DateTime.utc(2026, 9, 22, 5));
    final uri = nsmcSatelliteImageUri(time);
    expect(uri.queryParameters['datetime'], '202609220500');
    expect(uri.queryParameters['layers'], 'GEOS_IRX');
    expect(uri.queryParameters['format'], 'png');
    expect(
      uri.queryParameters['bbox'],
      '-180,-85.0511287798066,180,85.0511287798066',
    );
  });

  test('ignores API errors and invalid dates', () {
    expect(nsmcSatelliteLatestTime({'returnCode': 1, 'ds': entries}), isNull);
    expect(
      nsmcSatelliteLatestTime({
        'returnCode': 0,
        'ds': [
          null,
          {},
          {'dataDate': '20260230', 'dataTime': '050000'},
          {'dataDate': '20260922', 'dataTime': '250000'},
        ],
      }),
      isNull,
    );
    expect(nsmcSatelliteLatestTime([]), isNull);
  });

  test('Mercator rows remain north-up and map equator to the center', () {
    expect(nsmcSatelliteSourceRow(0, 2048, 1024), 0);
    expect(nsmcSatelliteSourceRow(2047, 2048, 1024), 1023);
    expect(nsmcSatelliteSourceRow(1023, 2048, 1024), 511);
    expect(nsmcSatelliteSourceRow(1024, 2048, 1024), 512);
    var previous = -1;
    for (var y = 0; y < 2048; y++) {
      final row = nsmcSatelliteSourceRow(y, 2048, 1024);
      expect(row, greaterThanOrEqualTo(previous));
      previous = row;
    }
  });

  test('rejects non-image responses', () {
    expect(
      () => nsmcSatelliteToMercator(
        Uint8List.fromList(utf8.encode('<html>error</html>')),
      ),
      throwsFormatException,
    );
  });

  test('disabled service does not request data or images', () async {
    final service = NsmcSatelliteCloudService.forTest(
      client: MockClient((_) async {
        fail('disabled layer requested data');
      }),
    );
    await service.fetchNow();
    expect(service.isRunning, isFalse);
  });

  test('rejects blank PNG responses even when their dimensions match', () {
    final bytes = img.encodePng(
      img.Image(width: 2048, height: 1024, numChannels: 4),
    );
    expect(() => nsmcSatelliteToMercator(bytes), throwsFormatException);
  });

  test('restart processes a new request after discarding an old one', () async {
    final pending = Completer<http.Response>();
    final restarted = Completer<void>();
    var requests = 0;
    final service = NsmcSatelliteCloudService.forTest(
      client: MockClient((_) {
        requests++;
        if (requests == 1) return pending.future;
        restarted.complete();
        return Future.value(http.Response('', 503));
      }),
    );
    addTearDown(() => service.stop(clear: true));
    service.start();
    await Future<void>.delayed(Duration.zero);
    service.stop(clear: true);
    service.start();
    pending.complete(times());
    await restarted.future.timeout(const Duration(seconds: 2));
    expect(requests, 2);
    expect(service.latestFrame, isNull);
  });

  test('stop during time request prevents the image request', () async {
    final pending = Completer<http.Response>();
    var requests = 0;
    final service = NsmcSatelliteCloudService.forTest(
      client: MockClient((_) {
        requests++;
        return pending.future;
      }),
    );
    service.start();
    await Future<void>.delayed(Duration.zero);
    service.stop(clear: true);
    pending.complete(times());
    await Future<void>.delayed(Duration.zero);
    expect(requests, 1);
    expect(service.latestFrame, isNull);
  });

  final sourcePath = Platform.environment['NSMC_CLOUD_TEST_IMAGE'];
  test(
    'captured official image preserves alpha, projection and Android payload',
    () async {
      final originalBytes = await File(sourcePath!).readAsBytes();
      final source = img.decodePng(originalBytes)!;
      final projectedBytes = nsmcSatelliteToMercator(originalBytes);
      final projected = img.decodePng(projectedBytes)!;
      expect(projected.width, 2048);
      expect(projected.height, 2048);
      final alphas = <num>{};
      for (var y = 0; y < 2048; y += 31) {
        final row = nsmcSatelliteSourceRow(y, 2048, source.height);
        for (var x = 0; x < 2048; x += 31) {
          final actual = projected.getPixel(x, y);
          final expected = source.getPixel(x, row);
          expect(
            [actual.r, actual.g, actual.b, actual.a],
            [expected.r, expected.g, expected.b, expected.a],
          );
          alphas.add(actual.a);
        }
      }
      expect(alphas.length, greaterThan(20));
      final frame = NsmcSatelliteCloudFrame(
        time: DateTime.utc(2026, 9, 22, 5),
        imageBytes: projectedBytes,
      );
      final payload = ForegroundStationPayload.nsmcSatelliteCloud(frame);
      final decoded = ForegroundStationPayload.decodeNsmcSatelliteCloud(
        payload,
      )!;
      expect(decoded.time, frame.time);
      expect(decoded.imageBytes, projectedBytes);
      final output = Directory('build/satellite-cloud-qa')
        ..createSync(recursive: true);
      await File(
        '${output.path}/nsmc-mercator.png',
      ).writeAsBytes(projectedBytes);

      var requests = 0;
      final service = NsmcSatelliteCloudService.forTest(
        client: MockClient((request) async {
          requests++;
          return request.url.toString() ==
                  NsmcSatelliteCloudService.targetTimesUrl
              ? times()
              : http.Response.bytes(originalBytes, 200);
        }),
      );
      addTearDown(() => service.stop(clear: true));
      final received = service.frameStream.first;
      service.start();
      final value = await received.timeout(const Duration(seconds: 30));
      expect(value!.imageBytes, projectedBytes);
      await service.fetchNow();
      expect(
        requests,
        3,
      ); // Same time checks the list but does not download again.
    },
    skip: sourcePath == null,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
