import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/core/source_estimation/palert_source_profile.dart';
import 'package:flutterrhythmquake/services/sources/native_palert_levels_io.dart';
import 'package:flutterrhythmquake/services/sources/palert_level_history.dart';
import 'package:flutterrhythmquake/services/sources/palert_service.dart';

import 'support/palert_level_history_before_20261015.dart';

void main() {
  for (final native in [false, true]) {
    group(
      native ? 'Rust levels' : 'Dart levels',
      () {
        late PAlertLevelHistory processor;
        late DartPAlertLevelHistoryReference reference;
        final start = DateTime.utc(2026, 10, 14, 9);
        setUp(() {
          processor = PAlertLevelHistory(useNative: native);
          reference = DartPAlertLevelHistoryReference();
        });
        tearDown(() => processor.clear());
        void layout(List<String> ids) {
          processor.setStations(ids);
          reference.setStations(ids);
        }

        void check(
          DateTime time,
          Map<String, double> pga,
          Map<String, double> pgv,
        ) {
          expect(
            processor.process(time, pga, pgv),
            reference.process(time, pga, pgv),
          );
        }

        test(
          'original 12 GraphQL responses and metadata, unchanged values and times',
          () {
            final dir = Directory('test/fixtures/palert_cadence_20261014');
            final metadata =
                jsonDecode(
                      File('${dir.path}/station-list.json').readAsStringSync(),
                    )['data']['stationList']['staInfos']
                    as List;
            layout([
              for (final item in metadata)
                if (item['station'].toString().trim().isNotEmpty &&
                    item['lat'] != null &&
                    item['lon'] != null)
                  item['station'].toString().trim(),
            ]);
            for (var i = 0; i < 12; i++) {
              final data = jsonDecode(
                File(
                  '${dir.path}/${i.toString().padLeft(2, '0')}.json',
                ).readAsStringSync(),
              )['data'];
              final time = PAlertService.parseTimestamp(
                data['pga']['timestamp'],
              )!;
              final pga = Map<String, double>.from(
                (data['pga']['dataVals'] as Map).map(
                  (key, value) => MapEntry(key, (value as num).toDouble()),
                ),
              );
              final pgv = data['pgv']['timestamp'] == data['pga']['timestamp']
                  ? Map<String, double>.from(
                      (data['pgv']['dataVals'] as Map).map(
                        (key, value) =>
                            MapEntry(key, (value as num).toDouble()),
                      ),
                    )
                  : <String, double>{};
              check(time, pga, pgv);
            }
          },
        );

        test('threshold edges, nonfinite, negative, zero and missing PGV', () {
          final pga = [
            -1.0,
            -0.0,
            double.nan,
            double.infinity,
            0.0,
            for (final v in PAlertSourceProfile.pgaThresholds) ...[
              v - 1e-10,
              v,
              v + 1e-10,
            ],
            79.999,
            80.0,
            800.0,
          ];
          layout([for (var i = 0; i < pga.length; i++) '$i']);
          for (final pgv in [
            null,
            -1.0,
            double.nan,
            double.infinity,
            0.0,
            for (final v in PAlertSourceProfile.pgvThresholds) ...[
              v - 1e-10,
              v,
              v + 1e-10,
            ],
          ]) {
            check(
              start,
              {for (var i = 0; i < pga.length; i++) '$i': pga[i]},
              {
                if (pgv != null)
                  for (var i = 0; i < pga.length; i++) '$i': pgv,
              },
            );
            processor.clear();
            reference.clear();
            layout([for (var i = 0; i < pga.length; i++) '$i']);
          }
        });

        test(
          'inclusive cutoff, absent PGA, invalid sample, rewind, directory remap and independent output',
          () {
            layout(['a', 'b']);
            final saved = processor.process(
              start,
              {'a': 800, 'b': 0.8},
              {'a': 140},
            );
            reference.process(start, {'a': 800, 'b': 0.8}, {'a': 140});
            check(start.add(const Duration(seconds: 3)), {'a': 0}, {});
            layout(['b', 'new', 'a']);
            check(start.add(const Duration(seconds: 3, microseconds: 1)), {
              'b': double.nan,
              'new': 80,
              'a': 0,
            }, {});
            check(start.subtract(const Duration(seconds: 1)), {
              'b': 0,
              'a': 0,
            }, {});
            expect(saved, [20, 20, 8, 8]);
            processor.clear();
            reference.clear();
            layout(['a']);
            check(start, {'a': 0}, {});
            layout([]);
            check(start, {}, {});
          },
        );
      },
      skip: native && !NativePAlertLevels.supported,
    );
  }

  test(
    'native owner and scratch release, no cross-session history',
    () {
      final count = NativePAlertLevels.diagnostics['sessions']!;
      final a = PAlertLevelHistory(useNative: true)..setStations(['a']);
      final b = PAlertLevelHistory(useNative: true)..setStations(['a']);
      try {
        final t = DateTime.utc(2026);
        expect(a.process(t, {'a': 800}, {'a': 140}), [20, 20]);
        expect(b.process(t, {'a': 0}, {}), [0, 0]);
        a.clear();
        a.clear();
        expect(NativePAlertLevels.diagnostics['sessions'], count + 1);
      } finally {
        a.clear();
        b.clear();
      }
      expect(NativePAlertLevels.diagnostics['sessions'], count);
    },
    skip: !NativePAlertLevels.supported,
  );

  test(
    'sampled level survives metadata copy and invalidates on measurements',
    () {
      const station = PAlertStation(
        id: 'a',
        network: '',
        name: '',
        area: '',
        coordinate: LatLng(23, 121),
        pgaGal: 80,
        pgvCms: 140,
        sampledLevel: 20,
      );
      expect(station.currentGridLevel, 20);
      expect(
        station.copyWith(receivedAt: DateTime.utc(2026)).currentGridLevel,
        20,
      );
      expect(station.copyWith(pgaGal: 0).currentGridLevel, 0);
      expect(station.copyWith(pgvCms: 15).currentGridLevel, 16);
    },
  );
}
