import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutterrhythmquake/models/source_payload.dart';
import 'package:flutterrhythmquake/services/sources/api_json_decoder.dart';

Future<void> main(List<String> arguments) async {
  final mode = arguments[0], kind = arguments[1], path = arguments[2];
  final count = int.parse(arguments[3]);
  final bytes = File(path).readAsBytesSync();
  final inputHash = sha256.convert(bytes).toString();
  List<List<int>>? chunks;
  if (kind == 'sse') {
    final manifest = jsonDecode(
      File(
        path.replaceFirst('.original.bytes', '.manifest.json'),
      ).readAsStringSync(),
    );
    chunks = [];
    var offset = 0;
    for (final length in (manifest['chunk_lengths'] as List).cast<int>()) {
      chunks.add(Uint8List.sublistView(bytes, offset, offset + length));
      offset += length;
    }
    if (offset != bytes.length || inputHash != manifest['sha256'])
      throw StateError('Original capture mismatch');
  }
  dynamic parse() => snapshotSourceJsonValue(
    kind == 'weather'
        ? (mode == 'native'
              ? decodeApiJsonIngressBytes(bytes, allowMalformed: true)
              : decodeApiJson(utf8.decode(bytes, allowMalformed: true)))
        : mode == 'native'
        ? decodeApiJsonBytes(bytes)
        : jsonDecode(utf8.decode(bytes)),
  );
  Future<List<dynamic>> stream() async => [
    await for (final frame in decodeApiSseStream(
      Stream.fromIterable(chunks!),
      preferNative: mode == 'native',
    ))
      snapshotSourceJsonValue(frame),
  ];
  final canonical = jsonEncode(kind == 'sse' ? await stream() : parse());
  final outputHash = sha256.convert(utf8.encode(canonical)).toString();
  for (var i = 0; i < 15; i++) {
    if (kind == 'sse') {
      await stream();
    } else {
      parse();
    }
  }
  var checksum = 0;
  final timer = Stopwatch()..start();
  for (var i = 0; i < count; i++) {
    final value = kind == 'sse' ? await stream() : parse();
    checksum += (value as dynamic).length as int;
  }
  timer.stop();
  final rss = ProcessInfo.currentRss / 1048576;
  disposeApiJsonResources();
  stdout.writeln(
    jsonEncode({
      'mode': mode,
      'kind': kind,
      'fixture': path,
      'iterations': count,
      'ms': timer.elapsedMicroseconds / 1000,
      'rss_mib': rss,
      'checksum': checksum,
      'input_sha256': inputHash,
      'output_sha256': outputHash,
    }),
  );
}
