import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutterrhythmquake/core/nied_replay_logger.dart';
import 'package:flutterrhythmquake/core/event_detection/event_detection_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_event_tracker.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/nied_source_estimation_driver.dart';
import 'package:flutterrhythmquake/services/sources/shake_detection_service.dart';

void main() {
  setUp(() {
    StationEventTracker.instance.resetNied();
    NiedReplayLogger.instance.resetForTest();
  });

  tearDown(() {
    NiedReplayLogger.instance.resetForTest(writeToDisk: true);
  });

  List<NiedStation> buildStations() {
    return List.generate(6, (index) {
      return NiedStation(
        id: index,
        code: 'SRC${index.toString().padLeft(3, '0')}',
        name: 'SRC$index',
        coordinate: LatLng(35.0 + index * 0.01, 140.0 + index * 0.01),
        network: 'K-NET',
        prefecture: 'Test',
        expireSeconds: 10,
      );
    });
  }

  void applyFrame(
    List<NiedStation> stations,
    DateTime observedAt,
    int level, {
    bool withGif = false,
  }) {
    for (final station in stations) {
      station
        ..level = level
        ..lastUpdate = observedAt
        ..lastDataTime = observedAt;
      if (withGif) {
        station.continuousShindo = level >= 0 ? (level + 0.5 - 7) / 2 : -3.0;
      }
    }
  }

  void markKaActive(List<NiedStation> stations, DateTime observedAt) {
    for (final station in stations) {
      station
        ..activity = 8
        ..ascend = 3
        ..triggerStamp = observedAt.millisecondsSinceEpoch
        ..isActive = true;
    }
  }

  test('preserves the ten-step JMA maximum index from raw KA levels', () {
    const cases = [(16, 5), (17, 6), (18, 7), (19, 8)];
    final observedAt = DateTime(2026, 7, 28, 12);

    for (final (kaLevel, expectedJmaIndex) in cases) {
      StationEventTracker.instance.resetNied();
      final stations = buildStations();
      applyFrame(stations, observedAt, kaLevel, withGif: true);
      markKaActive(stations, observedAt);

      NiedSourceEstimationDriver().processStations(
        stations,
        observedAt: observedAt,
      );

      final event = StationEventTracker.instance.currentNiedEvent.value;
      expect(event, isNotNull, reason: 'KA level $kaLevel');
      expect(
        event!.metadata['nied_max_jma_shindo_index'],
        expectedJmaIndex,
        reason: 'KA level $kaLevel',
      );
    }
  });

  test('generic source trigger cannot bypass KA active-station inference', () {
    final stations = buildStations();
    final driver = NiedSourceEstimationDriver();
    final start = DateTime(2026, 6, 20, 12, 0, 0);
    EventDetection? detection;

    for (var i = 0; i < 5; i++) {
      applyFrame(stations, start.add(Duration(seconds: i)), 7);
      detection = driver.processStations(stations);
    }
    expect(detection!.state, EventDetectionState.idle);
    expect(StationEventTracker.instance.currentNiedEvent.value, isNull);

    for (var i = 5; i < 9; i++) {
      applyFrame(stations, start.add(Duration(seconds: i)), 12);
      detection = driver.processStations(stations);
    }

    expect(detection!.state, EventDetectionState.confirmed);
    expect(StationEventTracker.instance.currentNiedEvent.value, isNull);
  });

  test(
    'generic source trigger does not start replay logging without KA active stations',
    () {
      NiedReplayLogger.instance.resetForTest(autoSaveOnSourceTrigger: true);
      final stations = buildStations();
      final driver = NiedSourceEstimationDriver();
      final start = DateTime(2026, 6, 20, 12, 0, 0);

      for (var i = 0; i < 5; i++) {
        final observedAt = start.add(Duration(seconds: i));
        applyFrame(stations, observedAt, 7);
        driver.processStations(stations, observedAt: observedAt);
      }
      expect(NiedReplayLogger.instance.isEnabled, isFalse);

      for (var i = 5; i < 9; i++) {
        final observedAt = start.add(Duration(seconds: i));
        applyFrame(stations, observedAt, 12);
        driver.processStations(stations, observedAt: observedAt);
      }

      expect(NiedReplayLogger.instance.isEnabled, isFalse);
      expect(NiedReplayLogger.instance.debugRecords, isEmpty);
    },
  );

  test('GIF frames without KA active stations do not open inference', () {
    final stations = buildStations();
    final driver = NiedSourceEstimationDriver();
    final start = DateTime(2026, 6, 20, 12, 0, 0);

    for (var i = 0; i < 4; i++) {
      applyFrame(
        stations,
        start.add(Duration(seconds: i)),
        i < 2 ? 7 : 12,
        withGif: true,
      );
      driver.processStations(
        stations,
        observedAt: start.add(Duration(seconds: i)),
      );
    }

    expect(StationEventTracker.instance.currentNiedEvent.value, isNull);
  });

  test('KA inference closes on the first frame without active stations', () {
    final stations = buildStations();
    final driver = NiedSourceEstimationDriver();
    final start = DateTime(2026, 6, 20, 12, 0, 0);
    applyFrame(stations, start, 12, withGif: true);
    markKaActive(stations, start);

    driver.processStations(stations, observedAt: start);
    expect(StationEventTracker.instance.currentNiedEvent.value, isNotNull);

    final endedAt = start.add(const Duration(seconds: 11));
    for (final station in stations) {
      station
        ..level = -1
        ..activity = 0
        ..ascend = 0
        ..triggerStamp = 0
        ..isActive = false
        ..lastUpdate = endedAt
        ..lastDataTime = endedAt;
    }
    driver.processStations(stations, observedAt: endedAt);

    expect(StationEventTracker.instance.currentNiedEvent.value, isNull);
    expect(StationEventTracker.instance.niedEventHistory.value, hasLength(1));
    expect(
      StationEventTracker.instance.niedEventHistory.value.single.endedAt,
      endedAt,
    );
  });

  test('GIF hypocenter input keeps Ka active-window stations', () {
    final stations = buildStations();
    final driver = NiedSourceEstimationDriver();
    final start = DateTime(2026, 6, 20, 12, 0, 0);

    void setStationState(
      NiedStation station, {
      required DateTime observedAt,
      required int level,
      required int ascend,
      required double activity,
      bool clearActive = false,
    }) {
      station
        ..level = level
        ..ascend = ascend
        ..activity = activity
        ..triggerStamp = ascend > 0 ? observedAt.millisecondsSinceEpoch : 0
        ..lastUpdate = observedAt
        ..lastDataTime = observedAt
        ..continuousShindo = level >= 0 ? (level + 0.5 - 7) / 2 : -3.0;
      if (clearActive) {
        station.isActive = false;
      }
    }

    final next = start.add(const Duration(seconds: 1));
    for (var index = 0; index < stations.length; index++) {
      setStationState(
        stations[index],
        observedAt: next,
        level: index == 5 ? 12 : 7,
        ascend: index == 5 ? 4 : 0,
        activity: index == 5 ? 8 : 1,
      );
      if (index < 5) {
        stations[index]
          ..isActive = true
          ..triggerStamp = start.millisecondsSinceEpoch;
      }
    }
    driver.processStations(stations, observedAt: next);

    final event = StationEventTracker.instance.currentNiedEvent.value;
    expect(event, isNotNull);
    final activeSnapshots =
        event!.metadata['nied_hypocenter_active_stations'] as List;
    final activeSnapshotMaps = activeSnapshots.cast<Map<String, Object?>>();
    final activeCodes = activeSnapshotMaps
        .map((snapshot) => snapshot['code'])
        .toSet();
    expect(
      activeCodes,
      containsAll(stations.take(5).map((station) => station.code)),
    );
    for (final snapshot in activeSnapshotMaps) {
      if (stations.take(5).any((station) => station.code == snapshot['code'])) {
        expect(snapshot['triggerStamp'], start.millisecondsSinceEpoch);
      }
    }
  });

  test('Yahoo input sends KA stations and their real trigger stamps', () {
    final stations = buildStations();
    final driver = NiedSourceEstimationDriver();
    final start = DateTime(2026, 6, 20, 12, 0, 0);

    for (var index = 0; index < stations.length; index++) {
      final triggerAt = start.add(Duration(milliseconds: index * 100));
      stations[index]
        ..level = 12
        ..ascend = 4
        ..activity = 12
        ..triggerStamp = triggerAt.millisecondsSinceEpoch
        ..lastUpdate = triggerAt
        ..lastDataTime = triggerAt;
    }

    driver.processStations(
      stations,
      observedAt: start.add(const Duration(seconds: 1)),
    );

    final event = StationEventTracker.instance.currentNiedEvent.value;
    expect(event, isNotNull);
    expect(event!.eventId, startsWith('nied-yahoo-dart-'));
    expect(event.metadata['nied_input_kind'], 'yahoo');
    expect(
      event.metadata['source_estimation_entry'],
      'ka_nied_hypocenter_direct',
    );
    final snapshots =
        (event.metadata['nied_hypocenter_active_stations'] as List)
            .cast<Map<String, Object?>>();
    expect(snapshots, hasLength(stations.length));
    for (var index = 0; index < stations.length; index++) {
      final snapshot = snapshots.singleWhere(
        (item) => item['code'] == stations[index].code,
      );
      expect(snapshot['level'], 12);
      expect(snapshot.containsKey('detectLevel'), isFalse);
      expect(snapshot.containsKey('activity'), isFalse);
      expect(snapshot['triggerStamp'], stations[index].triggerStamp);
    }
  });

  test('Scratch inactive input keeps all KA level-present stations', () {
    final observedAt = DateTime(2026, 6, 20, 12);
    final stations = <NiedStation>[
      for (var index = 0; index < 5; index++)
        NiedStation(
            id: index,
            code: 'ACTIVE$index',
            name: 'ACTIVE$index',
            coordinate: index == 4
                ? const LatLng(37.2, 142.2)
                : LatLng(35.2 + index * 0.01, 140.2 + index * 0.01),
            network: 'K-NET',
            prefecture: 'Test',
            expireSeconds: 10,
          )
          ..level = 10
          ..ascend = 3
          ..activity = 10
          ..triggerStamp = observedAt.millisecondsSinceEpoch
          ..lastUpdate = observedAt
          ..lastDataTime = observedAt
          ..isActive = true,
      NiedStation(
          id: 5,
          code: 'INACTIVE_NEAR',
          name: 'INACTIVE_NEAR',
          coordinate: const LatLng(36.2, 141.2),
          network: 'K-NET',
          prefecture: 'Test',
          expireSeconds: 10,
        )
        ..level = 0
        ..lastUpdate = observedAt
        ..lastDataTime = observedAt,
      NiedStation(
          id: 6,
          code: 'INACTIVE_FAR',
          name: 'INACTIVE_FAR',
          coordinate: const LatLng(38.2, 143.2),
          network: 'K-NET',
          prefecture: 'Test',
          expireSeconds: 10,
        )
        ..level = 0
        ..lastUpdate = observedAt
        ..lastDataTime = observedAt,
      NiedStation(
          id: 7,
          code: 'INACTIVE_OUTSIDE',
          name: 'INACTIVE_OUTSIDE',
          coordinate: const LatLng(41.2, 146.2),
          network: 'K-NET',
          prefecture: 'Test',
          expireSeconds: 10,
        )
        ..level = 0
        ..lastUpdate = observedAt
        ..lastDataTime = observedAt,
    ];

    final driver = NiedSourceEstimationDriver();
    driver.processStations(stations, observedAt: observedAt);

    final event = StationEventTracker.instance.currentNiedEvent.value;
    expect(event, isNotNull);
    expect(
      event!.metadata['nied_hypocenter_inactive_scope'],
      'ka_level_present_all_network_scratch_dynamic_radius',
    );
    final inactive =
        (event.metadata['nied_hypocenter_inactive_stations'] as List)
            .cast<Map<String, Object?>>();
    expect(inactive.map((station) => station['code']), [
      'INACTIVE_NEAR',
      'INACTIVE_FAR',
      'INACTIVE_OUTSIDE',
    ]);
    final grid =
        event.metadata['nied_hypocenter_detection_grid']
            as Map<String, Object?>;
    expect(grid['model'], 'ka_detection_1deg_event_offset_surrounding_9_grid');
    expect(grid['activeCells'], hasLength(2));
    expect(grid['surroundingCellCount'], 17);

    for (final station in stations.skip(1).take(4)) {
      station
        ..level = -1
        ..ascend = 0
        ..activity = 0
        ..isActive = false
        ..lastUpdate = observedAt.add(const Duration(seconds: 11))
        ..lastDataTime = observedAt.add(const Duration(seconds: 11));
    }
    driver.processStations(
      stations,
      observedAt: observedAt.add(const Duration(seconds: 11)),
    );

    final continuedEvent = StationEventTracker.instance.currentNiedEvent.value!;
    final continuedGrid =
        continuedEvent.metadata['nied_hypocenter_detection_grid']
            as Map<String, Object?>;
    final continuedInactive =
        (continuedEvent.metadata['nied_hypocenter_inactive_stations'] as List)
            .cast<Map<String, Object?>>();
    expect(continuedGrid['activeCells'], hasLength(1));
    expect(continuedGrid['surroundingCellCount'], 9);
    expect(continuedInactive.map((station) => station['code']), [
      'INACTIVE_NEAR',
      'INACTIVE_FAR',
      'INACTIVE_OUTSIDE',
    ]);
  });

  test('KA snapshot never invents a trigger stamp for an active station', () {
    final stations = buildStations();
    final driver = NiedSourceEstimationDriver();
    final observedAt = DateTime(2026, 6, 20, 12, 0, 0);

    for (final station in stations) {
      station
        ..level = 12
        ..ascend = 0
        ..activity = 0
        ..triggerStamp = 0
        ..isActive = true
        ..lastUpdate = observedAt
        ..lastDataTime = observedAt
        ..continuousShindo = 2.75;
    }

    driver.processStations(stations, observedAt: observedAt);

    final event = StationEventTracker.instance.currentNiedEvent.value;
    expect(event, isNotNull);
    final snapshots =
        (event!.metadata['nied_hypocenter_active_stations'] as List)
            .cast<Map<String, Object?>>();
    expect(snapshots, hasLength(stations.length));
    expect(
      snapshots.every((snapshot) => snapshot['triggerStamp'] == null),
      isTrue,
    );
    expect(event.estimate, isNull);
  });

  test('legacy detection service does not ingest source tracker directly', () {
    final stations = buildStations();
    final detector = ShakeDetectionService()..setSensitivity(2);
    final start = DateTime(2026, 6, 20, 12, 0, 0);

    for (var i = 0; i < 5; i++) {
      applyFrame(stations, start.add(Duration(seconds: i)), 7);
      detector.setStations(stations);
      detector.processUpdate();
    }

    for (var i = 5; i < 9; i++) {
      applyFrame(stations, start.add(Duration(seconds: i)), 12);
      detector.setStations(stations);
      detector.processUpdate();
    }

    expect(StationEventTracker.instance.currentNiedEvent.value, isNull);
  });

  test('source history preserves station data and receive timestamps', () {
    final stations = buildStations();
    final driver = NiedSourceEstimationDriver();
    final start = DateTime(2026, 6, 20, 12);

    for (var i = 0; i < 5; i++) {
      final frameTime = start.add(Duration(seconds: i));
      applyFrame(stations, frameTime, 7);
      markKaActive(stations, frameTime);
      for (final station in stations) {
        station.lastReceivedAt = frameTime.add(
          const Duration(milliseconds: 250),
        );
      }
      driver.processStations(stations);
    }
    for (var i = 5; i < 9; i++) {
      final frameTime = start.add(Duration(seconds: i));
      applyFrame(stations, frameTime, 12);
      markKaActive(stations, frameTime);
      for (final station in stations) {
        station.lastReceivedAt = frameTime.add(
          const Duration(milliseconds: 250),
        );
      }
      driver.processStations(stations);
    }

    final event = StationEventTracker.instance.currentNiedEvent.value!;
    final frame = event.records.first.observationHistory.latest!;
    expect(frame.receivedAt.difference(frame.dataTime).inMilliseconds, 250);
  });

  test('source driver exposes held replacement as effective event id', () {
    final oldStations = [
      NiedStation(
        id: 1,
        code: 'OLD1',
        name: 'OLD1',
        coordinate: const LatLng(37.1, 139.4),
        network: 'K-NET',
        prefecture: 'Test',
        expireSeconds: 10,
      ),
      NiedStation(
        id: 2,
        code: 'OLD2',
        name: 'OLD2',
        coordinate: const LatLng(37.2, 139.4),
        network: 'K-NET',
        prefecture: 'Test',
        expireSeconds: 10,
      ),
      NiedStation(
        id: 3,
        code: 'OLD3',
        name: 'OLD3',
        coordinate: const LatLng(37.1, 139.5),
        network: 'K-NET',
        prefecture: 'Test',
        expireSeconds: 10,
      ),
      NiedStation(
        id: 4,
        code: 'OLD4',
        name: 'OLD4',
        coordinate: const LatLng(37.2, 139.5),
        network: 'K-NET',
        prefecture: 'Test',
        expireSeconds: 10,
      ),
    ];
    final newStations = [
      NiedStation(
        id: 5,
        code: 'NEW1',
        name: 'NEW1',
        coordinate: const LatLng(36.2, 139.8),
        network: 'K-NET',
        prefecture: 'Test',
        expireSeconds: 10,
      ),
      NiedStation(
        id: 6,
        code: 'NEW2',
        name: 'NEW2',
        coordinate: const LatLng(36.3, 139.8),
        network: 'K-NET',
        prefecture: 'Test',
        expireSeconds: 10,
      ),
      NiedStation(
        id: 7,
        code: 'NEW3',
        name: 'NEW3',
        coordinate: const LatLng(36.2, 139.9),
        network: 'K-NET',
        prefecture: 'Test',
        expireSeconds: 10,
      ),
      NiedStation(
        id: 8,
        code: 'NEW4',
        name: 'NEW4',
        coordinate: const LatLng(36.3, 139.9),
        network: 'K-NET',
        prefecture: 'Test',
        expireSeconds: 10,
      ),
    ];
    final start = DateTime(2026, 6, 24, 13, 24, 54);
    final detector = _QueuedEventDetector([
      EventDetection(
        detectorId: 'fake',
        sourceId: 'nied_gif',
        eventId: 'event-a',
        state: EventDetectionState.confirmed,
        observedAt: start,
        memberStationIds: const ['OLD1', 'OLD2', 'OLD3', 'OLD4'],
      ),
      EventDetection(
        detectorId: 'fake',
        sourceId: 'nied_gif',
        eventId: 'event-b',
        state: EventDetectionState.candidate,
        observedAt: start.add(const Duration(seconds: 86)),
        memberStationIds: const ['NEW1', 'NEW2', 'NEW3', 'NEW4'],
      ),
    ]);
    final driver = NiedSourceEstimationDriver(
      stationTriggerDetector: const _PassThroughStationTriggerDetector(),
      eventDetector: detector,
    );

    final first = driver.processStations(oldStations, observedAt: start);
    expect(first.eventId, 'event-a');

    final held = driver.processStations(
      newStations,
      observedAt: start.add(const Duration(seconds: 86)),
    );
    expect(held.eventId, 'event-a');
    expect(held.reasonCodes, contains('source_trigger_replacement_held'));
    expect(held.metadata['source_trigger_continuity_raw_event_id'], 'event-b');
  });

  test('source estimator metadata uses current detection members', () {
    NiedStation station(String code, double lat, double lon) {
      return NiedStation(
        id: code.hashCode,
        code: code,
        name: code,
        coordinate: LatLng(lat, lon),
        network: 'K-NET',
        prefecture: 'Test',
        expireSeconds: 10,
      );
    }

    final stations = [
      station('A', 35.00, 140.00),
      station('B', 35.01, 140.01),
      station('C', 35.02, 140.02),
      station('D', 35.03, 140.03),
    ];
    final start = DateTime(2026, 6, 24, 13, 24, 54);
    final detector = _QueuedEventDetector([
      EventDetection(
        detectorId: 'fake',
        sourceId: 'nied_gif',
        eventId: 'event-a',
        state: EventDetectionState.confirmed,
        observedAt: start,
        memberStationIds: const ['A', 'B', 'C', 'D'],
      ),
      EventDetection(
        detectorId: 'fake',
        sourceId: 'nied_gif',
        eventId: 'event-a',
        state: EventDetectionState.confirmed,
        observedAt: start.add(const Duration(seconds: 1)),
        memberStationIds: const ['A', 'B'],
      ),
    ]);
    final driver = NiedSourceEstimationDriver(
      stationTriggerDetector: const _PassThroughStationTriggerDetector(),
      eventDetector: detector,
    );

    markKaActive(stations, start);

    driver.processStations(stations, observedAt: start);
    driver.processStations(
      stations,
      observedAt: start.add(const Duration(seconds: 1)),
    );

    final event = StationEventTracker.instance.currentNiedEvent.value;
    expect(event, isNotNull);
    expect(event!.metadata['source_trigger_member_ids'], ['A', 'B']);
    expect(event.metadata['source_trigger_continuity_member_ids'], [
      'A',
      'B',
      'C',
      'D',
    ]);
  });

  test('source continuity holds same-event far member replacement', () {
    NiedStation station(String code, double lat, double lon) {
      return NiedStation(
        id: code.hashCode,
        code: code,
        name: code,
        coordinate: LatLng(lat, lon),
        network: 'K-NET',
        prefecture: 'Test',
        expireSeconds: 10,
      );
    }

    final oldStations = [
      station('OLD1', 37.1, 139.4),
      station('OLD2', 37.2, 139.4),
      station('OLD3', 37.1, 139.5),
      station('OLD4', 37.2, 139.5),
    ];
    final newStations = [
      station('NEW1', 36.2, 139.8),
      station('NEW2', 36.3, 139.8),
      station('NEW3', 36.2, 139.9),
      station('NEW4', 36.3, 139.9),
    ];
    final start = DateTime(2026, 6, 24, 13, 24, 54);
    final detector = _QueuedEventDetector([
      EventDetection(
        detectorId: 'fake',
        sourceId: 'nied_gif',
        eventId: 'event-a',
        state: EventDetectionState.confirmed,
        observedAt: start,
        memberStationIds: const ['OLD1', 'OLD2', 'OLD3', 'OLD4'],
      ),
      EventDetection(
        detectorId: 'fake',
        sourceId: 'nied_gif',
        eventId: 'event-a',
        state: EventDetectionState.confirmed,
        observedAt: start.add(const Duration(seconds: 20)),
        memberStationIds: const ['NEW1', 'NEW2', 'NEW3', 'NEW4'],
      ),
    ]);
    final driver = NiedSourceEstimationDriver(
      stationTriggerDetector: const _PassThroughStationTriggerDetector(),
      eventDetector: detector,
    );

    markKaActive(oldStations, start);
    markKaActive(newStations, start.add(const Duration(seconds: 20)));

    driver.processStations(oldStations, observedAt: start);
    final held = driver.processStations(
      newStations,
      observedAt: start.add(const Duration(seconds: 20)),
    );

    expect(held.eventId, 'event-a');
    expect(held.reasonCodes, contains('source_trigger_replacement_held'));
    expect(
      held.metadata['source_trigger_continuity_hold_reason'],
      'same_event_member_replacement',
    );
    final event = StationEventTracker.instance.currentNiedEvent.value;
    expect(event, isNotNull);
    expect(event!.metadata['source_trigger_member_ids'], [
      'OLD1',
      'OLD2',
      'OLD3',
      'OLD4',
    ]);
  });
}

class _PassThroughStationTriggerDetector implements StationTriggerDetector {
  const _PassThroughStationTriggerDetector();

  @override
  String get detectorId => 'pass_through_station_trigger_detector';

  @override
  StationTriggerSnapshot update(StationObservationFrame observation) {
    return StationTriggerSnapshot(
      stationId: observation.stationId,
      code: observation.code,
      sourceId: observation.sourceId,
      observedAt: observation.observedAt,
      state: StationTriggerState.triggered,
      latitude: observation.latitude,
      longitude: observation.longitude,
      intensity: observation.intensity,
      rawLevel: observation.rawLevel,
      detectLevel: observation.detectLevel,
    );
  }

  @override
  void resetStation(String stationId) {}

  @override
  void reset() {}
}

class _QueuedEventDetector implements EventDetector {
  final List<EventDetection> _events;
  int _index = 0;

  _QueuedEventDetector(this._events);

  @override
  String get detectorId => 'queued_event_detector';

  @override
  EventDetection update({
    required DateTime observedAt,
    required List<StationTriggerSnapshot> stations,
  }) {
    final event = _events[_index++];
    return EventDetection(
      detectorId: event.detectorId,
      sourceId: event.sourceId,
      eventId: event.eventId,
      state: event.state,
      observedAt: observedAt,
      startedAt: event.startedAt,
      updatedAt: observedAt,
      endedAt: event.endedAt,
      memberStationIds: event.memberStationIds,
      detectionScore: event.detectionScore,
      maxIntensity: event.maxIntensity,
      reasonCodes: event.reasonCodes,
      metadata: event.metadata,
    );
  }

  @override
  void reset() {
    _index = 0;
  }
}
