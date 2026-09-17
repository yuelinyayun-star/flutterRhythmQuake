import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_motion_service_io.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_station_service.dart';

void main() {
  test(
    'opt-in real FDSN catalogue, subscriptions, metadata and clock probe',
    () async {
      final motion = FdsnMotionService();
      final earth = FdsnStationService.earthScope;
      final geo = FdsnStationService.geofon;
      final seen = <String>{};
      final measured = <String>{};
      final latest = <String, DateTime>{};
      final latestMeasured = <String, DateTime>{};
      final history = <Map<String, Object>>[];
      final startedAt = DateTime.now().toUtc();
      final bySource = <String, Set<String>>{};
      DateTime? previous;
      var backwards = 0;
      var clockBackwards = 0;
      DateTime? previousClock;
      void clockChanged() {
        final t = motion.dataTimeNotifier.value;
        if (t != null && previousClock != null && t.isBefore(previousClock!)) {
          clockBackwards++;
        }
        previousClock = t;
      }

      motion.dataTimeNotifier.addListener(clockChanged);
      final subscription = motion.sampleStream.listen((sample) {
        final key = '${sample.source}:${sample.code}';
        seen.add(key);
        if (latest[key] == null || sample.timestamp.isAfter(latest[key]!)) {
          latest[key] = sample.timestamp;
        }
        bySource.putIfAbsent(sample.source, () => {}).add(key);
        if (sample.hasMeasurement) {
          measured.add(key);
          if (latestMeasured[key] == null ||
              sample.timestamp.isAfter(latestMeasured[key]!)) {
            latestMeasured[key] = sample.timestamp;
          }
        }
        if (previous != null && sample.timestamp.isBefore(previous!)) {
          backwards++;
        }
        previous = sample.timestamp;
      });
      final loading = [earth.start(), geo.start()];
      const limit = int.fromEnvironment('FDSN_LIMIT', defaultValue: 300);
      const ticks = int.fromEnvironment('FDSN_TICKS', defaultValue: 12);
      motion.connect(stationLimit: limit);
      try {
        for (var i = 0; i < ticks; i++) {
          await Future<void>.delayed(const Duration(seconds: 15));
          history.add({
            'seconds': 15 * (i + 1),
            'elapsedSeconds': DateTime.now()
                .toUtc()
                .difference(startedAt)
                .inSeconds,
            'seen': seen.length,
            'measured': measured.length,
            'linked': motion.linkedStationCountNotifier.value,
            'connections': jsonDecode(
              jsonEncode(
                motion.connectionDiagnostics
                    .map(
                      (c) => {
                        ...c,
                        'decodeRejected': (c['decodeRejected'] as Map<int, int>)
                            .map((k, v) => MapEntry('$k', v)),
                      },
                    )
                    .toList(),
              ),
            ),
          });
          debugPrint(
            'FDSN LIVE ${15 * (i + 1)}s: seen=${seen.length}, measured=${measured.length}, linked=${motion.linkedStationCountNotifier.value}, metadata=${earth.stations.length}/${geo.stations.length}, connections=${motion.connectionDiagnostics}',
          );
        }
        final known = {
          for (final s in [...earth.stations, ...geo.stations])
            '${s.source}:${s.code}',
        };
        final result = {
          'startedAt': startedAt.toIso8601String(),
          'finishedAt': DateTime.now().toUtc().toIso8601String(),
          'target': limit,
          'seen': seen.length,
          'measured': measured.length,
          'bySource': {for (final e in bySource.entries) e.key: e.value.length},
          'linked': motion.linkedStationCountNotifier.value,
          'located': seen.intersection(known).length,
          'measuredLocated': measured.intersection(known).length,
          'freshLocated': latest.entries
              .where(
                (e) =>
                    known.contains(e.key) &&
                    DateTime.now().toUtc().difference(e.value) <=
                        FdsnStation.motionRetention,
              )
              .length,
          'freshMeasuredLocated': latestMeasured.entries
              .where(
                (e) =>
                    known.contains(e.key) &&
                    DateTime.now().toUtc().difference(e.value) <=
                        FdsnStation.motionRetention,
              )
              .length,
          'history': history,
          'missingMetadata': seen.difference(known).toList(),
          'rawArrivalBackwards': backwards,
          'summaryClockBackwards': clockBackwards,
          'latestDataTime': motion.dataTimeNotifier.value?.toIso8601String(),
          'connections': motion.connectionDiagnostics
              .map(
                (c) => {
                  ...c,
                  'decodeRejected': (c['decodeRejected'] as Map<int, int>).map(
                    (k, v) => MapEntry('$k', v),
                  ),
                },
              )
              .toList(),
        };
        debugPrint(jsonEncode(result));
        final dir = Directory('tmp/fdsn_connection_review')
          ..createSync(recursive: true);
        const tag = String.fromEnvironment('FDSN_PROBE_TAG');
        File(
          '${dir.path}/live_result_$limit${tag.isEmpty ? '' : '_$tag'}.json',
        ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
        expect(seen, isNotEmpty);
        expect(clockBackwards, 0);
      } finally {
        motion.dataTimeNotifier.removeListener(clockChanged);
        motion.disconnect();
        earth.stop();
        geo.stop();
        await subscription.cancel();
        await Future.wait(loading);
      }
    },
    skip: !const bool.fromEnvironment('FDSN_LIVE'),
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
