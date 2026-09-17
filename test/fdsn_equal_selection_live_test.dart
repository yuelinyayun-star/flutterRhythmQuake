import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_motion_service_io.dart';

void main() {
  test(
    'opt-in frozen full selection through production receiver',
    () async {
      const input = String.fromEnvironment('FDSN_EQUAL_INPUT');
      const output = String.fromEnvironment('FDSN_EQUAL_OUTPUT');
      final spec = jsonDecode(File(input).readAsStringSync()) as Map;
      final selections = spec['selected'] as List;
      final service = FdsnMotionService.forTesting(
        streams: [
          for (final row in selections)
            FdsnSeedLinkStream(
              source: 'EarthScope',
              host: 'rtserve.earthscope.org',
              port: 18500,
              secure: true,
              network: row[0] as String,
              station: row[1] as String,
              selector: row[2] as String,
            ),
        ],
      );
      final started = DateTime.now().toUtc();
      final history = <Map<String, Object?>>[];
      final seen = <String>{};
      final subscription = service.sampleStream.listen((s) => seen.add(s.code));
      var reason = 'observation-deadline';
      try {
      service.connectProvidedStreamsForTesting();
        for (var i = 0; i < 2400; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          final connections = service.connectionDiagnostics
              .map(
                (c) => {
                  ...c,
                  'decodeRejected': (c['decodeRejected'] as Map<int, int>).map(
                    (key, value) => MapEntry('$key', value),
                  ),
                },
              )
              .toList();
          final closed = connections.any((c) => c['lastCloseReason'] != '');
          if (i % 60 == 0 || closed) {
            final row = <String, Object?>{
              'at': DateTime.now().toUtc().toIso8601String(),
              'seconds':
                  DateTime.now().toUtc().difference(started).inMilliseconds /
                  1000,
              'seen': seen.length,
              'connections': connections,
            };
            history.add(row);
            // ignore: avoid_print
            print(jsonEncode(row));
          }
          if (closed) {
            reason = 'connection-closed';
            break;
          }
        }
        File(output).writeAsStringSync(
          jsonEncode({
            'startedAt': started.toIso8601String(),
            'finishedAt': DateTime.now().toUtc().toIso8601String(),
            'selected': selections.length,
            'reason': reason,
            'history': history,
          }),
        );
      } finally {
        service.disconnect();
        await subscription.cancel();
      }
    },
    skip: !const bool.fromEnvironment('FDSN_EQUAL_LIVE'),
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
