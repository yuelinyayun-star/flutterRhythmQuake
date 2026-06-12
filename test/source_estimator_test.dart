import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimator.dart';

void main() {
  test('trigger time grid estimator converges near synthetic epicenter', () {
    const estimator = TriggerTimeGridSearchEstimator();
    const epicenter = LatLng(35.50, 140.50);
    final origin = DateTime(2026, 6, 10, 12, 0, 0);
    final distance = const Distance();
    const speedKmps = 3.8;

    SeismicStationEventRecord buildRecord(
      String code,
      double lat,
      double lng,
      double shindo,
    ) {
      final station = LatLng(lat, lng);
      final distanceKm = distance.as(LengthUnit.Kilometer, epicenter, station);
      final triggerAt = origin.add(
        Duration(milliseconds: (distanceKm / speedKmps * 1000).round()),
      );
      return SeismicStationEventRecord(
        descriptor: SeismicStationDescriptor(
          stationId: code,
          code: code,
          sourceId: 'nied',
          network: 'K-NET',
          coordinate: station,
        ),
        firstObservedAt: triggerAt,
        firstRiseAt: triggerAt,
        firstTriggerAt: triggerAt,
        lastObservedAt: triggerAt,
        peakAt: triggerAt,
        peakValue: shindo,
        lastValue: shindo,
        state: StationLifecycleState.triggered,
      );
    }

    final request = SourceEstimationRequest(
      sourceId: 'nied',
      eventId: 'synthetic-1',
      observedAt: origin.add(const Duration(seconds: 5)),
      stageName: 'detected',
      maxShindo: 2,
      stations: [
        buildRecord('A', 35.30, 140.30, 0.6),
        buildRecord('B', 35.75, 140.35, 0.4),
        buildRecord('C', 35.42, 140.84, 0.5),
        buildRecord('D', 35.68, 140.72, 0.3),
      ],
    );

    final result = estimator.estimate(request);
    expect(result, isNotNull);
    expect((result!.latitude - epicenter.latitude).abs(), lessThan(0.18));
    expect((result.longitude - epicenter.longitude).abs(), lessThan(0.18));
    expect(result.method, 'trigger_time_grid_v2');
  });

  test('trigger time grid estimator falls back when timing data is sparse', () {
    const estimator = TriggerTimeGridSearchEstimator(
      fallback: WeightedCentroidSourceEstimator(),
    );
    final now = DateTime(2026, 6, 10, 12, 0, 0);
    final records = [
      SeismicStationEventRecord(
        descriptor: const SeismicStationDescriptor(
          stationId: 'A',
          code: 'A',
          sourceId: 'nied',
          network: 'K-NET',
          coordinate: LatLng(35.0, 140.0),
        ),
        firstObservedAt: now,
        lastObservedAt: now,
        peakValue: 0.4,
        lastValue: 0.4,
        state: StationLifecycleState.triggered,
      ),
      SeismicStationEventRecord(
        descriptor: const SeismicStationDescriptor(
          stationId: 'B',
          code: 'B',
          sourceId: 'nied',
          network: 'K-NET',
          coordinate: LatLng(35.2, 140.2),
        ),
        firstObservedAt: now,
        lastObservedAt: now,
        peakValue: 0.6,
        lastValue: 0.6,
        state: StationLifecycleState.triggered,
      ),
    ];
    final request = SourceEstimationRequest(
      sourceId: 'nied',
      eventId: 'synthetic-2',
      observedAt: now,
      stageName: 'detected',
      maxShindo: 1,
      stations: records,
    );

    final result = estimator.estimate(request);
    expect(result, isNotNull);
    expect(result!.method, 'weighted_centroid_baseline');
  });

  test(
    'trigger time depth grid estimator recovers a shallow synthetic depth',
    () {
      const estimator = TriggerTimeDepthGridSearchEstimator(
        depthCandidatesKm: [0, 10, 20, 30, 40, 60],
        coarseStepDeg: 0.15,
        fineStepDeg: 0.05,
        refineStepDeg: 0.02,
      );
      const epicenter = LatLng(36.20, 141.10);
      const depthKm = 30.0;
      const speedKmps = 4.0;
      final origin = DateTime(2026, 6, 10, 13, 0, 0);
      final distance = const Distance();

      SeismicStationEventRecord buildRecord(
        String code,
        double lat,
        double lng,
        double shindo,
      ) {
        final station = LatLng(lat, lng);
        final surfaceDistanceKm = distance.as(
          LengthUnit.Kilometer,
          epicenter,
          station,
        );
        final travelDistanceKm = math.sqrt(
          surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
        );
        final triggerAt = origin.add(
          Duration(milliseconds: (travelDistanceKm / speedKmps * 1000).round()),
        );
        return SeismicStationEventRecord(
          descriptor: SeismicStationDescriptor(
            stationId: code,
            code: code,
            sourceId: 'global',
            network: 'TEST',
            coordinate: station,
          ),
          firstObservedAt: triggerAt,
          firstRiseAt: triggerAt,
          firstTriggerAt: triggerAt,
          lastObservedAt: triggerAt,
          peakAt: triggerAt,
          peakValue: shindo,
          lastValue: shindo,
          state: StationLifecycleState.triggered,
        );
      }

      final request = SourceEstimationRequest(
        sourceId: 'global',
        eventId: 'synthetic-3',
        observedAt: origin.add(const Duration(seconds: 10)),
        stageName: 'detected',
        maxShindo: 3,
        stations: [
          buildRecord('A', 36.05, 140.90, 1.2),
          buildRecord('B', 36.45, 140.95, 0.9),
          buildRecord('C', 36.12, 141.42, 1.0),
          buildRecord('D', 36.40, 141.28, 0.8),
          buildRecord('E', 35.98, 141.05, 1.1),
        ],
      );

      final result = estimator.estimate(request);
      expect(result, isNotNull);
      expect((result!.latitude - epicenter.latitude).abs(), lessThan(0.15));
      expect((result.longitude - epicenter.longitude).abs(), lessThan(0.15));
      expect(result.depthKm, isNotNull);
      expect((result.depthKm! - depthKm).abs(), lessThanOrEqualTo(15));
      expect(result.method, 'trigger_time_depth_grid_v3');
    },
  );
}
