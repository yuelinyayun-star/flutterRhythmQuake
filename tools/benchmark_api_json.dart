import 'dart:convert';
import 'dart:io';
import 'package:flutterrhythmquake/services/sources/api_json_decoder.dart';
import 'package:flutterrhythmquake/models/source_payload.dart';

void main(List<String> args) {
  final native = args.first == 'rust';
  final path = args[1];
  final iterations = int.parse(args[2]);
  final retain = args.contains('retain');
  final snapshot = args.contains('snapshot');
  dynamic decode(String raw) {
    final value = native ? decodeApiJson(raw) : jsonDecode(raw);
    return snapshot ? snapshotSourceJsonValue(value) : value;
  }

  final raw = File(path).readAsStringSync();
  final originals = <dynamic>[];
  var checksum = 0.0;
  double read(dynamic root) {
    if (root is Map) {
      // Event/catalogue shape and row count access. The full original
      // graph stays available to later consumers; no fixture fields removed.
      final rows = root['features'] ?? root['Data'] ?? root['data'];
      final props = root['properties'];
      return root.length.toDouble() +
          (rows is List ? rows.length : 0) +
          (props is Map ? props.length : 0);
    }
    if (root is List) {
      var sum = root.length.toDouble();
      for (final row in root) {
        if (row is Map) sum += row.length;
      }
      return sum;
    }
    return 1;
  }

  for (var i = 0; i < 50; i++) {
    read(decode(raw));
  }
  final timer = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    final root = decode(raw);
    checksum += read(root);
    if (retain) originals.add(root);
  }
  timer.stop();
  final rss = ProcessInfo.currentRss;
  disposeApiJsonResources();
  final retainedChecksum = originals.fold<double>(
    0,
    (sum, root) => sum + read(root),
  );
  stdout.writeln(
    jsonEncode({
      'mode': native ? 'rust' : 'dart',
      'fixture': path,
      'frames': iterations,
      'processing_ms': timer.elapsedMicroseconds / 1000,
      'rss_mb': rss / 1048576,
      'checksum': checksum,
      'retained': originals.length,
      'snapshot': snapshot,
      'retained_checksum': retainedChecksum,
    }),
  );
}
