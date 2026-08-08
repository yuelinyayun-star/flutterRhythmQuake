import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_station_service.dart';

void main() {
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
