import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/api_json_decoder.dart';
import 'package:flutterrhythmquake/services/sources/json_wire_envelope.dart';
import 'package:flutterrhythmquake/services/sources/station_json_decoder.dart';
import 'package:flutterrhythmquake/models/source_payload.dart';

void compare(
  String source,
  JsonWireEnvelope kind,
  String name, {
  bool bytes = true,
}) {
  dynamic expected;
  try {
    expected = decodeJsonWireEnvelope(source, kind, name);
  } on FormatException {
    expect(
      () => decodeApiJsonEnvelope(source, kind, name),
      throwsFormatException,
      reason: source,
    );
    if (bytes) {
      expect(
        () => decodeApiJsonEnvelopeBytes(utf8.encode(source), kind, name),
        throwsFormatException,
        reason: source,
      );
    }
    return;
  }
  final actual = decodeApiJsonEnvelope(source, kind, name);
  expect(actual, expected, reason: source);
  if (bytes) {
    final input = Uint8List.fromList(utf8.encode(source));
    final saved = input.toList();
    expect(
      decodeApiJsonEnvelopeBytes(input, kind, name),
      expected,
      reason: source,
    );
    expect(input, saved);
  }
}

void main() {
  tearDown(disposeApiJsonResources);
  test('unchanged captured JSONP and JS fields match the original scanner', () {
    final cases = [
      (
        'cma_radar/radar_list_20260921.jsonp',
        JsonWireEnvelope.jsonp,
        'readRadarList',
      ),
      (
        'cma_precipitation/rain_list.jsonp',
        JsonWireEnvelope.jsonp,
        'getPreObs1h',
      ),
      (
        'china_weather_hourly/beijing_location.jsonp',
        JsonWireEnvelope.jsonpTight,
        'getData',
      ),
      (
        'china_weather_hourly/beijing.js',
        JsonWireEnvelope.assignment,
        'fc1h_24',
      ),
      (
        'china_weather_hourly/beijing_current.js',
        JsonWireEnvelope.assignment,
        'dataSK',
      ),
      (
        'china_weather_hourly/yiwu_current.js',
        JsonWireEnvelope.assignment,
        'dataSK',
      ),
      (
        'china_weather_hourly/yiwu_outlook.js',
        JsonWireEnvelope.assignment,
        'fc40',
      ),
      (
        'china_weather_hourly/yiwu_outlook.js',
        JsonWireEnvelope.assignment,
        'index3d',
      ),
    ];
    for (final (path, kind, name) in cases) {
      final bytes = File('test/fixtures/$path').readAsBytesSync();
      final text = utf8.decode(bytes);
      final expected = decodeJsonWireEnvelope(text, kind, name);
      expect(
        jsonEncode(decodeApiJsonEnvelopeBytes(bytes, kind, name)),
        jsonEncode(expected),
        reason: path,
      );
      expect(
        jsonEncode(decodeApiJsonEnvelope(text, kind, name)),
        jsonEncode(expected),
        reason: path,
      );
    }
  });

  test('wrapper boundary and Unicode whitespace contracts match Dart', () {
    // Controlled protocol boundaries, never injected into the live app.
    for (final code in [
      0,
      9,
      10,
      11,
      12,
      13,
      32,
      0x85,
      0xa0,
      0x1680,
      0x180e,
      ...List.generate(12, (i) => 0x2000 + i),
      0x2028,
      0x2029,
      0x202f,
      0x205f,
      0x3000,
      0xfeff,
    ]) {
      final w = String.fromCharCode(code);
      compare('${w}cb$w({"v":"日本語😀"})$w;$w', JsonWireEnvelope.jsonp, 'cb');
      compare('${w}var${w}x$w=$w{"v":1};', JsonWireEnvelope.assignment, 'x');
      compare('data:$w{"v":1}', JsonWireEnvelope.sseDataLine, '');
    }
    for (final s in [
      'cb({})',
      ' cb ({}) ;\n',
      'cb({});;',
      'cb({})x',
      'cb({})\n;',
      'cb({"s":")"})',
      'cb({"s":"\uFEFF"})',
    ]) {
      compare(s, JsonWireEnvelope.jsonp, 'cb');
      compare(s, JsonWireEnvelope.jsonpTight, 'cb');
    }
    for (final s in [
      'var x={};var x={"later":1}',
      'var x=0;var x={}',
      'xvar x={}',
      'var xyz={}; var x=[]',
      r'var x = {"a":[{}],"s":"}\""}; throw 1;',
      'var x=[}',
      'var x={"unterminated":',
      ';var x={"嵌套":{"v":2}};',
    ]) {
      compare(s, JsonWireEnvelope.assignment, 'x');
    }
    for (final name in ['', 'x.y', '中文😀']) {
      compare('var $name = {"n":1};', JsonWireEnvelope.assignment, name);
      compare('$name({"n":1})', JsonWireEnvelope.jsonp, name);
    }
    for (final s in [
      'event: info',
      'data:',
      'data: {broken',
      ' data: {}',
      'data: [1,1.0,-0.0,9223372036854775808]',
      'data: {"x":"\\ud800"}',
    ]) {
      compare(s, JsonWireEnvelope.sseDataLine, '');
    }
    compare(
      'var x={"x":"${String.fromCharCode(0xd800)}"};',
      JsonWireEnvelope.assignment,
      'x',
      bytes: false,
    );
  });

  test(
    'UTF8 validates the whole transport, while BOM handling preserves fields',
    () {
      final raw = utf8.encode('cb({"\uFEFF":"\uFEFF\uFEFF"})');
      expect(
        decodeApiJsonEnvelopeBytes(
          [0xef, 0xbb, 0xbf, ...raw],
          JsonWireEnvelope.jsonp,
          'cb',
        ),
        {'\uFEFF': '\uFEFF\uFEFF'},
      );
      for (final input in <List<int>>[
        [...raw, 0xff],
        [0xff, ...raw],
        [-1],
        [256],
      ]) {
        expect(
          () => decodeApiJsonEnvelopeBytes(input, JsonWireEnvelope.jsonp, 'cb'),
          throwsFormatException,
        );
      }
      expect(decodeApiJsonEnvelopeBytes(raw, JsonWireEnvelope.jsonp, 'cb'), {
        '\uFEFF': '\uFEFF\uFEFF',
      });
    },
  );

  test(
    'shared parser releases on failure and snapshots survive buffer reuse',
    () {
      final baseline = StationJsonDecoder.nativeSupported
          ? StationJsonDecoder.diagnostics['sessions']!
          : 0;
      final value = decodeApiJsonEnvelope(
        'var x={"list":[{"v":"中文"}]};',
        JsonWireEnvelope.assignment,
        'x',
      );
      final frozen = snapshotSourceJsonValue(value);
      decodeApiJsonEnvelopeBytes(
        utf8.encode('cb({"other":1})'),
        JsonWireEnvelope.jsonp,
        'cb',
      );
      if (StationJsonDecoder.nativeSupported) {
        expect(StationJsonDecoder.diagnostics['sessions'], baseline + 1);
      }
      expect(
        () => decodeApiJsonEnvelope('data: bad', JsonWireEnvelope.sseDataLine),
        throwsFormatException,
      );
      if (StationJsonDecoder.nativeSupported) {
        expect(StationJsonDecoder.diagnostics['sessions'], baseline);
      }
      value['list'][0]['v'] = 'changed';
      expect(frozen['list'][0]['v'], '中文');
      expect(() => frozen['list'].add(1), throwsUnsupportedError);
    },
  );
  test('large transport preserves the existing selected JSON size limit', () {
    if (!StationJsonDecoder.nativeSupported) return;
    // Controlled size-boundary input, not a captured event or benchmark.
    final wrapper = Uint8List(32 * 1024 * 1024 + 8)
      ..fillRange(0, 32 * 1024 * 1024, 32);
    wrapper.setRange(
      wrapper.length - 8,
      wrapper.length,
      utf8.encode('cb({})  '),
    );
    expect(
      decodeApiJsonEnvelopeBytes(wrapper, JsonWireEnvelope.jsonp, 'cb'),
      {},
    );
    final oversizedJson = '"${'a' * (32 * 1024 * 1024)}"';
    expect(() => decodeApiJson(oversizedJson), throwsFormatException);
    expect(
      () => decodeApiJsonEnvelopeBytes(
        utf8.encode('cb($oversizedJson)'),
        JsonWireEnvelope.jsonp,
        'cb',
      ),
      throwsFormatException,
    );
  });
}
