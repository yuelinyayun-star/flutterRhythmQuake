import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/palert_level_history.dart';
import 'package:flutterrhythmquake/services/sources/palert_wire_values.dart';
import 'package:flutterrhythmquake/services/sources/station_json_decoder.dart';
import 'package:flutterrhythmquake/services/sources/station_json_decoder_stub.dart'
    as stub;

void same(PAlertWireValues actual, PAlertWireValues expected) {
  expect(actual.validPgaCount, expected.validPgaCount);
  expect(actual.rows.length, expected.rows.length);
  final a = ByteData.sublistView(actual.rows);
  final b = ByteData.sublistView(expected.rows);
  for (var i = 0; i < actual.rows.length; i++) {
    if (expected.rows[i].isNaN) {
      expect(actual.rows[i].isNaN, isTrue, reason: 'row component $i');
    } else {
      expect(
        a.getUint64(i * 8, Endian.host),
        b.getUint64(i * 8, Endian.host),
        reason: 'row component $i',
      );
    }
  }
}

void main() {
  for (final native in [false, true]) {
    group(
      native ? 'Rust P-Alert fields' : 'Dart P-Alert fields',
      () {
        late StationJsonDecoder decoder;
        setUp(
          () => decoder = StationJsonDecoder(
            preferNative: native,
            prepareStationNumbers: false,
          ),
        );
        tearDown(() => decoder.dispose());

        test(
          '12 original response byte buffers, aligned history and snapshots',
          () {
            const path = 'test/fixtures/palert_cadence_20261014';
            final metadata =
                jsonDecode(
                      File('$path/station-list.json').readAsStringSync(),
                    )['data']['stationList']['staInfos']
                    as List;
            final ids = <String>{
              for (final item in metadata) item['station'].toString().trim(),
            }.toList();
            decoder.setPAlertStations(ids);
            final history = PAlertLevelHistory(useNative: native)
              ..setStations(ids);
            final expectedHistory = PAlertLevelHistory(useNative: false)
              ..setStations(ids);
            final saved = <PAlertWireResponse>[];
            final originals = <dynamic>[];
            try {
              for (var i = 0; i < 12; i++) {
                final bytes = File(
                  '$path/${i.toString().padLeft(2, '0')}.json',
                ).readAsBytesSync();
                final original = jsonDecode(utf8.decode(bytes));
                final wire = decoder.decodePAlertUtf8(bytes);
                same(wire.values, PAlertWireValues.fromJson(original, ids));
                final data = original['data'];
                final time = DateTime.parse(data['pga']['timestamp']);
                final pga = Map<String, double>.from(
                  (data['pga']['dataVals'] as Map).map(
                    (k, v) => MapEntry(k, (v as num).toDouble()),
                  ),
                );
                final pgv = Map<String, double>.from(
                  (data['pgv']['dataVals'] as Map).map(
                    (k, v) => MapEntry(k, (v as num).toDouble()),
                  ),
                );
                final aligned =
                    data['pga']['timestamp'] == data['pgv']['timestamp'];
                expect(
                  history.processWireValues(
                    time,
                    wire.values,
                    includePgv: aligned,
                  ),
                  expectedHistory.process(time, pga, aligned ? pgv : {}),
                );
                saved.add(wire);
                originals.add(original);
              }
              decoder.dispose();
              for (var i = 0; i < saved.length; i++) {
                expect(jsonEncode(saved[i].raw), jsonEncode(originals[i]));
                same(
                  saved[i].values,
                  PAlertWireValues.fromJson(originals[i], ids),
                );
              }
            } finally {
              history.clear();
              expectedHistory.clear();
            }
          },
        );

        test(
          'double grammar, Unicode trim, nonfinite, negative zero, integers and malformed values',
          () {
            final strings = [
              '0',
              '-0',
              '-.0',
              '.0',
              '0.',
              '-1.e3',
              '+.12e-9',
              '1234E+7',
              'NaN',
              '-NaN',
              '+NaN',
              'Infinity',
              '-Infinity',
              '+Infinity',
              'nan',
              'inf',
              'infinity',
              '0xFF',
              '1e',
              '.',
              '+',
              '--1',
              '1 2',
              '1_000',
              '1e9999999999999999999',
              '1e-999999999999999999',
              '2.2250738585072014e-308',
              '4.9406564584124654e-324',
              '1.7976931348623157e308',
              '9007199254740993',
              for (final unit in [
                9,
                10,
                11,
                12,
                13,
                32,
                0x85,
                0xa0,
                0x1680,
                0x2000,
                0x200a,
                0x2028,
                0x2029,
                0x202f,
                0x205f,
                0x3000,
                0xfeff,
                0x180e,
                0x200b,
                0,
                0xd800,
              ])
                '${String.fromCharCode(unit)}1.25${String.fromCharCode(unit)}',
            ];
            final values = <String, dynamic>{
              for (var i = 0; i < strings.length; i++) '$i': strings[i],
              'int': 9223372036854775807,
              'negative': -0.0,
              'null': null,
              'bool': true,
              'list': [1],
              'object': {'v': 2},
            };
            final ids = values.keys.toList();
            decoder.setPAlertStations(ids);
            final bytes = utf8.encode(
              jsonEncode({
                'data': {
                  'pga': {'dataVals': values},
                  'pgv': {'dataVals': values},
                },
              }),
            );
            final wire = decoder.decodePAlertUtf8(bytes);
            same(
              wire.values,
              PAlertWireValues.fromJson(jsonDecode(utf8.decode(bytes)), ids),
            );
            expect(() => wire.values.rows[0] = 1, throwsUnsupportedError);
          },
        );

        test(
          'last duplicate wins for fields, escaped IDs and unknown stations',
          () {
            final ids = ['a', '\uFEFF站点', '\uD800', 'a😀'];
            decoder.setPAlertStations(ids);
            const text =
                r'{"data":{"pga":{"dataVals":{"a":80,"\u0061":false,"unknown":1,"unknown":{},"missing":1,"\uFEFF站点":"\uFEFF-.0\u0085","\ud800":"NaN","a😀":"80"}},"pgv":{"dataVals":{"a":12,"a":null,"a😀":15}}},"data":{"pga":{"dataVals":{"a":80,"\u0061":false,"unknown":1,"unknown":{},"missing":1,"\uFEFF站点":"\uFEFF-.0\u0085","\ud800":"NaN","a😀":"80"}},"pgv":{"dataVals":{"a":12,"a":null,"a😀":15}}}}';
            final bytes = utf8.encode(text);
            final original = jsonDecode(text);
            final wire = decoder.decodePAlertUtf8(bytes);
            same(wire.values, PAlertWireValues.fromJson(original, ids));
            expect(wire.values.validPgaCount, 4);
            expect(wire.values.pga(0), isNull);
            expect(wire.values.pgv(3), 15);
            expect(jsonEncode(wire.raw), jsonEncode(original));
          },
        );

        test(
          'shape handling, directory reorder, empty layout and error recovery',
          () {
            decoder.setPAlertStations(['a', 'b']);
            final bytes = utf8.encode(
              r'{"data":{"pga":{"dataVals":{"a":80,"b":1}},"pgv":{"dataVals":{"a":140}}}}',
            );
            final saved = decoder.decodePAlertUtf8(bytes);
            expect(
              () => decoder.decodePAlertUtf8([
                123,
                34,
                120,
                34,
                58,
                34,
                255,
                34,
                125,
              ]),
              throwsFormatException,
            );
            final recovered = decoder.decodePAlertUtf8(bytes);
            same(recovered.values, saved.values);
            decoder.setPAlertStations(['b', 'new', 'a']);
            final reordered = decoder.decodePAlertUtf8(bytes);
            same(
              reordered.values,
              PAlertWireValues.fromJson(jsonDecode(utf8.decode(bytes)), [
                'b',
                'new',
                'a',
              ]),
            );
            for (final raw in [
              '[]',
              'null',
              '7',
              '{}',
              '{"data":[]}',
              '{"data":{"pga":{"dataVals":[]}}}',
            ]) {
              same(
                decoder.decodePAlertUtf8(utf8.encode(raw)).values,
                PAlertWireValues.fromJson(jsonDecode(raw), ['b', 'new', 'a']),
              );
            }
            decoder.setPAlertStations([]);
            expect(decoder.decodePAlertUtf8(bytes).values.rows, isEmpty);
            expect(
              () => decoder.setPAlertStations(['a', 'a']),
              throwsArgumentError,
            );
            expect(saved.values.pga(0), 80);
            expect(saved.values.pgv(0), 140);
          },
        );

        test(
          'skipped extraction preserves raw data and the following frame',
          () {
            decoder.setPAlertStations(['a']);
            final bytes = utf8.encode(
              r'{"data":{"pga":{"dataVals":{"a":80}}}}',
            );
            final skipped = decoder.decodePAlertUtf8(
              bytes,
              shouldExtract: (_) => false,
            );
            expect(skipped.hasValues, isFalse);
            expect(() => skipped.values, throwsStateError);
            expect(jsonEncode(skipped.raw), utf8.decode(bytes));
            expect(decoder.decodePAlertUtf8(bytes).values.pga(0), 80);
          },
        );

        test('mismatched PGV is excluded from the history input', () {
          decoder.setPAlertStations(['a']);
          final wire = decoder.decodePAlertUtf8(
            utf8.encode(
              r'{"data":{"pga":{"dataVals":{"a":80}},"pgv":{"dataVals":{"a":140}}}}',
            ),
          );
          final history = PAlertLevelHistory(useNative: native)
            ..setStations(['a']);
          try {
            expect(
              history.processWireValues(
                DateTime.utc(2026),
                wire.values,
                includePgv: false,
              ),
              [15, 15],
            );
          } finally {
            history.clear();
          }
        });
      },
      skip: native && !StationJsonDecoder.nativeSupported,
    );
  }

  test(
    'native owner released after failure and dispose',
    () {
      final baseline = StationJsonDecoder.diagnostics['sessions'];
      final decoder = StationJsonDecoder()..setPAlertStations(['a']);
      try {
        decoder.decodePAlertUtf8(utf8.encode('{}'));
        expect(StationJsonDecoder.diagnostics['sessions'], baseline! + 1);
        expect(
          () => decoder.decodePAlertUtf8(utf8.encode('{')),
          throwsFormatException,
        );
        expect(StationJsonDecoder.diagnostics['sessions'], baseline);
        decoder.decodePAlertUtf8(utf8.encode('{}'));
        decoder.dispose();
        decoder.dispose();
        expect(StationJsonDecoder.diagnostics['sessions'], baseline);
      } finally {
        decoder.dispose();
      }
    },
    skip: !StationJsonDecoder.nativeSupported,
  );

  test('non-IO stub exposes identical field interface', () {
    final decoder = stub.StationJsonDecoder()..setPAlertStations(['a']);
    final raw = {
      'data': {
        'pga': {
          'dataVals': {'a': '80'},
        },
        'pgv': {
          'dataVals': {'a': 140},
        },
      },
    };
    same(
      decoder.decodePAlertUtf8(utf8.encode(jsonEncode(raw))).values,
      PAlertWireValues.fromJson(raw, ['a']),
    );
    decoder.dispose();
  });
}
