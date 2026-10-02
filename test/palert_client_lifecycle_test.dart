import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flutterrhythmquake/services/sources/palert_service.dart';

class _TrackingClient extends http.BaseClient {
  bool closed = false;
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    throw StateError('Unexpected network request during initialization test');
  }

  @override
  void close() => closed = true;
}

void main() {
  test(
    'Closes a client that finishes loading after the source was stopped',
    () async {
      final pending = Completer<http.Client>();
      final client = _TrackingClient();
      final service = PAlertService.forTesting(
        clientFactory: () => pending.future,
      );
      addTearDown(service.stop);
      service.start();
      service.stop();
      pending.complete(client);
      await Future<void>.delayed(Duration.zero);
      expect(client.closed, isTrue);
      expect(client.requests, 0);
      expect(service.isRunning, isFalse);
      expect(service.dataTimeNotifier.value, isNull);
    },
  );

  test(
    'An old initialization cannot replace the restarted source client',
    () async {
      final first = Completer<http.Client>();
      final second = Completer<http.Client>();
      final oldClient = _TrackingClient();
      final currentClient = _TrackingClient();
      var calls = 0;
      final service = PAlertService.forTesting(
        clientFactory: () => calls++ == 0 ? first.future : second.future,
      );
      addTearDown(service.stop);
      service.start();
      service.stop();
      service.start();
      second.complete(currentClient);
      await Future<void>.delayed(Duration.zero);
      expect(currentClient.requests, greaterThan(0));
      first.complete(oldClient);
      await Future<void>.delayed(Duration.zero);
      expect(oldClient.closed, isTrue);
      expect(oldClient.requests, 0);
      expect(service.isRunning, isTrue);
      expect(currentClient.closed, isFalse);
      service.stop();
      expect(currentClient.closed, isTrue);
    },
  );

  test(
    'Initialization failure reports disconnected without fetching data',
    () async {
      final service = PAlertService.forTesting(
        clientFactory: () async =>
            throw StateError('Certificate asset unavailable'),
      );
      addTearDown(service.stop);
      final statuses = <bool>[];
      service.onStatusChanged = statuses.add;
      service.start();
      await Future<void>.delayed(Duration.zero);
      expect(statuses, [false]);
      expect(service.stations, isEmpty);
      expect(service.dataTimeNotifier.value, isNull);
    },
  );
}
