import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/debug/native_station_archive.dart';
import 'package:flutterrhythmquake/services/debug/station_archive_storage.dart';
import 'package:flutterrhythmquake/services/debug/station_json_archive.dart';

void sameValues(dynamic actual, dynamic expected) {
  if (expected is Map) {
    expect(actual, isA<Map>());
    expect((actual as Map).keys.toList(), expected.keys.toList());
    for (final key in expected.keys) {
      sameValues(actual[key], expected[key]);
    }
  } else if (expected is List) {
    expect(actual, isA<List>());
    expect((actual as List).length, expected.length);
    for (var i = 0; i < expected.length; i++) {
      sameValues(actual[i], expected[i]);
    }
  } else if (expected is double) {
    expect(actual, isA<double>());
    final a = ByteData(8)..setFloat64(0, actual as double);
    final b = ByteData(8)..setFloat64(0, expected);
    expect(a.getUint64(0), b.getUint64(0));
  } else {
    expect(actual.runtimeType, expected.runtimeType);
    expect(actual, expected);
  }
}

void main() {
  test('native JSON table preserves scalar types, float bits and UTF16', () {
    if (!NativeStationArchive.supported) {
      markTestSkipped('Native DLL required');
      return;
    }
    final values = <double>[
      0.0,
      -0.0,
      1.0,
      -1.0,
      5e-324,
      1.7976931348623157e308,
      1e-300,
      1e300,
    ];
    final random = Random(192);
    final bits = ByteData(8);
    for (var i = 0; i < 10000; i++) {
      bits.setUint32(0, random.nextInt(0x100000000));
      bits.setUint32(4, random.nextInt(0x100000000));
      final value = bits.getFloat64(0);
      if (value.isFinite) values.add(value);
    }
    final input = <String, dynamic>{
      'receivedAt': '2026-10-13T11:44:30.004673Z',
      'snapshot': {
        'kind': 'nied',
        'stations': [
          {
            '中文': '紀伊水道',
            'unicode': '🎼\u0000"\\\n',
            'units': String.fromCharCodes([0xd800, 65, 0xdc00]),
            'ints': [0, 1, -1, 0x7fffffffffffffff, -0x8000000000000000],
            'floats': values,
            'null': null,
            'bool': [false, true],
          },
        ],
      },
    };
    final before = jsonEncode(input);
    final output =
        jsonDecode(utf8.decode(NativeStationArchive.encode([input]))) as Map;
    final decoded = StationJsonArchive.decode(output);
    sameValues(decoded.single.toMap(), input);
    expect(jsonEncode(input), before);
    expect(NativeStationArchive.sessions, 0);
    sameValues(
      StationArchiveStorage.decode(
        StationArchiveStorage.wrapCompressed(
          NativeStationArchive.encodeCompressed([input]),
        ),
      ),
      output,
    );
    sameValues(
      StationArchiveStorage.decode(
        StationArchiveStorage.encodeBytes(NativeStationArchive.encode([input])),
      ),
      output,
    );
  });

  test('native codec rejects unsupported JSON and releases owners', () {
    if (!NativeStationArchive.supported) {
      markTestSkipped('Native DLL required');
      return;
    }
    for (final bad in [
      double.nan,
      double.infinity,
      DateTime(2026),
      {1: 'key'},
    ]) {
      expect(
        () => NativeStationArchive.encode([
          {'bad': bad},
        ]),
        throwsA(anything),
      );
      expect(NativeStationArchive.sessions, 0);
    }
    expect(
      jsonDecode(utf8.decode(NativeStationArchive.encode([])))['frames'],
      isEmpty,
    );
  });

  test(
    'saved original station archives round trip through native indexing',
    () {
      if (!NativeStationArchive.supported) {
        markTestSkipped('Native DLL required');
        return;
      }
      final path = File('tmp/nied-regression-active.json');
      if (!path.existsSync()) {
        markTestSkipped('Saved original capture required');
        return;
      }
      final stage = jsonDecode(path.readAsStringSync())['stage'] as String;
      final selected = <String, int>{};
      var frames = 0;
      for (final file in Directory(
        '$stage/station-history',
      ).listSync().whereType<File>()) {
        final record = jsonDecode(file.readAsStringSync()) as Map;
        final key = record['key'] as String;
        final kind = [
          'nied',
          'cwa',
          'palert',
        ].where((kind) => key.contains('_archive_${kind}_')).firstOrNull;
        if (kind == null || (selected[kind] ?? 0) >= 3) continue;
        final original = StationJsonArchive.decode(
          StationArchiveStorage.decode(record['value'] as String),
        );
        final input = [for (final frame in original) frame.toMap()];
        final native = StationJsonArchive.decode(
          jsonDecode(utf8.decode(NativeStationArchive.encode(input))) as Map,
        );
        sameValues([for (final frame in native) frame.toMap()], input);
        final compressed = StationJsonArchive.decode(
          StationArchiveStorage.decode(
            StationArchiveStorage.wrapCompressed(
              NativeStationArchive.encodeCompressed(input),
            ),
          ),
        );
        sameValues([for (final frame in compressed) frame.toMap()], input);
        selected[kind] = (selected[kind] ?? 0) + 1;
        frames += original.length;
      }
      expect(selected, {'nied': 3, 'cwa': 3, 'palert': 3});
      expect(frames, greaterThan(0));
      expect(NativeStationArchive.sessions, 0);
    },
  );
}
