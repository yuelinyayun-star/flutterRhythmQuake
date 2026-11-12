import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutterrhythmquake/services/sources/native_station_runtime.dart';

void main() {
  test(
    'native KMA and TREM ingress reaches prepared UI snapshots',
    () async {
      final owners = <NativeStationRuntime>[];
      final completed = <String, Map<String, dynamic>>{};
      final done = Completer<void>();
      for (final name in ['kma', 'cwa', 'jian-kma']) {
        final kind = name == 'jian-kma' ? 'kma' : name;
        final owner = NativeStationRuntime();
        owners.add(owner);
        owner.onFrame = (frame) {
          if ((frame['frames'] as int) > 0 &&
              (frame['stations'] as List).isNotEmpty) {
            completed[name] = {
              'stations': (frame['stations'] as List).length,
              'frames': frame['frames'],
              'dataTime': frame['dataTime'],
              'status': frame['status'],
              'grids': (frame['grids'] as List).length,
            };
            if (completed.length == 3 && !done.isCompleted) done.complete();
          }
        };
        owner.start({
          'kind': kind,
          'source': name == 'jian-kma' ? 'jian' : 'pews',
        });
      }
      try {
        await done.future.timeout(const Duration(seconds: 65));
      } finally {
        for (final owner in owners) {
          owner.stop();
        }
      }
      final end = DateTime.now().add(const Duration(seconds: 8));
      while (NativeStationRuntime.workers > 0 && DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(NativeStationRuntime.workers, 0);
      final report = File('tmp/native_kma_trem_20261017/native-live.json');
      report.writeAsStringSync(jsonEncode(completed));
      debugPrint(jsonEncode(completed));
    },
    skip: Platform.environment['RQ_NATIVE_STATION_LIVE'] != '1',
    timeout: const Timeout(Duration(seconds: 85)),
  );
}
