import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/nied_station_topology.dart';
import 'package:flutterrhythmquake/services/sources/native_topology_sort.dart';

import 'support/nied_replay_fixture.dart';
import 'support/nied_topology_reference.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'both neighbour rules equal frozen implementation on original stations',
    () async {
      final file = File(
        'tmp/captures/20260610_180130_jst_nara_m36/20260610180120.lmoni.jma_s.gif',
      );
      if (!file.existsSync()) {
        markTestSkipped('Requires original Nara capture.');
        return;
      }
      final service = LmoniImageService()..start();
      addTearDown(service.stop);
      final frame = (await decodeNiedGifFile(file))!;
      final next = service.stationStream.firstWhere((value) => value != null);
      service.processPixels(
        frame.packedRgb,
        dataTime: DateTime(2026, 6, 10, 18, 1, 20),
      );
      final stations = (await next)!;
      expect(stations.map((s) => s.id).toSet().length, stations.length);
      final legacyClock = Stopwatch()..start();
      final reference = NiedTopologyReference();
      final expectedHyp = reference.hypocenter(stations);
      final expectedDetection = reference.detection(stations);
      legacyClock.stop();
      final clock = Stopwatch()..start();
      final sortCalls = NativeTopologySort.supported
          ? NativeTopologySort.calls
          : 0;
      final topology = NiedStationTopology.fromStations(stations);
      clock.stop();
      if (NativeTopologySort.supported) {
        expect(NativeTopologySort.calls - sortCalls, stations.length);
      }
      expect(topology.hypocenterAdjacentIds, expectedHyp);
      expect(topology.detectionAdjacentCodes, expectedDetection);
      expect(topology.matchesStations(stations), isTrue);
      expect(
        topology.matchesStations(
          stations.map(NiedStation.detachedSnapshot).toList(),
        ),
        isTrue,
      );
      expect(topology.matchesStations(stations.reversed.toList()), isFalse);
      expect(topology.matchesStations(stations.skip(1).toList()), isFalse);
      expect(
        () => topology.detectionAdjacentCodes.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => topology.hypocenterAdjacentIds.values.first.clear(),
        throwsUnsupportedError,
      );
      // Original catalogue data, in a different order, must produce the same rules.
      final reordered = stations.reversed.toList();
      final reversedReference = NiedTopologyReference();
      final reversedTopology = NiedStationTopology.fromStations(reordered);
      expect(
        reversedTopology.hypocenterAdjacentIds,
        reversedReference.hypocenter(reordered),
      );
      expect(
        reversedTopology.detectionAdjacentCodes,
        reversedReference.detection(reordered),
      );
      final output = Platform.environment['RQ_TOPOLOGY_MEASUREMENTS'];
      if (output != null) {
        await File(output).writeAsString(
          jsonEncode({
            'stations': stations.length,
            'referenceUs': legacyClock.elapsedMicroseconds,
            'refactoredUs': clock.elapsedMicroseconds,
            'allNeighbourListsExactlyEqual': true,
          }),
        );
      }
      // ignore: avoid_print
      print(
        'NIED_TOPOLOGY stations=${stations.length} referenceUs=${legacyClock.elapsedMicroseconds} refactoredUs=${clock.elapsedMicroseconds}',
      );
    },
  );
}
