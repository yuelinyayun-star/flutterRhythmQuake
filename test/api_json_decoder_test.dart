import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/source_payload.dart';
import 'package:flutterrhythmquake/services/sources/api_json_decoder.dart';
import 'package:flutterrhythmquake/services/sources/station_json_decoder.dart';

void main() {
  tearDown(disposeApiJsonResources);
  test('parser teardown leaves the returned graph usable', () {
    if (!StationJsonDecoder.nativeSupported) return;
    final before = StationJsonDecoder.diagnostics['sessions'];
    final graph = decodeApiJson('{"a":[1,{"x":"日本語"}]}');
    expect(StationJsonDecoder.diagnostics['sessions'], before! + 1);
    disposeApiJsonResources();
    expect(StationJsonDecoder.diagnostics['sessions'], before);
    graph['a'][1]['x'] = 'changed';
    expect(jsonEncode(graph), '{"a":[1,{"x":"changed"}]}');
  });

  test('literal UTF16 and escaped keys retain exact values and types', () {
    for (final raw in [
      '{"a":1,"\\u0061":2,"x":"\\ud800"}',
      '{"a":"${String.fromCharCode(0xd800)}","b":"😀"}',
      '[1,1.0,-0.0,9223372036854775808,1e999]',
    ]) {
      final actual = decodeApiJson(raw);
      final expected = jsonDecode(raw);
      // Nonfinite primitives cannot be JSON-encoded, compare original types
      // and values directly for that language-contract case.
      expect(actual, expected);
      if (actual is List) {
        expect(
          actual.map((value) => value.runtimeType),
          (expected as List).map((value) => value.runtimeType),
        );
        expect((actual[2] as double).isNegative, isTrue);
      }
    }
  });
  test('complete stored JSON corpus retains original values and order', () {
    var checked = 0;
    for (final file in Directory('test/fixtures').listSync(recursive: true)) {
      if (file is! File ||
          !(file.path.endsWith('.json') || file.path.endsWith('.geojson'))) {
        continue;
      }
      final raw = file.readAsStringSync();
      dynamic expected;
      try {
        expected = jsonDecode(raw);
      } on FormatException {
        expect(
          () => decodeApiJson(raw),
          throwsFormatException,
          reason: file.path,
        );
        continue;
      }
      final actual = decodeApiJson(raw);
      expect(jsonEncode(actual), jsonEncode(expected), reason: file.path);
      checked++;
    }
    expect(checked, greaterThan(100));
  });

  test(
    'nested references, original fields and growable mutations match Dart',
    () {
      const raw = '{"a":[{"x":1},2],"b":{"c":3},"null":null}';
      final actual = decodeApiJson(raw) as Map<String, dynamic>;
      final expected = jsonDecode(raw) as Map<String, dynamic>;
      final child = actual['a'][0];
      expect(identical(child, actual['a'][0]), isTrue);
      void change(Map<String, dynamic> value) {
        value['a'][0]['x'] = -0.0;
        (value['a'] as List).add({'new': '日本語😀'});
        (value['a'] as List).insert(0, false);
        (value['a'] as List).removeAt(2);
        (value['b'] as Map).remove('c');
        value['b']['new'] = null;
        value.remove('null');
        value['unknown'] = [1.0, null];
      }

      change(actual);
      change(expected);
      expect(jsonEncode(actual), jsonEncode(expected));
      expect(child['x'], -0.0);
      (actual['a'] as List).length = 7;
      (expected['a'] as List).length = 7;
      expect(jsonEncode(actual), jsonEncode(expected));
      (actual['a'] as List).clear();
      (expected['a'] as List).clear();
      expect(jsonEncode(actual), jsonEncode(expected));
      final copy = decodeApiJson(raw);
      expect(jsonEncode(copy), raw);
    },
  );

  test('map live keys, duplicate order and iterator mutation match Dart', () {
    final map = decodeApiJson('{"a":1,"b":2,"a":3}') as Map;
    expect(map.keys.toList(), ['a', 'b']);
    expect(map['a'], 3);
    final keys = map.keys;
    final iterator = keys.iterator;
    expect(iterator.moveNext(), isTrue);
    map['a'] = 4;
    expect(iterator.moveNext(), isTrue);
    map['c'] = 5;
    expect(keys.toList(), ['a', 'b', 'c']);
    expect(iterator.moveNext, throwsConcurrentModificationError);
    map.clear();
    expect(keys, isEmpty);
  });

  test('snapshot is frozen independently of later parser graph mutations', () {
    final map = decodeApiJson('{"a":[{"x":1}],"b":2}') as Map<String, dynamic>;
    final snapshot = snapshotSourcePayload(map);
    map['a'][0]['x'] = 99;
    map['b'] = 3;
    expect(jsonEncode(snapshot), '{"a":[{"x":1}],"b":2}');
    expect(() => snapshot['a'][0]['x'] = 4, throwsUnsupportedError);
    final changed = snapshotSourcePayload(map);
    expect(jsonEncode(changed), '{"a":[{"x":99}],"b":3}');
    map['a'][0]['x'] = 100;
    expect(changed['a'][0]['x'], 99);
    expect(() => changed['a'][0]['x'] = 0, throwsUnsupportedError);
  });

  test(
    'invalid input releases native owners and does not poison later APIs',
    () {
      if (!StationJsonDecoder.nativeSupported) return;
      final sessions = StationJsonDecoder.diagnostics['sessions'];
      for (var i = 0; i < 30; i++) {
        expect(() => decodeApiJson('{"a":['), throwsFormatException);
        final frame = decodeApiJson('{"a":[1,2,3]}');
        expect(frame['a'], [1, 2, 3]);
        disposeApiJsonResources();
        expect(StationJsonDecoder.diagnostics['sessions'], sessions);
      }
    },
  );
}
