import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutterrhythmquake/models/source_payload.dart';
import 'package:flutterrhythmquake/services/sources/api_json_decoder.dart';
import 'package:flutterrhythmquake/services/sources/station_json_decoder.dart';

void main() {
  tearDown(disposeApiJsonResources);
  test(
    'all original JSON and GeoJSON bytes match the original UTF8/String path',
    () {
      var count = 0;
      for (final file in Directory('test/fixtures').listSync(recursive: true)) {
        if (file is! File ||
            !(file.path.endsWith('.json') || file.path.endsWith('.geojson'))) {
          continue;
        }
        final bytes = file.readAsBytesSync();
        final original = Uint8List.fromList(bytes);
        dynamic expected;
        try {
          expected = jsonDecode(utf8.decode(bytes));
        } on FormatException {
          expect(
            () => decodeApiJsonBytes(bytes),
            throwsFormatException,
            reason: file.path,
          );
          continue;
        }
        final actual = decodeApiJsonBytes(bytes);
        expect(jsonEncode(actual), jsonEncode(expected), reason: file.path);
        expect(bytes, original);
        count++;
      }
      expect(count, greaterThan(100));
    },
  );

  test(
    'BOM, UTF8 boundaries, surrogate escapes and original number types survive',
    () {
      for (final text in [
        '{"bom":"\uFEFF","\uFEFFkey":"\uFEFF\uFEFF"}',
        '{"中文":"日本語😀","bom":"\uFEFF","\uFEFFkey":"\uFEFF\uFEFF","s":"\\ud800"}',
        '[1,1.0,-0.0,9223372036854775808,1e999]',
        '{"a":1,"\\u0061":2}',
      ]) {
        expect(decodeApiJson(text), jsonDecode(text));
        for (final bom in [false, true]) {
          final bytes = Uint8List.fromList([
            if (bom) ...[0xef, 0xbb, 0xbf],
            ...utf8.encode(text),
          ]);
          final expected = jsonDecode(utf8.decode(bytes));
          for (final input in <List<int>>[bytes, bytes.toList()]) {
            final actual = decodeApiJsonBytes(input);
            expect(actual, expected);
            if (actual is List) {
              expect(
                actual.map((v) => v.runtimeType),
                (expected as List).map((v) => v.runtimeType),
              );
              expect((actual[2] as double).isNegative, isTrue);
            }
          }
        }
      }
    },
  );

  test(
    'invalid UTF8 is rejected eagerly even in an unconsumed JSON member',
    () {
      for (final invalid in [
        [0xc0, 0xaf],
        [0xed, 0xa0, 0x80],
        [0xf0, 0x9f],
        [0x80],
        [0xff],
      ]) {
        final bytes = Uint8List.fromList([
          ...utf8.encode('{"unused":"'),
          ...invalid,
          ...utf8.encode('"}'),
        ]);
        expect(() => jsonDecode(utf8.decode(bytes)), throwsFormatException);
        expect(() => decodeApiJsonBytes(bytes), throwsFormatException);
        expect(decodeApiJsonBytes(utf8.encode('{"ok":1}'))['ok'], 1);
      }
      for (final bytes in <List<int>>[
        [],
        [0xef, 0xbb, 0xbf],
        [0xef, 0xbb, 0xbf, 0xef, 0xbb, 0xbf, 0x31],
        [-1],
        [256],
      ]) {
        expect(() => jsonDecode(utf8.decode(bytes)), throwsFormatException);
        expect(() => decodeApiJsonBytes(bytes), throwsFormatException);
      }
    },
  );

  test(
    'HTTP body charset, missing/unknown charset and malformed headers match package:http',
    () {
      for (final header in <String?>[
        null,
        'application/json',
        'application/json; charset=utf-8',
        'APPLICATION/JSON; CHARSET="UTF-8"',
        'text/plain; charset=utf-8',
        'application/json; charset=unknown',
        'application/json; charset=iso-8859-1',
        'application/problem+json',
        'not a media type',
      ]) {
        final response = http.Response.bytes(
          utf8.encode('{"name":"日本中文😀"}'),
          200,
          headers: header == null ? const {} : {'content-type': header},
        );
        dynamic expected;
        try {
          expected = jsonDecode(response.body);
        } on FormatException {
          expect(() => decodeApiJsonResponse(response), throwsFormatException);
          continue;
        }
        expect(
          decodeApiJsonResponse(response),
          expected,
          reason: header ?? 'no header',
        );
      }
    },
  );

  test(
    'stream collects original chunks with split multibyte sequences and BOM',
    () async {
      final original = Uint8List.fromList([
        0xef,
        0xbb,
        0xbf,
        ...utf8.encode('{"v":"中文😀"}'),
      ]);
      final bytes = await readApiJsonBytes(
        Stream.fromIterable([
          for (final byte in original) <int>[byte],
        ]),
      );
      expect(bytes, original);
      expect(decodeApiJsonBytes(bytes), jsonDecode(utf8.decode(original)));
      final failed = Stream<List<int>>.error(
        const FormatException('transport'),
      );
      await expectLater(readApiJsonBytes(failed), throwsFormatException);
      final controller = StreamController<List<int>>();
      await expectLater(
        readApiJsonBytes(
          controller.stream,
          timeout: const Duration(milliseconds: 1),
        ),
        throwsA(isA<TimeoutException>()),
      );
      await controller.close();
    },
  );

  test(
    'byte input, mutable graph and frozen snapshot have independent ownership',
    () {
      final bytes = Uint8List.fromList(utf8.encode('{"a":[{"v":"日本語"}]}'));
      final value = decodeApiJsonBytes(Uint8List.sublistView(bytes));
      final snapshot = snapshotSourcePayload(value as Map<String, dynamic>);
      bytes.fillRange(
        0,
        bytes.length,
        0,
      ); // Controlled buffer-ownership boundary.
      disposeApiJsonResources();
      value['a'][0]['v'] = 'changed';
      expect(snapshot['a'][0]['v'], '日本語');
      expect(value['a'][0]['v'], 'changed');
      expect(() => snapshot['a'].add(1), throwsUnsupportedError);
    },
  );

  test('String and bytes share one parser and release it after failure', () {
    if (!StationJsonDecoder.nativeSupported) return;
    final before = StationJsonDecoder.diagnostics['sessions']!;
    decodeApiJson('{"a":1}');
    decodeApiJsonBytes(utf8.encode('{"b":2}'));
    expect(StationJsonDecoder.diagnostics['sessions'], before + 1);
    expect(() => decodeApiJsonBytes([0xff]), throwsFormatException);
    expect(StationJsonDecoder.diagnostics['sessions'], before);
    expect(decodeApiJsonBytes(utf8.encode('[3]')), [3]);
    disposeApiJsonResources();
    expect(StationJsonDecoder.diagnostics['sessions'], before);
  });
}
