import 'dart:convert';
import 'dart:io';
import 'package:flutterrhythmquake/models/source_payload.dart';
import 'package:flutterrhythmquake/services/sources/api_json_decoder.dart';
import 'package:flutterrhythmquake/services/sources/json_wire_envelope.dart';

void main(List<String> args) {
  final mode = args[0], path = args[1], name = args[3];
  final kind = JsonWireEnvelope.values[int.parse(args[2])];
  final frames = int.parse(args[4]);
  final bytes = File(path).readAsBytesSync();
  dynamic parse() => snapshotSourceJsonValue(switch (mode) {
    'bytes' => decodeApiJsonEnvelopeBytes(bytes, kind, name),
    'string' => decodeApiJsonEnvelope(utf8.decode(bytes), kind, name),
    _ => decodeJsonWireEnvelope(
      utf8.decode(bytes),
      kind,
      name,
      decoder: decodeApiJson,
    ),
  });
  int read(dynamic value) => value is Map
      ? value.length
      : value is List
      ? value.length
      : 1;
  for (var i = 0; i < 30; i++) {
    read(parse());
  }
  var checksum = 0;
  final timer = Stopwatch()..start();
  for (var i = 0; i < frames; i++) {
    checksum += read(parse());
  }
  timer.stop();
  final rss = ProcessInfo.currentRss;
  disposeApiJsonResources();
  stdout.writeln(
    jsonEncode({
      'mode': mode,
      'fixture': path,
      'selector': name,
      'frames': frames,
      'ms': timer.elapsedMicroseconds / 1000,
      'rss_mib': rss / 1048576,
      'checksum': checksum,
    }),
  );
}
