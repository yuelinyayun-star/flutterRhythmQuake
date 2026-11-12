// Internal offline performance probe. Only unchanged captured transport bytes
// enter the native testing actor; this process never starts live APP services.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutterrhythmquake/models/source_payload.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:flutterrhythmquake/services/sources/native_station_runtime.dart';
import '../test/support/foreground_station_payload_before_frozen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final root = Directory(Platform.environment['RQ_PERF_ROOT']!);
  final out = File('${root.path}/oct25-prepared-decode-benchmark.json');
  final results = <Object?>[];
  try {
    for (final kind in ['kma', 'cwa']) {
      final runtime = NativeStationRuntime();
      final frameReady = Completer<Map<String, dynamic>>();
      runtime.onFrame = (frame) {
        if (!frameReady.isCompleted && (frame['frames'] as int) >= 1) {
          frameReady.complete(frame);
        }
      };
      runtime.start({'kind': kind, 'source': 'pews', 'testing': true});
      final inputs = <File>[];
      final clock = DateTime.now();
      if (kind == 'kma') {
        inputs.addAll([
          File('${root.path}/fixtures/kma_01.original.bytes'),
          File('${root.path}/fixtures/kma_02.original.bytes'),
        ]);
        for (final file in inputs) {
          runtime.injectOriginal(file.readAsBytesSync(), clock);
        }
      } else {
        final meta = File('${root.path}/fixtures/trem_metadata.original.bytes');
        final stream = File('${root.path}/fixtures/trem_stream.original.bytes');
        inputs.addAll([meta, stream]);
        runtime.injectOriginal(meta.readAsBytesSync(), clock);
        for (final line in stream.readAsLinesSync(encoding: utf8)) {
          if (!line.startsWith('data:')) continue;
          final original = line.substring(5).trim();
          try {
            if ((jsonDecode(original) as Map)['station'] is! Map) continue;
          } on FormatException {
            continue; // Original capture ends mid-frame; do not repair it.
          }
          runtime.injectOriginal(utf8.encode(original), clock);
          break;
        }
      }
      final frame = await frameReady.future.timeout(
        const Duration(seconds: 15),
      );
      final stations = frame['stations'] as List;
      final bytes = packedSourceJsonTransport(
        stations.first as Map<String, dynamic>,
      )!.$1;
      runtime.stop();
      dynamic decode(dynamic rows, bool before) => kind == 'cwa'
          ? before
                ? OriginalForegroundStationPayload.decodeCwa(rows)
                : ForegroundStationPayload.decodeCwa(rows)
          : before
          ? OriginalForegroundStationPayload.decodeKma(rows)
          : ForegroundStationPayload.decodeKma(rows);
      String canonical(dynamic value) => jsonEncode(
        kind == 'cwa'
            ? ForegroundStationPayload.cwa(value)
            : ForegroundStationPayload.kma(value),
      );
      final expected = canonical(decode(stations, true));
      if (canonical(decode(stations, false)) != expected) {
        throw StateError('Decoded station fields differ: $kind');
      }
      final rounds = <Object?>[];
      var checksum = 0;
      for (var round = 0; round < 8; round++) {
        for (final before in round.isEven ? [true, false] : [false, true]) {
          var micros = 0;
          for (var i = 0; i < 120; i++) {
            // A fresh tree matches actual per-frame delivery. Exclude the
            // shared byte copy, actor and encoder from decoder-only timing.
            final tree = PackedSourceJson(Uint8List.fromList(bytes));
            final rows = (tree.root as Map)['stations'];
            final watch = Stopwatch()..start();
            final decoded = decode(rows, before);
            watch.stop();
            micros += watch.elapsedMicroseconds;
            checksum += (decoded as List).length;
          }
          rounds.add({'before': before, 'frames': 120, 'micros': micros});
        }
      }
      results.add({
        'kind': kind,
        'stations': stations.length,
        'rounds': rounds,
        'checksum': checksum,
        'equalCanonicalFields': true,
        'canonicalSha256': sha256.convert(utf8.encode(expected)).toString(),
        'inputs': [
          for (final file in inputs)
            {
              'name': file.uri.pathSegments.last,
              'sha256': sha256.convert(file.readAsBytesSync()).toString(),
            },
        ],
      });
    }
    out.writeAsStringSync(jsonEncode({'results': results}), encoding: utf8);
    exit(0);
  } catch (error, stack) {
    out.writeAsStringSync(
      jsonEncode({'error': '$error', 'stack': '$stack', 'results': results}),
      encoding: utf8,
    );
    exit(1);
  }
}
