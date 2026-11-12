import 'dart:convert';
import 'dart:io';
// ignore_for_file: avoid_print, curly_braces_in_flow_control_structures
import 'package:flutterrhythmquake/services/sources/native_station_summary.dart';
import 'package:flutterrhythmquake/services/sources/jp_shindo_scale.dart';

// AOT component benchmark of the summary owner/FFI boundary. Inputs are the
// unchanged captured NIED directory/frame and SeisJS frames. Repetition is a
// throughput exercise, not a replay of fabricated real-world timing/events.
void main(List<String> args) {
  final mode = args[0], workload = args[1], iterations = int.parse(args[2]);
  // The real application already loads this shared core for other sources.
  // Load it in both processes so DLL residency isn't called summary overhead.
  NativeStationSummary.diagnostics;
  final directory =
      jsonDecode(
            File(
              'test/fixtures/whews_nied/stations.json',
            ).readAsStringSync(encoding: utf8),
          )
          as Map;
  final raw =
      jsonDecode(
            File(
              'test/fixtures/whews_nied/observations.json',
            ).readAsStringSync(encoding: utf8),
          )
          as Map;
  final stations = directory['stations'] as List;
  final levels = [
    for (final value in raw['Data']['shindo'] as List)
      value is num && value > -3 && value <= 7
          ? JpShindoScale.kanameishiLevelFromShindo(value.toDouble())
          : -1,
  ];
  final frames = <Map<String, dynamic>>[
    for (var i = 1; i <= 7; i++)
      Map<String, dynamic>.from(
        jsonDecode(
              File(
                'test/fixtures/source_ws_followup_20261016/seisjs_0$i.original.bytes',
              ).readAsStringSync(encoding: utf8),
            )
            as Map,
      ),
  ];
  final latest = <String, Map<String, dynamic>>{};
  final snapshots = <List<Map<String, dynamic>>>[];
  for (final frame in frames) {
    latest[frame['type'] as String] = frame;
    snapshots.add(latest.values.toList(growable: false));
  }
  // Keep the native directory resident in both modes. The comparison measures
  // per-update processing, rather than loading the DLL/allocator in one mode.
  final owner = NativeStationSummary();
  final native = mode == 'native' ? owner : null;
  var configured = false;
  void nied() {
    if (configured) {
      owner.niedLevels(levels.length, (rows) {
        for (var i = 0; i < levels.length; i++) {
          rows[i * 2] = levels[i];
          rows[i * 2 + 1] = 0;
        }
      });
      return;
    }
    owner.update(1, levels.length, (rows) {
      for (var i = 0; i < levels.length; i++) {
        final p = i * 5;
        rows[p] = levels[i].toDouble();
        rows[p + 1] = levels[i].toDouble();
        rows[p + 2] = 0;
        rows[p + 3] = (stations[i]['latitude'] as num).toDouble();
        rows[p + 4] = (stations[i]['longitude'] as num).toDouble();
      }
    });
    configured = true;
  }

  nied();
  int referenceNied() {
    var best = -1, value = -1;
    for (var i = 0; i < levels.length; i++) {
      if (levels[i] >= 0 && levels[i] > value) {
        best = i;
        value = levels[i];
      }
    }
    return best;
  }

  int run(int n) {
    final js = snapshots[n % snapshots.length];
    if (native == null) {
      final nied = referenceNied();
      var max = double.negativeInfinity, best = -1;
      for (var i = 0; i < js.length; i++) {
        final value = (js[i]['Intensity'] as num).toDouble();
        if (value.isFinite && value > max) {
          max = value;
          best = i;
        }
      }
      return nied * 31 + best;
    }
    if (workload == 'nied') nied();
    native.update(0, js.length, (rows) {
      for (var i = 0; i < js.length; i++)
        rows[i * 5] = (js[i]['Intensity'] as num).toDouble();
    }, regions: [for (final s in js) s['region'] as String]);
    return native.readIndices((indices) => indices[2] * 31 + indices[1]);
  }

  try {
    for (var i = 0; i < 500; i++) run(i);
    final counts = mode == 'native' ? NativeStationSummary.diagnostics : null;
    final rss = ProcessInfo.currentRss;
    var checksum = 0;
    final watch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) checksum += run(i);
    watch.stop();
    final after = mode == 'native' ? NativeStationSummary.diagnostics : null;
    print(
      jsonEncode({
        'mode': mode,
        'workload': workload,
        'iterations': iterations,
        'niedStations': levels.length,
        'milliseconds': watch.elapsedMicroseconds / 1000,
        'checksum': checksum,
        'rssBeforeMiB': rss / 1048576,
        'rssAfterMiB': ProcessInfo.currentRss / 1048576,
        'peakRssMiB': ProcessInfo.maxRss / 1048576,
        if (after != null) 'nativeRows': after['rows']! - counts!['rows']!,
        'scope':
            'max-selection and its FFI; does not measure complete sidebar, inference, UI, GPU or application savings',
      }),
    );
  } finally {
    owner.dispose();
  }
}
