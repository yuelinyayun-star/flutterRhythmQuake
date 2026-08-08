import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutterrhythmquake/core/event_detection/event_detection_models.dart';
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

  test('sensor selection explicitly separates surface and borehole roles', () {
    const selection = SensorSelection.surfaceOnly();
    const surface = SeismicStationDescriptor(
      stationId: 'S',
      code: 'S',
      sourceId: 'test',
      network: 'K-NET',
      coordinate: LatLng(35, 140),
      sensorRole: StationSensorRole.surface,
    );
    const borehole = SeismicStationDescriptor(
      stationId: 'B',
      code: 'B',
      sourceId: 'test',
      network: 'KiK-net',
      coordinate: LatLng(35, 140),
      sensorRole: StationSensorRole.borehole,
    );

    expect(selection.accepts(surface), isTrue);
    expect(selection.accepts(borehole), isFalse);
  });

  SeismicStationSample buildSample({
    required String code,
    required double lat,
    required double lng,
    DateTime? observedAt,
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
      observedAt: observedAt ?? DateTime(2026, 6, 10, 16, 0, 0),
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
    var notificationCount = 0;
    tracker.currentEventNotifier('global-demo').addListener(() {
      notificationCount++;
    });
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
      current.records.every((r) => r.observationHistory.length == 1),
      isTrue,
    );
    expect(
      current.records.every((r) => r.qualityFlags.contains('synthetic')),
      isTrue,
    );
    expect(current.estimate, isNotNull);
    expect(current.metadata['estimate_revision'], 1);
    expect(notificationCount, 1);

    tracker.ingestFrame(
      sourceId: 'global-demo',
      observedAt: DateTime(2026, 6, 10, 16, 0, 1),
      stageName: 'detected',
      maxShindo: 2,
      samples: [
        buildSample(code: 'G01', lat: 10.0, lng: 120.0, value: 1.1),
        buildSample(code: 'G02', lat: 10.2, lng: 120.2, value: 1.5),
      ],
      metadata: const {'network_group': 'demo'},
    );

    expect(current.metadata['estimate_revision'], 2);
    expect(notificationCount, 2);
    expect(
      current.records.every((r) => r.observationHistory.length == 2),
      isTrue,
    );

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
    final archived = tracker.history('global-demo').first;
    expect(archived.isClosed, isTrue);
    expect(archived.estimate, isNotNull);
    expect(archived.metadata['network_group'], 'demo');
    expect(
      archived.records,
      isEmpty,
      reason: 'closed events must not retain per-station frame histories',
    );
  });

  test('missing station frame is retained without deleting event evidence', () {
    final start = DateTime(2026, 6, 10, 16);
    final triggered = buildSample(code: 'G01', lat: 10, lng: 120, value: 1.5);
    tracker.ingestFrame(
      sourceId: 'global-demo',
      observedAt: start,
      stageName: 'detected',
      maxShindo: 2,
      samples: [triggered],
    );

    tracker.ingestFrame(
      sourceId: 'global-demo',
      observedAt: start.add(const Duration(seconds: 1)),
      stageName: 'detected',
      maxShindo: 2,
      samples: [
        SeismicStationSample(
          descriptor: triggered.descriptor,
          observedAt: start.add(const Duration(seconds: 1)),
          valueType: StationValueType.jmaShindo,
        ),
      ],
    );

    final record = tracker.currentEvent('global-demo')!.records.single;
    expect(record.peakValue, 1.5);
    expect(record.firstTriggerInterval?.start, start);
    expect(record.firstTriggerInterval?.end, start);
    expect(record.observationHistory.length, 2);
    expect(record.observationHistory.latest!.isMissing, isTrue);
    expect(record.state, StationLifecycleState.ended);
  });

  test('rejects physical values without independent provenance', () {
    final start = DateTime(2026, 6, 10, 16);
    final base = buildSample(code: 'G01', lat: 10, lng: 120);
    tracker.ingestFrame(
      sourceId: 'global-demo',
      observedAt: start,
      stageName: 'detected',
      maxShindo: 2,
      samples: [
        SeismicStationSample(
          descriptor: base.descriptor,
          observedAt: start,
          valueType: StationValueType.jmaShindo,
          value: 1.2,
          observedPga: 99,
          rawLevel: 10,
          detectLevel: 10,
          isTriggered: true,
          provenance: const {
            StationValueType.pga: ObservationProvenance(
              origin: ObservationOrigin.derived,
              quantity: StationValueType.pga,
              layerId: 'jma',
              qualityFlags: {'derived_from_shindo'},
            ),
          },
        ),
      ],
    );

    expect(tracker.currentEvent('global-demo')!.records.single.lastPga, isNull);
  });

  test('accepts PGA from the independent acmap layer', () {
    final start = DateTime(2026, 6, 10, 16);
    final base = buildSample(code: 'G01', lat: 10, lng: 120);
    tracker.ingestFrame(
      sourceId: 'global-demo',
      observedAt: start,
      stageName: 'detected',
      maxShindo: 2,
      samples: [
        SeismicStationSample(
          descriptor: base.descriptor,
          observedAt: start,
          valueType: StationValueType.pga,
          value: 12,
          observedPga: 12,
          rawLevel: 10,
          detectLevel: 10,
          isTriggered: true,
          provenance: const {
            StationValueType.pga: ObservationProvenance(
              origin: ObservationOrigin.niedGifLayer,
              quantity: StationValueType.pga,
              layerId: 'acmap',
              isIndependentPhysicalMeasurement: true,
            ),
          },
        ),
      ],
    );

    expect(tracker.currentEvent('global-demo')!.records.single.lastPga, 12);
  });

  test('keeps raw event-window PGV peaks only from the trigger onward', () {
    final start = DateTime(2026, 6, 10, 16);
    final base = buildSample(code: 'G01', lat: 10, lng: 120);
    const pgvProvenance = ObservationProvenance(
      origin: ObservationOrigin.niedGifLayer,
      quantity: StationValueType.pgv,
      layerId: 'vcmap',
      isIndependentPhysicalMeasurement: true,
    );

    SeismicStationSample frame({
      required DateTime at,
      required double pgv,
      required double colorPosition,
      required bool triggered,
    }) {
      return SeismicStationSample(
        descriptor: base.descriptor,
        observedAt: at,
        receivedAt: at.add(const Duration(milliseconds: 250)),
        valueType: StationValueType.jmaShindo,
        value: 1.2,
        rawLevel: 10,
        detectLevel: 10,
        activity: 1,
        isTriggered: triggered,
        firstTriggerInterval: triggered
            ? ObservationTimeInterval(start: at, end: at)
            : null,
        observedPgv: pgv,
        physicalObservations: {
          StationValueType.pgv: SeismicPhysicalObservation(
            quantity: StationValueType.pgv,
            layerId: 'vcmap',
            value: pgv,
            colorPosition: colorPosition,
            dataTime: at,
            receivedAt: at.add(const Duration(milliseconds: 250)),
          ),
        },
        provenance: const {StationValueType.pgv: pgvProvenance},
      );
    }

    tracker.ingestFrame(
      sourceId: 'global-demo',
      observedAt: start,
      stageName: 'detected',
      maxShindo: 1,
      samples: [
        frame(at: start, pgv: 30, colorPosition: 0.70, triggered: false),
      ],
    );
    tracker.ingestFrame(
      sourceId: 'global-demo',
      observedAt: start.add(const Duration(seconds: 1)),
      stageName: 'detected',
      maxShindo: 1,
      samples: [
        frame(
          at: start.add(const Duration(seconds: 1)),
          pgv: 5,
          colorPosition: 0.44,
          triggered: true,
        ),
      ],
    );

    final record = tracker.currentEvent('global-demo')!.records.single;
    final peak = record.eventPhysicalPeaks[StationValueType.pgv];
    expect(peak, isNotNull);
    expect(peak!.value, 5);
    expect(peak.colorPosition, 0.44);
    expect(peak.dataTime, start.add(const Duration(seconds: 1)));
    expect(
      peak.receivedAt,
      start.add(const Duration(seconds: 1, milliseconds: 250)),
    );
    expect(
      record
          .observationHistory
          .frames
          .first
          .physicalObservations
          .values
          .single
          .value,
      30,
    );
  });

  test('stability policy holds a late drifting estimate', () {
    final start = DateTime(2026, 6, 10, 16);
    tracker
      ..setEstimator(
        'global-demo',
        _SequenceSourceEstimator([
          const SourceEstimate(
            latitude: 35.0,
            longitude: 140.0,
            confidence: 0.7,
            method: 'sequence',
            supportingStationCount: 2,
          ),
          const SourceEstimate(
            latitude: 35.01,
            longitude: 140.01,
            confidence: 0.7,
            method: 'sequence',
            supportingStationCount: 2,
          ),
          const SourceEstimate(
            latitude: 37.0,
            longitude: 142.0,
            confidence: 0.7,
            method: 'sequence',
            supportingStationCount: 2,
          ),
        ]),
      )
      ..setStabilityConfig(
        'global-demo',
        const SourceEstimateStabilityConfig(
          warmupDuration: Duration(seconds: 1),
          maxJumpKm: 20,
          maxAnchorDistanceKm: 40,
        ),
      );

    void ingest(DateTime observedAt, double value) {
      tracker.ingestFrame(
        sourceId: 'global-demo',
        observedAt: observedAt,
        stageName: 'detected',
        maxShindo: 2,
        samples: [
          buildSample(
            code: 'G01',
            lat: 35.0,
            lng: 140.0,
            observedAt: observedAt,
            value: value,
          ),
          buildSample(
            code: 'G02',
            lat: 35.1,
            lng: 140.1,
            observedAt: observedAt,
            value: value + 0.1,
          ),
        ],
      );
    }

    ingest(start, 1.0);
    final first = tracker.currentEvent('global-demo')!;
    expect(first.estimate!.latitude, 35.0);
    expect(first.metadata['estimate_revision'], 1);

    ingest(start.add(const Duration(seconds: 1)), 1.1);
    final warmed = tracker.currentEvent('global-demo')!;
    expect(warmed.estimate!.latitude, 35.01);
    expect(warmed.metadata['estimate_revision'], 2);
    expect(warmed.metadata['estimate_held_due_to_stability'], isNull);

    ingest(start.add(const Duration(seconds: 3)), 1.2);
    final held = tracker.currentEvent('global-demo')!;
    expect(held.estimate!.latitude, 35.01);
    expect(held.estimate!.longitude, 140.01);
    expect(held.metadata['estimate_revision'], 2);
    expect(held.metadata['estimate_held_due_to_stability'], isTrue);
    expect(held.metadata['stability_candidate_latitude'], 37.0);
    expect(held.metadata['stability_candidate_longitude'], 142.0);
  });

  test(
    'annotates delayed candidate region without changing estimate location',
    () {
      final start = DateTime(2026, 6, 22, 16, 38, 23);
      tracker.setEstimator(
        'global-demo',
        _SequenceSourceEstimator([
          _candidateEstimate(candidateSupportedByValues: false),
          _candidateEstimate(candidateSupportedByValues: true),
        ]),
      );

      void ingest(DateTime observedAt, double firstValue, double secondValue) {
        tracker.ingestFrame(
          sourceId: 'global-demo',
          observedAt: observedAt,
          stageName: 'detected',
          maxShindo: 1,
          samples: [
            buildSample(
              code: 'G01',
              lat: 0,
              lng: 0,
              observedAt: observedAt,
              value: firstValue,
            ),
            buildSample(
              code: 'G02',
              lat: 0,
              lng: 1,
              observedAt: observedAt,
              value: secondValue,
            ),
          ],
        );
      }

      ingest(start, 2, 0);
      final pending = tracker.currentEvent('global-demo')!;
      expect(pending.estimate!.latitude, 0);
      expect(pending.estimate!.longitude, 0);
      final pendingRegion = pending.metadata['candidate_region'] as Map;
      expect(pendingRegion['status'], 'pending');
      expect(pendingRegion['production_coordinate_switch_allowed'], isFalse);

      ingest(start.add(const Duration(seconds: 4)), 0, 2);
      final confirmed = tracker.currentEvent('global-demo')!;
      expect(confirmed.estimate!.latitude, 0);
      expect(confirmed.estimate!.longitude, 0);
      final confirmedRegion = confirmed.metadata['candidate_region'] as Map;
      expect(confirmedRegion['status'], 'confirmedDelayed');
      expect(confirmedRegion['confirmation_delay_seconds'], 4);
      expect(confirmedRegion['production_coordinate_switch_allowed'], isFalse);
      final gate = confirmed.metadata['candidate_region_residual_gate'] as Map;
      expect(gate['residual_supported'], isTrue);
    },
  );

  test('does not confirm an unsupported candidate region', () {
    final start = DateTime(2026, 6, 22, 16, 38, 23);
    tracker.setEstimator(
      'global-demo',
      _SequenceSourceEstimator([
        _candidateEstimate(candidateSupportedByValues: false),
        _candidateEstimate(candidateSupportedByValues: false),
      ]),
    );

    for (var i = 0; i < 2; i++) {
      tracker.ingestFrame(
        sourceId: 'global-demo',
        observedAt: start.add(Duration(seconds: i)),
        stageName: 'detected',
        maxShindo: 1,
        samples: [
          buildSample(
            code: 'G01',
            lat: 0,
            lng: 0,
            observedAt: start.add(Duration(seconds: i)),
            value: (2 + i).toDouble(),
          ),
          buildSample(
            code: 'G02',
            lat: 0,
            lng: 1,
            observedAt: start.add(Duration(seconds: i)),
            value: i.toDouble(),
          ),
        ],
      );
    }

    final current = tracker.currentEvent('global-demo')!;
    final region = current.metadata['candidate_region'] as Map;
    expect(region['status'], 'pending');
    expect(region['production_coordinate_switch_allowed'], isFalse);
  });

  test(
    'confirms pending candidate region from local support without coordinate switch',
    () {
      final start = DateTime(2026, 6, 25, 19, 21, 43);
      tracker.setEstimator(
        'global-demo',
        _SequenceSourceEstimator([
          _localSupportCandidateEstimate(),
          _localSupportConvergedEstimate(),
        ]),
      );

      final firstMembers = List.generate(5, (index) => 'LS${index + 1}');
      final laterMembers = List.generate(10, (index) => 'LS${index + 1}');

      tracker.ingestFrame(
        sourceId: 'global-demo',
        eventId: 'iwate-local-support',
        observedAt: start,
        stageName: 'detected',
        maxShindo: 1,
        samples: [
          for (var i = 0; i < firstMembers.length; i++)
            buildSample(
              code: firstMembers[i],
              lat: 0.0,
              lng: i * 0.01,
              observedAt: start,
              value: 1.0 + i * 0.1,
            ),
        ],
        metadata: {'source_trigger_member_ids': firstMembers},
      );
      final pending = tracker.currentEvent('global-demo')!;
      final pendingRegion = pending.metadata['candidate_region'] as Map;
      expect(pendingRegion['status'], 'pending');
      expect(pending.estimate!.latitude, 0);
      expect(pending.estimate!.longitude, 1.38);

      tracker.ingestFrame(
        sourceId: 'global-demo',
        eventId: 'iwate-local-support',
        observedAt: start.add(const Duration(seconds: 3)),
        stageName: 'detected',
        maxShindo: 1,
        samples: [
          for (var i = 0; i < laterMembers.length; i++)
            buildSample(
              code: laterMembers[i],
              lat: 0.0,
              lng: i * 0.005,
              observedAt: start.add(const Duration(seconds: 3)),
              value: 1.0 + i * 0.1,
            ),
        ],
        metadata: {'source_trigger_member_ids': laterMembers},
      );

      final confirmed = tracker.currentEvent('global-demo')!;
      expect(confirmed.estimate!.latitude, 0);
      expect(confirmed.estimate!.longitude, 0.02);
      final confirmedRegion = confirmed.metadata['candidate_region'] as Map;
      expect(confirmedRegion['status'], 'confirmedDelayed');
      expect(
        confirmedRegion['reason'],
        'same_region_local_support_confirmation',
      );
      expect(confirmedRegion['production_coordinate_switch_allowed'], isFalse);
      final localGate =
          confirmed.metadata['candidate_region_local_support_gate'] as Map;
      expect(localGate['local_support_confirmed'], isTrue);
      expect(localGate['member_count'], 10);
      expect(localGate['member_growth_supported'], isTrue);
    },
  );

  test('raw detect level alone does not become source timing evidence', () {
    final start = DateTime(2026, 6, 10, 16);
    final base = buildSample(code: 'G01', lat: 10, lng: 120);
    tracker.ingestFrame(
      sourceId: 'global-demo',
      observedAt: start,
      stageName: 'detected',
      maxShindo: 0,
      samples: [
        SeismicStationSample(
          descriptor: base.descriptor,
          observedAt: start,
          valueType: StationValueType.jmaShindo,
          value: -1.0,
          rawLevel: 2,
          detectLevel: 2,
        ),
      ],
    );

    final record = tracker.currentEvent('global-demo')!.records.single;
    expect(record.state, StationLifecycleState.idle);
    expect(record.firstRiseAt, isNull);
    expect(record.firstTriggerAt, isNull);
    expect(tracker.currentEvent('global-demo')!.estimate, isNull);
  });

  test('holds the last estimate when active support drops below minimum', () {
    final start = DateTime(2026, 6, 10, 16);
    tracker.ingestFrame(
      sourceId: 'global-demo',
      observedAt: start,
      stageName: 'detected',
      maxShindo: 2,
      samples: [
        buildSample(code: 'G01', lat: 10, lng: 120),
        buildSample(code: 'G02', lat: 10.2, lng: 120.2),
      ],
    );
    final stable = tracker.currentEvent('global-demo')!.estimate;

    tracker.ingestFrame(
      sourceId: 'global-demo',
      observedAt: start.add(const Duration(seconds: 1)),
      stageName: 'detected',
      maxShindo: 1,
      samples: [
        buildSample(
          code: 'G01',
          lat: 10,
          lng: 120,
          activity: 0,
          ascend: 0,
          isTriggered: false,
        ),
        buildSample(
          code: 'G02',
          lat: 10.2,
          lng: 120.2,
          activity: 0,
          ascend: 0,
          isTriggered: false,
        ),
      ],
    );

    final current = tracker.currentEvent('global-demo')!;
    expect(current.estimate, same(stable));
    expect(current.metadata['estimate_held_due_to_low_support'], isTrue);
  });

  test(
    'estimator-owned JS lifecycle bypasses tracker hold and clears output',
    () {
      final start = DateTime(2026, 7, 17, 16);
      final estimator = _LifecycleOwnerEstimator([
        const SourceEstimate(
          latitude: 35,
          longitude: 140,
          confidence: 0.5,
          method: 'owned-lifecycle',
          supportingStationCount: 5,
        ),
        const SourceEstimate(
          latitude: 38,
          longitude: 144,
          confidence: 0.5,
          method: 'owned-lifecycle',
          supportingStationCount: 5,
        ),
        null,
      ]);
      tracker
        ..setEstimator('global-demo', estimator)
        ..setStabilityConfig(
          'global-demo',
          const SourceEstimateStabilityConfig(
            warmupDuration: Duration.zero,
            maxJumpKm: 1,
            maxAnchorDistanceKm: 1,
          ),
        );

      void ingest(Duration offset) {
        final observedAt = start.add(offset);
        tracker.ingestFrame(
          sourceId: 'global-demo',
          observedAt: observedAt,
          stageName: 'detected',
          maxShindo: 2,
          samples: [
            buildSample(code: 'G01', lat: 35, lng: 140, observedAt: observedAt),
            buildSample(
              code: 'G02',
              lat: 35.1,
              lng: 140.1,
              observedAt: observedAt,
            ),
          ],
        );
      }

      ingest(Duration.zero);
      expect(tracker.currentEvent('global-demo')!.estimate!.latitude, 35);
      ingest(Duration.zero);
      expect(estimator.callCount, 1);
      expect(tracker.currentEvent('global-demo')!.estimate!.latitude, 35);

      ingest(const Duration(seconds: 2));
      final moved = tracker.currentEvent('global-demo')!;
      expect(moved.estimate!.latitude, 38);
      expect(moved.metadata['estimate_held_due_to_stability'], isNull);

      ingest(const Duration(seconds: 3));
      final cleared = tracker.currentEvent('global-demo')!;
      expect(cleared.estimate, isNull);
      expect(cleared.metadata['nied_dart_hyp_clear_published_source'], isTrue);
      expect(cleared.metadata['estimate_held_due_to_low_support'], isNull);
    },
  );
}

class _SequenceSourceEstimator implements SourceEstimator {
  _SequenceSourceEstimator(this.estimates);

  final List<SourceEstimate> estimates;
  var _index = 0;

  @override
  String get methodId => 'sequence';

  @override
  bool supports(SourceEstimationRequest request) =>
      request.stations.length >= 2;

  @override
  SourceEstimate? estimate(SourceEstimationRequest request) {
    if (_index >= estimates.length) {
      return estimates.last;
    }
    return estimates[_index++];
  }
}

class _LifecycleOwnerEstimator
    implements SourceEstimator, SourceEstimatorLifecycleOwner {
  _LifecycleOwnerEstimator(this.estimates);

  final List<SourceEstimate?> estimates;
  var _index = 0;

  int get callCount => _index;

  @override
  String get methodId => 'owned-lifecycle';

  @override
  bool get ownsOutputLifecycle => true;

  @override
  bool get requiresEveryFrame => true;

  @override
  bool supports(SourceEstimationRequest request) => true;

  @override
  SourceEstimate? estimate(SourceEstimationRequest request) {
    final index = _index < estimates.length ? _index : estimates.length - 1;
    final estimate = estimates[index];
    _index += 1;
    if (estimate == null) {
      request.metadata
        ..['nied_dart_hyp_clear_published_source'] = true
        ..['nied_dart_hyp_source_clear_reason'] = 'test_js_lifecycle_end';
    } else {
      request.metadata
        ..remove('nied_dart_hyp_clear_published_source')
        ..remove('nied_dart_hyp_source_clear_reason');
    }
    return estimate;
  }
}

SourceEstimate _candidateEstimate({required bool candidateSupportedByValues}) {
  return SourceEstimate(
    latitude: 0,
    longitude: 0,
    confidence: 0.4,
    method: 'sequence',
    supportingStationCount: 2,
    diagnostics: {
      'candidate_corrections': {
        'one_sided_boundary_centroid_guard': {
          'latitude': 0.0,
          'longitude': 1.0,
        },
      },
      'top_timing_picks': [
        {
          'code': 'G01',
          'network': 'TEST',
          'latitude': 0.0,
          'longitude': 0.0,
          'delay_s': 0.0,
          'value': candidateSupportedByValues ? 0.0 : 2.0,
        },
        {
          'code': 'G02',
          'network': 'TEST',
          'latitude': 0.0,
          'longitude': 1.0,
          'delay_s': 1.0,
          'value': candidateSupportedByValues ? 2.0 : 0.0,
        },
      ],
    },
  );
}

SourceEstimate _localSupportCandidateEstimate() {
  return const SourceEstimate(
    latitude: 0,
    longitude: 1.38,
    confidence: 0.4,
    method: 'sequence',
    supportingStationCount: 5,
    diagnostics: {
      'station_geometry': 'one_sided',
      'candidate_corrections': {
        'one_sided_boundary_centroid_guard': {
          'latitude': 0.0,
          'longitude': 1.0,
        },
      },
      'top_timing_picks': [
        {
          'code': 'G01',
          'network': 'TEST',
          'latitude': 0.0,
          'longitude': 0.0,
          'delay_s': 0.0,
          'value': 2.0,
        },
        {
          'code': 'G02',
          'network': 'TEST',
          'latitude': 0.0,
          'longitude': 1.0,
          'delay_s': 1.0,
          'value': 0.0,
        },
      ],
    },
  );
}

SourceEstimate _localSupportConvergedEstimate() {
  return const SourceEstimate(
    latitude: 0,
    longitude: 0.02,
    confidence: 0.4,
    method: 'sequence',
    supportingStationCount: 10,
    diagnostics: {'station_geometry': 'surrounded'},
  );
}
