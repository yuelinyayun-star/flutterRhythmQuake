import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_station_service.dart';
import 'package:flutterrhythmquake/widgets/map/fdsn_map_station_store.dart';

FdsnStation station(
  String code, {
  String source = 'EarthScope',
  DateTime? time,
}) => FdsnStation(
  network: 'XX',
  station: code,
  location: '',
  source: source,
  coordinate: const LatLng(30, 105),
  lastMotionUpdate: time,
);

void main() {
  test(
    'motion updates preserve original inputs and catalogue overlap order',
    () {
      final original = List.generate(20000, (i) => station('S$i'));
      final store = FdsnMapStationStore()..setSource('EarthScope', original);
      expect(store.displayStations({'EarthScope'}), isEmpty);
      final now = DateTime.now();
      for (final i in [15000, 1, 900, 5]) {
        store.update(
          original[i].copyWith(
            pga: 123,
            pgv: 4,
            intensity: 5.25,
            lastMotionUpdate: now,
          ),
        );
      }
      final displayed = store.displayStations({'EarthScope'});
      expect(
        identical(store.displayStations({'EarthScope'}), displayed),
        isTrue,
      );
      expect(() => displayed.clear(), throwsUnsupportedError);
      expect(displayed.map((s) => s.station), ['S1', 'S5', 'S900', 'S15000']);
      expect(
        displayed.every(
          (s) =>
              identical(s.lastMotionUpdate, now) &&
              s.pga == 123 &&
              s.intensity == 5.25,
        ),
        isTrue,
      );
      expect(
        original.every((s) => s.lastMotionUpdate == null && s.pga == null),
        isTrue,
      );
      expect(identical(store.find('EarthScope', 'XX.S2'), original[2]), isTrue);
    },
  );

  test('regional precedence, disabled source, expiry, refresh and removal', () {
    final now = DateTime.now();
    final earth = station('DUP', time: now);
    final regional = station('DUP', source: 'GeoNet', time: now);
    final store = FdsnMapStationStore()
      ..setSource('EarthScope', [earth])
      ..setSource('GeoNet', [regional]);
    expect(store.displayStations({'EarthScope', 'GeoNet'}), [regional]);
    expect(store.displayStations({'EarthScope'}), [earth]);
    store.update(
      regional.copyWith(
        lastMotionUpdate: now.subtract(const Duration(minutes: 4)),
      ),
    );
    expect(store.displayStations({'EarthScope', 'GeoNet'}), [earth]);
    store.update(regional.copyWith(lastMotionUpdate: now));
    expect(
      store.displayStations({'EarthScope', 'GeoNet'}).single.source,
      'GeoNet',
    );
    store.setSource('GeoNet', []);
    expect(store.displayStations({'EarthScope', 'GeoNet'}), [earth]);
    store.removeSource('EarthScope');
    store.update(earth);
    expect(store.displayStations({'EarthScope', 'GeoNet'}), isEmpty);
    store.clear();
    expect(store.isNotEmpty, isFalse);
  });

  test('cached snapshot expires without incoming data', () async {
    final end = DateTime.now().add(const Duration(milliseconds: 100));
    final store = FdsnMapStationStore()
      ..setSource('EarthScope', [
        station('OLD', time: end.subtract(FdsnStation.motionRetention)),
      ]);
    expect(store.displayStations({'EarthScope'}), hasLength(1));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(store.displayStations({'EarthScope'}), isEmpty);
  });

  test('catalogue update workload compared with prior full-list copying', () {
    final now = DateTime.now();
    final sources = [for (var i = 0; i < 7; i++) 'SOURCE$i'];
    final catalogues = {
      for (final source in sources)
        source: [
          for (var i = 0; i < 4000; i++) station('$source-$i', source: source),
        ],
    };
    final indices = {
      for (final source in sources)
        source: {
          for (var i = 0; i < 4000; i++)
            '$source:${catalogues[source]![i].code}': i,
        },
    };
    final samples = {
      for (final source in sources)
        for (var i = 0; i < 700; i++)
          '$source:${catalogues[source]![i].code}': catalogues[source]![i]
              .copyWith(
                pga: 2.5,
                pgv: 1.25,
                intensity: 3.1,
                lastMotionUpdate: now,
              ),
    };
    var legacy = {...catalogues};
    final store = FdsnMapStationStore();
    for (final source in sources) {
      store.setSource(source, catalogues[source]!);
    }
    List<FdsnStation> previous = [], next = [];
    final oldTimes = <int>[], newTimes = <int>[];
    for (var iteration = 0; iteration < 40; iteration++) {
      final watch = Stopwatch()..start();
      for (final source in sources) {
        List<FdsnStation>? updated;
        for (final entry in samples.entries) {
          final index = indices[source]![entry.key];
          if (index == null) continue;
          updated ??= List.of(legacy[source]!, growable: false);
          updated[index] = entry.value;
        }
        if (updated != null) legacy[source] = updated;
      }
      previous = deduplicateFdsnStations([
        for (final source in sources) ...legacy[source]!,
      ]);
      final oldMicros = watch.elapsedMicroseconds;
      watch
        ..reset()
        ..start();
      for (final s in samples.values) {
        store.update(s);
      }
      next = store.displayStations(sources.toSet());
      if (iteration >= 10) {
        oldTimes.add(oldMicros);
        newTimes.add(watch.elapsedMicroseconds);
      }
    }
    expect(next, orderedEquals(previous));
    oldTimes.sort();
    newTimes.sort();
    // Local test-process benchmark, not a Release CPU or FPS claim.
    debugPrint(
      'FDSN store 28000 catalogue / 4900 active median: before=${oldTimes[15]}us after=${newTimes[15]}us',
    );
  });
}
