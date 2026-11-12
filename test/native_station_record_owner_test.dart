import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/event_detection/event_detection_models.dart';
import 'package:flutterrhythmquake/core/nied_replay_logger.dart';
import 'package:flutterrhythmquake/core/source_estimation/native_station_record_owner.dart';
import 'package:flutterrhythmquake/core/source_estimation/seismic_source_tracker.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_event_tracker.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_observation_history.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_source_estimation_driver.dart';
import 'package:flutterrhythmquake/services/sources/shake_detection_service.dart';
import 'package:latlong2/latlong.dart';

import 'native_observation_history_test.dart' show bits, values;
import 'support/nied_replay_fixture.dart';

Object? timestamp(DateTime? time) =>
    time == null ? null : [time.microsecondsSinceEpoch, time.isUtc];
Object? interval(ObservationTimeInterval? time) =>
    time == null ? null : [timestamp(time.start), timestamp(time.end)];
Object? number(double? value) => value == null ? null : bits(value);
Object recordValues(SeismicStationEventRecord record) => [
  timestamp(record.firstObservedAt),
  timestamp(record.lastObservedAt),
  timestamp(record.peakAt),
  timestamp(record.endAt),
  interval(record.firstRiseInterval),
  interval(record.firstTriggerInterval),
  number(record.peakValue),
  number(record.lastValue),
  number(record.lastPga),
  number(record.lastPgv),
  number(record.lastPgd),
  record.lastRawLevel,
  record.lastDetectLevel,
  number(record.lastActivity),
  record.lastAscend,
  record.sampleCount,
  record.state.index,
  record.qualityFlags.toList(),
  {
    for (final e in record.provenance.entries)
      e.key.index: [
        e.value.origin.index,
        e.value.quantity.index,
        e.value.layerId,
        e.value.isIndependentPhysicalMeasurement,
        e.value.qualityFlags.toList(),
      ],
  },
  {
    for (final e in record.eventPhysicalPeaks.entries)
      e.key.index: [
        e.value.quantity.index,
        e.value.layerId,
        number(e.value.value),
        number(e.value.colorPosition),
        timestamp(e.value.dataTime),
        timestamp(e.value.receivedAt),
        e.value.qualityFlags.toList(),
      ],
  },
  values(record.observationHistory.latest),
  record.observationHistory.length,
];

class _RawSampleBridge implements StationEventTracker {
  final reference = SeismicSourceTracker();
  final native = SeismicSourceTracker()
    ..setObservationHistoryFactory('nied', StationObservationHistory.native)
    ..setNativeRecordProcessing('nied', true);
  int comparisons = 0;
  @override
  ValueNotifier<SeismicActiveEvent?> get currentNiedEvent =>
      reference.currentEventNotifier('nied');
  @override
  void ingestSamples({
    required String sourceId,
    required DateTime observedAt,
    required String stageName,
    required int maxShindo,
    required List<SeismicStationSample> samples,
    String? eventId,
    Map<String, Object?> metadata = const {},
  }) {
    for (final tracker in [reference, native]) {
      tracker.ingestFrame(
        sourceId: sourceId,
        observedAt: observedAt,
        stageName: stageName,
        maxShindo: maxShindo,
        samples: samples,
        eventId: eventId,
        metadata: metadata,
      );
    }
    final expected = reference.currentEvent(sourceId),
        actual = native.currentEvent(sourceId);
    expect(actual?.eventId, expected?.eventId);
    expect(actual?.stationRecords.keys, expected?.stationRecords.keys);
    if (expected != null) {
      for (final entry in expected.stationRecords.entries) {
        expect(
          recordValues(actual!.stationRecords[entry.key]!),
          recordValues(entry.value),
          reason: '${entry.key} $observedAt',
        );
        comparisons++;
      }
    }
  }

  void dispose() {
    reference.resetAll();
    native.resetAll();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'unaltered decoded GIF samples preserve all record fields through native event owner',
    () async {
      final directory = Directory('tmp/captures/20260610_180130_jst_nara_m36');
      if (!directory.existsSync()) {
        markTestSkipped('Original capture required');
        return;
      }
      final sessions = NativeStationRecordOwner.diagnostics['sessions'];
      final frames = NativeStationRecordOwner.diagnostics['frames']!;
      final bridge = _RawSampleBridge();
      final driver = NiedSourceEstimationDriver(stationEventTracker: bridge);
      final image = LmoniImageService()..start();
      final detector = ShakeDetectionService()..setSensitivity(2);
      try {
        for (var second = 20; second <= 70; second++) {
          final time = DateTime(2026, 6, 10, 18, 1, second);
          final file = File(
            '${directory.path}/${formatNiedTimeKey(time)}.lmoni.jma_s.gif',
          );
          final decoded = (await decodeNiedGifFile(file))!;
          final next = image.stationStream.firstWhere((v) => v != null);
          image.processPixels(
            decoded.packedRgb,
            surfaceGifBytes: decoded.gifBytes,
            dataTime: time,
            receivedAt: time,
          );
          final stations = (await next)!;
          detector.setStations(stations);
          detector.processUpdate();
          driver.processStations(stations, observedAt: time);
        }
        expect(bridge.comparisons, 65360);
        expect(NativeStationRecordOwner.diagnostics['frames']! - frames, 40);
        // ignore: avoid_print
        print(
          'Native station records: ${bridge.comparisons} complete field comparisons over original GIF samples',
        );
      } finally {
        driver.dispose();
        bridge.dispose();
        image.stop();
        detector.reset(detachStations: true);
        NiedReplayLogger.instance.resetForTest();
      }
      expect(NativeStationRecordOwner.diagnostics['sessions'], sessions);
    },
    skip: !NativeStationRecordOwner.supported,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'strict timing, missing frames and independent physical peaks keep original lifecycle',
    () {
      // Controlled contract boundaries; replay evidence is tested separately above.
      final bridge = _RawSampleBridge();
      final origin = DateTime.utc(2026, 10, 18);
      const descriptor = SeismicStationDescriptor(
        stationId: 'contract',
        code: 'contract',
        sourceId: 'nied',
        network: '',
        coordinate: LatLng(35, 135),
      );
      try {
        for (var index = 0; index < 8; index++) {
          final time = origin.add(Duration(seconds: index));
          final physical = SeismicPhysicalObservation(
            quantity: StationValueType.pga,
            layerId: 'pga',
            value: 10.0 + index,
            dataTime: time,
            receivedAt: time,
            qualityFlags: index == 6 ? const {'stale_observation'} : const {},
          );
          final sample = SeismicStationSample(
            descriptor: descriptor,
            observedAt: time,
            receivedAt: time,
            valueType: StationValueType.jmaShindo,
            value: index == 2 ? double.nan : index.toDouble(),
            rawLevel: index == 5 ? null : index,
            detectLevel: index == 5 ? null : 15,
            activity: index == 5 ? 0 : 1,
            ascend: index == 5 ? 0 : 1,
            isTriggered: index >= 2 && index < 5,
            firstRiseInterval: index == 1
                ? ObservationTimeInterval(start: origin.toLocal(), end: time)
                : null,
            firstTriggerInterval: index == 2
                ? ObservationTimeInterval(start: time, end: time.toLocal())
                : null,
            observedPga: physical.value,
            physicalObservations: {StationValueType.pga: physical},
            provenance: {
              StationValueType.pga: ObservationProvenance(
                origin: index == 3
                    ? ObservationOrigin.derived
                    : ObservationOrigin.niedGifLayer,
                quantity: StationValueType.pga,
                isIndependentPhysicalMeasurement: true,
                qualityFlags: index == 4
                    ? const {'derived_from_shindo'}
                    : const {},
              ),
            },
          );
          bridge.ingestSamples(
            sourceId: 'nied',
            observedAt: time,
            stageName: 'triggered',
            maxShindo: 1,
            samples: [sample],
            eventId: 'contract',
          );
        }
        bridge.ingestSamples(
          sourceId: 'nied',
          observedAt: origin.add(const Duration(seconds: 9)),
          stageName: 'idle',
          maxShindo: 0,
          samples: const [],
          eventId: 'contract',
        );
        expect(bridge.native.currentEvent('nied'), isNull);
      } finally {
        bridge.dispose();
      }
    },
    skip: !NativeStationRecordOwner.supported,
  );
}
