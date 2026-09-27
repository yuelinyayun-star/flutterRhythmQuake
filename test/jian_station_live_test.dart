import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/jian_station_service.dart';
import 'package:flutterrhythmquake/services/sources/whews_nied_station_metadata.dart';
import 'package:flutterrhythmquake/services/sources/whews_station_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const runLive = bool.fromEnvironment('JIAN_STATION_LIVE');

  for (final kind in WhewsStationKind.values) {
    test('Jian $kind publishes a current station frame', () async {
      final service = JianStationService(kind: kind);
      try {
        final nextFrame = service.frameStream.first.timeout(
          const Duration(seconds: 25),
        );
        service.start();
        final frame = await nextFrame;
        expect(frame.source, 'jian');
        expect(frame.kind, kind);
        expect(frame.coordinates, isNotEmpty);
        expect(frame.values.length, frame.coordinates.length);
        expect(frame.codes.length, frame.coordinates.length);
        expect(frame.names.length, frame.coordinates.length);
        expect(frame.regions.length, frame.coordinates.length);
        expect(frame.stationTypes.length, frame.coordinates.length);
        if (kind == WhewsStationKind.nied) {
          expect(frame.codes.every((code) => code.isNotEmpty), isTrue);
          expect(frame.names.every((name) => name.isNotEmpty), isTrue);
          expect(frame.regions.every((region) => region.isNotEmpty), isTrue);
          expect(frame.stationTypes.every((type) => type.isNotEmpty), isTrue);
          await loadWhewsNiedPrefectures();
          final stations = buildWhewsNiedStations(
            frame.coordinates,
            source: frame.source,
            codes: frame.codes,
            names: frame.names,
            regions: frame.regions,
            stationTypes: frame.stationTypes,
          );
          expect(stations, hasLength(frame.coordinates.length));
          for (var index = 0; index < stations.length; index++) {
            expect(stations[index].code, frame.codes[index]);
            expect(stations[index].name, frame.names[index]);
            expect(stations[index].prefecture, frame.regions[index]);
            expect(stations[index].network, frame.stationTypes[index]);
          }
        }
        expect(
          DateTime.now().toUtc().difference(frame.dataTime).inSeconds.abs(),
          lessThan(kind == WhewsStationKind.snet ? 180 : 90),
        );
      } finally {
        service.dispose();
      }
    }, skip: !runLive);
  }
}
