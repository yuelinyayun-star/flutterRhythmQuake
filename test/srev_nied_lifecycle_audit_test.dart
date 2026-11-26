import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/native_nied_detection_owner.dart';
import 'package:flutterrhythmquake/services/sources/nied_source_estimation_worker.dart';
import 'srev_nied_hyp_integration_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final input = Platform.environment['RQ_SREV_FULL_INPUT'];
  test(
    'SREV lifecycle: recorded observations then synthetic quiet tail',
    () {
      final file = File(input!);
      final d = jsonDecode(file.readAsStringSync()) as Map;
      final report = <Map<String, Object?>>[];
      for (final c in d['cases'] as List) {
        final s = fixtures.catalogue(d);
        List<dynamic> rows = const [];
        final owner = NativeNiedDetectionOwner(
          s,
          manualClock: true,
          useSrev: true,
          onUpdate: (r) {
            if (r.length > 4) rows = r[4] as List;
          },
        );
        final projection = SrevSourceProjection();
        final events = <String, Map<String, dynamic>>{};
        final frames = c['frames'] as List;
        final first = frames.first['time'] as num;
        final last = frames.last['time'] as num;
        var lastActive = <String>{};
        var historyCount = 0, quietTail = 0, activeAfter120 = 0;
        try {
          for (var f = 0; f < frames.length + 650; f++) {
            final real = f < frames.length;
            final t = real
                ? frames[f]['time'] as num
                : last + f - frames.length + 1;
            final levels = real
                ? (frames[f]['levels'] as List).cast<int>()
                : List.filled(s.length, 0);
            final time = DateTime.fromMicrosecondsSinceEpoch(
              (t * 1000000).round() + fixtures.epoch,
              isUtc: true,
            );
            for (var i = 0; i < s.length; i++) {
              s[i]
                ..level = levels[i]
                ..recentLevel = [levels[i]]
                ..lastDataTime = time
                ..lastUpdate = time;
            }
            rows = const [];
            owner.process(
              s,
              2,
              clock: ((t - first) * 1000).round(),
              solveSrev: true,
            );
            owner.rebind(s);
            final result = projection.project(rows, s, time);
            final active = <String>{};
            for (final row in rows) {
              final age = t - (row['start'] as num);
              final id = "${row['id']}:${row['start']}";
              active.add(id);
              final e = events.putIfAbsent(
                id,
                () => {
                  'id': row['id'],
                  'start': row['start'],
                  'firstAge': age,
                  'firstFrame': f,
                },
              );
              e['lastAge'] = age;
              e['lastCount'] = row['count'];
              e['lastFrame'] = f;
              final a = row['estimate'];
              if (a is Map) {
                expect(row['hyp_state'], age >= 120 ? 'finished' : 'updating');
                final accepted = row['hyp_accepted_at'] as num?;
                expect(accepted, isNotNull);
                expect(accepted! - (row['start'] as num), lessThan(120));
                final oldAccepted = e['acceptedAt'];
                if (oldAccepted == null || accepted != oldAccepted) {
                  if (oldAccepted == null || accepted == row['observed_at']) {
                    e['reportCount'] = ((e['reportCount'] as int?) ?? 0) + 1;
                  }
                  e['acceptedAt'] = accepted;
                  e['lastAcceptedAge'] = accepted - (row['start'] as num);
                }
                final published =
                    (result.event!.metadata['nied_dart_hyp_sources'] as List)
                        .cast<Map>()
                        .singleWhere(
                          (v) =>
                              (v['diagnostics']
                                  as Map)['selected_detection_id'] ==
                              row['id'],
                        );
                final diag = published['diagnostics'] as Map;
                expect(diag['srev_hyp_state'], row['hyp_state']);
                expect(diag['srev_hyp_report_num'], e['reportCount']);
                expect(diag['srev_hyp_accepted_at'], accepted);

                final loc = [a['lat'], a['lon'], a['depth'], a['origin']];
                final sig = loc.join(',');
                e['firstEstimateAge'] ??= age;
                if (e['signature'] != sig) {
                  e['lastLocationUpdateAge'] = age;
                  e['lastLocationUpdateFrame'] = f;
                  e['signature'] = sig;
                }
                if (age >= 120) {
                  activeAfter120++;
                  e['firstFrozenAge'] ??= age;
                  e['firstFrozenRadius'] ??= a['s_radius'];
                  e['lastFrozenRadius'] = a['s_radius'];
                  e['lastFrozenMagnitude'] = a['magnitude'];
                  expect(
                    e['lastLocationUpdateAge'] as num,
                    lessThan(120),
                    reason: 'same event geometry changed after HYP cutoff',
                  );
                }
              }
            }
            for (final id in lastActive.difference(active)) {
              events[id]!['endedAge'] = t - (events[id]!['start'] as num);
              events[id]!['endedFrame'] = f;
              events[id]!['endedInSyntheticTail'] = !real;
            }
            lastActive = active;
            if (result.history != null) historyCount = result.history!.length;
            expect(result.event == null, rows.isEmpty);
            if (!real) {
              quietTail++;
              if (rows.isEmpty && !s.any((v) => v.isActive)) break;
            }
          }
          expect(lastActive, isEmpty);
          expect(historyCount, greaterThan(0));
        } finally {
          owner.dispose();
        }
        final entry = {
          'case': c['name'],
          'recordedFrames': frames.length,
          'syntheticQuietFrames': quietTail,
          'activeEstimatedSlotFramesAfter120': activeAfter120,
          'historyCount': historyCount,
          'events': events.values.toList(),
        };
        report.add(entry);
        print(jsonEncode(entry));
      }
      File(
        '${file.parent.path}/srev_lifecycle_ui_report.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    },
    skip: input == null,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
