import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/models/source_payload.dart';
import 'package:flutterrhythmquake/services/sources/api_json_decoder.dart';
import 'package:flutterrhythmquake/services/sources/palert_level_history.dart';
import 'package:flutterrhythmquake/services/sources/palert_wire_values.dart';
import 'package:flutterrhythmquake/services/sources/station_json_decoder.dart';

// Exact previous PAlertService._asValueMap conversion, using the same native
// generic JSON parser and the same native level/history kernel as the new path.
Map<String, double> numbers(dynamic raw) {
  if (raw is! Map) return const {};
  final result = <String, double>{};
  for (final entry in raw.entries) {
    final v = entry.value;
    final n = v is num
        ? v.toDouble()
        : v is String
        ? double.tryParse(v.trim())
        : null;
    if (n != null) result[entry.key.toString()] = n;
  }
  return result;
}

void main(List<String> args) {
  final mode = args[0], workload = args[1];
  final cycles = int.parse(args[2]);
  const dir = 'test/fixtures/palert_cadence_20261014';
  final metadata =
      jsonDecode(
            File('$dir/station-list.json').readAsStringSync(),
          )['data']['stationList']['staInfos']
          as List;
  final ids = <String>{
    for (final item in metadata) item['station'].toString().trim(),
  }.toList();
  final original = [
    for (var i = 0; i < 12; i++)
      File('$dir/${i.toString().padLeft(2, '0')}.json').readAsBytesSync(),
  ];
  final frames = [
    for (final bytes in original)
      for (var repeat = 0; repeat < (workload == 'repeat3' ? 3 : 1); repeat++)
        bytes,
  ];
  final decoder = StationJsonDecoder(prepareStationNumbers: false)
    ..setPAlertStations(ids);
  final history = PAlertLevelHistory(useNative: true);
  var checksum = 0, accepted = 0;
  Map<String, dynamic>? lastSnapshot;
  void cycle() {
    history.clear();
    history.setStations(ids);
    DateTime? last;
    bool newer(dynamic raw) {
      final stamp = DateTime.parse(raw['data']['pga']['timestamp']);
      return last == null || stamp.isAfter(last);
    }

    for (final bytes in frames) {
      PAlertWireResponse? wire;
      final raw = mode == 'native'
          ? (wire = decoder.decodePAlertUtf8(bytes, shouldExtract: newer)).raw
          : decodeApiJsonBytes(bytes);
      final data = raw['data'];
      final stamp = DateTime.parse(data['pga']['timestamp']);
      final velocityTime = DateTime.parse(data['pgv']['timestamp']);
      lastSnapshot = snapshotSourcePayload(raw as Map<String, dynamic>);
      if (last != null && !stamp.isAfter(last)) continue;
      final levels = mode == 'native'
          ? history.processWireValues(
              stamp,
              wire!.values,
              includePgv: stamp == velocityTime,
            )
          : history.process(
              stamp,
              numbers(data['pga']['dataVals']),
              stamp == velocityTime ? numbers(data['pgv']['dataVals']) : {},
            );
      for (final value in levels) {
        checksum = (checksum * 31 + value) & 0x7fffffff;
      }
      accepted++;
      last = stamp;
    }
  }

  for (var i = 0; i < 10; i++) {
    cycle();
  }
  checksum = 0;
  accepted = 0;
  final jsonBefore = StationJsonDecoder.diagnostics['calls']!;
  final fieldsBefore = StationJsonDecoder.palertDiagnostics['calls']!;
  final watch = Stopwatch()..start();
  for (var i = 0; i < cycles; i++) {
    cycle();
  }
  watch.stop();
  if (jsonEncode(lastSnapshot) !=
      jsonEncode(jsonDecode(utf8.decode(original.last)))) {
    throw StateError('Original snapshot changed');
  }
  final jsonCalls = StationJsonDecoder.diagnostics['calls']! - jsonBefore;
  final fieldCalls =
      StationJsonDecoder.palertDiagnostics['calls']! - fieldsBefore;
  decoder.dispose();
  history.clear();
  disposeApiJsonResources();
  if (mode == 'native' && fieldCalls != accepted) {
    throw StateError('Duplicate frames extracted fields');
  }
  stdout.writeln(
    jsonEncode({
      'mode': mode,
      'workload': workload,
      'cycles': cycles,
      'stations': ids.length,
      'responses': frames.length * cycles,
      'accepted': accepted,
      'ms': watch.elapsedMicroseconds / 1000,
      'checksum': checksum,
      'json_calls': jsonCalls,
      'field_calls': fieldCalls,
      'rss_mib': ProcessInfo.currentRss / (1024 * 1024),
    }),
  );
}
