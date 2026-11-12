import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/services/sources/palert_level_history.dart';
import '../test/support/palert_level_history_before_20261015.dart';

void main(List<String> args) {
  final mode = args[0];
  final cycles = int.parse(args[1]);
  final dir = Directory('test/fixtures/palert_cadence_20261014');
  final metadata =
      jsonDecode(
            File('${dir.path}/station-list.json').readAsStringSync(),
          )['data']['stationList']['staInfos']
          as List;
  final ids = <String>{
    for (final item in metadata)
      if (item['station'].toString().trim().isNotEmpty &&
          item['lat'] != null &&
          item['lon'] != null)
        item['station'].toString().trim(),
  }.toList();
  final frames = [
    for (var i = 0; i < 12; i++)
      jsonDecode(
            File(
              '${dir.path}/${i.toString().padLeft(2, '0')}.json',
            ).readAsStringSync(),
          )['data']
          as Map,
  ];
  final inputs = [
    for (final frame in frames)
      (
        time: DateTime.parse(frame['pga']['timestamp']),
        pga: Map<String, double>.from(
          (frame['pga']['dataVals'] as Map).map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          ),
        ),
        pgv: frame['pgv']['timestamp'] == frame['pga']['timestamp']
            ? Map<String, double>.from(
                (frame['pgv']['dataVals'] as Map).map(
                  (k, v) => MapEntry(k, (v as num).toDouble()),
                ),
              )
            : <String, double>{},
      ),
  ];
  final native = mode == 'native';
  final processor = mode == 'reference'
      ? null
      : PAlertLevelHistory(useNative: native);
  final reference = mode == 'reference'
      ? DartPAlertLevelHistoryReference()
      : null;
  var checksum = 0;
  void cycle() {
    processor?.clear();
    reference?.clear();
    processor?.setStations(ids);
    reference?.setStations(ids);
    for (final frame in inputs) {
      final values =
          processor?.process(frame.time, frame.pga, frame.pgv) ??
          reference!.process(frame.time, frame.pga, frame.pgv);
      for (final value in values) {
        checksum = (checksum * 31 + value) & 0x7fffffff;
      }
    }
  }

  for (var i = 0; i < 20; i++) {
    cycle();
  }
  checksum = 0;
  final watch = Stopwatch()..start();
  for (var i = 0; i < cycles; i++) {
    cycle();
  }
  watch.stop();
  processor?.clear();
  reference?.clear();
  stdout.writeln(
    jsonEncode({
      'mode': mode,
      'cycles': cycles,
      'source_frames': frames.length,
      'stations': ids.length,
      'ms': watch.elapsedMicroseconds / 1000,
      'checksum': checksum,
      'rss_mib': ProcessInfo.currentRss / (1024 * 1024),
    }),
  );
}
