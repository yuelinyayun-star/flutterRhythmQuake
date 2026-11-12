import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/source_payload.dart';
import 'package:flutterrhythmquake/services/sources/native_station_core_library_io.dart';
import 'package:flutterrhythmquake/services/sources/station_json_decoder_io.dart';

void sameJson(dynamic actual, dynamic expected) {
  expect(actual.runtimeType == int, expected.runtimeType == int);
  if (expected is double) {
    expect(actual, isA<double>());
    final a = ByteData(8)..setFloat64(0, actual as double);
    final b = ByteData(8)..setFloat64(0, expected);
    expect(a.getUint64(0), b.getUint64(0));
  } else if (expected is Map) {
    expect(actual, isA<Map>());
    expect((actual as Map).keys.toList(), expected.keys.toList());
    for (final key in expected.keys) {
      sameJson(actual[key], expected[key]);
    }
  } else if (expected is List) {
    expect(actual, isA<List>());
    expect((actual as List).length, expected.length);
    for (var i = 0; i < expected.length; i++) {
      sameJson(actual[i], expected[i]);
    }
  } else {
    expect(actual, expected);
  }
}

void main() {
  final native = StationCoreLibrary.supported;
  test(
    'dense unique numbers and repeated mixed literals retain every original item',
    () {
      final decoder = StationJsonDecoder();
      addTearDown(decoder.dispose);
      for (final raw in [
        '[${List.generate(2000, (i) => '$i.125').join(',')}]',
        '[${List.generate(2000, (i) => i % 2 == 0 ? '1.0' : '1e0').join(',')}]',
        '[1,1,1.0,0,-0,0.0,-0.0,1.000,1e0,2,1]',
      ]) {
        sameJson(decoder.decode(raw), jsonDecode(raw));
      }
    },
  );
  test(
    'unchanged source captures retain every ordered field and numeric bit',
    () {
      final decoder = StationJsonDecoder();
      addTearDown(decoder.dispose);
      for (final path in [
        'test/fixtures/whews_nied/stations.json',
        'test/fixtures/whews_nied/observations.json',
        'test/fixtures/jian/all.json',
        'test/fixtures/jian/jmalist_response.json',
        'test/fixtures/catalog_20260917/whews_all.json',
        'test/fixtures/catalog_20260917/jian_all.json',
      ]) {
        final raw = File(path).readAsStringSync();
        final decoded = decoder.decode(raw);
        sameJson(decoded, jsonDecode(raw));
        expect(jsonEncode(decoded), jsonEncode(jsonDecode(raw)), reason: path);
        final snapshot = decoded is Map
            ? snapshotSourcePayload(Map<String, dynamic>.from(decoded))
            : snapshotSourcePayloadList(decoded as List<dynamic>);
        sameJson(snapshot, decoded);
      }
    },
  );
  test(
    'JSON primitive contracts preserve signed bounds, negative zero and UTF16',
    () {
      final decoder = StationJsonDecoder();
      addTearDown(decoder.dispose);
      for (final raw in [
        'null',
        'true',
        'false',
        '-0',
        '-0.0',
        '1e999',
        '-1e999',
        '9223372036854775807',
        '-9223372036854775808',
        '9223372036854775808',
        '-9223372036854775809',
        '5e-324',
        '2.2250738585072014e-308',
        '1.7976931348623157e308',
        r'"\ud800\udfff\ud800\u0000\n\r\t\/\\\""',
        '"${String.fromCharCodes([0xd800, 0xffff, 0xdc00])}"',
        r'{"a":1,"b":0,"a":2,"日本語":"中文🌏","empty":[{},[]]}',
      ]) {
        sameJson(decoder.decode(raw), jsonDecode(raw));
      }
      final random = Random(20261015);
      for (var i = 0; i < 5000; i++) {
        final raw =
            '${random.nextBool() ? '-' : ''}${random.nextInt(1000000000)}.${random.nextInt(1000000000)}e${random.nextInt(650) - 325}';
        sameJson(decoder.decode(raw), jsonDecode(raw));
      }
    },
  );
  test(
    'invalid JSON is rejected and a subsequent complete frame is independent',
    () {
      final decoder = StationJsonDecoder();
      addTearDown(decoder.dispose);
      for (final raw in [
        '',
        '[1,]',
        '{"x":}',
        '01',
        '1.',
        '1e',
        'true false',
        '\ufeff{}',
        r'"\u00xz"',
        '"\n"',
        '[',
        '{',
      ]) {
        expect(() => decoder.decode(raw), throwsFormatException, reason: raw);
        sameJson(decoder.decode('{"ok":true}'), {'ok': true});
      }
    },
  );
  test(
    'snapshots survive buffer reuse and disposal and reject nested mutation',
    () {
      final decoder = StationJsonDecoder();
      final original =
          decoder.decode('{"x":[1,{"name":"日本語"}]}') as Map<String, dynamic>;
      final snapshot = snapshotSourcePayload(original);
      decoder.decode('{"completely":"different"}');
      decoder.dispose();
      sameJson(snapshot, {
        'x': [
          1,
          {'name': '日本語'},
        ],
      });
      expect(() => snapshot['x'] = 1, throwsUnsupportedError);
      expect(() => (snapshot['x'] as List)[0] = 2, throwsUnsupportedError);
      expect(
        () => ((snapshot['x'] as List)[1] as Map).clear(),
        throwsUnsupportedError,
      );
      if (native) {
        expect(identical(snapshot, original), isTrue);
      }
    },
  );
  test('all native allocations are released on dispose', () {
    final memory = StationCoreLibrary.library
        .lookupFunction<Uint64 Function(), int Function()>(
          'rq_station_memory_current',
        );
    final warm = StationJsonDecoder()..decode('{}');
    warm.dispose();
    final baseline = memory();
    for (var i = 0; i < 100; i++) {
      final decoder = StationJsonDecoder()..decode('{"x":[1,2,3]}');
      decoder.dispose();
      expect(StationJsonDecoder.diagnostics['sessions'], 0);
      expect(memory(), baseline);
    }
  }, skip: !native);
}
