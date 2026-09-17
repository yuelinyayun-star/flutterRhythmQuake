import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_station_service.dart';

void main() {
  test(
    'metadata burst publishes one complete snapshot with original stations',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.write('XX|BASE|30|105|0|Test|2020-01-01T00:00:00Z|');
        await request.response.close();
      });
      final service = FdsnStationService(
        endpoint: FdsnStationEndpoint(
          name: 'Test',
          stationUrl: 'http://127.0.0.1:${server.port}/query',
        ),
      );
      final emitted = <List<FdsnStation>>[];
      StreamSubscription<List<FdsnStation>>? sub;
      try {
        await service.start();
        final baseline = service.stations;
        final published = Completer<void>();
        sub = service.stationStream.listen((value) {
          emitted.add(value);
          if (!published.isCompleted) published.complete();
        });
        final original = [
          for (var i = 0; i < 5000; i++)
            FdsnStation(
              network: 'XX',
              station: 'BATCH$i',
              location: '',
              source: 'Test',
              coordinate: LatLng(30 + i % 10 * .01, 105),
            ),
        ];
        for (final station in original) {
          service.acceptChannelStation(station);
          service.acceptChannelStation(station);
        }
        await published.future.timeout(const Duration(seconds: 3));
        expect(emitted, hasLength(1));
        expect(emitted.single, hasLength(5001));
        expect(baseline, hasLength(1));
        for (var i = 0; i < original.length; i++) {
          expect(identical(emitted.single[i + 1], original[i]), isTrue);
        }
        service.acceptChannelStation(
          const FdsnStation(
            network: 'XX',
            station: 'STOP',
            location: '',
            source: 'Test',
            coordinate: LatLng(31, 105),
          ),
        );
        service.stop();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(emitted, hasLength(1));
        expect(service.stations, hasLength(5002));
        expect(emitted.single, hasLength(5001));
        await service.start();
        expect(service.stations, hasLength(5002));
      } finally {
        await sub?.cancel();
        service.dispose();
        await server.close(force: true);
      }
    },
  );
  test('stop cancels an in-flight FDSN station request', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestStarted = Completer<void>();
    final releaseResponse = Completer<void>();

    server.listen((request) async {
      if (!requestStarted.isCompleted) requestStarted.complete();
      await releaseResponse.future;
      request.response
        ..statusCode = HttpStatus.ok
        ..write('XX|TEST|Test Station|1.0|2.0|3.0|2026-01-01T00:00:00Z|');
      await request.response.close();
    });

    final service = FdsnStationService(
      endpoint: FdsnStationEndpoint(
        name: 'Test',
        stationUrl:
            'http://${server.address.address}:${server.port}/fdsnws/station/1/query',
      ),
    );

    final startFuture = service.start();
    await requestStarted.future.timeout(const Duration(seconds: 2));
    service.stop();

    await startFuture.timeout(const Duration(seconds: 2));
    expect(service.stations, isEmpty);

    releaseResponse.complete();
    service.dispose();
    await server.close(force: true);
  });
}
