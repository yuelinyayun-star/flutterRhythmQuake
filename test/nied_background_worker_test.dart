import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;

import 'package:flutterrhythmquake/models/nied_scan_positions.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_background_worker.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_observation.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/shindo_color_util.dart';

void main() {
  test('background worker decodes and samples NIED image bytes', () async {
    final image = image_lib.Image(width: 352, height: 400);
    image.setPixelRgb(10, 20, 255, 0, 0);
    final bytes = Uint8List.fromList(image_lib.encodePng(image));

    final result = await NiedBackgroundWorker.instance.scanFrame(
      surfaceBytes: bytes,
      configs: const [NiedScanConfig(pixelX: 10, pixelY: 20)],
      configSignature: 'worker-scan-test',
    );

    expect(result, isNotNull);
    expect(result!.width, 352);
    expect(result.height, 400);
    expect(result.samples, hasLength(1));
    expect(
      result.samples.first.surfacePosition,
      closeTo(ShindoColorUtil.rgbaToPosition(255, 0, 0)!, 1e-9),
    );
  });

  test('background worker runs station chain detection', () async {
    final expire = await NiedBackgroundWorker.instance.configureDetector(
      signature: 'worker-detect-test',
      stations: const [
        [0, 35.0, 139.0, 'a'],
        [1, 35.05, 139.05, 'b'],
        [2, 35.1, 139.1, 'c'],
      ],
    );
    expect(expire, hasLength(3));
    expect(expire, everyElement(NiedStation.kaExpireSeconds));

    final result = await NiedBackgroundWorker.instance.detect(
      stations: const [
        NiedDetectionInput(
          kaLevel: 10,
          activity: 20,
          ascend: 3,
          isActive: false,
        ),
        NiedDetectionInput(
          kaLevel: 10,
          activity: 20,
          ascend: 3,
          isActive: false,
        ),
        NiedDetectionInput(
          kaLevel: 10,
          activity: 20,
          ascend: 3,
          isActive: false,
        ),
      ],
      sensitivity: 2,
      hadActiveGrid: false,
    );

    expect(result, isNotNull);
    expect(result!.activeIndices, containsAll(<int>[0, 1, 2]));
    expect(result.strongestIndex, isNotNull);
  });

  test(
    'background worker doubles threshold for abnormal station pair',
    () async {
      await NiedBackgroundWorker.instance.configureDetector(
        signature: 'worker-abnormal-pair-test',
        stations: const [
          [0, 35.0, 139.0, 'a'],
          [1, 35.05, 139.05, 'b'],
          [2, 35.1, 139.1, 'c'],
        ],
      );

      final result = await NiedBackgroundWorker.instance.detect(
        stations: const [
          NiedDetectionInput(
            kaLevel: 10,
            activity: 3,
            ascend: 3,
            isActive: false,
            triggerStamp: 100000,
          ),
          NiedDetectionInput(
            kaLevel: 10,
            activity: 3,
            ascend: 3,
            isActive: false,
            triggerStamp: 200000,
          ),
          NiedDetectionInput(
            kaLevel: 10,
            activity: 3,
            ascend: 3,
            isActive: false,
            triggerStamp: 100000,
          ),
        ],
        sensitivity: 2,
        hadActiveGrid: false,
      );

      expect(result, isNotNull);
      expect(result!.activeIndices, isEmpty);
    },
  );

  test('sampled GIF path reads surface for KiK stations by default', () async {
    final service = LmoniImageService()
      ..stop()
      ..start();
    addTearDown(service.stop);

    var mappedIndex = -1;
    var mappedCount = 0;
    for (final row in NiedStationDb.stations) {
      final code = row['code'] as String;
      if (!NiedScanPositions.positions.containsKey(code)) continue;
      final network = (row['network'] as String?) ?? 'K-NET';
      if (mappedIndex < 0 && network.toLowerCase().contains('kik')) {
        mappedIndex = mappedCount;
      }
      mappedCount++;
    }
    expect(mappedIndex, greaterThanOrEqualTo(0));

    final samples = List<NiedPixelSample>.filled(
      mappedCount,
      const NiedPixelSample(surfacePosition: null),
    );
    const surfacePosition = 0.4; // shindo 1.0
    samples[mappedIndex] = const NiedPixelSample(
      surfacePosition: surfacePosition,
    );

    final nextStations = service.stationStream.first;
    service.processSampledFrame(
      NiedFrameScanResult(width: 352, height: 400, samples: samples),
      surfaceGifBytes: Uint8List(0),
      dataTime: DateTime(2026, 6, 27, 2, 30),
    );

    final stations = await nextStations.timeout(const Duration(seconds: 2));
    final station = stations![mappedIndex];
    expect(station.gifLayerQualityFlags[NiedGifLayer.realtimeShindo], isNull);
    expect(station.gifObservation?.shindo, closeTo(1.0, 0.001));
    expect(station.level, greaterThanOrEqualTo(0));
  });

  test('GIF frame gap over 10 seconds only clears active state', () async {
    final service = LmoniImageService()
      ..stop()
      ..start();
    addTearDown(service.stop);

    final sampleInfo = _firstMappedStationSample();
    final nextStations = service.stationStream.first;
    service.processSampledFrame(
      NiedFrameScanResult(
        width: 352,
        height: 400,
        samples: _samplesWithValidSurface(sampleInfo.count, sampleInfo.index),
      ),
      surfaceGifBytes: Uint8List(0),
      dataTime: DateTime(2026, 6, 27, 2, 30),
    );

    final stations = await nextStations.timeout(const Duration(seconds: 2));
    final station = stations![sampleInfo.index]
      ..isActive = true
      ..activity = 12.5
      ..ascend = 4
      ..level = 10;

    service.applyFrameGapForTest(DateTime(2026, 6, 27, 2, 30, 11));

    expect(station.isActive, isFalse);
    expect(station.activity, 12.5);
    expect(station.ascend, 4);
    expect(station.level, 10);
  });

  test(
    'GIF service restart clears frame time for source switch reset',
    () async {
      final service = LmoniImageService()
        ..stop()
        ..start();
      addTearDown(service.stop);

      final sampleInfo = _firstMappedStationSample();
      final frameTime = DateTime(2026, 6, 27, 2, 31);
      final nextStations = service.stationStream.first;
      service.processSampledFrame(
        NiedFrameScanResult(
          width: 352,
          height: 400,
          samples: _samplesWithValidSurface(sampleInfo.count, sampleInfo.index),
        ),
        surfaceGifBytes: Uint8List(0),
        dataTime: frameTime,
      );
      await nextStations.timeout(const Duration(seconds: 2));
      expect(service.lastFrameTime, frameTime);

      service
        ..stop()
        ..start();

      expect(service.lastFrameTime, isNull);
    },
  );
}

({int index, int count}) _firstMappedStationSample() {
  var mappedIndex = -1;
  var mappedCount = 0;
  for (final row in NiedStationDb.stations) {
    final code = row['code'] as String;
    if (!NiedScanPositions.positions.containsKey(code)) continue;
    if (mappedIndex < 0) mappedIndex = mappedCount;
    mappedCount++;
  }
  expect(mappedIndex, greaterThanOrEqualTo(0));
  return (index: mappedIndex, count: mappedCount);
}

List<NiedPixelSample> _samplesWithValidSurface(int count, int validIndex) {
  final samples = List<NiedPixelSample>.filled(
    count,
    const NiedPixelSample(surfacePosition: null),
  );
  samples[validIndex] = const NiedPixelSample(surfacePosition: 0.4);
  return samples;
}
