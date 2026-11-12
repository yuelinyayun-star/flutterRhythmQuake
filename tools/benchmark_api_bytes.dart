import 'dart:convert';
import 'dart:io';
import 'package:flutterrhythmquake/models/source_payload.dart';
import 'package:flutterrhythmquake/services/sources/api_json_decoder.dart';

void main(List<String> arguments) {
  final mode = arguments[0], path = arguments[1];
  final iterations = int.parse(arguments[2]);
  final retain = arguments.contains('retain');
  final bytes = File(path).readAsBytesSync();
  final values = <dynamic>[];
  dynamic decode() => snapshotSourceJsonValue(
    mode == 'bytes'
        ? decodeApiJsonBytes(bytes)
        : decodeApiJson(utf8.decode(bytes)),
  );
  int read(dynamic value) => value is Map
      ? value.length
      : value is List
      ? value.length
      : 1;
  for (var index = 0; index < 30; index++) {
    read(decode());
  }
  final timer = Stopwatch()..start();
  var checksum = 0;
  for (var index = 0; index < iterations; index++) {
    final value = decode();
    checksum += read(value);
    if (retain) values.add(value);
  }
  timer.stop();
  final rss = ProcessInfo.currentRss;
  disposeApiJsonResources();
  stdout.writeln(
    jsonEncode({
      'mode': mode,
      'fixture': path,
      'frames': iterations,
      'processing_ms': timer.elapsedMicroseconds / 1000,
      'rss_mib': rss / 1048576,
      'checksum': checksum,
      'retained': values.length,
      'retained_checksum': values.fold<int>(
        0,
        (sum, value) => sum + read(value),
      ),
    }),
  );
}
