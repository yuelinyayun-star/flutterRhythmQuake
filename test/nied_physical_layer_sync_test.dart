import 'package:flutter_test/flutter_test.dart';

import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_observation.dart';

void main() {
  test('physical layer sampling stays separate from realtime shindo', () async {
    final service = LmoniImageService();
    service
      ..stop()
      ..start();
    final configs = service.backgroundScanConfigs;
    final surfaceIndex = configs.isEmpty ? -1 : 0;
    expect(surfaceIndex, greaterThanOrEqualTo(0));
    final config = configs[surfaceIndex];
    final pixels = List<int>.filled(352 * 400, 0);
    pixels[config.pixelY * 352 + config.pixelX] = 0xff0000;
    final receivedAt = DateTime.utc(2026, 6, 21, 7, 33, 18, 250);
    final future = service.stationStream.first;

    service.processPhysicalLayerPixels(
      layer: NiedGifLayer.peakAcceleration,
      dataTime: DateTime.utc(2026, 6, 21, 7, 33, 18),
      receivedAt: receivedAt,
      surfacePackedRgb: pixels,
    );
    service.publishStations();

    final stations = await future.timeout(const Duration(seconds: 2));
    final station = stations![surfaceIndex];
    expect(station.gifObservation, isNull);
    expect(station.pgaObservation?.pga, isNotNull);
    expect(station.pgvObservation, isNull);
    expect(station.lastReceivedAt, receivedAt);
    service.stop();
  });

  test('missing selected sensor layer clears stale physical value', () async {
    final service = LmoniImageService();
    service
      ..stop()
      ..start();
    final configs = service.backgroundScanConfigs;
    final surfaceIndex = configs.isEmpty ? -1 : 0;
    final config = configs[surfaceIndex];
    final pixels = List<int>.filled(352 * 400, 0);
    pixels[config.pixelY * 352 + config.pixelX] = 0xff0000;
    final time = DateTime.utc(2026, 6, 21, 7, 33, 18);

    service.processPhysicalLayerPixels(
      layer: NiedGifLayer.peakVelocity,
      dataTime: time,
      receivedAt: time,
      surfacePackedRgb: pixels,
    );
    service.processPhysicalLayerPixels(
      layer: NiedGifLayer.peakVelocity,
      dataTime: time.add(const Duration(seconds: 1)),
      receivedAt: time.add(const Duration(seconds: 1)),
    );
    final future = service.stationStream.first;
    service.publishStations();

    final station = (await future.timeout(
      const Duration(seconds: 2),
    ))![surfaceIndex];
    expect(station.pgvObservation, isNull);
    expect(
      station.gifLayerQualityFlags[NiedGifLayer.peakVelocity],
      contains('layer_missing'),
    );
    service.stop();
  });
}
