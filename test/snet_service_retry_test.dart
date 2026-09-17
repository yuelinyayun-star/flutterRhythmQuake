import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/snet_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const times = '[{"basetime":"20260907120000","validtime":"20260907120000"}]';
  final tile = img.encodePng(
    img.Image(width: 256, height: 256, numChannels: 4)
      ..clear(img.ColorRgba8(0, 255, 0, 255)),
  );

  test(
    'failed and partial tile downloads retry the same frame before committing',
    () async {
      var fail = true;
      var downloads = 0;
      var frames = 0;
      final service = SnetService.forTesting(
        client: MockClient((request) async {
          if (request.url.path.endsWith('targetTimes.json')) {
            return http.Response(times, 200);
          }
          downloads++;
          if (fail && request.url.path.endsWith('/12.png')) {
            return http.Response('', 503);
          }
          return http.Response.bytes(tile, 200);
        }),
      );
      service.onDataUpdated = (_) => frames++;
      await service.fetchLatestData();
      expect(frames, 0);
      fail = false;
      await service.fetchLatestData();
      expect(frames, 1);
      expect(downloads, 4);
      await service.fetchLatestData();
      expect(downloads, 4);
      service.dispose();
    },
  );

  test(
    'overlapping requests share work and stopped startup cannot rearm timer',
    () async {
      final target = Completer<http.Response>();
      var requests = 0;
      var frames = 0;
      final service = SnetService.forTesting(
        client: MockClient((_) {
          requests++;
          return target.future;
        }),
      );
      service.onDataUpdated = (_) => frames++;
      final start = service.startMonitoring(intervalSeconds: 1);
      final second = service.fetchLatestData();
      await Future<void>.delayed(Duration.zero);
      expect(requests, 1);
      service.stopMonitoring();
      target.complete(http.Response(times, 200));
      await start;
      await second;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(requests, 1);
      expect(frames, 0);
      expect(service.isMonitoring, isFalse);
      service.dispose();
    },
  );
}
