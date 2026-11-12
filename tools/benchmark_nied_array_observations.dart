// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/sources/native_ka_history.dart';
import 'package:flutterrhythmquake/services/sources/native_station_summary.dart';
import '../test/support/dart_ka_station_reference.dart';

// AOT component comparison: unchanged original WHEWS array is repeated for
// throughput, not presented as a real-time/replayed earthquake sequence.
// Covers validity, KA history + derived state, native bridge, UI field binding,
// and maximum summary. Excludes network/JSON, detector, inference and rendering.
void main(List<String> args) {
  final nativeMode = args[0] == 'native', iterations = int.parse(args[1]);
  NativeKaHistorySession.diagnostics;
  final directory =
      jsonDecode(
            File(
              'test/fixtures/whews_nied/stations.json',
            ).readAsStringSync(encoding: utf8),
          )
          as Map;
  final body =
      jsonDecode(
            File(
              'test/fixtures/whews_nied/observations.json',
            ).readAsStringSync(encoding: utf8),
          )
          as Map;
  final rows = directory['stations'] as List;
  final raw = [
    for (final value in body['Data']['shindo'] as List)
      (value as num).toDouble(),
  ];
  // Documented source UTC+8; preserve the original wall-clock fields.
  final time = DateTime.parse(
    '${body['Data']['timestamp'].toString().replaceFirst(' ', 'T')}+08:00',
  );
  final views = [
    for (var i = 0; i < rows.length; i++)
      DartKaStationReference(
        id: i,
        code: '$i',
        name: '',
        coordinate: LatLng(
          (rows[i]['latitude'] as num).toDouble(),
          (rows[i]['longitude'] as num).toDouble(),
        ),
        network: 'K-NET',
        prefecture: '',
        expireSeconds: 10,
      ),
  ];
  final ka = nativeMode ? NativeKaHistorySession(rows.length) : null;
  final summary = nativeMode ? NativeStationSummary() : null;
  if (ka != null) {
    for (var i = 0; i < views.length; i++) {
      views[i].recentLevel = ka.histories[i];
    }
    summary!.update(1, views.length, (data) {
      for (var i = 0; i < views.length; i++) {
        final p = i * 5;
        data[p] = data[p + 1] = -1;
        data[p + 2] = 0;
        data[p + 3] = views[i].coordinate.latitude;
        data[p + 4] = views[i].coordinate.longitude;
      }
    });
  }
  int run() {
    if (ka == null) {
      var maximum = -1, selected = -1;
      for (var i = 0; i < views.length; i++) {
        final s = views[i], v = raw[i];
        s.lastUpdate = s.lastDataTime = time;
        s.updateFromContinuousShindo(v.isFinite && v > -3 && v <= 7 ? v : null);
        if (s.level > maximum) {
          maximum = s.level;
          selected = i;
        }
      }
      return selected;
    }
    for (var i = 0; i < views.length; i++) {
      final s = views[i];
      ka.writeShindoInput(
        i,
        shindo: raw[i],
        expireSeconds: s.expireSeconds,
        isActive: s.isActive,
      );
    }
    ka.processShindoFrame(time.millisecondsSinceEpoch);
    for (var i = 0; i < views.length; i++) {
      final s = views[i], flags = ka.observationFlags(i), r = ka.result(i);
      s.lastUpdate = s.lastDataTime = time;
      if (flags & 1 != 0) s.continuousShindo = raw[i];
      if (flags & 2 != 0) s.isActive = false;
      s.level = r.level;
      s.ascend = r.ascend;
      s.triggerStamp = r.triggerStamp;
      s.activity = r.activity;
      s.abnormalUpdateCount = r.abnormalUpdateCount;
    }
    summary!.niedKaResults(ka, (active) {
      for (var i = 0; i < views.length; i++) {
        active[i] = views[i].isActive ? 1 : 0;
      }
    });
    return summary.readIndices((indices) => indices[2]);
  }

  try {
    for (var i = 0; i < 120; i++) {
      run();
    }
    final before = ProcessInfo.currentRss;
    var checksum = 0;
    final watch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      checksum += run();
    }
    watch.stop();
    print(
      jsonEncode({
        'mode': nativeMode ? 'native' : 'dart',
        'iterations': iterations,
        'stations': raw.length,
        'milliseconds': watch.elapsedMicroseconds / 1000,
        'checksum': checksum,
        'rssBeforeMiB': before / 1048576,
        'rssAfterMiB': ProcessInfo.currentRss / 1048576,
        'peakRssMiB': ProcessInfo.maxRss / 1048576,
        'scope':
            'original-array KA + FFI + UI result binding + max-summary only; no full APP savings claim',
      }),
    );
  } finally {
    summary?.dispose();
    ka?.dispose();
  }
}
