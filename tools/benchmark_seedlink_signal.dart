import 'dart:convert';
import 'dart:io';
import 'package:flutterrhythmquake/services/sources/seedlink_signal_analysis.dart';

// Replay identical, unmodified raw observations into independent analyzers.
// This is a throughput workload, NOT 5000 observed real stations.
void main(List<String> args) {
  final input = File(
    args.isEmpty
        ? 'tmp/fdsn_connection_review/costa_rica_QUEP_mmi_input.json'
        : args[0],
  );
  final root = jsonDecode(input.readAsStringSync()) as Map;
  final records = (root['records'] as List)
      .where((r) => r['id'] == 'TC.QUEP..EHZ')
      .map(
        (r) => (
          (r['samples'] as List).cast<int>().toList(growable: false),
          (r['sampleRate'] as num).toDouble(),
          DateTime.parse(r['start'] as String),
        ),
      )
      .toList(growable: false);
  final count = args.length > 1 ? int.parse(args[1]) : 5000;
  final rssBefore = ProcessInfo.currentRss;
  final streams = List.generate(count, (_) => SeedLinkSignalAnalysis());
  final watch = Stopwatch()..start();
  var samples = 0, packets = 0;
  double checksum = 0;
  for (final (values, rate, time) in records) {
    for (final stream in streams) {
      checksum += stream.accept(values, rate, time).ratio ?? 0;
      samples += values.length;
      packets++;
    }
  }
  watch.stop();
  final duration =
      records.last.$3.difference(records.first.$3).inMicroseconds / 1e6 +
      records.last.$1.length / records.last.$2;
  stdout.writeln(
    jsonEncode({
      'mode': 'unmodified-original-record replay throughput',
      'original_sha256': root['sha256'],
      'streams': count,
      'packets': packets,
      'samples': samples,
      'observation_seconds': duration,
      'processing_ms': watch.elapsedMicroseconds / 1000,
      'ms_per_observation_second': watch.elapsedMicroseconds / 1000 / duration,
      'rss_delta_mb': (ProcessInfo.currentRss - rssBefore) / 1048576,
      'process_rss_mb': ProcessInfo.currentRss / 1048576,
      'checksum': checksum,
    }),
  );
}
