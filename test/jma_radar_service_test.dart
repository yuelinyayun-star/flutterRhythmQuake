import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/jma_radar_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('refreshes JMA radar every five minutes', () {
    expect(JmaRadarService.refreshInterval, const Duration(minutes: 5));
  });

  test('parses the latest high-resolution precipitation nowcast time', () {
    final frame = jmaRadarFrameFromTargetTimes(_targetTimes());

    expect(frame, isNotNull);
    expect(frame!.basetime, '20260814160500');
    expect(frame.validtime, '20260814160500');
    expect(frame.time, DateTime(2026, 8, 14, 16, 5));
    expect(
      frame.tileUrlTemplate,
      'https://www.jma.go.jp/bosai/jmatile/data/nowc/'
      '20260814160500/none/20260814160500/surf/hrpns/{z}/{x}/{y}.png',
    );
  });

  test('skips target times that do not include hrpns', () {
    final frame = jmaRadarFrameFromTargetTimes([
      {
        'basetime': '20260814161000',
        'validtime': '20260814161000',
        'elements': ['liden'],
      },
      {
        'basetime': '20260814160500',
        'validtime': '20260814160500',
        'elements': ['hrpns', 'hrpns_nd'],
      },
    ]);

    expect(frame, isNotNull);
    expect(frame!.validtime, '20260814160500');
  });

  test('uses even native zooms because odd JMA tiles are empty', () {
    expect(jmaRadarNativeZoom(3.2), 4);
    expect(jmaRadarNativeZoom(4), 4);
    expect(jmaRadarNativeZoom(5.4), 4);
    expect(jmaRadarNativeZoom(6), 6);
    expect(jmaRadarNativeZoom(7.2), 6);
    expect(jmaRadarNativeZoom(8.4), 8);
    expect(jmaRadarNativeZoom(9.4), 8);
    expect(jmaRadarNativeZoom(10), 10);
    expect(jmaRadarNativeZoom(14), 10);
    expect(jmaRadarNativeZoom(18), 10);
  });

  test('parses a compact JST timestamp', () {
    expect(
      jmaRadarTimeFromStamp('20260814160500'),
      DateTime(2026, 8, 14, 16, 5),
    );
    expect(jmaRadarTimeFromStamp('bad'), isNull);
  });

  test('fetches the latest radar frame from targetTimes_N1.json', () async {
    final service = JmaRadarService.forTest(
      client: MockClient((request) async {
        expect(request.url.toString(), JmaRadarService.targetTimesUrl);
        return http.Response(
          jsonEncode(_targetTimes()),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final frameFuture = service.frameStream.first;
    service.start();
    final frame = await frameFuture.timeout(const Duration(seconds: 2));
    expect(frame, isNotNull);
    expect(frame!.validtime, '20260814160500');
    expect(service.latestFrame?.validtime, '20260814160500');
    service.stop(clear: true);
    expect(service.latestFrame, isNull);
  });
}

List<Map<String, dynamic>> _targetTimes() => [
  {
    'basetime': '20260814160500',
    'validtime': '20260814160500',
    'elements': ['hrpns', 'hrpns_nd'],
  },
  {
    'basetime': '20260814160000',
    'validtime': '20260814160000',
    'elements': ['hrpns', 'hrpns_nd'],
  },
];
