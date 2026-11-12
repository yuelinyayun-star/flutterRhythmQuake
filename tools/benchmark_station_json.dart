import 'dart:convert';
import 'dart:io';
import 'package:flutterrhythmquake/models/source_payload.dart';
import 'package:flutterrhythmquake/services/sources/station_json_decoder_io.dart';
import 'package:flutterrhythmquake/services/sources/station_json_values.dart';
import '../test/support/source_payload_before_station_json_20261015.dart'
    as before;
import '../test/support/station_json_values_before_20261015.dart';

void main(List<String> args) {
  final mode = args[0], workload = args[1];
  final decoder = StationJsonDecoder(preferNative: mode == 'rust');
  final reference = FrozenStationJsonValues();
  final paths = workload == 'observations'
      ? ['test/fixtures/whews_nied/observations.json']
      : workload == 'metadata'
      ? ['test/fixtures/whews_nied/stations.json']
      : [
          'test/fixtures/jian/all.json',
          'test/fixtures/jian/jmalist_response.json',
        ];
  final originals = [for (final path in paths) File(path).readAsStringSync()];
  final iterations = int.parse(args.length > 2 ? args[2] : '1500');
  var checksum = 0.0;
  final retain = args.length > 3 && args[3] == 'retain';
  final retained = <List<Object?>>[];
  void consume(String raw) {
    final root = decoder.decode(raw) as Map<String, dynamic>;
    final snapshot = mode == 'rust'
        ? snapshotSourcePayload(Map<String, dynamic>.from(root))
        : before.snapshotSourcePayload(Map<String, dynamic>.from(root));
    if (workload == 'observations') {
      final data = snapshot['Data'] as Map;
      final values = mode == 'dart'
          ? reference.primary(data['shindo'] as List)!
          : readStationJsonNumbers(
              data['shindo'] as List,
              minimum: -3,
              maximum: 7,
            )!;
      final pga = mode == 'dart'
          ? reference.motion(data['pga'], values.length)!
          : readStationJsonNumbers(data['pga'] as List, minimum: 0)!;
      final pgv = mode == 'dart'
          ? reference.motion(data['pgv'], values.length)!
          : readStationJsonNumbers(data['pgv'] as List, minimum: 0)!;
      if (retain) retained.add([snapshot, values, pga, pgv]);
      for (var i = 0; i < values.length; i++) {
        checksum += values[i] + pga[i] + pgv[i];
      }
    } else if (workload == 'metadata') {
      for (final row in snapshot['stations'] as List) {
        checksum += ((row as Map)['latitude'] as num).toDouble();
        checksum += (row['longitude'] as num).toDouble();
      }
    } else {
      checksum += snapshot.length;
    }
  }

  for (var i = 0; i < 100; i++) {
    for (final raw in originals) {
      consume(raw);
    }
  }
  checksum = 0;
  retained.clear();
  final watch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    for (final raw in originals) {
      consume(raw);
    }
  }
  watch.stop();
  final rss = ProcessInfo.currentRss / 1048576;
  // Use references after the RSS sample so retained snapshots stay live.
  final retainedChecksum = retained.fold<double>(
    0,
    (sum, row) =>
        sum + (row[1] as List<double>).first + (row[2] as List<double>).last,
  );
  decoder.dispose();
  stdout.writeln(
    jsonEncode({
      'mode': mode,
      'workload': workload,
      'frames': iterations * originals.length,
      'processing_ms': watch.elapsedMicroseconds / 1000,
      'checksum': checksum,
      'rss_mb': rss,
      if (retain) 'retained': retained.length,
      if (retain) 'retained_checksum': retainedChecksum,
    }),
  );
}
