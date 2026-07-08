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
        ..detectLevel = level
        ..lastUpdate = observedAt
        ..lastDataTime = observedAt;
      if (withGif) {
        station.continuousShindo = level >= 0 ? (level + 0.5 - 7) / 2 : -3.0;
      }
    }
  }

  test('source driver starts tracker from independent source trigger', () {
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
    final event = StationEventTracker.instance.currentNiedEvent.value;
    expect(event, isNotNull);
    expect(
      event!.metadata['source_trigger_detector_id'],
      'spatiotemporal_event_detector_v1_source_trigger',
    );
    expect(
      event.records.every((record) => record.firstTriggerAt != null),
      isTrue,
    );
    expect(
      event.records.every(
        (record) =>
            record.firstTriggerInterval != null &&
            !record.firstTriggerInterval!.end.isBefore(
              record.firstTriggerInterval!.start,
            ),
      ),
      isTrue,
    );
  });

  test(
    'source trigger auto-starts replay logger when debug switch is enabled',
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

      final records = NiedReplayLogger.instance.debugRecords;
      expect(NiedReplayLogger.instance.isEnabled, isTrue);
      expect(
        records.any((record) => record['type'] == 'source_trigger'),
        isTrue,
      );
      expect(records.any((record) => record['type'] == 'epicenter'), isFalse);
    },
  );

  test('GIF direct input uses Dart hypocenter snapshot metadata', () {
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

    final event = StationEventTracker.instance.currentNiedEvent.value;
    expect(event, isNotNull);
    expect(event!.eventId, startsWith('nied-gif-dart-'));
    expect(
      event.metadata['source_estimation_entry'],
      'dart_nied_hypocenter_direct',
    );
    expect(
      event.metadata['nied_hypocenter_input_format'],
      'nied_station_hypocenter_snapshot_v1',
    );
    expect(event.metadata.containsKey('kotoho7_receiver_frame_key'), isFalse);
    expect(
      event.metadata.containsKey('kotoho7_receiver_current_frame_observations'),
      isFalse,
    );
    expect(event.metadata['nied_hypocenter_new_active_stations'], isA<List>());
    expect(event.metadata['nied_hypocenter_active_stations'], isA<List>());
    expect(event.metadata['nied_hypocenter_inactive_stations'], isA<List>());
    expect(event.metadata['nied_hypocenter_adj_station_ids'], isA<Map>());
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
