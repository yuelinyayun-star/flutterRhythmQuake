import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutterrhythmquake/core/source_estimation/station_event_tracker.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_observation.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';

void main() {
  final tracker = StationEventTracker.instance;

  setUp(() {
    tracker.resetNied();
  });

  NiedStation buildStation({
    required String code,
    required double lat,
    required double lng,
    int level = 8,
    int detectLevel = 7,
    double shindo = 0.2,
    double activity = 10,
    int ascend = 2,
    bool isActive = true,
  }) {
    final station = NiedStation(
      id: 1,
      code: code,
      name: code,
      coordinate: LatLng(lat, lng),
      network: 'K-NET',
      prefecture: 'Test',
      expireSeconds: 10,
    );
    station
      ..level = level
      ..detectLevel = detectLevel
      ..continuousShindo = shindo
      ..updateGifObservation(
        NiedGifObservation(shindo: shindo, pga: 0.12, pgv: 0.034, pgd: 0.0045),
      )
      ..activity = activity
      ..ascend = ascend
      ..isActive = isActive
      ..lastUpdate = DateTime(2026, 6, 10, 12, 0, 0);
    return station;
  }

  test('creates active NIED event and computes baseline estimate', () {
    final stations = [
      buildStation(code: 'AAA001', lat: 35.0, lng: 140.0, shindo: 0.3),
      buildStation(code: 'AAA002', lat: 35.2, lng: 140.2, shindo: 0.5),
    ];

    tracker.ingestNiedFrame(
      stations: stations,
      observedAt: DateTime(2026, 6, 10, 12, 0, 0),
      stageName: 'detected',
      maxShindo: 1,
    );

    final event = tracker.currentNiedEvent.value;
    expect(event, isNotNull);
    expect(event!.stageName, 'detected');
    expect(event.stationRecords.length, 2);
    expect(event.records.every((r) => r.firstTriggerAt != null), isTrue);
    expect(event.records.first.lastPga, isNotNull);
    expect(event.records.first.lastPgv, isNotNull);
    expect(event.records.first.lastPgd, isNotNull);
    expect(event.estimate, isNotNull);
  });

  test('uses detectLevel midpoint when gif observation is absent', () {
    final station =
        NiedStation(
            id: 1,
            code: 'YAH001',
            name: 'YAH001',
            coordinate: const LatLng(35.0, 140.0),
            network: 'K-NET',
            prefecture: 'Test',
            expireSeconds: 10,
          )
          ..level = 12
          ..detectLevel = 11
          ..activity = 6
          ..ascend = 2
          ..isActive = true
          ..lastUpdate = DateTime(2026, 6, 10, 12, 0, 0);

    tracker.ingestNiedFrame(
      stations: [station],
      observedAt: DateTime(2026, 6, 10, 12, 0, 0),
      stageName: 'detected',
      maxShindo: 2,
    );

    final event = tracker.currentNiedEvent.value;
    expect(event, isNotNull);
    expect(event!.records.single.lastValue, closeTo(2.25, 1e-9));
    expect(event.estimate, isNull);
  });

  test('closes current NIED event when stage returns to idle', () {
    final activeStations = [
      buildStation(code: 'AAA001', lat: 35.0, lng: 140.0),
      buildStation(code: 'AAA002', lat: 35.2, lng: 140.2),
    ];
    tracker.ingestNiedFrame(
      stations: activeStations,
      observedAt: DateTime(2026, 6, 10, 12, 0, 0),
      stageName: 'detected',
      maxShindo: 1,
    );

    final idleStations = activeStations
        .map((station) {
          station
            ..isActive = false
            ..activity = 0
            ..ascend = 0
            ..detectLevel = -1
            ..level = -1
            ..lastUpdate = DateTime(2026, 6, 10, 12, 0, 5);
          return station;
        })
        .toList(growable: false);

    tracker.ingestNiedFrame(
      stations: idleStations,
      observedAt: DateTime(2026, 6, 10, 12, 0, 5),
      stageName: 'idle',
      maxShindo: -1,
    );

    expect(tracker.currentNiedEvent.value, isNull);
    expect(tracker.niedEventHistory.value, isNotEmpty);
    expect(tracker.niedEventHistory.value.first.isClosed, isTrue);
  });
}
