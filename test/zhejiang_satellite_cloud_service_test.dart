import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:flutterrhythmquake/services/sources/fan_satellite_cloud_service.dart';
import 'package:image/image.dart' as image;

void main() {
  final png = image.encodePng(image.Image(width: 1, height: 1));
  final response = <String, dynamic>{
    'cloudname': 'data:image/png;base64,${base64Encode(png)}',
    'timeStr': '202609231500.png',
    'diffTime': 0,
    'minLat': -2,
    'maxLat': 43,
    'minLng': 95,
    'maxLng': 160,
  };

  test('uses Zhejiang cloud image and its published geographic bounds', () {
    final frame = FanSatelliteCloudService.parseZhejiangFrame(response)!;
    expect(frame.time, DateTime(2026, 9, 23, 15));
    expect(frame.southWest.latitude, -2);
    expect(frame.southWest.longitude, 95);
    expect(frame.northEast.latitude, 43);
    expect(frame.northEast.longitude, 160);
    expect(frame.imageBytes, png);

    final payload = ForegroundStationPayload.fanSatellite(frame);
    final restored = ForegroundStationPayload.decodeFanSatellite(payload)!;
    expect(restored.southWest, frame.southWest);
    expect(restored.northEast, frame.northEast);
    expect(restored.imageBytes, frame.imageBytes);
  });

  test('rejects stale, misplaced and non-image responses', () {
    expect(
      FanSatelliteCloudService.parseZhejiangFrame({
        ...response,
        'diffTime': 30000,
      }),
      isNull,
    );
    expect(
      FanSatelliteCloudService.parseZhejiangFrame({...response, 'minLng': 170}),
      isNull,
    );
    expect(
      FanSatelliteCloudService.parseZhejiangFrame({
        ...response,
        'cloudname': '202609231500.png',
      }),
      isNull,
    );
    expect(
      FanSatelliteCloudService.parseZhejiangFrame({
        ...response,
        'timeStr': '202613231500.png',
      }),
      isNull,
    );
  });
}
