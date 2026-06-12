import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutterrhythmquake/core/source_estimation/seismic_source_tracker.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimator.dart';

void main() {
  late SeismicSourceTracker tracker;

  setUp(() {
    tracker = SeismicSourceTracker();
    tracker.setEstimator(
      'global-demo',
      const WeightedCentroidSourceEstimator(),
    );
  });

  SeismicStationSample buildSample({
    required String code,
    required double lat,
    required double lng,
    double value = 1.2,
    double activity = 8,
    int ascend = 2,
    bool isTriggered = true,
  }) {
    return SeismicStationSample(
      descriptor: SeismicStationDescriptor(
        stationId: code,
        code: code,
        sourceId: 'global-demo',
        network: 'TEST',
        coordinate: LatLng(lat, lng),
      ),
      observedAt: DateTime(2026, 6, 10, 16, 0, 0),
      valueType: StationValueType.jmaShindo,
      value: value,
      rawLevel: 10,
      detectLevel: 9,
      activity: activity,
      ascend: ascend,
      isTriggered: isTriggered,
      qualityFlags: const {'synthetic'},
    );
  }

  test('tracks generic non-NIED source event lifecycle', () {
    tracker.ingestFrame(
      sourceId: 'global-demo',
      observedAt: DateTime(2026, 6, 10, 16, 0, 0),
      stageName: 'detected',
      maxShindo: 2,
      samples: [
        buildSample(code: 'G01', lat: 10.0, lng: 120.0, value: 0.8),
        buildSample(code: 'G02', lat: 10.2, lng: 120.2, value: 1.3),
      ],
      metadata: const {'network_group': 'demo'},
    );

    final current = tracker.currentEvent('global-demo');
    expect(current, isNotNull);
    expect(current!.sourceId, 'global-demo');
    expect(current.records.length, 2);
    expect(
      current.records.every((r) => r.qualityFlags.contains('synthetic')),
      isTrue,
    );
    expect(current.estimate, isNotNull);

    tracker.ingestFrame(
      sourceId: 'global-demo',
      observedAt: DateTime(2026, 6, 10, 16, 0, 5),
      stageName: 'idle',
      maxShindo: -1,
      samples: [
        buildSample(
          code: 'G01',
          lat: 10.0,
          lng: 120.0,
          value: 0.0,
          activity: 0,
          ascend: 0,
          isTriggered: false,
        ),
        buildSample(
          code: 'G02',
          lat: 10.2,
          lng: 120.2,
          value: 0.0,
          activity: 0,
          ascend: 0,
          isTriggered: false,
        ),
      ],
    );

    expect(tracker.currentEvent('global-demo'), isNull);
    expect(tracker.history('global-demo'), isNotEmpty);
    expect(tracker.history('global-demo').first.isClosed, isTrue);
  });
}
