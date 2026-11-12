import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/api_json_decoder.dart';
import 'package:flutterrhythmquake/services/sources/station_json_decoder.dart';
import 'package:flutterrhythmquake/services/sources/json_wire_envelope.dart'
    show decodeJsonWireEnvelope;

const directory = 'test/fixtures/api_ingress_20261016';
Iterable<List<int>> chunks(Uint8List bytes, int width) sync* {
  for (var i = 0; i < bytes.length; i += width) {
    yield Uint8List.sublistView(bytes, i, (i + width).clamp(0, bytes.length));
  }
}

List<Map<String, dynamic>> originalSse(Uint8List bytes) {
  final result = <Map<String, dynamic>>[];
  for (final line in const LineSplitter().convert(utf8.decode(bytes))) {
    if (!line.startsWith('data:')) continue;
    try {
      final value = jsonDecode(line.substring(5).trimLeft());
      if (value is Map<String, dynamic> && value.isNotEmpty) result.add(value);
    } on FormatException {
      /* Original client skips invalid JSON lines. */
    }
  }
  return result;
}

void main() {
  tearDown(disposeApiJsonResources);
  final bytes = File('$directory/trem_stream.original.bytes').readAsBytesSync();
  final manifest = jsonDecode(
    File('$directory/trem_stream.manifest.json').readAsStringSync(),
  );

  test(
    'original HTTP SSE chunks retain all timestamps, fields and order',
    () async {
      expect(sha256.convert(bytes).toString(), manifest['sha256']);
      final input = <List<int>>[];
      var offset = 0;
      for (final length in (manifest['chunk_lengths'] as List).cast<int>()) {
        input.add(Uint8List.sublistView(bytes, offset, offset + length));
        offset += length;
      }
      expect(offset, bytes.length);
      final expected = originalSse(bytes);
      expect(expected.length, greaterThan(1));
      final actual = await decodeApiSseStream(
        Stream.fromIterable(input),
      ).toList();
      expect(jsonEncode(actual), jsonEncode(expected));
      expect(sha256.convert(bytes).toString(), manifest['sha256']);
    },
  );

  for (final width in [1, 2, 3, 7, 1024, 16384]) {
    test('unchanged captured SSE split at $width-byte boundaries', () async {
      final actual = await decodeApiSseStream(
        Stream.fromIterable(chunks(bytes, width)),
      ).toList();
      expect(jsonEncode(actual), jsonEncode(originalSse(bytes)));
    });
  }

  test('controlled protocol edges match original per-line semantics', () async {
    // Protocol cases only; never used for performance claims or live injection.
    final bytes = Uint8List.fromList(
      utf8.encode(
        '\ufeff: 日本\r\ndata: {"x":"🌏"}\r\n'
        'id: abc\ndata: {}\ndata: []\ndata: {broken}\ndata:\n'
        'data: {"nested":[{"a":1}]}\rdata: {"last":true}',
      ),
    );
    final expected = originalSse(bytes);
    for (var width = 1; width <= 17; width++) {
      final actual = await decodeApiSseStream(
        Stream.fromIterable(chunks(bytes, width)),
      ).toList();
      expect(actual, expected, reason: 'chunk width $width');
    }
  });

  test(
    'malformed UTF8 comments and incomplete EOF terminate strict SSE',
    () async {
      for (final invalid in [
        Uint8List.fromList([58, 32, 0xff, 10]),
        Uint8List.fromList([0xe6, 0x97]),
      ]) {
        await expectLater(
          decodeApiSseStream(Stream.fromIterable(chunks(invalid, 1))).toList(),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'cancel/error/EOF release native owners and published snapshots survive',
    () async {
      if (!StationJsonDecoder.nativeSupported) return;
      final before = StationJsonDecoder.diagnostics['sessions'];
      final first = await decodeApiSseStream(
        Stream.fromIterable(chunks(bytes, 1024)),
      ).take(1).single;
      expect(StationJsonDecoder.diagnostics['sessions'], before);
      expect(first, originalSse(bytes).first);
      await expectLater(
        decodeApiSseStream(
          Stream.error(StateError('controlled disconnect')),
        ).toList(),
        throwsStateError,
      );
      expect(StationJsonDecoder.diagnostics['sessions'], before);
      final next = await decodeApiSseStream(
        Stream.fromIterable([bytes]),
      ).toList();
      expect(next, originalSse(bytes));
      expect(StationJsonDecoder.diagnostics['sessions'], before);
    },
  );

  test('opt-in malformed UTF8 policy matches Dart byte for byte', () {
    final cases = <List<int>>[
      for (var byte = 0; byte <= 255; byte++) [byte],
      [0xed, 0xa0, 0x80],
      [0xe0, 0x80, 0xaf],
      [0xf0, 0x80, 0x80, 0x80],
      [0xf4, 0x90, 0x80, 0x80],
      [0xe6, 0x97],
      [0xef, 0xbb],
      [0xc2, 0x85],
      for (final first in [
        0xc0,
        0xc2,
        0xdf,
        0xe0,
        0xed,
        0xef,
        0xf0,
        0xf4,
        0xf5,
        0xff,
      ])
        for (var second = 0x70; second <= 0xc0; second++) [first, second],
    ];
    for (final body in cases) {
      final raw = <int>[123, 34, 120, 34, 58, 34, ...body, 34, 125];
      dynamic expected;
      try {
        expected = jsonDecode(utf8.decode(raw, allowMalformed: true));
      } on FormatException {
        expect(
          () => decodeApiJsonIngressBytes(raw, allowMalformed: true),
          throwsFormatException,
        );
        continue;
      }
      expect(
        decodeApiJsonIngressBytes(raw, allowMalformed: true),
        expected,
        reason: body.toString(),
      );
    }
    expect(
      () => decodeApiJsonIngressBytes([123, 34, 120, 34, 58, 34, 255, 34, 125]),
      throwsFormatException,
    );
  });

  test('weather JS wrappers preserve the old greedy and first-close rules', () {
    for (final (kind, text) in [
      (JsonWireEnvelope.firstObject, 'ignore({"日本":"暴雨"});'),
      (JsonWireEnvelope.firstObject, '{"x":1}; {"x":2}'),
      (
        JsonWireEnvelope.weatherAlarmAssignment,
        'xvar alarminfo = {"ISSUECONTENT":"日本🌏"};',
      ),
      (JsonWireEnvelope.weatherAlarmAssignment, 'var alarminfo={"x":"}"};'),
    ]) {
      final original = () => decodeJsonWireEnvelope(text, kind, '');
      dynamic expected;
      try {
        expected = original();
      } on FormatException {
        expect(
          () => decodeApiJsonIngressBytes(
            utf8.encode(text),
            allowMalformed: true,
            envelope: kind,
          ),
          throwsFormatException,
        );
        continue;
      }
      expect(
        decodeApiJsonIngressBytes(
          utf8.encode(text),
          allowMalformed: true,
          envelope: kind,
        ),
        expected,
      );
    }
  });

  test('complete original weather HTTP response keeps every field', () {
    final bytes = File(
      '$directory/weather_alarm_full.original.bytes',
    ).readAsBytesSync();
    final manifest = jsonDecode(
      File('$directory/weather_alarm_full.manifest.json').readAsStringSync(),
    );
    expect(sha256.convert(bytes).toString(), manifest['sha256']);
    final expected = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    final actual = decodeApiJsonIngressBytes(bytes, allowMalformed: true);
    expect(jsonEncode(actual), jsonEncode(expected));
  });
}
