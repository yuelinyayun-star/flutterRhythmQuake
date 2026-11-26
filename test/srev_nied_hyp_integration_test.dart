import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/sources/native_nied_detection_owner.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/nied_source_estimation_worker.dart';
import 'package:flutterrhythmquake/services/sources/palert_service.dart';

const epoch = 946684800000000;
final env = Platform.environment;
List<NiedStation> catalogue(Map d) => [
  for (final c in d['catalog'] as List)
    NiedStation(
      id: c['id'] as int,
      code: c['code'] as String,
      name: c['name'] as String,
      coordinate: LatLng(
        (c['lat'] as num).toDouble(),
        (c['lon'] as num).toDouble(),
      ),
      network: '',
      prefecture: '',
      expireSeconds: 10,
    ),
];
double distance(double a, double b, double x, double y) {
  final dy = (a - x) * math.pi / 180, dx = (b - y) * math.pi / 180;
  final h =
      math.pow(math.sin(dy / 2), 2) +
      math.cos(a * math.pi / 180) *
          math.cos(x * math.pi / 180) *
          math.pow(math.sin(dx / 2), 2);
  return 12742 * math.asin(math.sqrt(h.clamp(0, 1)));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final reference in [true, false]) {
    final input =
        env[reference ? 'RQ_SREV_ORIGINAL_HYP' : 'RQ_SREV_FULL_INPUT'];
    test(
      reference
          ? 'Original SREV HYP and magnitude per-frame parity on 535 frames'
          : '1725 station production HYP and magnitude replay',
      () {
        expect(NativeNiedDetectionOwner.supported, isTrue);
        final file = File(input!);
        final d = jsonDecode(file.readAsStringSync()) as Map;
        final report = <Map<String, Object?>>[];
        const official = [
          (27.778333333, 139.928333333, 507, 6.8),
          (34.151666667, 135.803333333, 50, 3.6),
          (30.756666667, 131.488333333, 40, 3.3),
        ];
        final watch = Stopwatch();
        var ci = 0;
        for (final c in d['cases'] as List) {
          final stations = catalogue(d);
          List<dynamic> rows = const [];
          final projector = SrevSourceProjection();
          final owner = NativeNiedDetectionOwner(
            stations,
            manualClock: true,
            useSrev: true,
            onUpdate: (r) {
              if (r.length > 4) rows = r[4] as List;
            },
          );
          final firstTime = c['frames'][0]['time'] as num;
          final diffs = <Map<String, Object?>>[];
          final data = <Map<String, Object?>>[];
          final ms = <double>[];
          var first = -1, peak = 0, estFrames = 0, comparisons = 0;
          double? best;
          final fref = official[ci++];
          try {
            var f = 0;
            for (final frame in c['frames'] as List) {
              final t = DateTime.fromMicrosecondsSinceEpoch(
                ((frame['time'] as num) * 1000000).round() + epoch,
                isUtc: true,
              );
              final levels = (frame['levels'] as List).cast<int>();
              for (var i = 0; i < stations.length; i++) {
                stations[i]
                  ..level = levels[i]
                  ..recentLevel = [levels[i]]
                  ..lastDataTime = t
                  ..lastUpdate = t;
              }
              rows = const [];
              watch.reset();
              watch.start();
              owner.process(
                stations,
                2,
                clock: ((frame['time'] - firstTime) * 1000).round() as int,
                solveSrev: true,
              );
              owner.rebind(stations);
              watch.stop();
              ms.add(watch.elapsedMicroseconds / 1000);
              expect(stations.map((s) => s.level), levels);
              final result = projector.project(rows, stations, t);
              if (rows.length > peak) peak = rows.length;
              if (reference) {
                final wanted = frame['expected'] as List;
                void check(Object? a, Object? b, String field) {
                  if (a is num && b is num) {
                    comparisons++;
                    if ((a - b).abs() > 1e-7 + 1e-10 * b.abs())
                      diffs.add({
                        'frame': f,
                        'field': field,
                        'got': a,
                        'want': b,
                      });
                  } else if (a != b) {
                    diffs.add({
                      'frame': f,
                      'field': field,
                      'got': a,
                      'want': b,
                    });
                  }
                }

                check(rows.length, wanted.length, 'event count');
                for (var i = 0; i < math.min(rows.length, wanted.length); i++) {
                  final a = rows[i] as Map, b = wanted[i] as Map;
                  for (final k in ['id', 'start', 'count']) {
                    check(a[k], b[k], k);
                  }
                  final ae = a['estimate'], be = b['estimate'];
                  if (ae is Map && be is Map) {
                    for (final k in [
                      'lat',
                      'lon',
                      'depth',
                      'origin',
                      'error',
                      'magnitude',
                    ]) {
                      check(ae[k], be[k], k);
                    }
                  } else {
                    check(ae, be, 'estimate');
                  }
                }
              }
              final estimate = result.event?.estimate;
              if (estimate != null) {
                if (first < 0) first = f;
                estFrames++;
                expect(estimate.method, SrevSourceProjection.method);
                expect(estimate.magnitude, isNotNull);
                expect(
                  estimate.magnitude,
                  estimate.diagnostics['rq_magnitude_shadow'],
                );
                expect(
                  estimate.diagnostics['srev_original_magnitude'],
                  isNotNull,
                );
                expect(
                  estimate.diagnostics['magnitude_model'],
                  isNot('srev_original_fallback'),
                );
                final km = distance(
                  estimate.latitude,
                  estimate.longitude,
                  fref.$1,
                  fref.$2,
                );
                best = best == null ? km : math.min(best, km);
                data.add({
                  'frame': f,
                  'time': frame['jst'],
                  'lat': estimate.latitude,
                  'lon': estimate.longitude,
                  'depth': estimate.depthKm,
                  'origin': estimate.originTime?.toIso8601String(),
                  'magnitude': estimate.magnitude,
                  'count': estimate.supportingStationCount,
                  'errorKm': km,
                  'residual': estimate.diagnostics['srev_error'],
                  for (final key in [
                    'srev_original_magnitude',
                    'magnitude_model',
                    'rq_magnitude_shadow',
                    'rq_magnitude_shadow_current',
                    'rq_magnitude_shadow_input',
                    'rq_magnitude_shadow_peak',
                    'rq_magnitude_shadow_distance_km',
                    'rq_magnitude_shadow_multiple_sources',
                    'rq_magnitude_uncalibrated_current',
                  ])
                    key: estimate.diagnostics[key],
                });
              }
              f++;
            }
          } finally {
            owner.dispose();
          }
          ms.sort();
          report.add({
            'case': c['name'],
            'frames': ms.length,
            'estimateFrames': estFrames,
            'first': first,
            'peakConcurrentEvents': peak,
            'bestKm': best,
            'last': data.isEmpty ? null : data.last,
            'meanMs': ms.reduce((a, b) => a + b) / ms.length,
            'p95Ms': ms[(ms.length * .95).ceil() - 1],
            'maxMs': ms.last,
            'comparedValues': comparisons,
            'differenceCount': diffs.length,
            'differences': diffs.take(100).toList(),
            'estimates': data,
          });
        }
        final reportFile = File(
          '${file.parent.path}/${reference ? 'srev_hyp_original_parity_rq_magnitude' : 'srev_hyp_full_catalog_rq_magnitude'}.json',
        );
        reportFile.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(report),
        );
        for (final r in report) {
          print(
            {...r}
              ..remove('estimates')
              ..remove('differences'),
          );
          expect(r['estimateFrames'] as int, greaterThan(0));
          if (reference)
            expect(
              r['differenceCount'],
              0,
              reason: '${r['case']} independent SREV baseline',
            );
        }
      },
      skip: input == null,
      timeout: const Timeout(Duration(minutes: 6)),
    );
  }
  test(
    'Archived station worker uses SREV HYP, not the previous KA estimator',
    () async {
      final d =
          jsonDecode(File(env['RQ_SREV_FULL_INPUT']!).readAsStringSync())
              as Map;
      final cat = d['catalog'] as List;
      final c = (d['cases'] as List)[1] as Map;
      final worker = NiedSourceEstimationWorker(
        displayOnly: true,
        useSrevHyp: true,
      );
      var count = 0;
      try {
        for (final frame in c['frames'] as List) {
          final time = DateTime.fromMicrosecondsSinceEpoch(
            ((frame['time'] as num) * 1000000).round() + epoch,
            isUtc: true,
          );
          final levels = frame['levels'] as List;
          final rows = [
            for (var i = 0; i < cat.length; i++)
              {
                'id': cat[i]['id'],
                'code': cat[i]['code'],
                'name': cat[i]['name'],
                'coordinate': {'lat': cat[i]['lat'], 'lng': cat[i]['lon']},
                'network': '',
                'prefecture': '',
                'expireSeconds': 10,
                'level': levels[i],
                'lastDataTime': time.toIso8601String(),
                'lastUpdate': time.toIso8601String(),
              },
          ];
          final result = await worker.processRawStations(rows);
          expect(result, isNotNull);
          if (result!.event?.estimate case final estimate?) {
            expect(estimate.method, SrevSourceProjection.method);
            expect(estimate.magnitude, isNotNull);
            expect(
              estimate.magnitude,
              estimate.diagnostics['rq_magnitude_shadow'],
            );
            count++;
          }
        }
        expect(count, 60);
      } finally {
        worker.dispose();
      }
    },
    skip: env['RQ_SREV_FULL_INPUT'] == null,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'RQ published magnitude retains the event peak and resets across source slots',
    () {
      final projector = SrevSourceProjection();
      final time = DateTime.utc(2026, 11, 25);
      final station = NiedStation(
        id: 1,
        code: 'A',
        name: 'A',
        coordinate: const LatLng(35, 135),
        network: '',
        prefecture: '',
        expireSeconds: 10,
        level: 13,
      )..isActive = true;
      final start = (time.millisecondsSinceEpoch - 946684800000) / 1000;
      Map<String, dynamic> slot(num t) => {
        'id': 1,
        'start': t,
        'count': 1,
        'members': [0],
        'estimate': {
          'lat': 35.0,
          'lon': 135.0,
          'depth': 10.0,
          'origin': t - 5,
          'magnitude': 2.0,
          'error': 1.0,
        },
      };
      final a = projector
          .project([slot(start)], [station], time)
          .event!
          .estimate!;
      station.level = 7;
      final b = projector
          .project(
            [slot(start)],
            [station],
            time.add(const Duration(seconds: 12)),
          )
          .event!
          .estimate!;
      expect(a.magnitude, a.diagnostics['rq_magnitude_shadow']);
      expect(b.magnitude, a.magnitude);
      expect(a.diagnostics['srev_original_magnitude'], 2);
      expect(b.diagnostics['srev_original_magnitude'], 2);
      expect(
        b.diagnostics['rq_magnitude_shadow'],
        a.diagnostics['rq_magnitude_shadow'],
      );
      expect(
        b.diagnostics['rq_magnitude_shadow_current'] as num,
        lessThan(b.diagnostics['rq_magnitude_shadow'] as num),
      );
      projector.project([], [station], time.add(const Duration(seconds: 13)));
      final c = projector
          .project(
            [slot(start + 14)],
            [station],
            time.add(const Duration(seconds: 14)),
          )
          .event!
          .estimate!;
      expect(
        c.diagnostics['rq_magnitude_shadow'] as num,
        lessThan(b.diagnostics['rq_magnitude_shadow'] as num),
      );
      station.isActive = false;
      final fallback = SrevSourceProjection()
          .project(
            [slot(start + 20)],
            [station],
            time.add(const Duration(seconds: 20)),
          )
          .event!
          .estimate!;
      expect(fallback.magnitude, 2);
      expect(fallback.diagnostics['magnitude_model'], 'srev_original_fallback');
      expect(fallback.diagnostics['rq_magnitude_shadow'], isNull);
    },
  );
  test('P-Alert production inference is intentionally disconnected', () {
    expect(PAlertService.sourceEstimationAvailable, isFalse);
  });
}
