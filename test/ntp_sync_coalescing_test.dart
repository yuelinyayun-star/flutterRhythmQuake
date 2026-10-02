import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutterrhythmquake/services/ntp_service.dart';

void main() {
  test(
    'concurrent synchronization callers wait for the same completed request',
    () async {
      final reply = Completer<http.Response>();
      var requests = 0;
      await http.runWithClient(
        () async {
          final service = NtpService();
          final first = service.syncTime();
          var secondDone = false;
          final second = service.syncTime();
          expect(identical(first, second), isTrue);
          final completion = second.then((_) => secondDone = true);
          await Future<void>.delayed(Duration.zero);
          expect(secondDone, isFalse);
          expect(requests, 1);
          // Controlled clock transport response, not an earthquake observation.
          reply.complete(
            http.Response(
              jsonEncode({
                'unixtime_ms': DateTime.now().millisecondsSinceEpoch,
              }),
              200,
            ),
          );
          await Future.wait([first, second, completion]);
          expect(secondDone, isTrue);
          expect(service.lastSyncedAt, isNotNull);
          expect(service.isSynced, isTrue);
          await service.syncTime();
          expect(requests, 2);
        },
        () => MockClient((request) {
          requests++;
          return reply.future;
        }),
      );
    },
  );
}
