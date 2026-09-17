import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_channel_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const rows =
      'XX|AAA||BHZ|30|105|2|0|0|-90|test|1000|1|M/S|20|2020-01-01T00:00:00|2026-01-01T00:00:00|\n'
      'XX|AAA||BHZ|31|106|3|0|0|-90|test|2000|1|M/S|20|2026-01-01T00:00:00||\n'
      'XX|AAA|00|BHZ|32|107|4|0|0|-90|test|3000|1|M/S|20|2020-01-01T00:00:00||\n'
      'YY|AAA||BHZ|33|108|5|0|0|-90|test|4000|1|M/S|20|2020-01-01T00:00:00||';
  test(
    'bulk metadata matches original NSLC and epoch without location guessing',
    () async {
      var calls = 0;
      final catalog = FdsnChannelCatalog(
        MockClient((request) async {
          calls++;
          expect(request.url.queryParameters['network'], 'XX');
          expect(request.url.queryParameters.containsKey('station'), isFalse);
          return http.Response(rows, 200);
        }),
      );
      addTearDown(catalog.dispose);
      final results = await Future.wait([
        catalog.find(
          source: 'EarthScope',
          network: 'XX',
          station: 'AAA',
          location: '',
          channel: 'BHZ',
          time: DateTime.utc(2025),
        ),
        catalog.find(
          source: 'EarthScope',
          network: 'XX',
          station: 'AAA',
          location: '',
          channel: 'BHZ',
          time: DateTime.utc(2026),
        ),
        catalog.find(
          source: 'EarthScope',
          network: 'XX',
          station: 'AAA',
          location: '00',
          channel: 'BHZ',
          time: DateTime.utc(2026),
        ),
        catalog.find(
          source: 'EarthScope',
          network: 'XX',
          station: 'AAA',
          location: '10',
          channel: 'BHZ',
          time: DateTime.utc(2026),
        ),
      ]);
      expect(calls, 1);
      expect(results.map((r) => r?.sensitivity), [1000, 2000, 3000, null]);
      expect(results.map((r) => r?.latitude), [30, 31, 32, null]);
    },
  );

  test(
    'metadata network concurrency stays bounded and stop releases queued work',
    () async {
      final gate = Completer<void>();
      var calls = 0;
      final catalog = FdsnChannelCatalog(
        MockClient((request) async {
          calls++;
          await gate.future;
          return http.Response('', 204);
        }),
      );
      final loads = [
        for (var i = 0; i < 20; i++) catalog.load('EarthScope', '$i'),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, 4);
      catalog.dispose();
      gate.complete();
      expect((await Future.wait(loads)).every((r) => r.isEmpty), isTrue);
      expect(calls, 4);
    },
  );
}
