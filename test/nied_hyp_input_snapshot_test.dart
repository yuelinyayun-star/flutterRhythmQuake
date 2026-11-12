import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/core/source_estimation/nied_hyp_input_snapshot.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';

void main() {
  test('typed NIED view exports original fields, bits and local times', () {
    final station = NiedStationDb.stations.first;
    final latitude = (station['lat'] as num).toDouble();
    final longitude = (station['lng'] as num).toDouble();
    // Boundary inputs test the transport contract, not event performance.
    for (final stamp in [null, -1, 0, 1, 1791522664003]) {
      final snapshot = NiedHypStationSnapshot(
        stationId: 0,
        code: station['code'] as String,
        coordinate: LatLng(latitude, longitude),
        triggerStamp: stamp,
        updateStamp: 1791522664003,
        ascend: 2,
        level: 7,
        currentShindo: -0.0,
        active: true,
      );
      final original = <String, Object?>{
        'id': 0,
        'code': station['code'],
        'latLng': [latitude, longitude],
        'triggerStamp': stamp,
        'updateStamp': 1791522664003,
        'ascend': 2,
        'level': 7,
        'shindo': -0.0,
        'isActive': true,
      };
      expect(jsonEncode(snapshot), jsonEncode(original));
      expect(snapshot.keys, original.keys);
      expect(snapshot.containsKey('triggerStamp'), isTrue);
      expect(snapshot.containsKey('unknown'), isFalse);
      expect(snapshot.id, '0');
      expect(
        snapshot.triggerAt?.millisecondsSinceEpoch,
        stamp != null && stamp > 0 ? stamp : null,
      );
      expect(
        snapshot.triggerAt?.isUtc,
        stamp != null && stamp > 0 ? false : null,
      );
      expect(snapshot.updateAt!.isUtc, isFalse);
      final bits = ByteData(8)..setFloat64(0, snapshot.currentShindo!);
      expect(bits.getUint64(0), 0x8000000000000000);
      expect(() => snapshot['level'] = 8, throwsUnsupportedError);
      expect(() => (snapshot['latLng'] as List)[0] = 0.0, throwsUnsupportedError);
    }
  });

  test('only an owned immutable adjacency may retain its parsed view', () {
    final original = <String, List<int>>{
      '0': [2, 1, 2],
      '1': [0],
    };
    final snapshot = NiedHypAdjacencySnapshot<int>(original);
    final parsed = snapshot.parsed;
    original['0']!.clear();
    original['new'] = [7];
    expect(snapshot['0'], [2, 1, 2]);
    expect(parsed['0']!.toList(), ['2', '1']);
    expect(identical(parsed, snapshot.parsed), isTrue);
    expect(snapshot.containsKey('new'), isFalse);
    expect(() => snapshot['0']!.add(3), throwsUnsupportedError);
    expect(() => parsed['0']!.add('3'), throwsUnsupportedError);
    expect(() => parsed['new'] = {'7'}, throwsUnsupportedError);
    expect(() => snapshot.clear(), throwsUnsupportedError);
  });

  test(
    'snapshot and parsed adjacency cross isolates without native owners',
    () async {
      final snapshot = NiedHypStationSnapshot(
        stationId: 1,
        code: 'boundary-contract',
        coordinate: const LatLng(35, 139),
        triggerStamp: 1,
        updateStamp: 2,
        ascend: 2,
        level: 7,
        currentShindo: 0,
        active: true,
      );
      final adjacency = NiedHypAdjacencySnapshot<int>({
        '1': [1],
      });
      final parsed = adjacency.parsed;
      snapshot.triggerAt; // Also exercise already initialized lazy fields.
      final exported = await Isolate.run(
        () => [
          jsonEncode(snapshot),
          jsonEncode(adjacency),
          parsed['1']!.toList(),
          snapshot.triggerAt!.microsecondsSinceEpoch,
        ],
      );
      expect(exported, [
        jsonEncode(snapshot),
        '{"1":[1]}',
        ['1'],
        1000,
      ]);
    },
  );
}
